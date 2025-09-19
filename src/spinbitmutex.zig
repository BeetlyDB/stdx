const std = @import("std");

/// /// SpinBitMutex - a spinlock implementation using bit flags.
/// Stores the lock state and optional metadata (e.g. owner ID) in a single value.
/// The least significant bit (bit 0) is used for the lock state (0 = unlocked, 1 = locked).
/// The following bits (1–10) can be used to store additional data (e.g. a thread ID).
pub const SpinBitMutex = struct {
    state: std.atomic.Value(u32),

    pub inline fn init() SpinBitMutex {
        return SpinBitMutex{
            .state = std.atomic.Value(u32).init(0),
        };
    }

    pub inline fn lock(self: *SpinBitMutex, owner_id: u16) void {
        const new_state = 1 | (@as(u32, owner_id) << 1);

        while (true) {
            const old_state = self.state.cmpxchgStrong(0, new_state, .acquire, .monotonic);
            if (old_state == null) {
                return;
            }
            std.atomic.spinLoopHint();
        }
    }

    pub inline fn tryLock(self: *SpinBitMutex, owner_id: u16) bool {
        const new_state = 1 | (@as(u32, owner_id) << 1);
        return self.state.cmpxchgStrong(0, new_state, .acquire, .monotonic) == null;
    }

    pub inline fn unlock(self: *SpinBitMutex, owner_id: u16) void {
        const expected_state = 1 | (@as(u32, owner_id) << 1);
        const old_state = self.state.cmpxchgStrong(expected_state, 0, .release, .monotonic);
        if (old_state != null) {
            @panic("SpinBitMutex: unlock by non-owner or not locked");
        }
    }

    pub inline fn getOwnerId(self: *SpinBitMutex) ?u16 {
        const current = self.state.load(.monotonic);
        if ((current & 1) == 0) return null;
        return @truncate(current >> 1);
    }
};

test "SpinBitMutex" {
    const expect = std.testing.expect;
    var mutex = SpinBitMutex.init();

    // single-thread tests
    mutex.lock(42);
    try expect(mutex.getOwnerId() == 42);
    mutex.unlock(42);
    try expect(mutex.getOwnerId() == null);

    try expect(mutex.tryLock(43) == true);
    try expect(mutex.getOwnerId() == 43);
    try expect(mutex.tryLock(44) == false); // busy
    mutex.unlock(43);

    // multithread tests
    const Thread = std.Thread;

    var thread1_done = std.atomic.Value(bool).init(false);
    var thread2_done = std.atomic.Value(bool).init(false);

    const thread1 = try Thread.spawn(.{}, struct {
        fn run(m: *SpinBitMutex, done: *std.atomic.Value(bool)) void {
            m.lock(1);
            std.Thread.sleep(100_000_000); // 100ms
            m.unlock(1);
            done.store(true, .release);
        }
    }.run, .{ &mutex, &thread1_done });

    const thread2 = try Thread.spawn(.{}, struct {
        fn run(m: *SpinBitMutex, done: *std.atomic.Value(bool)) void {
            m.lock(2);
            m.unlock(2);
            done.store(true, .release);
        }
    }.run, .{ &mutex, &thread2_done });

    thread1.join();
    thread2.join();

    try expect(thread1_done.load(.acquire));
    try expect(thread2_done.load(.acquire));
}
