const std = @import("std");
const builtin = @import("builtin");
const Futex = std.Thread.Futex;
const assert = @import("lib.zig").assert;

pub const Mutex = struct {
    comptime {
        if (builtin.os.tag != .linux) {
            @panic("this implementation only for linux");
        }
    }
    _: void align(std.atomic.cache_line) = {},
    state: std.atomic.Value(u32) align(std.atomic.cache_line) = std.atomic.Value(u32).init(UNLOCKED),

    const unlocked: u32 = 0b00;
    const locked: u32 = 0b01;
    const contended: u32 = 0b11; // locked + has waiters
    //
    const UNLOCKED = unlocked;
    const LOCKED = locked;
    const CONTENDED = contended;

    inline fn wake(self: *Mutex) void {
        std.Thread.Futex.wake(&self.state, 1);
    }

    /// Try to acquire the lock without blocking
    pub inline fn trylock(self: *Mutex) bool {
        @branchHint(.likely);
        // On x86  `lock bts` - smaller instruction, better for inlining
        if (comptime builtin.target.cpu.arch.isX86()) {
            return self.state.bitSet(@ctz(LOCKED), .acquire) == 0;
        }

        return self.state.cmpxchgWeak(UNLOCKED, LOCKED, .acquire, .monotonic) == null;
    }

    pub inline fn lock(self: *Mutex) void {
        if (!self.trylock()) {
            self.lockSlow();
        }
    }

    pub inline fn unlock(self: *Mutex) void {
        // Release barrier ensures critical section happens before unlock
        switch (self.state.swap(UNLOCKED, .release)) {
            UNLOCKED => unreachable,
            LOCKED => {},
            CONTENDED => self.wake(),
            else => unreachable,
        }
    }

    fn lockSlow(self: *Mutex) void {
        @branchHint(.cold);
        var spin: u8 = 50;
        while (spin > 0) : (spin -= 1) {
            std.atomic.spinLoopHint();
            switch (self.state.load(.monotonic)) {
                UNLOCKED => if (self.trylock()) return,
                LOCKED => continue,
                CONTENDED => break,
                else => unreachable,
            }
        }
        if (self.state.load(.monotonic) == contended) {
            self.wait(contended);
        }

        // Acquire with `contended` so next unlocker wakes another thread
        while (self.state.swap(contended, .acquire) != unlocked) {
            self.wait(contended);
        }
    }
    inline fn wait(self: *Mutex, expect: u32) void {
        std.Thread.Futex.wait(&self.state, expect);
    }
};
