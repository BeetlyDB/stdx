//===================================================================================================================
// Copyright 2021, Hexops Contributors (given via the Git commit history).
//
// Licensed under the Apache License, Version 2.0 (see LICENSE-APACHE or http://www.apache.org/licenses/LICENSE-2.0)
// or the MIT license (see LICENSE-MIT or http://opensource.org/licenses/MIT), at
// your option. All files in the project without exclusions may not be copied,
// modified, or distributed except according to those terms.
// ===================================================================================================================
// MODIFIED VERSION OF //https://github.com/hexops/fastfilter | https://github.com/FastFilter/xor_singleheader
const std = @import("std");
const lib = @import("lib.zig");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const math = std.math;
const testing = std.testing;
const is_debug = builtin.mode == .Debug;
const prng = @import("prng.zig");
const hsh = @import("hash.zig");

const ArenaAllocator = @import("ArenaAllocator.zig").ArenaAllocator;

/// probability of success should always be > 0.5 so 100 iterations is highly unlikely
const max_iterations: usize = 100;

pub const Error = error{
    KeysLikelyNotUnique,
    OutOfMemory,
};

pub fn SliceIterator(comptime T: type) type {
    return struct {
        slice: []const T,
        i: usize = 0,

        const Self = @This();

        pub inline fn init(slice: []const T) Self {
            return .{ .slice = slice };
        }

        pub inline fn next(self: *Self) ?T {
            if (self.i >= self.slice.len) {
                self.i = 0;
                return null;
            }
            const v = self.slice[self.i];
            self.i += 1;
            return v;
        }

        pub inline fn len(self: *Self) usize {
            return self.slice.len;
        }
    };
}

