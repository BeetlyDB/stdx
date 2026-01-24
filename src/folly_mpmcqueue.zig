const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const lib = @import("lib.zig");
const assert = lib.assert;

pub fn MPMCQueue(comptime T: type) type {
    comptime {
        assert(@sizeOf(T) > 0); // T must be non-zero size
    }
    return struct {
        const Self = @This();

        const Slot = struct {
            data: T align(std.atomic.cache_line) = undefined,
            turn: usize = 0,

            pub inline fn loadTurn(slot: *const Slot) usize {
                return @atomicLoad(usize, &slot.turn, .acquire);
            }

            pub inline fn storeTurn(slot: *Slot, value: usize) void {
                @atomicStore(usize, &slot.turn, value, .release);
            }
        };

        const NoSlots: []Slot = &[0]Slot{};

        _head: usize align(std.atomic.cache_line) = 0,
        _tail: usize align(std.atomic.cache_line) = 0,
        _slots: []Slot align(std.atomic.cache_line) = NoSlots,
        allocator: Allocator,

        pub fn init(allocator: std.mem.Allocator, _capacity: usize) !Self {
            const slots = try allocator.alloc(Slot, _capacity + 1);
            assert(@intFromPtr(slots.ptr) % std.atomic.cache_line == 0);
            assert(@intFromPtr(slots.ptr) % @alignOf(T) == 0);
            @memset(slots, .{});
            var self = Self{
                .allocator = allocator,
            };

            self._slots.ptr = slots.ptr;
            self._slots.len = _capacity;
            self.allocator = allocator;
            return self;
        }

        pub fn deinit(self: *Self) void {
            assert(self._slots.ptr != NoSlots.ptr);
            var slots = self._slots;
            slots.len = self._slots.len + 1; // free extra slot
            self.allocator.free(slots);
        }

        pub inline fn capacity(self: *const Self) usize {
            return self._slots.len;
        }

        pub inline fn empty(self: *const Self) bool {
            return self.size() == 0;
        }

        pub inline fn size(self: *const Self) usize {
            const head = self.loadHead(.acquire);
            const tail = self.loadTail(.acquire);
            const diff = head - tail;
            return if (diff > self._slots.len) self._slots.len else diff;
        }
        /// Enqueue `value`, blocking while queue is full.
        pub inline fn enqueue(self: *Self, value: T) void {
            const head = self.bumpHead();
            const slot = self.nthSlot(head);
            const turn = self.nthTurn(head);
            while (turn != slot.loadTurn()) {
                std.atomic.spinLoopHint();
            }
            slot.data = value;
            slot.storeTurn(turn + 1);
        }

        /// Enqueue `value` if queue is not full,
        /// return `true` if enqueued, `false` otherwise.
        pub inline fn enqueueIfNotFull(self: *Self, value: T) bool {
            var head = self.loadHead(.acquire);
            while (true) {
                const slot = self.nthSlot(head);
                const turn = self.nthTurn(head);
                if (turn == slot.loadTurn()) {
                    if (self.bumpHeadIfEql(head)) {
                        slot.data = value;
                        slot.storeTurn(turn + 1);
                        return true;
                    }
                } else {
                    const prev_head = head;
                    head = self.loadHead(.acquire);
                    if (head == prev_head) {
                        return false;
                    }
                }
            }
        }

        /// Dequeue one element, blocking while queue is empty.
        pub inline fn dequeue(self: *Self) T {
            const tail = self.bumpTail();
            const slot = self.nthSlot(tail);
            const turn = self.nthTurn(tail) + 1;
            while (turn != slot.loadTurn()) {
                // await our turn to dequeue
            }
            const value = slot.data;
            slot.data = undefined;
            slot.storeTurn(turn + 1);
            return value;
        }

        /// Dequeue one element if queue is not empty,
        /// return value if dequeued, `null` otherwise.
        pub fn dequeueIfNotEmpty(self: *Self) ?T {
            var tail = self.loadTail(.acquire);
            while (true) {
                const slot = self.nthSlot(tail);
                const turn = self.nthTurn(tail) + 1;
                if (turn == slot.loadTurn()) {
                    if (self.bumpTailIfEql(tail)) {
                        const result = slot.data;
                        slot.data = undefined;
                        slot.storeTurn(turn + 1);
                        return result;
                    }
                } else {
                    const prev_tail = tail;
                    tail = self.loadTail(.acquire);
                    if (tail == prev_tail) {
                        return null;
                    }
                }
            }
        }

        const Order = std.builtin.AtomicOrder;

        inline fn bumpHead(self: *Self) usize {
            return @atomicRmw(usize, &self._head, .Add, 1, .monotonic);
        }

        inline fn bumpHeadIfEql(self: *Self, n: usize) bool {
            return null == @cmpxchgStrong(usize, &self._head, n, n + 1, .acq_rel, .monotonic);
        }

        inline fn loadHead(self: *const Self, comptime order: Order) usize {
            return @atomicLoad(usize, &self._head, order);
        }

        inline fn bumpTail(self: *Self) usize {
            return @atomicRmw(usize, &self._tail, .Add, 1, .monotonic);
        }

        inline fn bumpTailIfEql(self: *Self, n: usize) bool {
            return null == @cmpxchgStrong(usize, &self._tail, n, n + 1, .monotonic, .monotonic);
        }

        inline fn loadTail(self: *const Self, comptime order: Order) usize {
            return @atomicLoad(usize, &self._tail, order);
        }

        inline fn nthSlot(self: *Self, n: usize) *Slot {
            return &self._slots[(n % self._slots.len)];
        }

        inline fn nthTurn(self: *const Self, n: usize) usize {
            return (n / self._slots.len) * 2;
        }
    };
}

