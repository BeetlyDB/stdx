const std = @import("std");
const builtin = @import("builtin");
const Futex = std.Thread.Futex;
const assert = std.debug.assert;

inline fn waitBitset(
    ptr: *const std.atomic.Value(usize),
    expect: usize,
    bitset: usize,
    timeout: ?u64,
) !void {
    var ts: std.os.linux.timespec = undefined;
    const tsptr = if (timeout) |t| blk: {
        ts.sec = @intCast(t / std.time.ns_per_s);
        ts.nsec = @intCast(t % std.time.ns_per_s);
        break :blk &ts;
    } else null;

    const futex_size: std.os.linux.FUTEX2_SIZE = blk: {
        if (@bitSizeOf(usize) == 64) break :blk .U64;
        break :blk .U32;
    };

    const rc = std.os.linux.futex2_wait(
        @ptrCast(&ptr.raw),
        expect,
        bitset,
        .{ .private = true, .size = futex_size },
        tsptr,
        .MONOTONIC,
    );
    switch (std.os.linux.E.init(rc)) {
        .SUCCESS => {},
        .INTR => {},
        .TIMEDOUT => return error.Timeout,
        .AGAIN => {},
        else => unreachable,
    }
}

inline fn wakeBitset(ptr: *const std.atomic.Value(usize), max: usize, bitset: usize) void {
    const futex_size: std.os.linux.FUTEX2_SIZE =
        if (@bitSizeOf(usize) == 64) .U64 else .U32;

    _ = std.os.linux.futex2_wake(
        @ptrCast(&ptr.raw),
        bitset,
        @min(max, std.math.maxInt(i32)),
        .{ .private = true, .size = futex_size },
    );
}

inline fn wait(ptr: *const std.atomic.Value(usize), expect: u32) !void {
    const rc = std.os.linux.futex_3arg(
        @ptrCast(&ptr.raw),
        .{ .cmd = .WAIT, .private = true },
        expect,
    );
    switch (std.os.linux.E.init(rc)) {
        .SUCCESS => {}, // notified by `wake()`
        .INTR => {}, // spurious wakeup
        .AGAIN => {}, // ptr.* != expect
        .INVAL => {}, // possibly timeout overflow
        .FAULT => unreachable, // ptr was invalid
        else => unreachable,
    }
}

inline fn waitTime(ptr: *const std.atomic.Value(usize), expect: u32, timeout: ?u64) !void {
    var ts: std.os.linux.timespec = undefined;
    if (timeout) |timeout_ns| {
        ts.sec = @as(@TypeOf(ts.sec), @intCast(timeout_ns / std.time.ns_per_s));
        ts.nsec = @as(@TypeOf(ts.nsec), @intCast(timeout_ns % std.time.ns_per_s));
    }

    const rc = std.os.linux.futex_4arg(
        @ptrCast(&ptr.raw),
        .{ .cmd = .WAIT, .private = true },
        expect,
        if (timeout != null) &ts else null,
    );
    switch (std.os.linux.E.init(rc)) {
        .SUCCESS => {}, // notified by `wake()`
        .INTR => {}, // spurious wakeup
        .TIMEDOUT => {
            assert(timeout != null);
            return error.Timeout;
        },

        .AGAIN => {}, // ptr.* != expect
        .INVAL => {}, // possibly timeout overflow
        .FAULT => unreachable, // ptr was invalid
        else => unreachable,
    }
}

inline fn timedWait(ptr: *const std.atomic.Value(usize), expect: u32, timeout_ns: u64) error{Timeout}!void {
    // Avoid calling into the OS for no-op timeouts.
    if (timeout_ns == 0) {
        if (ptr.load(.seq_cst) != expect) return;
        return error.Timeout;
    }

    return waitTime(ptr, expect, timeout_ns);
}

inline fn wake(ptr: *const std.atomic.Value(usize), max_waiters: u32) void {
    const rc = std.os.linux.futex_3arg(
        &ptr.raw,
        .{ .cmd = .WAKE, .private = true },
        @min(max_waiters, std.math.maxInt(i32)),
    );

    switch (std.os.linux.E.init(rc)) {
        .SUCCESS => {}, // successful wake up
        .INVAL => {}, // invalid futex_wait() on ptr done elsewhere
        .FAULT => {}, // pointer became invalid while doing the wake
        else => unreachable,
    }
}

const DoublyLinkedListType = @import("doublelinkedlist.zig").DoublyLinkedListType;

