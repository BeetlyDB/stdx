const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;
const mem = std.mem;
const testing = std.testing;

pub const SPSC = @import("spscqueue_ring_buffer.zig");

pub const Time = @import("time.zig");

pub const LockFreeRingBuffer = @import("folly_lock_free_ringbuffer.zig").LockFreeRingBuffer;

pub const RingBuffer = @import("ring_buffer.zig").RingBuffer;

pub const MPMCQueue = @import("folly_mpmcqueue.zig").MPMCQueue;

pub const ArrayList = @import("ArrayList.zig").AlignedList;

pub const ArenaAllocator = @import("ArenaAllocator.zig").ArenaAllocator;

pub const Pool = @import("pool.zig").Growing;

pub const ThreadPool = @import("threadpool.zig");

pub const InstrusiveLinkedList = @import("linkedlist.zig");

pub const InstrusiveStack = @import("stack.zig");

pub const BinaryFuse = @import("binary_fuse_filter.zig");

pub const BinaryFuseu8 = BinaryFuse.BinaryFuse(u8);

const native_endian = builtin.cpu.arch.endian();

const has_avx2 = std.Target.x86.featureSetHas(builtin.cpu.features, .avx2);

test {
    std.testing.refAllDecls(@This());
}

pub inline fn isPowerOfTwo(comptime T: type) bool {
    comptime switch (@typeInfo(T)) {
        .int => return (T & (T - 1)) == 0,
        else => return false,
    };
}

//=====================GENERAL PURPOSE UTILS================================
//
//
// Set the affinity of the current thread to the given CPU.
pub fn setYadro(cpu: usize) void {
    var cpu_set: std.os.linux.cpu_set_t = undefined;
    @memset(&cpu_set, 0);

    const cpu_elt = cpu / (@sizeOf(usize) * 8);
    const cpu_mask = @as(usize, 1) << @truncate(cpu % (@sizeOf(usize) * 8));
    cpu_set[cpu_elt] |= cpu_mask;

    _ = std.os.linux.syscall3(.sched_setaffinity, @as(usize, @bitCast(@as(isize, 0))), @sizeOf(std.os.linux.cpu_set_t), @intFromPtr(&cpu_set));
}

pub inline fn copy(comptime T: type, dest: []T, source: []const T) void {
    if (builtin.link_libc) {
        _ = memcpy(dest.ptr, source.ptr, source.len * @sizeOf(T));
    }
    if (comptime has_avx2) {
        _ = __folly_memcpy(
            @ptrCast(dest.ptr),
            @ptrCast(source.ptr),
            source.len * @sizeOf(T),
        );
    } else {
        @memcpy(dest[0..source.len], source);
    }
}

pub const Vct = struct {
    pub const vector_len = suggestVectorLength(u8) orelse @compileError("No SIMD features available");
    pub const zer: vector = @splat(0);
    pub const one: vector = @splat(255);
    pub const slash: vector = @splat('\\');
    pub const quote: vector = @splat('"');
};

pub const vector = @Vector(Vct.vector_len, u8);
pub const boolx32 = @Vector(32, bool);
pub const boolx16 = @Vector(16, bool);
pub const boolx8 = @Vector(8, bool);
pub const boolx4 = @Vector(4, bool);
pub const i1x32 = @Vector(32, i1);
pub const i8x8 = @Vector(8, i8);
pub const i8x16 = @Vector(16, i8);
pub const i8x32 = @Vector(32, i8);
pub const i16x4 = @Vector(4, i16);
pub const i16x8 = @Vector(8, i16);
pub const i32x2 = @Vector(2, i32);
pub const i32x4 = @Vector(4, i32);
pub const i32x8 = @Vector(8, i32);
pub const u1x4 = @Vector(4, u1);
pub const u1x8 = @Vector(8, u1);
pub const u1x16 = @Vector(16, u1);
pub const u1x32 = @Vector(32, u1);
pub const u8x8 = @Vector(8, u8);
pub const u8x16 = @Vector(16, u8);
pub const u8x32 = @Vector(32, u8);
pub const u8x64 = @Vector(64, u8);
pub const u16x8 = @Vector(8, u16);
pub const u32x4 = @Vector(4, u32);
pub const i64x2 = @Vector(2, i64);
pub const u64x2 = @Vector(2, u64);
pub const u64x4 = @Vector(4, u64);

