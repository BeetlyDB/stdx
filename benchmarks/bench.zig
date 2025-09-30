const std = @import("std");
const stdx = @import("stdx");

const Timer = std.time.Timer;
const Allocator = std.mem.Allocator;

pub const Opts = struct {
    samples: u32 = 10_000,
    runtime: usize = 3 * std.time.ms_per_s,
};

const key: u64 = 47821748217481;

pub fn Result(comptime SAMPLE_COUNT: usize) type {
    return struct {
        total: u64,
        iterations: u64,
        requested_bytes: usize,
        // sorted, use samples()
        _samples: [SAMPLE_COUNT]u64,

        const Self = @This();

        pub fn print(self: *const Self, name: []const u8) void {
            std.debug.print("{s}\n", .{name});
            std.debug.print("  {d} iterations\t{d:.2}ns per iterations\n", .{ self.iterations, self.mean() });
            std.debug.print("  {d:.2} bytes per iteration\n", .{self.requested_bytes / self.iterations});
            std.debug.print("  worst: {d}ns\tmedian: {d:.2}ns\tstddev: {d:.2}ns\n\n", .{ self.worst(), self.median(), self.stdDev() });
        }

        // pub fn samples(self: *const Self) []const u64 {
        //     return self._samples[0..@min(self.iterations, SAMPLE_COUNT)];
        // }

        pub fn samples(self: *const Self) []const u64 {
            const len = @min(self.iterations, SAMPLE_COUNT);
            return if (len == 0) self._samples[0..0] else self._samples[0..len];
        }

        // pub fn worst(self: *const Self) u64 {
        //     const s = self.samples();
        //     return s[s.len - 1];
        // }

        pub fn worst(self: *const Self) u64 {
            const s = self.samples();
            if (s.len == 0) return 0;
            return s[s.len - 1];
        }

        // pub fn mean(self: *const Self) f64 {
        //     const s = self.samples();
        //
        //     var total: u64 = 0;
        //     for (s) |value| {
        //         total += value;
        //     }
        //     return @as(f64, @floatFromInt(total)) / @as(f64, @floatFromInt(s.len));
        // }

        pub fn mean(self: *const Self) f64 {
            const s = self.samples();
            if (s.len == 0) return 0.0;
            var total: u64 = 0;
            for (s) |value| total += value;
            return @as(f64, @floatFromInt(total)) / @as(f64, @floatFromInt(s.len));
        }

        // pub fn median(self: *const Self) u64 {
        //     const s = self.samples();
        //     return s[s.len / 2];
        // }

        pub fn median(self: *const Self) u64 {
            const s = self.samples();
            if (s.len == 0) return 0;
            return s[s.len / 2];
        }

        pub fn stdDev(self: *const Self) f64 {
            const s = self.samples();
            if (s.len <= 1) return 0.0;
            const m = self.mean();
            var total: f64 = 0.0;
            for (s) |value| {
                const t = @as(f64, @floatFromInt(value)) - m;
                total += t * t;
            }
            const variance = total / @as(f64, @floatFromInt(s.len - 1));
            return std.math.sqrt(variance);
        }
    };
}

pub fn runWithAllocator(allocator: std.mem.Allocator, func: TypeOfBenchmark(void), comptime opts: Opts) !Result(opts.samples) {
    const sample_count = opts.samples;
    const run_time = opts.runtime * std.time.ns_per_ms;

    var total: u64 = 0;
    var iterations: usize = 0;
    var timer = try std.time.Timer.start();
    var samples = std.mem.zeroes([sample_count]u64);

    while (true) {
        iterations += 1;
        timer.reset();
        try func(allocator, &timer);
        const elapsed = timer.lap();

        total += elapsed;
        samples[@mod(iterations, sample_count)] = elapsed;
        if (total > run_time) break;
    }

    std.sort.heap(u64, samples[0..@min(sample_count, iterations)], {}, resultLessThan);

    return .{
        .total = total,
        ._samples = samples,
        .iterations = iterations,
        .requested_bytes = 0,
    };
}

pub fn run(func: TypeOfBenchmark(void), comptime opts: Opts) !Result(opts.samples) {
    return runC({}, func, opts);
}