pub const Mutex = struct {
    state: std.atomic.Value(usize) = std.atomic.Value(usize).init(UNLOCKED),
    const UNLOCKED: usize = 0;
    const LOCKED: usize = 1;
    const PARKED: usize = 2;
    const WAKING: usize = 1 << 8;
    const WAITING: usize = ~@as(usize, (1 << 9) - 1);
    const RETRY: usize = 0;
    const HANDOFF: usize = 1;
    const TIMEOUT: usize = 2;
    const STACK_LOCKED: usize = 4;

    const Waiter = struct {
        prev: ?*Waiter align(@max(@alignOf(usize), ~WAITING + 1)),
        next: ?*Waiter,
        tail: ?*Waiter,
    };

    inline fn tryAcquirex86(self: *Mutex) bool {
        const locked_bit = @ctz(LOCKED);
        return self.state.bitSet(locked_bit, .acquire) == 0;
    }

    pub inline fn trylock(self: *Mutex) bool {
        if (comptime builtin.target.cpu.arch.isX86()) {
            return self.tryAcquirex86();
        }
        if (self.state.raw & LOCKED != 0) return false;
        return @cmpxchgWeak(usize, &self.state.raw, self.state.raw, self.state.raw | LOCKED, .acquire, .acquire) == null;
    }

    inline fn trylockHard(self: *Mutex) bool {
        if (comptime builtin.target.cpu.arch.isX86()) {
            return self.tryAcquirex86();
        }
        if (self.state.raw & LOCKED != 0) return false;
        return @cmpxchgStrong(usize, &self.state.raw, self.state.raw, self.state.raw | LOCKED, .acquire, .acquire) == null;
    }

    pub inline fn lock(self: *Mutex) !void {
        if (!self.trylock()) {
            try self.acquireSlow(null);
        }
    }

    pub fn trylockFor(self: *Mutex, duration: u64) error{TimedOut}!void {
        return self.trylockUntil(std.time.timestamp() + duration);
    }

    pub fn unlock(self: *Mutex) void {
        self.release();
    }

    pub fn trylockUntil(self: *Mutex, deadline: u64) error{TimedOut}!void {
        return self.acquireInner(deadline);
    }

    inline fn acquireInner(self: *Mutex, deadline: ?u64) error{TimedOut}!void {
        if (self.trylock()) return;
        try self.acquireSlow(deadline);
    }

    inline fn release(self: *Mutex) void {
        if (@atomicRmw(usize, &self.state.raw, .Xchg, UNLOCKED, .release) != LOCKED) {
            self.releaseSlow();
        }
    }
    inline fn acquireSlow(self: *Mutex, deadline: ?u64) !void {
        var waiter: Waiter = .{
            .tail = null,
            .prev = null,
            .next = null,
        };

        var spin_count: usize = 0;
        const max_spins = 20;
        var state = self.state.load(.acquire);

        while (true) {
            if (state & LOCKED == 0) {
                if (self.trylock()) return;
                try std.Thread.yield();
                state = self.state.load(.acquire);
                continue;
            }

            const head: ?*Waiter = @ptrFromInt(state & WAITING);
            if (head == null) {
                spin_count +%= 1;
                try std.Thread.yield();
                std.atomic.spinLoopHint();
                state = self.state.load(.acquire);
                continue;
            }

            if (spin_count < max_spins) {
                spin_count += 1;
                try std.Thread.yield();
                std.atomic.spinLoopHint();
                state = self.state.load(.acquire);
                continue;
            }

            if ((state & PARKED) == 0) {
                if (@cmpxchgWeak(usize, &self.state.raw, state, state | PARKED, .seq_cst, .monotonic)) |updated| {
                    state = updated;
                    continue;
                }
            }

            waiter.prev = null;
            waiter.next = head;
            waiter.tail = if (head == null) &waiter else null;

            const new_state = (state & ~WAITING) | @intFromPtr(&waiter);
            state = @cmpxchgWeak(usize, &self.state.raw, state, new_state, .release, .monotonic) orelse blk: {
                const bitset = LOCKED | PARKED;
                if (deadline) |d| {
                    const timeout = d - @as(u64, @intCast(std.time.timestamp()));
                    if (timeout <= 0) {
                        return error.TimedOut;
                    }

                    try waitBitset(&self.state, state, bitset, timeout);
                } else {
                    try waitBitset(&self.state, state, bitset, null);
                }
                spin_count = 0;
                break :blk self.state.load(.acquire);
            };
        }
    }

    inline fn releaseSlow(self: *Mutex) void {
        var state = self.state.load(.acquire);
        while (true) {
            if ((state & (PARKED | WAITING)) == 0 or (state & WAKING) != 0) {
                if ((state & PARKED) != 0) {
                    const new_state = state & ~(PARKED | WAKING);
                    if (@cmpxchgWeak(usize, &self.state.raw, state, new_state, .release, .monotonic)) |updated| {
                        state = updated;
                        continue;
                    }
                }
                return;
            }

            if (@cmpxchgStrong(usize, &self.state.raw, state, state | WAKING, .acquire, .monotonic)) |updated| {
                state = updated;
                continue;
            }

            const head: ?*Waiter = @ptrFromInt(state & WAITING);
            if (head == null) {
                const new_state = state & ~(PARKED | WAKING);
                if (@cmpxchgStrong(usize, &self.state.raw, state, new_state, .release, .monotonic)) |updated| {
                    state = updated;
                    continue;
                }
                return;
            }

            const next = head.?.next;
            const tail = head.?.tail;
            const new_state = (state & ~WAITING) | @intFromPtr(next);
            if (next) |n| {
                n.tail = tail;
            }
            if (@cmpxchgStrong(usize, &self.state.raw, state, new_state & ~WAKING, .release, .monotonic)) |updated| {
                state = updated;
                continue;
            }
            const bitset = LOCKED;
            wakeBitset(&self.state, 1, bitset);
            return;
        }
    }
};