pub inline fn lookupTable(table: vector, nibbles: vector) vector {
    switch (comptime builtin.cpu.arch) {
        .x86_64 => {
            return asm (
                \\vpshufb %[nibbles], %[table], %[ret]
                : [ret] "=v" (-> vector),
                : [table] "v" (table),
                  [nibbles] "v" (nibbles),
            );
        },
        .aarch64 => {
            return asm (
                \\tbl %[ret].16b, {%[table].16b}, %[nibbles].16b
                : [ret] "=w" (-> vector),
                : [table] "w" (table),
                  [nibbles] "w" (nibbles),
            );
        },
        else => @compileError("not implemented for this target"),
    }
}

pub inline fn pack(vec1: @Vector(4, i32), vec2: @Vector(4, i32)) @Vector(8, u16) {
    switch (comptime builtin.cpu.arch) {
        .x86_64 => {
            return asm (
                \\vpackusdw %[vec1], %[vec2], %[ret]
                : [ret] "=v" (-> @Vector(8, u16)),
                : [vec1] "v" (vec1),
                  [vec2] "v" (vec2),
            );
        },
        else => @compileError("Intrinsic not implemented for this target"),
    }
}

pub inline fn mulSaturatingAdd(vec1: @Vector(16, u8), vec2: @Vector(16, u8)) @Vector(8, u16) {
    switch (comptime builtin.cpu.arch) {
        .x86_64 => {
            return asm (
                \\vpmaddubsw %[vec1], %[vec2], %[ret]
                : [ret] "=v" (-> @Vector(8, u16)),
                : [vec1] "v" (vec1),
                  [vec2] "v" (vec2),
            );
        },
        else => @compileError("Intrinsic not implemented for this target"),
    }
}

pub inline fn mulWrappingAdd(vec1: @Vector(8, i16), vec2: @Vector(8, i16)) @Vector(4, i32) {
    switch (comptime builtin.cpu.arch) {
        .x86_64 => {
            return asm (
                \\vpmaddwd %[vec1], %[vec2], %[ret]
                : [ret] "=v" (-> @Vector(4, i32)),
                : [vec1] "v" (vec1),
                  [vec2] "v" (vec2),
            );
        },
        else => @compileError("Intrinsic not implemented for this target"),
    }
}

pub inline fn clmul(m: u64) u64 {
    switch (comptime builtin.cpu.arch) {
        .x86_64 => {
            const ones: @Vector(16, u8) = @splat(0xFF);
            return asm (
                \\vpclmulqdq $0, %[ones], %[quotes], %[ret]
                : [ret] "=v" (-> u64),
                : [ones] "v" (ones),
                  [quotes] "v" (m),
            );
        },
        else => {
            var bitmask = m;
            bitmask ^= bitmask << 1;
            bitmask ^= bitmask << 2;
            bitmask ^= bitmask << 4;
            bitmask ^= bitmask << 8;
            bitmask ^= bitmask << 16;
            bitmask ^= bitmask << 32;
            return bitmask;
        },
    }
}

/// e.g. `0 1 2 3` -> `1 2 3 0`.
pub inline fn rotateOnce(comptime T: type, items: []T) void {
    const tmp = items[0];
    move(T, items[0 .. items.len - 1], items[1..items.len]);
    items[items.len - 1] = tmp;
}

/// e.g. `0 1 2 3` -> `3 0 1 2`.
pub inline fn rotateOnceR(comptime T: type, items: []T) void {
    const tmp = items[items.len - 1];
    move(T, items[1..items.len], items[0 .. items.len - 1]);
    items[0] = tmp;
}

/// e.g. rotating `4` in to `0 1 2 3` makes it `1 2 3 4` and returns `0`.
pub inline fn rotateIn(comptime T: type, items: []T, item: T) T {
    const removed = items[0];
    move(T, items[0 .. items.len - 1], items[1..items.len]);
    items[items.len - 1] = item;
    return removed;
}

/// e.g. rotating `4` in to `0 1 2 3` makes it `4 0 1 2` and returns `3`.
pub inline fn rotateInR(comptime T: type, items: []T, item: T) T {
    const removed = items[items.len - 1];
    move(T, items[1..items.len], items[0 .. items.len - 1]);
    items[0] = item;
    return removed;
}