pub fn runC(context: anytype, func: TypeOfBenchmark(@TypeOf(context)), comptime opts: Opts) !Result(opts.samples) {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .enable_memory_limit = true }){};
    const allocator = gpa.allocator();

    const sample_count = opts.samples;
    const run_time = opts.runtime * std.time.ns_per_ms;

    var total: u64 = 0;
    var iterations: usize = 0;
    var timer = try Timer.start();
    var samples = std.mem.zeroes([sample_count]u64);

    while (true) {
        iterations += 1;
        timer.reset();

        if (@TypeOf(context) == void) {
            try func(allocator, &timer);
        } else {
            try func(context, allocator, &timer);
        }
        const elapsed = timer.lap();

        total += elapsed;
        samples[@mod(iterations, sample_count)] = elapsed;
        if (total > run_time) break;
    }

    std.sort.heap(u64, samples[0..@min(sample_count, iterations)], {}, resultLessThan);

    return .{
        .total = total,
        ._samples = samples,
        .iterations = iterations,
        .requested_bytes = gpa.total_requested_bytes,
    };
}

fn TypeOfBenchmark(comptime C: type) type {
    return switch (C) {
        void => *const fn (Allocator, *Timer) anyerror!void,
        else => *const fn (C, Allocator, *Timer) anyerror!void,
    };
}

fn resultLessThan(context: void, lhs: u64, rhs: u64) bool {
    _ = context;
    return lhs < rhs;
}

pub fn benchStdArena(allocator: Allocator, _: *Timer) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const a = arena.allocator();

    var i: usize = 0;
    while (i < 10000) : (i += 1) {
        const buf = try a.alloc(u8, 256);
        @memset(buf, 0xAA);
        _ = arena.reset(.free_all);
    }
}

pub fn benchMutexStd(_: Allocator, _: *Timer) !void {
    const NUM_THREADS = 4;
    const ITERATIONS = 100_000;

    var mtx = std.Thread.Mutex{};
    var counter: i32 = 0;
    var threads: [NUM_THREADS]std.Thread = undefined;

    for (threads, 0..NUM_THREADS) |_, i| {
        threads[i] = try std.Thread.spawn(.{}, struct {
            fn run(conter: *i32, mx: *std.Thread.Mutex) void {
                for (0..ITERATIONS) |_| {
                    mx.lock();
                    conter.* += 1;
                    mx.unlock();
                }
            }
        }.run, .{ &counter, &mtx });
    }

    for (threads) |t| t.join();
}

pub fn benchMutexFutex(_: Allocator, _: *Timer) !void {
    const NUM_THREADS = 4;
    const ITERATIONS = 100_000;

    var mtx = stdx.Mutex{};
    var counter: i32 = 0;
    var threads: [NUM_THREADS]std.Thread = undefined;

    for (threads, 0..NUM_THREADS) |_, i| {
        threads[i] = try std.Thread.spawn(.{}, struct {
            fn run(conter: *i32, mx: *stdx.Mutex) !void {
                for (0..ITERATIONS) |_| {
                    try mx.lock();
                    defer mx.unlock();
                    conter.* += 1;
                }
            }
        }.run, .{ &counter, &mtx });
    }

    for (threads) |t| t.join();
}

pub fn benchStdxArena(allocator: Allocator, _: *Timer) !void {
    var arena = stdx.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const a = arena.allocator();

    var i: usize = 0;
    while (i < 10000) : (i += 1) {
        const buf = try a.alloc(u8, 256);
        @memset(buf, 0xBB);
        arena.reset();
    }
}

pub fn benchManySmallStd(a: Allocator, _: *Timer) !void {
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();

    const alloc = arena.allocator();
    var i: usize = 0;
    while (i < 100_000) : (i += 1) {
        _ = try alloc.alloc(u8, 8);
    }
}

pub fn benchManySmallStdx(a: Allocator, _: *Timer) !void {
    var arena = stdx.ArenaAllocator.init(a);
    defer arena.deinit();

    const alloc = arena.allocator();
    var i: usize = 0;
    while (i < 100_000) : (i += 1) {
        _ = try alloc.alloc(u8, 8);
    }
}

pub fn benchBigStd(a: Allocator, _: *Timer) !void {
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();

    const alloc = arena.allocator();
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        const buf = try alloc.alloc(u8, 1024 * 1024); // 1 MB
        @memset(buf, 0x11);
        _ = arena.reset(.free_all);
    }
}

pub fn benchStdxRetain(a: Allocator, _: *Timer) !void {
    var arena = stdx.ArenaAllocator.init(a);
    defer arena.deinit();

    const alloc = arena.allocator();
    var i: usize = 0;
    while (i < 10_000) : (i += 1) {
        const buf = try alloc.alloc(u8, 256);
        @memset(buf, 0x33);
        _ = arena.resetWithMode(.retain_capacity);
    }
}

