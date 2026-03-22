const std = @import("std");
const lib = @import("lib.zig");
const assert = lib.assert;
const builtin = @import("builtin");

const is_x86_64 = builtin.target.cpu.arch == .x86_64;

const has_avx2 = std.Target.x86.featureSetHas(builtin.cpu.features, .avx2);
const has_avx = std.Target.x86.featureSetHas(builtin.cpu.features, .avx);
const has_pclmul = std.Target.x86.featureSetHas(builtin.cpu.features, .pclmul);
const has_sse4_2 = std.Target.x86.featureSetHas(builtin.cpu.features, .sse4_2);
const has_sse4_1 = std.Target.x86.featureSetHas(builtin.cpu.features, .sse4_1);
const has_ssse3 = std.Target.x86.featureSetHas(builtin.cpu.features, .ssse3);
const has_sse3 = std.Target.x86.featureSetHas(builtin.cpu.features, .sse3);
const has_sse2 = std.Target.x86.featureSetHas(builtin.cpu.features, .sse2);
const has_sse = std.Target.x86.featureSetHas(builtin.cpu.features, .sse);

pub inline fn _mm_crc32_u16(crc: u32, v: u16) u32 {
    if ((has_sse4_2) and is_x86_64) {
        return struct {
            extern fn @"llvm.x86.sse42.crc32.32.16"(u32, u16) u32;
        }.@"llvm.x86.sse42.crc32.32.16"(crc, v);
    }
}

pub inline fn _mm_crc32_u32(crc: u32, v: u32) u32 {
    if ((has_sse4_2) and is_x86_64) {
        return struct {
            extern fn @"llvm.x86.sse42.crc32.32.32"(u32, u32) u32;
        }.@"llvm.x86.sse42.crc32.32.32"(crc, v);
    }
}

pub inline fn _mm_crc32_u64(crc: u64, v: u64) u64 {
    if ((is_x86_64) and (has_sse4_2)) {
        return struct {
            extern fn @"llvm.x86.sse42.crc32.64.64"(u64, u64) u64;
        }.@"llvm.x86.sse42.crc32.64.64"(crc, v);
    }
}

pub inline fn _mm_crc32_u8(crc: u32, v: u8) u32 {
    if (is_x86_64 and (has_sse4_2)) {
        return struct {
            extern fn @"llvm.x86.sse42.crc32.32.8"(u32, u8) u32;
        }.@"llvm.x86.sse42.crc32.32.8"(crc, v);
    }
}