/// A binary fuse filter. This is an extension of fuse filters:
///
/// Dietzfelbinger & Walzer's fuse filters, described in "Dense Peelable Random Uniform Hypergraphs",
/// https://arxiv.org/abs/1907.04749, can accomodate fill factors up to 87.9% full, rather than
/// 1 / 1.23 = 81.3%. In the 8-bit case, this reduces the memory usage from 9.84 bits per entry to
/// 9.1 bits.
///
/// An issue with traditional fuse filters is that the algorithm requires a large number of unique
/// keys in order for population to succeed, see [FastFilter/xor_singleheader#21](https://github.com/FastFilter/xor_singleheader/issues/21).
/// If you have few (<~125k consecutive) keys, fuse filter creation would fail.
///
/// By contrast, binary fuse filters, a revision of fuse filters made by Thomas Mueller Graf &
/// Daniel Lemire do not suffer from this issue. See https://github.com/FastFilter/xor_singleheader/issues/21
///
/// Note: We assume that you have a large set of 64-bit integers and you want a data structure to
/// do membership tests using no more than ~8 or ~16 bits per key. If your initial set is made of
/// strings or other types, you first need to hash them to a 64-bit integer.
pub fn BinaryFuse(comptime T: type) type {
    return struct {
        seed: u64,
        segment_length: u32,
        segment_length_mask: u32,
        segment_count: u32,
        segment_count_length: u32,
        fingerprints: []T,

        const Self = @This();

        inline fn relaxedFloatToInt(comptime DestType: type, float: anytype) DestType {
            if (math.isInf(float) or math.isNegativeInf(float) or math.isNan(float)) {
                return 1 << @bitSizeOf(DestType) - 1;
            }
            return @as(DestType, @intFromFloat(float));
        }

        inline fn calculateSegmentLength(arity: u32, size: usize) u32 {
            // These parameters are very sensitive. Replacing `floor` by `round` can substantially affect
            // the construction time.
            if (size == 0) return 4;
            if (arity == 3) {
                const shift_count = @as(u32, @truncate(relaxedFloatToInt(usize, @floor(math.log(f64, math.e, @as(f64, @floatFromInt(size))) / math.log(f64, math.e, 3.33) + 2.25))));
                return if (shift_count >= 31) 0 else @as(u32, 1) << @as(u5, @truncate(shift_count));
            } else if (arity == 4) {
                const shift_count = @as(u32, @truncate(relaxedFloatToInt(usize, @floor(math.log(f64, math.e, @as(f64, @floatFromInt(size))) / math.log(f64, math.e, 2.91) - 0.5))));
                return if (shift_count >= 31) 0 else @as(u32, 1) << @as(u5, @truncate(shift_count));
            }
            return 65536;
        }

        inline fn calculateSizeFactor(arity: u32, size: usize) f64 {
            if (arity == 3) {
                return @max(1.125, 0.875 + 0.25 * math.log(f64, math.e, 1000000.0) / math.log(f64, math.e, @as(f64, @floatFromInt(size))));
            } else if (arity == 4) {
                return @max(1.075, 0.77 + 0.305 * math.log(f64, math.e, 600000.0) / math.log(f64, math.e, @as(f64, @floatFromInt(size))));
            }
            return 2.0;
        }

        /// initializes a binary fuse filter with enough capacity for a set containing up to `size`
        /// elements.
        ///
        /// `deinit()` must be called by the caller to free the memory.
        pub fn init(allocator: Allocator, size: usize) !Self {
            const arity: u32 = 3;
            var segment_length = calculateSegmentLength(arity, size);
            if (segment_length > 262144) {
                segment_length = 262144;
            }
            const segment_length_mask = segment_length - 1;
            const size_factor: f64 = if (size == 0) 4 else calculateSizeFactor(arity, size);
            const capacity = if (size <= 1) 0 else @as(u32, @intFromFloat(@round(@as(f64, @floatFromInt(size)) * size_factor)));
            const init_segment_count: u32 = (capacity + segment_length - 1) / segment_length -% (arity - 1);
            var slice_length = (init_segment_count +% arity - 1) * segment_length;
            var segment_count = (slice_length + segment_length - 1) / segment_length;
            if (segment_count <= arity - 1) {
                segment_count = 1;
            } else {
                segment_count = segment_count - (arity - 1);
            }
            slice_length = (segment_count + arity - 1) * segment_length;
            const segment_count_length = segment_count * segment_length;

            return Self{
                .seed = undefined,
                .segment_length = segment_length,
                .segment_length_mask = segment_length_mask,
                .segment_count = segment_count,
                .segment_count_length = segment_count_length,
                .fingerprints = try allocator.alloc(T, slice_length),
            };
        }

        pub inline fn deinit(self: *const Self, allocator: Allocator) void {
            allocator.free(self.fingerprints);
        }

        /// reports the size in bytes of the filter.
        pub inline fn sizeInBytes(self: *const Self) usize {
            return self.fingerprints.len * @sizeOf(T) + @sizeOf(Self);
        }

        /// populates the filter with the given keys.
        ///
        /// The function could return an error after too many iterations, but it is statistically
        /// unlikely and you probably don't need to worry about it.
        ///
        /// The provided allocator will be used for creating temporary buffers that do not outlive the
        /// function call.
        pub fn populate(self: *Self, allocator: Allocator, keys: []u64) Error!void {
            var iter = SliceIterator(u64).init(keys);
            return self.populateIter(allocator, &iter);
        }

        /// Identical to populate, except it takes an iterator of keys so you need not store them
        /// in-memory.
        ///
        /// `keys.next()` must return `?u64`, the next key or none if the end of the list has been
        /// reached. The iterator must reset after hitting the end of the list, such that the `next()`
        /// call leads to the first element again.
        ///
        /// `keys.len()` must return the `usize` length.
        pub fn populateIter(self: *Self, alloc: Allocator, keys: anytype) Error!void {
            if (keys.len() == 0) {
                return;
            }

            var arena = std.heap.ArenaAllocator.init(alloc);
            defer arena.deinit();
            const allocator = arena.allocator();

            var rng_counter: u64 = 0x726b2b9d438b9d4d;
            self.seed = prng.rngSplitMix64(&rng_counter);
            var size = keys.len();
            const reverse_order = try allocator.alloc(u64, size + 1);
            lib.set(u8, std.mem.sliceAsBytes(reverse_order), 0);

            const capacity = self.fingerprints.len;
            const alone = try allocator.alloc(u32, capacity);

            const t2count = try allocator.alloc(T, capacity);
            lib.set(u8, std.mem.sliceAsBytes(t2count), 0);

            const reverse_h = try allocator.alloc(T, size);

            const t2hash = try allocator.alloc(u64, capacity);
            lib.set(u8, std.mem.sliceAsBytes(t2hash), 0);

            var block_bits: u5 = 1;
            while ((@as(u32, 1) << block_bits) < self.segment_count) {
                block_bits += 1;
            }
            const block: u32 = @as(u32, 1) << block_bits;

            const start_pos = try allocator.alloc(u32, @as(usize, 1) << block_bits);

            var expect_num_keys: ?usize = null;

            var h012: [5]u32 = undefined;

            reverse_order[size] = 1;
            var loop: usize = 0;
            while (true) : (loop += 1) {
                @branchHint(.likely);
                if (loop + 1 > max_iterations) {
                    @branchHint(.cold);
                    // too many iterations, this is statistically unlikely to happen
                    return Error.KeysLikelyNotUnique;
                }

                var i: u32 = 0;
                while (i < block) : (i += 1) {
                    // important : i * size would overflow as a 32-bit number in some
                    // cases.
                    start_pos[i] = @as(u32, @truncate((@as(u64, @intCast(i)) * size) >> block_bits));
                }

                const mask_block: u64 = block - 1;
                var got_num_keys: usize = 0;
                while (keys.next()) |key| {
                    if (comptime is_debug) got_num_keys += 1;
                    const sum: u64 = key +% self.seed;
                    const hash = hsh._wx64(sum);

                    const shift_count = @as(usize, 64) - @as(usize, block_bits);
                    var segment_index: u64 = if (shift_count >= 63) 0 else hash >> @as(u6, @truncate(shift_count));
                    while (reverse_order[start_pos[segment_index]] != 0) {
                        segment_index += 1;
                        segment_index &= mask_block;
                    }
                    reverse_order[start_pos[segment_index]] = hash;
                    start_pos[segment_index] += 1;
                }
                if (comptime is_debug) {
                    if (expect_num_keys) |expect| {
                        if (expect != got_num_keys) @panic("fastfilter: iterator illegal: does not wrap around");
                    }
                    expect_num_keys = got_num_keys;
                }

                var err = false;
                var duplicates: u32 = 0;
                i = 0;
                while (i < size) : (i += 1) {
                    const hash = reverse_order[i];
                    const h0 = self.fuseHash(0, hash);
                    const h1 = self.fuseHash(1, hash);
                    const h2 = self.fuseHash(2, hash);
                    t2count[h0] +%= 4;
                    t2hash[h0] ^= hash;
                    t2count[h1] +%= 4;
                    t2count[h1] ^= 1;
                    t2hash[h1] ^= hash;
                    t2count[h2] +%= 4;
                    t2count[h2] ^= 2;
                    t2hash[h2] ^= hash;
                    // If we have duplicated hash values, then it is likely that the next comparison
                    // is true
                    if (t2hash[h0] & t2hash[h1] & t2hash[h2] == 0) {
                        // next we do the actual test
                        if (((t2hash[h0] == 0) and (t2count[h0] == 8)) or ((t2hash[h1] == 0) and (t2count[h1] == 8)) or ((t2hash[h2] == 0) and (t2count[h2] == 8))) {
                            duplicates += 1;
                            t2count[h0] -%= 4;
                            t2hash[h0] ^= hash;
                            t2count[h1] -%= 4;
                            t2count[h1] ^= 1;
                            t2hash[h1] ^= hash;
                            t2count[h2] -%= 4;
                            t2count[h2] ^= 2;
                            t2hash[h2] ^= hash;
                        }
                    }
                    err = (t2count[h0] < 4) or err;
                    err = (t2count[h1] < 4) or err;
                    err = (t2count[h2] < 4) or err;
                }
                if (err) {
                    i = 0;
                    while (i < size) : (i += 1) {
                        reverse_order[i] = 0;
                    }
                    i = 0;
                    while (i < capacity) : (i += 1) {
                        t2count[i] = 0;
                        t2hash[i] = 0;
                    }

                    self.seed = prng.rngSplitMix64(&rng_counter);
                    continue;
                }

                // End of key addition
                var Qsize: u32 = 0;
                // Add sets with one key to the queue.
                i = 0;
                while (i < capacity) : (i += 1) {
                    alone[Qsize] = i;
                    Qsize += if ((t2count[i] >> 2) == 1) @as(u32, 1) else @as(u32, 0);
                }
                var stacksize: u32 = 0;
                while (Qsize > 0) {
                    Qsize -= 1;
                    const index: u32 = alone[Qsize];
                    if ((t2count[index] >> 2) == 1) {
                        const hash = t2hash[index];

                        //h012[0] = self.fuseHash(0, hash);
                        h012[1] = self.fuseHash(1, hash);
                        h012[2] = self.fuseHash(2, hash);
                        h012[3] = self.fuseHash(0, hash); // == h012[0];
                        h012[4] = h012[1];
                        const found = t2count[index] & 3;
                        reverse_h[stacksize] = found;
                        reverse_order[stacksize] = hash;
                        stacksize += 1;
                        const other_index1 = h012[found + 1];
                        alone[Qsize] = other_index1;
                        Qsize += if ((t2count[other_index1] >> 2) == 2) @as(u32, 1) else @as(u32, 0);

                        t2count[other_index1] -= 4;
                        t2count[other_index1] ^= fuseMod3(T, found + 1);
                        t2hash[other_index1] ^= hash;

                        const other_index2 = h012[found + 2];
                        alone[Qsize] = other_index2;
                        Qsize += if ((t2count[other_index2] >> 2) == 2) @as(u32, 1) else @as(u32, 0);
                        t2count[other_index2] -= 4;
                        t2count[other_index2] ^= fuseMod3(T, found + 2);
                        t2hash[other_index2] ^= hash;
                    }
                }
                if (stacksize + duplicates == size) {
                    @branchHint(.likely);
                    // success
                    size = stacksize;
                    break;
                }
                @memset(reverse_order[0..size], 0);
                @memset(t2count[0..capacity], 0);
                @memset(t2hash[0..capacity], 0);
                self.seed = prng.rngSplitMix64(&rng_counter);
            }
            if (size == 0) return;

            var i: u32 = @as(u32, @truncate(size - 1));
            while (i < size) : (i -%= 1) {
                @branchHint(.likely);
                // the hash of the key we insert next
                const hash: u64 = reverse_order[i];
                const xor2: T = @as(T, @truncate(fingerprint(hash)));
                const found: T = reverse_h[i];
                h012[0] = self.fuseHash(0, hash);
                h012[1] = self.fuseHash(1, hash);
                h012[2] = self.fuseHash(2, hash);
                h012[3] = h012[0];
                h012[4] = h012[1];
                self.fingerprints[h012[found]] = xor2 ^ self.fingerprints[h012[found + 1]] ^ self.fingerprints[h012[found + 2]];
            }
        }

        /// reports if the specified key is within the set with false-positive rate.
        pub inline fn contain(self: *const Self, key: u64) bool {
            const hash = mixSplit(key, self.seed);
            var f = @as(T, @truncate(fingerprint(hash)));
            const hashes = self.fuseHashBatch(hash);
            f ^= self.fingerprints[hashes.h0] ^ self.fingerprints[hashes.h1] ^ self.fingerprints[hashes.h2];
            return f == 0;
        }

        inline fn fuseHashBatch(self: *const Self, hash: u64) Hashes {
            const hi: u64 = mulhi(hash, self.segment_count_length);
            var ans: Hashes = undefined;
            ans.h0 = @as(u32, @truncate(hi));
            ans.h1 = ans.h0 + self.segment_length;
            ans.h2 = ans.h1 + self.segment_length;
            ans.h1 ^= @as(u32, @truncate(hash >> 18)) & self.segment_length_mask;
            ans.h2 ^= @as(u32, @truncate(hash)) & self.segment_length_mask;
            return ans;
        }

        inline fn mulhi(a: u64, b: u64) u64 {
            return @as(u64, @truncate((@as(u128, @intCast(a)) *% @as(u128, @intCast(b))) >> 64));
        }

        inline fn fuseHash(self: *Self, index: usize, hash: u64) u32 {
            var h = mulhi(hash, self.segment_count_length);
            h +%= index * self.segment_length;
            // keep the lower 36 bits
            const hh: u64 = hash & ((@as(u64, 1) << 36) - 1);
            // index 0: right shift by 36; index 1: right shift by 18; index 2: no shift
            const shift_count = (36 - 18 * index);
            if (shift_count >= 63) {
                h ^= 0 & self.segment_length_mask;
            } else {
                h ^= (hh >> @as(u6, @truncate(shift_count))) & self.segment_length_mask;
            }
            return @as(u32, @truncate(h));
        }
    };
}

