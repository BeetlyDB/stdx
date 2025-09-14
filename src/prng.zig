const std = @import("std");
const assert = std.debug.assert;

pub const SplitMix64Runtime = struct {
    state: u64,
    pub inline fn from_seed(seed: u64) SplitMix64Runtime {
        return SplitMix64Runtime{ .state = seed };
    }

    pub inline fn next(self: *SplitMix64Runtime) u64 {
        self.state +%= 0x9e3779b97f4a7c15;
        var z = self.state;
        z = (z ^ (z >> 30)) *% 0xbf58476d1ce4e5b9;
        z = (z ^ (z >> 27)) *% 0x94d049bb133111eb;
        return z ^ (z >> 31);
    }

    pub inline fn next_u32(self: *SplitMix64Runtime) u32 {
        return @truncate(self.next());
    }

    pub inline fn next_u16(self: *SplitMix64Runtime) u16 {
        return @truncate(self.next());
    }
};

// returns random number, modifies the seed.
pub inline fn rngSplitMix64(seed: *u64) u64 {
    seed.* = seed.* +% 0x9E3779B97F4A7C15;
    var z = seed.*;
    z = (z ^ (z >> 30)) *% 0xBF58476D1CE4E5B9;
    z = (z ^ (z >> 27)) *% 0x94D049BB133111EB;
    return z ^ (z >> 31);
}

pub const SplitMix64 = struct {
    state: u64,

    pub inline fn from_seed(seed: u64) SplitMix64 {
        return SplitMix64{ .state = seed };
    }

    pub inline fn next(self: SplitMix64) struct { value: u64, next_state: SplitMix64 } {
        const state = self.state +% 0x9e3779b97f4a7c15;
        var z = state;
        z = (z ^ (z >> 30)) *% 0xbf58476d1ce4e5b9;
        z = (z ^ (z >> 27)) *% 0x94d049bb133111eb;
        const value = z ^ (z >> 31);
        return .{ .value = value, .next_state = SplitMix64{ .state = state } };
    }

    pub inline fn next_u32(self: SplitMix64) struct { value: u32, next_state: SplitMix64 } {
        const result = self.next();
        return .{ .value = @truncate(result.value), .next_state = result.next_state };
    }

    pub inline fn next_u16(self: SplitMix64) struct { value: u16, next_state: SplitMix64 } {
        const result = self.next();
        return .{ .value = @truncate(result.value), .next_state = result.next_state };
    }
};

pub fn XorShift32(comptime Bits: comptime_int) type {
    comptime {
        assert(Bits == 16 or Bits == 32);
    }
    return struct {
        state: u32,
        const Self = @This();

        pub fn init(seed: u32) Self {
            var x = Self{ .state = seed };
            _ = x.next();
            _ = x.next();
            _ = x.next();
            return x;
        }

        pub fn next(self: *Self) u32 {
            self.state ^= self.state << 13;
            self.state ^= self.state >> 17;
            self.state ^= self.state << 5;
            return self.state;
        }

        pub fn nextBounded(self: *Self, comptime T: type) T {
            const result = self.next();
            return @truncate(if (Bits == 16) @as(u16, @truncate(result)) else result);
        }
    };
}