pub fn suggestVectorLengthForCpu(comptime T: type, comptime cpu: std.Target.Cpu) ?comptime_int {
    @setEvalBranchQuota(10000);
    // This is guesswork, if you have better suggestions can add it or edit the current here
    const element_bit_size = @max(8, std.math.ceilPowerOfTwo(u16, @bitSizeOf(T)) catch unreachable);
    const vector_bit_size: u16 = blk: {
        if (cpu.arch.isX86()) {
            if (T == bool and std.Target.x86.featureSetHas(cpu.features, .prefer_mask_registers)) return 64;
            if (builtin.zig_backend != .stage2_x86_64 and std.Target.x86.featureSetHas(cpu.features, .avx512f) and !std.Target.x86.featureSetHasAny(cpu.features, .{ .prefer_256_bit, .prefer_128_bit })) break :blk 512;
            if (std.Target.x86.featureSetHasAny(cpu.features, .{ .prefer_256_bit, .avx2 }) and !std.Target.x86.featureSetHas(cpu.features, .prefer_128_bit)) break :blk 256;
            if (std.Target.x86.featureSetHas(cpu.features, .sse)) break :blk 128;
            if (std.Target.x86.featureSetHasAny(cpu.features, .{ .mmx, .@"3dnow" })) break :blk 64;
        } else if (cpu.arch.isArm()) {
            if (std.Target.arm.featureSetHas(cpu.features, .neon)) break :blk 128;
        } else if (cpu.arch.isAARCH64()) {
            // SVE allows up to 2048 bits in the specification, as of 2022 the most powerful machine has implemented 512-bit
            // I think is safer to just be on 128 until is more common
            // TODO: Check on this return when bigger values are more common
            if (std.Target.aarch64.featureSetHas(cpu.features, .sve)) break :blk 128;
            if (std.Target.aarch64.featureSetHas(cpu.features, .neon)) break :blk 128;
        } else if (cpu.arch.isPowerPC()) {
            if (std.Target.powerpc.featureSetHas(cpu.features, .altivec)) break :blk 128;
        } else if (cpu.arch.isMIPS()) {
            if (std.Target.mips.featureSetHas(cpu.features, .msa)) break :blk 128;
            // TODO: Test MIPS capability to handle bigger vectors
            //       In theory MDMX and by extension mips3d have 32 registers of 64 bits which can use in parallel
            //       for multiple processing, but I don't know what's optimal here, if using
            //       the 2048 bits or using just 64 per vector or something in between
            if (std.Target.mips.featureSetHas(cpu.features, std.Target.mips.Feature.mips3d)) break :blk 64;
        } else if (cpu.arch.isRISCV()) {
            // In RISC-V Vector Registers are length agnostic so there's no good way to determine the best size.
            // The usual vector length in most RISC-V cpus is 256 bits, however it can get to multiple kB.
            if (std.Target.riscv.featureSetHas(cpu.features, .v)) {
                var vec_bit_length: u32 = 256;
                if (std.Target.riscv.featureSetHas(cpu.features, .zvl32b)) {
                    vec_bit_length = 32;
                } else if (std.Target.riscv.featureSetHas(cpu.features, .zvl64b)) {
                    vec_bit_length = 64;
                } else if (std.Target.riscv.featureSetHas(cpu.features, .zvl128b)) {
                    vec_bit_length = 128;
                } else if (std.Target.riscv.featureSetHas(cpu.features, .zvl256b)) {
                    vec_bit_length = 256;
                } else if (std.Target.riscv.featureSetHas(cpu.features, .zvl512b)) {
                    vec_bit_length = 512;
                } else if (std.Target.riscv.featureSetHas(cpu.features, .zvl1024b)) {
                    vec_bit_length = 1024;
                } else if (std.Target.riscv.featureSetHas(cpu.features, .zvl2048b)) {
                    vec_bit_length = 2048;
                } else if (std.Target.riscv.featureSetHas(cpu.features, .zvl4096b)) {
                    vec_bit_length = 4096;
                } else if (std.Target.riscv.featureSetHas(cpu.features, .zvl8192b)) {
                    vec_bit_length = 8192;
                } else if (std.Target.riscv.featureSetHas(cpu.features, .zvl16384b)) {
                    vec_bit_length = 16384;
                } else if (std.Target.riscv.featureSetHas(cpu.features, .zvl32768b)) {
                    vec_bit_length = 32768;
                } else if (std.Target.riscv.featureSetHas(cpu.features, .zvl65536b)) {
                    vec_bit_length = 65536;
                }
                break :blk vec_bit_length;
            }
        } else if (cpu.arch.isSPARC()) {
            if (std.Target.sparc.featureSetHasAny(cpu.features, .{ .vis, .vis2, .vis3 })) break :blk 64;
        } else if (cpu.arch.isWasm()) {
            if (std.Target.wasm.featureSetHas(cpu.features, .simd128)) break :blk 128;
        }
        return null;
    };
    if (vector_bit_size <= element_bit_size) return null;

    return @divExact(vector_bit_size, element_bit_size);
}