pub fn benchBigStdx(a: Allocator, _: *Timer) !void {
    var arena = stdx.ArenaAllocator.init(a);
    defer arena.deinit();

    const alloc = arena.allocator();
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        const buf = try alloc.alloc(u8, 1024 * 1024);
        @memset(buf, 0x22);
        arena.reset();
    }
}

pub fn benchMPMC(allocator: Allocator, _: *Timer) !void {
    var q = try stdx.MPMCQueue(u64).init(allocator, 1024);
    defer q.deinit();

    var i: u64 = 0;
    while (i < 1000) : (i += 1) {
        q.enqueue(i);
        _ = q.dequeue();
    }
}

pub fn benchRing(allocator: Allocator, _: *Timer) !void {
    var rb = try stdx.LockFreeRingBuffer(u64, 1024).init(allocator);
    defer rb.deinit();

    var i: u64 = 0;
    var tmp: u64 = 0;
    while (i < 1000) : (i += 1) {
        rb.write(i);
        _ = rb.waitAndTryRead(&tmp, rb.currentTail());
    }
}

const RingWorkerArgs = struct {
    rb: *stdx.LockFreeRingBuffer(u64, 1024),
    ops: u64,
    done: *std.atomic.Value(u32),
};

fn mpmcWorker(q: *stdx.MPMCQueue(u64), ops: u64, done: *std.atomic.Value(u32)) void {
    var j: u64 = 0;
    while (j < ops) : (j += 1) {
        q.enqueue(j);
        _ = q.dequeue();
    }
    _ = done.fetchAdd(1, .acq_rel);
}

fn ringWorker(rb: *stdx.LockFreeRingBuffer(u64, 1024), ops: u64, done: *std.atomic.Value(u32)) void {
    var j: u64 = 0;
    var tmp: u64 = 0;
    while (j < ops) : (j += 1) {
        rb.write(j);
        _ = rb.tryRead(&tmp, rb.currentTail());
    }
    _ = done.fetchAdd(1, .acq_rel);
}

pub fn benchMPMC_MT(allocator: Allocator, _: *Timer) !void {
    const Thread = std.Thread;
    const THREADS = 4;
    const OPS = 10_000;

    var q = try stdx.MPMCQueue(u64).init(allocator, 1024);
    defer q.deinit();

    var done: std.atomic.Value(u32) = std.atomic.Value(u32).init(0);
    var threads: [THREADS]Thread = undefined;

    for (threads, 0..THREADS) |_, i| {
        threads[i] = try std.Thread.spawn(.{}, mpmcWorker, .{ &q, OPS, &done });
    }

    while (done.load(.acquire) != THREADS) {
        std.Thread.sleep(std.time.ns_per_ms);
    }

    for (threads) |t| t.join();
}

pub fn benchRing_MT(allocator: Allocator, _: *Timer) !void {
    var rb = try stdx.LockFreeRingBuffer(u64, 1024).init(allocator);
    const THREADS = 4;

    defer rb.deinit();
    const OPS = 10_000;

    var done: std.atomic.Value(u32) = std.atomic.Value(u32).init(0);
    var threads: [THREADS]std.Thread = undefined;

    for (threads, 0..THREADS) |_, i| {
        threads[i] = try std.Thread.spawn(.{}, ringWorker, .{ &rb, OPS, &done });
    }

    while (done.load(.acquire) != THREADS) {
        std.Thread.sleep(std.time.ns_per_ms);
    }

    for (threads) |t| t.join();
}

pub fn benchTcsManySmall(a: std.mem.Allocator, _: *std.time.Timer) !void {
    var i: usize = 0;
    while (i < 100_000) : (i += 1) {
        const buf = try a.alloc(u8, 8);
        @memset(buf, 0xAA);
        a.free(buf);
    }
}

pub fn benchSmpManySmall(a: std.mem.Allocator, _: *std.time.Timer) !void {
    var i: usize = 0;
    while (i < 100_000) : (i += 1) {
        const buf = try a.alloc(u8, 8);
        @memset(buf, 0xBB);
        a.free(buf);
    }
}

pub fn benchTcsBig(a: std.mem.Allocator, _: *std.time.Timer) !void {
    var i: usize = 0;
    while (i < 1_000) : (i += 1) {
        const buf = try a.alloc(u8, 1024 * 1024);
        @memset(buf, 0xCC);
        a.free(buf);
    }
}