test "MPMCQueue basics" {
    const Data = struct {
        a: [56]u8,
    };
    const Slot = MPMCQueue(Data).Slot;

    const expectEqual = std.testing.expectEqual;

    try expectEqual(std.atomic.cache_line, @alignOf(Slot));
    try expectEqual(true, @sizeOf(Slot) % std.atomic.cache_line == 0);

    std.debug.print("\n", .{});
    std.debug.print("@sizeOf(Data):{}\n", .{@sizeOf(Data)});
    std.debug.print("@sizeOf(Slot):{}\n", .{@sizeOf(Slot)});

    const allocator = std.testing.allocator;

    var queue = try MPMCQueue(usize).init(allocator, 4);
    defer queue.deinit();

    try expectEqual(@as(usize, 4), queue.capacity());
    try expectEqual(@as(usize, 0), queue.size());
    try expectEqual(true, queue.empty());

    queue.enqueue(@as(usize, 0));
    try expectEqual(@as(usize, 1), queue.size());
    try expectEqual(false, queue.empty());

    queue.enqueue(@as(usize, 1));
    try expectEqual(@as(usize, 2), queue.size());
    try expectEqual(false, queue.empty());

    queue.enqueue(@as(usize, 2));
    try expectEqual(@as(usize, 3), queue.size());
    try expectEqual(false, queue.empty());

    queue.enqueue(@as(usize, 3));
    try expectEqual(@as(usize, 4), queue.size());
    try expectEqual(false, queue.empty());

    try expectEqual(false, queue.enqueueIfNotFull(4));
    try expectEqual(@as(usize, 4), queue.size());
    try expectEqual(false, queue.empty());

    try expectEqual(@as(usize, 0), queue.dequeue());
    try expectEqual(@as(usize, 3), queue.size());
    try expectEqual(false, queue.empty());

    try expectEqual(@as(usize, 1), queue.dequeue());
    try expectEqual(@as(usize, 2), queue.size());
    try expectEqual(false, queue.empty());

    try expectEqual(@as(usize, 2), queue.dequeue());
    try expectEqual(@as(usize, 1), queue.size());
    try expectEqual(false, queue.empty());

    try expectEqual(@as(usize, 3), queue.dequeue());
    try expectEqual(@as(usize, 0), queue.size());
    try expectEqual(true, queue.empty());
}