pub fn suggestVectorLength(comptime T: type) ?comptime_int {
    return suggestVectorLengthForCpu(T, builtin.cpu);
}

const use_vectors = switch (builtin.zig_backend) {
    // These backends don't support vectors yet.
    .stage2_spirv,
    .stage2_riscv64,
    => false,
    else => true,
};

const use_vectors_for_comparison = use_vectors and !builtin.fuzz;

pub inline fn eql(comptime T: type, a: []const T, b: []const T) bool {
    if (!@inComptime() and @sizeOf(T) != 0 and std.meta.hasUniqueRepresentation(T) and
        use_vectors_for_comparison)
    {
        return eqlBytes(sliceAsBytes(a), sliceAsBytes(b));
    }

    if (a.len != b.len) return false;
    if (a.len == 0 or a.ptr == b.ptr) return true;

    for (a, b) |a_elem, b_elem| {
        if (a_elem != b_elem) return false;
    }
    return true;
}

inline fn CopyPtrAttrs(
    comptime source: type,
    comptime size: std.builtin.Type.Pointer.Size,
    comptime child: type,
) type {
    const info = @typeInfo(source).pointer;
    return @Type(.{
        .pointer = .{
            .size = size,
            .is_const = info.is_const,
            .is_volatile = info.is_volatile,
            .is_allowzero = info.is_allowzero,
            .alignment = info.alignment,
            .address_space = info.address_space,
            .child = child,
            .sentinel_ptr = null,
        },
    });
}

inline fn SliceAsBytesReturnType(comptime Slice: type) type {
    return CopyPtrAttrs(Slice, .slice, u8);
}

pub inline fn sliceAsBytes(slice: anytype) SliceAsBytesReturnType(@TypeOf(slice)) {
    const Slice = @TypeOf(slice);

    // a slice of zero-bit values always occupies zero bytes
    if (@sizeOf(std.meta.Elem(Slice)) == 0) return &[0]u8{};

    // let's not give an undefined pointer to @ptrCast
    // it may be equal to zero and fail a null check
    if (slice.len == 0 and std.meta.sentinel(Slice) == null) return &[0]u8{};

    const cast_target = CopyPtrAttrs(Slice, .many, u8);

    return @as(cast_target, @ptrCast(slice))[0 .. slice.len * @sizeOf(std.meta.Elem(Slice))];
}