const Hashes = struct {
    h0: u32,
    h1: u32,
    h2: u32,
};

inline fn fuseMod3(comptime T: type, x: T) T {
    return if (x > 2) x - 3 else x;
}

inline fn fingerprint(hash: u64) u64 {
    return hash ^ (hash >> 32);
}

inline fn mixSplit(key: u64, seed: u64) u64 {
    return hsh._wx64(@as(u64, key +% seed));
}

inline fn binaryFuseTest(T: anytype, size: usize, size_in_bytes: usize) !void {
    const allocator = std.heap.page_allocator;
    var filter = try BinaryFuse(T).init(allocator, size);
    defer filter.deinit(allocator);

    var keys: []u64 = undefined;
    if (size == 1337) {
        const duplicate_keys: [6]u64 = .{ 303, 1, 77, 31, 241, 303 };
        keys = try allocator.alloc(u64, duplicate_keys.len);
        for (keys, 0..) |_, i| {
            keys[i] = duplicate_keys[i];
        }
    } else {
        keys = try allocator.alloc(u64, size);
        for (keys, 0..) |_, i| {
            keys[i] = i;
        }
    }
    defer allocator.free(keys);

    try filter.populate(allocator, keys[0..]);

    if (size != 1337) {
        if (size == 0) {
            try testing.expect(!filter.contain(0));
            try testing.expect(!filter.contain(1));
        }
        if (size > 0) try testing.expect(filter.contain(0));
        if (size > 1) try testing.expect(filter.contain(1));
        if (size > 9) {
            try testing.expect(filter.contain(1) == true);
            try testing.expect(filter.contain(5) == true);
            try testing.expect(filter.contain(9) == true);
        }
        if (size > 1234) try testing.expect(filter.contain(1234) == true);
    }
    try testing.expectEqual(@as(usize, size_in_bytes), filter.sizeInBytes());

    for (keys) |key| {
        try testing.expect(filter.contain(key) == true);
    }

    var random_matches: u64 = 0;
    const trials = 10000000;
    var i: u64 = 0;
    var rng = std.Random.DefaultPrng.init(0);
    const random = rng.random();
    while (i < trials) : (i += 1) {
        const random_key: u64 = random.uintAtMost(u64, std.math.maxInt(u64));
        if (filter.contain(random_key)) {
            if (random_key >= keys.len) {
                random_matches += 1;
            }
        }
    }
}

