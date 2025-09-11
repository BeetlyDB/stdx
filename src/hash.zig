const std = @import("std");
const lib = @import("lib.zig");
const assert = std.debug.assert;

pub inline fn hash_inline(value: anytype) u64 {
    comptime {
        assert(lib.no_padding(@TypeOf(value)));
        assert(std.meta.hasUniqueRepresentation(@TypeOf(value)));
    }
    return low_level_hash(0, switch (@typeInfo(@TypeOf(value))) {
        .Struct, .Int => std.mem.asBytes(&value),
        else => @compileError("unsupported hashing for " ++ @typeName(@TypeOf(value))),
    });
}

/// Inline version of Google Abseil "LowLevelHash" (inspired by wyhash).
/// https://github.com/abseil/abseil-cpp/blob/master/absl/hash/internal/low_level_hash.cc
inline fn low_level_hash(seed: u64, input: anytype) u64 {
    const salt = [_]u64{
        0xa0761d6478bd642f,
        0xe7037ed1a0b428db,
        0x8ebc6af09c88c6e3,
        0x589965cc75374cc3,
        0x1d8e4e27c47d124f,
    };

    var in: []const u8 = input;
    var state = seed ^ salt[0];
    const starting_len = input.len;

    if (in.len > 64) {
        var dup = [_]u64{ state, state };
        defer state = dup[0] ^ dup[1];

        while (in.len > 64) : (in = in[64..]) {
            for (@as([2][4]u64, @bitCast(in[0..64].*)), 0..) |chunk, i| {
                const mix1 = @as(u128, chunk[0] ^ salt[(i * 2) + 1]) *% (chunk[1] ^ dup[i]);
                const mix2 = @as(u128, chunk[2] ^ salt[(i * 2) + 2]) *% (chunk[3] ^ dup[i]);
                dup[i] = @as(u64, @truncate(mix1 ^ (mix1 >> 64)));
                dup[i] ^= @as(u64, @truncate(mix2 ^ (mix2 >> 64)));
            }
        }
    }

    while (in.len > 16) : (in = in[16..]) {
        const chunk = @as([2]u64, @bitCast(in[0..16].*));
        const mixed = @as(u128, chunk[0] ^ salt[1]) *% (chunk[1] ^ state);
        state = @as(u64, @truncate(mixed ^ (mixed >> 64)));
    }

    var chunk = std.mem.zeroes([2]u64);
    if (in.len > 8) {
        chunk[0] = @as(u64, @bitCast(in[0..8].*));
        chunk[1] = @as(u64, @bitCast(in[in.len - 8 ..][0..8].*));
    } else if (in.len > 3) {
        chunk[0] = @as(u32, @bitCast(in[0..4].*));
        chunk[1] = @as(u32, @bitCast(in[in.len - 4 ..][0..4].*));
    } else if (in.len > 0) {
        chunk[0] = (@as(u64, in[0]) << 16) | (@as(u64, in[in.len / 2]) << 8) | in[in.len - 1];
    }

    var mixed = @as(u128, chunk[0] ^ salt[1]) *% (chunk[1] ^ state);
    mixed = @as(u64, @truncate(mixed ^ (mixed >> 64)));
    mixed *%= (@as(u64, starting_len) ^ salt[1]);
    return @as(u64, @truncate(mixed ^ (mixed >> 64)));
}