inline fn eqlBytes(a: []const u8, b: []const u8) bool {
    comptime assert(use_vectors_for_comparison);
    if (a.len != b.len) return false;
    if (a.len == 0 or a.ptr == b.ptr) return true;
    if (a[0] != b[0]) return false;

    if (a.len <= 16) {
        if (a.len < 4) {
            const x = (a[0] ^ b[0]) | (a[a.len - 1] ^ b[a.len - 1]) | (a[a.len / 2] ^ b[a.len / 2]);
            return x == 0;
        }
        var x: u32 = 0;
        for ([_]usize{ 0, a.len - 4, (a.len / 8) * 4, a.len - 4 - ((a.len / 8) * 4) }) |n| {
            x |= @as(u32, @bitCast(a[n..][0..4].*)) ^ @as(u32, @bitCast(b[n..][0..4].*));
        }
        return x == 0;
    }

    // Figure out the fastest way to scan through the input in chunks.
    // Uses vectors when supported and falls back to usize/words when not.
    const Scan = if (suggestVectorLength(u8)) |vec_size|
        struct {
            pub const size = vec_size;
            pub const Chunk = @Vector(size, u8);
            pub inline fn isNotEqual(chunk_a: Chunk, chunk_b: Chunk) bool {
                return @reduce(.Or, chunk_a != chunk_b);
            }
        }
    else
        struct {
            pub const size = @sizeOf(usize);
            pub const Chunk = usize;
            pub inline fn isNotEqual(chunk_a: Chunk, chunk_b: Chunk) bool {
                return chunk_a != chunk_b;
            }
        };

    inline for (1..6) |s| {
        const n = 16 << s;
        if (n <= Scan.size and a.len <= n) {
            const V = @Vector(n / 2, u8);
            var x = @as(V, a[0 .. n / 2].*) ^ @as(V, b[0 .. n / 2].*);
            x |= @as(V, a[a.len - n / 2 ..][0 .. n / 2].*) ^ @as(V, b[a.len - n / 2 ..][0 .. n / 2].*);
            const zero: V = @splat(0);
            return !@reduce(.Or, x != zero);
        }
    }
    // Compare inputs in chunks at a time (excluding the last chunk).
    for (0..(a.len - 1) / Scan.size) |i| {
        const a_chunk: Scan.Chunk = @bitCast(a[i * Scan.size ..][0..Scan.size].*);
        const b_chunk: Scan.Chunk = @bitCast(b[i * Scan.size ..][0..Scan.size].*);
        if (Scan.isNotEqual(a_chunk, b_chunk)) return false;
    }

    // Compare the last chunk using an overlapping read (similar to the previous size strategies).
    const last_a_chunk: Scan.Chunk = @bitCast(a[a.len - Scan.size ..][0..Scan.size].*);
    const last_b_chunk: Scan.Chunk = @bitCast(b[a.len - Scan.size ..][0..Scan.size].*);
    return !Scan.isNotEqual(last_a_chunk, last_b_chunk);
}

pub inline fn isAscii(input: []const u8) bool {
    var remain = input;
    if (comptime suggestVectorLength(u8)) |vector_len| {
        while (remain.len > vector_len) {
            const chunk: @Vector(vector_len, u8) = remain[0..vector_len].*;
            if (@reduce(.Max, chunk) < 128) {
                return true;
            }
            remain = remain[vector_len..];
        }
    }
    for (remain) |c| {
        if (c < 128) {
            return true;
        }
    }
    return false;
}

// TODO(zig): Zig 0.11 doesn't have the statfs / fstatfs syscalls to get the type of a filesystem.
// Once those are available, this can be removed.
// The `statfs` definition used by the Linux kernel, and the magic number for tmpfs, from
// `man 2 fstatfs`.
const fsblkcnt64_t = u64;
const fsfilcnt64_t = u64;
const fsword_t = i64;
const fsid_t = u64;

pub const TmpfsMagic = 0x01021994;
pub const StatFs = extern struct {
    f_type: fsword_t,
    f_bsize: fsword_t,
    f_blocks: fsblkcnt64_t,
    f_bfree: fsblkcnt64_t,
    f_bavail: fsblkcnt64_t,
    f_files: fsfilcnt64_t,
    f_ffree: fsfilcnt64_t,
    f_fsid: fsid_t,
    f_namelen: fsword_t,
    f_frsize: fsword_t,
    f_flags: fsword_t,
    f_spare: [4]fsword_t,
};

pub fn fstatfs(fd: i32, statfs_buf: *StatFs) usize {
    return std.os.linux.syscall2(
        if (@hasField(std.os.linux.SYS, "fstatfs64")) .fstatfs64 else .fstatfs,
        @as(usize, @bitCast(@as(isize, fd))),
        @intFromPtr(statfs_buf),
    );
}

