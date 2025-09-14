const std = @import("std");

pub const AtomicCounter = struct {
    value: std.atomic.Value(u64),

    pub fn init(initial: u64) AtomicCounter {
        return .{ .value = std.atomic.Value(u64).init(initial) };
    }

    pub fn increment(self: *AtomicCounter) u64 {
        return self.value.fetchAdd(1, .acq_rel) + 1;
    }

    pub fn decrement(self: *AtomicCounter) u64 {
        return self.value.fetchSub(1, .acq_rel) - 1;
    }

    pub fn get(self: *AtomicCounter) u64 {
        return self.value.load(.acq_rel);
    }
};

pub const SpinLock = extern struct {
    locked: std.atomic.Value(u32) = .{ .raw = 0 },

    pub fn init(self: *SpinLock) void {
        self.* = .{};
    }

    pub fn deinit(self: *SpinLock) void {
        self.* = undefined;
    }

    pub fn acquire(self: *SpinLock) void {
        while (self.locked.fetchOr(1, .acquire) & 1 > 0) {
            while (true) {
                std.atomic.spinLoopHint();
                if (self.locked.load(.monotonic) == 0) break;
            }
        }
    }

    pub fn release(self: *SpinLock) void {
        self.locked.store(0, .release);
    }
};