test "Mutex: basic lock and unlock" {
    var mutex = Mutex{};
    try std.testing.expectEqual(mutex.state.raw, Mutex.UNLOCKED);
    try mutex.lock();
    try std.testing.expectEqual(mutex.state.raw & Mutex.LOCKED, Mutex.LOCKED);
    mutex.unlock();
    try std.testing.expectEqual(mutex.state.raw, Mutex.UNLOCKED);
}

test "Mutex: trylock" {
    var mutex = Mutex{};
    try std.testing.expect(mutex.trylock()); // Should succeed
    try std.testing.expectEqual(mutex.state.raw & Mutex.LOCKED, Mutex.LOCKED);
    try std.testing.expect(!mutex.trylock()); // Should fail
    mutex.unlock();
    try std.testing.expectEqual(mutex.state.raw, Mutex.UNLOCKED);
}

test "Mutex: concurrent access" {
    const Counter = struct {
        value: i32 = 0,
        mutex: Mutex = .{},
        fn increment(self: *@This()) !void {
            try self.mutex.lock();
            defer self.mutex.unlock();
            self.value += 1;
        }
    };

    var counter = Counter{};
    const num_threads = 10;
    const increments_per_thread = 1000;
    var threads: [num_threads]std.Thread = undefined;

    for (&threads) |*t| {
        t.* = try std.Thread.spawn(.{}, struct {
            fn run(c: *Counter) !void {
                for (0..increments_per_thread) |_| {
                    try c.increment();
                }
            }
        }.run, .{&counter});
    }

    for (threads) |t| t.join();
    try std.testing.expectEqual(counter.value, @as(i32, num_threads * increments_per_thread));
}

test "Mutex: benchmark" {
    const Counter = struct {
        value: i32 = 0,
        mutex: Mutex = .{},
        std_mutex: std.Thread.Mutex = .{},
        fn incrementCustom(self: *@This()) !void {
            try self.mutex.lock();
            defer self.mutex.unlock();
            self.value += 1;
        }
        fn incrementStd(self: *@This()) void {
            self.std_mutex.lock();
            defer self.std_mutex.unlock();
            self.value += 1;
        }
    };
    var counter = Counter{};
    const num_threads = 10;
    const increments_per_thread = 1000;

    var threads: [num_threads]std.Thread = undefined;
    const start = std.time.nanoTimestamp();
    for (&threads) |*t| {
        t.* = try std.Thread.spawn(.{}, struct {
            fn run(c: *Counter) !void {
                for (0..increments_per_thread) |_| {
                    try c.incrementCustom();
                }
            }
        }.run, .{&counter});
    }
    for (threads) |t| t.join();
    const end = std.time.nanoTimestamp();
    std.debug.print("Custom Mutex: {} ns\n", .{end - start});
    try std.testing.expectEqual(counter.value, @as(i32, num_threads * increments_per_thread));

    counter.value = 0;
    const start_std = std.time.nanoTimestamp();
    for (&threads) |*t| {
        t.* = try std.Thread.spawn(.{}, struct {
            fn run(c: *Counter) !void {
                for (0..increments_per_thread) |_| {
                    c.incrementStd();
                }
            }
        }.run, .{&counter});
    }
    for (threads) |t| t.join();
    const end_std = std.time.nanoTimestamp();
    std.debug.print("Std Mutex: {} ns\n", .{end_std - start_std});
    try std.testing.expectEqual(counter.value, @as(i32, num_threads * increments_per_thread));
}