test "binaryFuse8_small_input_edge_cases" {
    try binaryFuseTest(u8, 0, 52);
    try binaryFuseTest(u8, 1, 52);
    try binaryFuseTest(u8, 2, 52);
    try binaryFuseTest(u8, 3, 64);
}

test "binaryFuse8_zero" {
    try binaryFuseTest(u8, 0, 52);
}

test "binaryFuse8_1" {
    try binaryFuseTest(u8, 1, 52);
}

test "binaryFuse8_10" {
    try binaryFuseTest(u8, 10, 88);
}

test "binaryFuse8" {
    try binaryFuseTest(u8, 1_000_000, 1130536);
}

test "binaryFuse8_2m" {
    try binaryFuseTest(u8, 2_000_000, 2261032);
}

test "binaryFuse8_5m" {
    try binaryFuseTest(u8, 5_000_000, 5636136);
}

test "binaryFuse16" {
    try binaryFuseTest(u16, 1_000_000, 2261032);
}

test "binaryFuse32" {
    try binaryFuseTest(u32, 1_000_000, 4522024);
}

test "binaryFuse8_duplicate_keys" {
    try binaryFuseTest(u8, 1337, 2088);
}

test "binaryFuse8_mid_num_keys" {
    try binaryFuseTest(u8, 11500, 14376);
}