test "MPMCQueue(usize) multiple consumers" {
    std.debug.print("\n", .{});

    const allocator = std.testing.allocator;

    const JobQueue = MPMCQueue(usize);
    var queue = try JobQueue.init(allocator, 4);
    defer queue.deinit();

    const Context = struct {
        queue: *JobQueue,
    };
    var context = Context{ .queue = &queue };

    const JobThread = struct {
        pub fn main(ctx: *Context) void {
            const tid = std.Thread.getCurrentId();

            while (true) {
                const job = ctx.queue.dequeue();
                std.debug.print("thread {} job {}\n", .{ tid, job });

                if (job == @as(usize, 0)) break;

                std.Thread.sleep(10);
            }

            std.debug.print("thread {} EXIT\n", .{tid});
        }
    };

    const threads = [4]std.Thread{
        try std.Thread.spawn(.{}, JobThread.main, .{&context}),
        try std.Thread.spawn(.{}, JobThread.main, .{&context}),
        try std.Thread.spawn(.{}, JobThread.main, .{&context}),
        try std.Thread.spawn(.{}, JobThread.main, .{&context}),
    };

    queue.enqueue(@as(usize, 1));
    queue.enqueue(@as(usize, 2));
    queue.enqueue(@as(usize, 3));
    queue.enqueue(@as(usize, 4));

    std.Thread.sleep(100);

    queue.enqueue(@as(usize, 0));
    queue.enqueue(@as(usize, 0));
    queue.enqueue(@as(usize, 0));
    queue.enqueue(@as(usize, 0));

    for (threads) |thread| {
        thread.join();
    }

    std.debug.print("DONE\n", .{});
}

test "MPMCQueue(Job) multiple consumers" {
    std.debug.print("\n", .{});

    const Job = struct {
        const Self = @This();

        a: [56]u8 = undefined,

        pub fn init(id: u8) Self {
            var self = Self{};
            self.a[0] = id;
            return self;
        }
    };

    const JobQueue = MPMCQueue(Job);

    const allocator = std.testing.allocator;
    var queue = try JobQueue.init(allocator, 4);
    defer queue.deinit();

    const JobThread = struct {
        const Self = @This();
        const Thread = std.Thread;
        const SpawnConfig = Thread.SpawnConfig;
        const SpawnError = Thread.SpawnError;

        index: usize,
        queue: *JobQueue,

        pub fn init(index: usize, _queue: *JobQueue) Self {
            return Self{ .index = index, .queue = _queue };
        }

        pub fn spawn(config: SpawnConfig, index: usize, _queue: *JobQueue) !Thread {
            return Thread.spawn(config, Self.main, .{Self.init(index, _queue)});
        }

        pub fn main(self: Self) void {
            std.debug.print("JobThread {} START\n", .{self.index});

            while (true) {
                const job = self.queue.dequeue();
                std.debug.print("JobThread {} run job {}\n", .{ self.index, job.a[0] });

                if (job.a[0] == @as(u8, 0)) break;

                std.Thread.sleep(1);
            }

            std.debug.print("JobThread {} EXIT\n", .{self.index});
        }
    };

    const threads = [4]std.Thread{
        try JobThread.spawn(.{}, 1, &queue),
        try JobThread.spawn(.{}, 2, &queue),
        try JobThread.spawn(.{}, 3, &queue),
        try JobThread.spawn(.{}, 4, &queue),
    };

    queue.enqueue(Job.init(1));
    queue.enqueue(Job.init(2));
    queue.enqueue(Job.init(3));
    queue.enqueue(Job.init(4));

    std.Thread.sleep(100);

    queue.enqueue(Job.init(0));
    queue.enqueue(Job.init(0));
    queue.enqueue(Job.init(0));
    queue.enqueue(Job.init(0));

    for (threads) |thread| {
        thread.join();
    }

    std.debug.print("DONE\n", .{});
}