pub fn benchSmpBig(a: std.mem.Allocator, _: *std.time.Timer) !void {
    var i: usize = 0;
    while (i < 1_000) : (i += 1) {
        const buf = try a.alloc(u8, 1024 * 1024);
        @memset(buf, 0xDD);
        a.free(buf);
    }
}

const SmallData = extern struct {
    data: [8]u8 align(8) = [_]u8{0xAA} ** 8,
};

const MediumData = extern struct {
    data: [64]u8 align(8) = [_]u8{0xBB} ** 64,
};

const LargeData = extern struct {
    data: [1024]u8 align(8) = [_]u8{0xCC} ** 1024,
};

pub fn benchHashInlineSmall(_: Allocator, _: *Timer) !void {
    const data = SmallData{};
    _ = stdx.hash.hash_inline(data);
}

pub fn benchHashInlineMedium(_: Allocator, _: *Timer) !void {
    const data = MediumData{};
    _ = stdx.hash.hash_inline(data);
}

pub fn benchHashInlineLarge(_: Allocator, _: *Timer) !void {
    const data = LargeData{};
    _ = stdx.hash.hash_inline(data);
}

pub fn benchWhashSmall(_: Allocator, _: *Timer) !void {
    const data = SmallData{};
    _ = stdx.hash._whash(std.mem.asBytes(&data), 0);
}

pub fn benchWhashMedium(_: Allocator, _: *Timer) !void {
    const data = MediumData{};
    _ = stdx.hash._whash(std.mem.asBytes(&data), 0);
}

pub fn benchWhashLarge(_: Allocator, _: *Timer) !void {
    const data = LargeData{};
    _ = stdx.hash._whash(std.mem.asBytes(&data), 0);
}

pub fn benchWhashStdLarge(_: Allocator, _: *Timer) !void {
    const data = LargeData{};
    _ = std.hash.Wyhash.hash(0, std.mem.asBytes(&data));
}

pub fn benchInlineU64(_: Allocator, _: *Timer) !void {
    _ = stdx.hash.hash_inline(key);
}

pub fn benchWhashU64(_: Allocator, _: *Timer) !void {
    _ = stdx.hash._wx64(key);
}

pub fn benchWhashStdU64(_: Allocator, _: *Timer) !void {
    _ = std.hash.Wyhash.hash(0, std.mem.asBytes(&key));
}

pub fn benchXXhashStdU64(_: Allocator, _: *Timer) !void {
    _ = std.hash.XxHash64.hash(0, std.mem.asBytes(&key));
}

pub fn benchMurMurU64(_: Allocator, _: *Timer) !void {
    _ = stdx.hash.murmur64(key);
}

pub fn main() !void {
    const opts = Opts{ .samples = 1000, .runtime = 1000 };
    const r1 = try run(benchMPMC, opts);
    r1.print("MPMCQueue");

    const r2 = try run(benchRing, opts);
    r2.print("LockFreeRingBuffer");

    const r3 = try run(benchMPMC_MT, opts);
    r3.print("MPMCQueue concurrent");

    const r4 = try run(benchRing_MT, opts);
    r4.print("LockFreeRingBuffer concurrent");

    const r_std = try run(benchMutexStd, opts);
    r_std.print("std.Thread.Mutex");

    const r_futex = try run(benchMutexFutex, opts);
    r_futex.print("Futex Mutex");

    // (8 byte)
    const inlsmll = try run(benchHashInlineSmall, opts);
    inlsmll.print("hash_inline (8 bytes)");
    const whsmll = try run(benchWhashSmall, opts);
    whsmll.print("_whash (8 bytes)");

    // (64 bytes)
    const inlmd = try run(benchHashInlineMedium, opts);
    inlmd.print("hash_inline (64 bytes)");
    const whmd = try run(benchWhashMedium, opts);
    whmd.print("_whash (64 bytes)");

    // (1 Кb)
    const r5 = try run(benchHashInlineLarge, opts);
    r5.print("hash_inline (1 KB)");
    const r6 = try run(benchWhashLarge, opts);
    r6.print("_whash (1 KB)");
    const stwh = try run(benchWhashStdLarge, opts);
    stwh.print("std_whash (1 KB)");

    const r7 = try run(benchInlineU64, opts);
    r7.print("hash_inline (u64)");
    const r8 = try run(benchWhashU64, opts);
    r8.print("_whash (u64)");
    const r9 = try run(benchWhashStdU64, opts);
    r9.print("std_whash (u64)");
    const r10 = try run(benchMurMurU64, opts);
    r10.print("murmur(u64)");
    const r11 = try run(benchXXhashStdU64, opts);
    r11.print("xxhash(u64)");
}