/// Checks that a type does not have implicit padding.
pub fn no_padding(comptime T: type) bool {
    comptime switch (@typeInfo(T)) {
        .void => return true,
        .int => return @bitSizeOf(T) == 8 * @sizeOf(T),
        .array => |info| return no_padding(info.child),
        .@"struct" => |info| {
            switch (info.layout) {
                .auto => return false,
                .@"extern" => {
                    for (info.fields) |field| {
                        if (!no_padding(field.type)) return false;
                    }

                    // Check offsets of u128 and pseudo-u256 fields.
                    for (info.fields) |field| {
                        if (field.type == u128) {
                            const offset = @offsetOf(T, field.name);
                            if (offset % @sizeOf(u128) != 0) return false;

                            if (@hasField(T, field.name ++ "_padding")) {
                                if (offset % @sizeOf(u256) != 0) return false;
                                if (offset + @sizeOf(u128) !=
                                    @offsetOf(T, field.name ++ "_padding"))
                                {
                                    return false;
                                }
                            }
                        }
                    }

                    var offset = 0;
                    for (info.fields) |field| {
                        const field_offset = @offsetOf(T, field.name);
                        if (offset != field_offset) return false;
                        offset += @sizeOf(field.type);
                    }
                    return offset == @sizeOf(T);
                },
                .@"packed" => return @bitSizeOf(T) == 8 * @sizeOf(T),
            }
        },
        .@"enum" => |info| {
            return no_padding(info.tag_type);
        },
        .pointer => return false,
        .@"union" => return false,
        else => return false,
    };
}

pub inline fn set(comptime T: type, dest: []T, value: T) void {
    if (comptime @sizeOf(T) == 1) {
        if (comptime has_avx2) {
            __folly_memset(@ptrCast(dest.ptr), @intCast(value), dest.len);
            return;
        }
    }

    @memset(dest, value);
}

pub inline fn roundeven(x: anytype) @TypeOf(x) {
    return struct {
        extern fn @"llvm.roundeven"(@TypeOf(x)) @TypeOf(x);
    }.@"llvm.roundeven"(x);
}

//Preferred use for all cases
pub inline fn move(comptime T: type, dest: []T, source: []const T) void {
    if (comptime !has_avx2 and builtin.link_libc) {
        _ = memmove(dest.ptr, source.ptr, source.len * @sizeOf(T));
    }
    if (comptime has_avx2) {
        _ = __folly_memcpy(
            @ptrCast(dest.ptr),
            @ptrCast(source.ptr),
            source.len * @sizeOf(T),
        );
    } else {
        @memmove(dest, source);
    }
}

extern "c" fn memcpy(*anyopaque, *const anyopaque, usize) *anyopaque;
extern "c" fn memmove(*anyopaque, *const anyopaque, usize) *anyopaque;

extern fn __folly_memcpy(dest: *anyopaque, src: *const anyopaque, n: usize) *anyopaque;
extern fn __folly_memset(dest: *anyopaque, ch: c_int, size: usize) void;

test "eql-2" {
    try std.testing.expect(eql(u8, "abcd", "abcd"));

    try std.testing.expect(eql(u8, "abc", "abc"));
    try std.testing.expect(!eql(u8, "abc", "abcd"));

    try std.testing.expect(eql(u8, "abcdfty78uhgfdxsedrtyghvfxdzesr80hBRUHugyt799t8oguvhckdi9rtgvc", "abcdfty78uhgfdxsedrtyghvfxdzesr80hBRUHugyt799t8oguvhckdi9rtgvc"));
    try std.testing.expect(!eql(u8, "abcdfty78uhgfdxsedrtyghvfxdzesr80hBRUHugyt799t8oguvhckdi9rtgvc", "abcdfty78uhgfdxsedrtyghvfxdzesr80hBRUHugyt799t8oguvhckdi9rtgvca"));
}

test "eql - u8 equal strings" {
    const a = "hello world";
    const b = "hello world";
    try testing.expect(eql(u8, a, b));
}

test "eql - u8 different strings" {
    const a = "hello world";
    const b = "hello earth";
    try testing.expect(!eql(u8, a, b));
}

test "eql - bool different arrays" {
    const a = [_]bool{ true, false, true };
    const b = [_]bool{ true, true, true };
    try testing.expect(!eql(bool, a[0..], b[0..]));
}

test "eql - f32 equal arrays" {
    const a = [_]f32{ 1.0, 2.0, 3.0 };
    const b = [_]f32{ 1.0, 2.0, 3.0 };
    try testing.expect(eql(f32, a[0..], b[0..]));
}

test "eql - u32 equal arrays" {
    const a = [_]u32{ 1, 2, 3, 4, 5 };
    const b = [_]u32{ 1, 2, 3, 4, 5 };
    try testing.expect(eql(u32, a[0..], b[0..]));
}

test "eql - u32 different arrays" {
    const a = [_]u32{ 1, 2, 3, 4, 5 };
    const b = [_]u32{ 1, 2, 3, 4, 6 };
    try testing.expect(!eql(u32, a[0..], b[0..]));
}
