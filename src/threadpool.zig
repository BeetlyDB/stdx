const std = @import("std");

const Thread = std.Thread;
const Allocator = std.mem.Allocator;

const MPMCQueue = @import("folly_mpmcqueue.zig").MPMCQueue;

//THREAD SAFE
pub fn ThreadPool(comptime F: anytype) type {
    const Args = std.meta.ArgsTuple(@TypeOf(F));
    return struct {
        const Self = @This();
        queue: *MPMCQueue(Args),
        threads: []Thread,
        allocator: Allocator,
        stop: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

        pub const Opts = struct {
            count: usize = 4, // Number of worker threads
            queue_capacity: usize = 16, // Max tasks in queue
        };

        /// Initialize thread pool with allocator and options.
        pub fn init(allocator: Allocator, opts: Opts) !*Self {
            if (opts.count == 0) return error.InvalidThreadCount;
            if (opts.queue_capacity == 0) return error.InvalidQueueCapacity;

            // Allocate queue on heap so worker threads can use it after init returns
            const qptr = try allocator.create(MPMCQueue(Args));
            // if something fails after this point, we must destroy qptr
            errdefer allocator.destroy(qptr);

            // initialize the queue in-place
            qptr.* = try MPMCQueue(Args).init(allocator, opts.queue_capacity);
            // now qptr points to a valid heap-allocated queue

            const threads = try allocator.alloc(Thread, opts.count);
            errdefer allocator.free(threads);

            const pool = try allocator.create(Self);
            errdefer allocator.destroy(pool);

            pool.* = .{
                .allocator = allocator,
                .queue = qptr,
                .threads = threads,
            };

            var started: usize = 0;
            errdefer {
                pool.stop.store(true, .release);
                for (0..started) |i| {
                    threads[i].join();
                }
            }

            for (0..threads.len) |i| {
                threads[i] = try Thread.spawn(.{}, Self.worker, .{ pool, i });
                started += 1;
            }

            return pool;
        }

        pub fn deinit(self: *Self) void {
            self.stop.store(true, .release);

            for (self.threads) |t| {
                t.join();
            }
            self.queue.deinit();
            self.allocator.destroy(self.queue);
            self.allocator.free(self.threads);
            self.allocator.destroy(self);
        }

        /// Check if the queue is empty. Thread-safe but may be inaccurate.
        pub fn isEmpty(self: *const Self) bool {
            return self.queue.empty();
        }

        /// Spawn a task by pushing to the shared MPMC queue.
        /// Returns true if successful, false if queue is full.
        pub fn spawn(self: *Self, args: Args) bool {
            return self.queue.enqueueIfNotFull(args);
        }

        /// Spawn a task by pushing to the shared MPMC queue, blocking if full.
        pub fn spawnBlocking(self: *Self, args: Args) void {
            self.queue.enqueue(args);
        }

        /// Worker function for each thread, consuming tasks from the shared queue.
        fn worker(self: *Self, thread_idx: usize) void {
            _ = thread_idx;
            while (true) {
                if (self.queue.dequeueIfNotEmpty()) |args| {
                    @call(.always_inline, F, args);
                    continue;
                }

                if (self.stop.load(.acquire)) break;

                std.atomic.spinLoopHint();
            }
        }
    };
}

fn exampleTask(id: usize) void {
    std.debug.print("Task {} executed on thread {}\n", .{ id, std.Thread.getCurrentId() });
}

test "ThreadPool with MPMCQueue (queue full check)" {
    const allocator = std.testing.allocator;
    var q = try MPMCQueue(usize).init(allocator, 8);
    defer q.deinit();

    for (0..8) |i| {
        try std.testing.expect(q.enqueueIfNotFull(i));
    }
    try std.testing.expect(!q.enqueueIfNotFull(99));
}

test "ThreadPool concurrent tasks" {
    const allocator = std.testing.allocator;
    const TaskCounter = struct {
        const Self = @This();
        counter: *std.atomic.Value(usize),
        fn task(self: *Self, id: usize) void { // Non-const self for @call
            _ = self.counter.fetchAdd(1, .release);
            std.debug.print("Task {} executed on thread {}\n", .{ id, std.Thread.getCurrentId() });
        }
    };

    var counter = std.atomic.Value(usize).init(0);
    var task_counter = TaskCounter{ .counter = &counter }; // Non-const instance
    var pool = try ThreadPool(TaskCounter.task).init(allocator, .{ .count = 4, .queue_capacity = 16 });
    defer pool.deinit();

    const producer = struct {
        fn run(pl: *ThreadPool(TaskCounter.task), tc: *TaskCounter) void {
            for (0..10) |i| {
                while (!pl.spawn(.{ tc, i })) { // Pass non-const tc
                    std.Thread.sleep(1_000);
                }
            }
        }
    };

    const producers = [2]std.Thread{
        try std.Thread.spawn(.{}, producer.run, .{ pool, &task_counter }),
        try std.Thread.spawn(.{}, producer.run, .{ pool, &task_counter }),
    };

    for (producers) |thread| thread.join();
    std.Thread.sleep(10_000_000); // Wait for tasks to process
    try std.testing.expectEqual(@as(usize, 20), counter.load(.acquire));
    try std.testing.expect(pool.isEmpty());
}

test "ThreadPool zero capacity" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidQueueCapacity, ThreadPool(exampleTask).init(allocator, .{ .count = 1, .queue_capacity = 0 }));
}

test "ThreadPool zero threads" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidThreadCount, ThreadPool(exampleTask).init(allocator, .{ .count = 0, .queue_capacity = 8 }));
}

test "ThreadPool: small fuzz" {
    testSum = 0; // global defined near the end of this file
    var tp = try ThreadPool(testIncr).init(std.testing.allocator, .{ .count = 3, .queue_capacity = 3 });

    for (0..50_000) |_| {
        tp.spawnBlocking(.{1}); //wait until space be available
    }
    //or
    // for (0..50_000) |_| {
    //     while (!tp.spawn(.{1})) {
    //         std.atomic.spinLoopHint();
    //     }
    // }
    while (tp.isEmpty() == false) {
        std.Thread.sleep(std.time.ns_per_ms);
    }
    tp.deinit();
    // std.debug.print("testsum: ", testSum);
    try std.testing.expectEqual(50_000, testSum);
}

test "ThreadPool: large fuzz" {
    testSum = 0; // global defined near the end of this file
    var tp = try ThreadPool(testIncr).init(std.testing.allocator, .{ .count = 50, .queue_capacity = 1000 });

    for (0..50_000) |_| {
        tp.spawnBlocking(.{1});
    }
    while (tp.isEmpty() == false) {
        std.Thread.sleep(std.time.ns_per_ms);
    }
    tp.deinit();
    try std.testing.expectEqual(50_000, testSum);
}

var testSum: u64 = 0;
fn testIncr(c: u64) void {
    _ = @atomicRmw(u64, &testSum, .Add, c, .monotonic);
}
