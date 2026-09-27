const std = @import("std");
const assert = @import("lib.zig").assert;

const BUF_SIZE = 24;

const cutoff = std.math.maxInt(u64) / 10;
const cutlim = std.math.maxInt(u64) % 10;

const cutoff_neg = @as(u64, std.math.maxInt(i64)) + 1;
const cutoff_no_neg = @as(u64, std.math.maxInt(i64));

const cutoffNegDiv10 = cutoff_neg / 10;

const cutoffNegMod10 = cutoff_neg % 10;
const cutoffPosDiv10 = cutoff_no_neg / 10;
const cutoffPosMod10 = cutoff_no_neg % 10;

const digits3 = blk: {
    var table: [1000]u32 = undefined;
    for (0..1000) |i| {
        const a: u8 = '0' + @as(u8, @intCast(i / 100));
        const b: u8 = '0' + @as(u8, @intCast((i / 10) % 10));
        const c: u8 = '0' + @as(u8, @intCast(i % 10));
        table[i] = (@as(u32, a) << 16) | (@as(u32, b) << 8) | @as(u32, c);
    }
    break :blk table;
};

const digits = [_]u8{
    '0', '0', '0', '1', '0', '2', '0', '3', '0', '4', '0', '5', '0', '6', '0', '7', '0', '8', '0', '9',
    '1', '0', '1', '1', '1', '2', '1', '3', '1', '4', '1', '5', '1', '6', '1', '7', '1', '8', '1', '9',
    '2', '0', '2', '1', '2', '2', '2', '3', '2', '4', '2', '5', '2', '6', '2', '7', '2', '8', '2', '9',
    '3', '0', '3', '1', '3', '2', '3', '3', '3', '4', '3', '5', '3', '6', '3', '7', '3', '8', '3', '9',
    '4', '0', '4', '1', '4', '2', '4', '3', '4', '4', '4', '5', '4', '6', '4', '7', '4', '8', '4', '9',
    '5', '0', '5', '1', '5', '2', '5', '3', '5', '4', '5', '5', '5', '6', '5', '7', '5', '8', '5', '9',
    '6', '0', '6', '1', '6', '2', '6', '3', '6', '4', '6', '5', '6', '6', '6', '7', '6', '8', '6', '9',
    '7', '0', '7', '1', '7', '2', '7', '3', '7', '4', '7', '5', '7', '6', '7', '7', '7', '8', '7', '9',
    '8', '0', '8', '1', '8', '2', '8', '3', '8', '4', '8', '5', '8', '6', '8', '7', '8', '8', '8', '9',
    '9', '0', '9', '1', '9', '2', '9', '3', '9', '4', '9', '5', '9', '6', '9', '7', '9', '8', '9', '9',
};

const Digits10Bound = struct { d: u32, thr: u64 };

const digits10_tab = blk: {
    @setEvalBranchQuota(10_000);
    var t: [64]Digits10Bound = undefined;
    for (0..64) |lg| {
        const v: u64 = @as(u64, 1) << @intCast(lg);
        var d: u32 = 1;
        var x = v / 10;
        while (x > 0) : (x /= 10) d += 1;
        var thr: u64 = 1;
        var k: u32 = 0;
        while (k < d) : (k += 1) thr *= 10;
        t[lg] = .{ .d = d, .thr = thr };
    }
    break :blk t;
};

inline fn digits10(v: u64) u32 {
    const lg: usize = 63 ^ @as(usize, @clz(v | 1));
    const e = digits10_tab[lg];
    return e.d + @as(u32, @intFromBool(v >= e.thr));
}

pub inline fn sum_overflows(comptime Int: type, a: Int, b: Int) bool {
    comptime assert(Int != comptime_int);
    comptime assert(Int != comptime_float);
    _ = std.math.add(Int, a, b) catch return true;
    return false;
}

pub inline fn format_int(comptime T: type, dst: []u8, v: T) usize {
    comptime assert(@typeInfo(T) == .int);
    const info = @typeInfo(T).int;

    if (comptime info.signedness == .unsigned) {
        return format_uint(T, dst, v);
    }

    const U = std.meta.Int(.unsigned, info.bits);
    var uval: U = @bitCast(v);
    var negative = false;

    if (v < 0) {
        negative = true;
        uval = -%uval; // two's complement negation
    }

    if (negative) {
        if (dst.len < 2) {
            @branchHint(.cold);
            if (dst.len > 0) dst[0] = 0;
            return 0;
        }
        dst[0] = '-';
        const len = format_uint(U, dst[1..], uval);
        if (len == 0) {
            @branchHint(.cold);
            dst[0] = 0;
            return 0;
        }
        return len + 1;
    }

    return format_uint(U, dst, uval);
}

pub inline fn format_uint(comptime T: type, dst: []u8, v: T) usize {
    comptime assert(@typeInfo(T) == .int);
    comptime assert(@typeInfo(T).int.signedness == .unsigned);

    const dstlen = dst.len;
    var value: u64 = @as(u64, v);

    if (value < 100) {
        if (value < 10) {
            if (dstlen < 1) {
                @branchHint(.cold);
                return 0;
            }
            dst[0] = '0' + @as(u8, @intCast(value));
            return 1;
        }
        if (dstlen < 2) {
            @branchHint(.cold);
            if (dstlen > 0) dst[0] = 0;
            return 0;
        }
        const i: usize = @intCast(value * 2);
        dst[0] = digits[i];
        dst[1] = digits[i + 1];
        return 2;
    }

    const length = digits10(value);

    if (length > dstlen) {
        @branchHint(.cold);
        if (dstlen > 0) dst[0] = 0;
        return 0;
    }

    var next: usize = length;

    while (value >= 1000) {
        const r = value % 1000;
        value /= 1000;
        next -= 3;

        const t = digits3[@intCast(r)];
        dst[next] = @truncate(t >> 16);
        dst[next + 1] = @truncate(t >> 8);
        dst[next + 2] = @truncate(t);
    }

    if (value < 10) {
        next -= 1;
        dst[next] = '0' + @as(u8, @intCast(value));
    } else if (value < 100) {
        next -= 2;
        const i: usize = @intCast(value * 2);
        dst[next] = digits[i];
        dst[next + 1] = digits[i + 1];
    } else {
        next -= 3;
        const t = digits3[@intCast(value)];
        dst[next] = @truncate(t >> 16);
        dst[next + 1] = @truncate(t >> 8);
        dst[next + 2] = @truncate(t);
    }

    return length;
}

pub const ParseError = error{
    EmptyString,
    InvalidCharacter,
    InvalidString,
    Overflow,
};

pub inline fn parse_8_digits_swar(buf: []const u8, offset: usize) ?u64 {
    const loaded = std.mem.readInt(u64, buf[offset..][0..8], .little);

    if ((loaded & 0xF0F0F0F0F0F0F0F0) != 0x3030303030303030) return null;

    const low = loaded & 0x0F0F0F0F0F0F0F0F;
    if (((low +% 0x0606060606060606) & 0xF0F0F0F0F0F0F0F0) != 0) return null;

    var lo = low & 0x00FF00FF00FF00FF;
    var hi = (low >> 8) & 0x00FF00FF00FF00FF;
    var val = lo *% 10 +% hi;

    lo = val & 0x0000FFFF0000FFFF;
    hi = (val >> 16) & 0x0000FFFF0000FFFF;
    val = lo *% 100 +% hi;

    lo = val & 0x00000000FFFFFFFF;
    hi = val >> 32;
    return lo *% 10000 +% hi;
}

pub inline fn parse_uint_fast(comptime T: type, buf: []const u8) ParseError!T {
    comptime assert(@typeInfo(T) == .int);
    comptime assert(@typeInfo(T).int.signedness == .unsigned);

    var v: u64 = 0;
    var i: usize = 0;
    const n = buf.len;

    while (i + 8 <= n) {
        const chunk = parse_8_digits_swar(buf, i) orelse return error.InvalidCharacter;
        v = v *% 100_000_000 +% chunk;
        i += 8;
    }

    while (i < n) : (i += 1) {
        const c = buf[i];
        if (c < '0' or c > '9') return error.InvalidCharacter;
        v = v *% 10 +% (c - '0');
    }

    return @intCast(v);
}

pub inline fn parse_uint_slow(comptime T: type, buf: []const u8) ParseError!T {
    comptime assert(@typeInfo(T) == .int);
    comptime assert(@typeInfo(T).int.signedness == .unsigned);

    var v: u64 = 0;
    for (buf) |c| {
        if (c < '0' or c > '9') return error.InvalidCharacter;
        const d: u64 = c - '0';
        if (v > cutoff or (v == cutoff and d > cutlim)) return error.Overflow;
        v = v * 10 + d;
    }

    return @intCast(v);
}

pub inline fn parse_uint(comptime T: type, buf: []const u8) ParseError!T {
    comptime assert(@typeInfo(T) == .int);
    comptime assert(@typeInfo(T).int.signedness == .unsigned);
    comptime assert(@typeInfo(T).int.bits <= 64);

    if (buf.len == 0) return error.EmptyString;

    const v: u64 = if (buf.len <= 19)
        try parse_uint_fast(u64, buf)
    else
        try parse_uint_slow(u64, buf);

    if (v > std.math.maxInt(T)) return error.Overflow;
    return @intCast(v);
}

pub inline fn parse_int(comptime T: type, buf: []const u8) ParseError!T {
    comptime assert(@typeInfo(T) == .int);
    comptime assert(@typeInfo(T).int.bits <= 64);

    const info = @typeInfo(T).int;
    if (comptime info.signedness == .unsigned) {
        return parse_uint(T, buf);
    }

    if (buf.len == 0) return error.EmptyString;

    const first = buf[0];
    const is_neg = first == '-';
    const has_sign = is_neg or (first == '+');
    const start: usize = @intFromBool(has_sign);

    if (start >= buf.len) return error.InvalidString;

    const digits_buf = buf[start..];

    const v: u64 = if (digits_buf.len <= 19)
        try parse_uint_fast(u64, digits_buf)
    else
        try parse_uint_slow(u64, digits_buf);

    // max_abs = maxInt(T) + (1 if negative else 0)
    const max_abs: u64 = @as(u64, std.math.maxInt(T)) + @intFromBool(is_neg);
    if (v > max_abs) return error.Overflow;

    // branchless: if is_neg  (v ^ all1) - all1 == -v in two's complement
    const neg_mask: u64 = 0 -% @as(u64, @intFromBool(is_neg));
    const bits: u64 = (v ^ neg_mask) -% neg_mask;
    const U = std.meta.Int(.unsigned, info.bits);
    return @bitCast(@as(U, @truncate(bits)));
}

test "format_uint" {
    var buf: [BUF_SIZE]u8 = undefined;

    const tests = [_]struct {
        value: u64,
        expected: []const u8,
    }{
        .{ .value = 0, .expected = "0" },
        .{ .value = 1, .expected = "1" },
        .{ .value = 9, .expected = "9" },
        .{ .value = 10, .expected = "10" },
        .{ .value = 99, .expected = "99" },
        .{ .value = 100, .expected = "100" },
        .{ .value = 101, .expected = "101" },
        .{ .value = 999, .expected = "999" },
        .{ .value = 1000, .expected = "1000" },
        .{ .value = 12345, .expected = "12345" },
        .{ .value = 99999, .expected = "99999" },
        .{ .value = 100000, .expected = "100000" },
        .{ .value = 123456789, .expected = "123456789" },
        .{ .value = 1_000_000_000, .expected = "1000000000" },
        .{ .value = 18_446_744_073_709_551_615, .expected = "18446744073709551615" },
    };

    for (tests) |t| {
        const len = format_uint(u64, &buf, t.value);

        try std.testing.expectEqual(t.expected.len, len);
        try std.testing.expectEqualSlices(u8, t.expected, buf[0..len]);
    }
}

test "format_uint boundaries" {
    var buf: [BUF_SIZE]u8 = undefined;

    const values = [_]u64{
        8,
        9,
        10,
        11,
        98,
        99,
        100,
        101,
        998,
        999,
        1000,
        1001,
        9998,
        9999,
        10000,
    };

    for (values) |value| {
        const len = format_uint(u64, &buf, value);

        var expected: [BUF_SIZE]u8 = undefined;
        const expected_len = try std.fmt.bufPrint(&expected, "{d}", .{value});

        try std.testing.expectEqual(expected_len.len, len);
        try std.testing.expectEqualSlices(
            u8,
            expected[0..expected_len.len],
            buf[0..len],
        );
    }
}

const iterations = 10_000_0000;

fn benchCustom() void {
    var buf: [BUF_SIZE]u8 = undefined;
    var sum: usize = 0;

    for (0..iterations) |i| {
        sum += format_uint(u64, &buf, @as(u64, i));
    }

    std.mem.doNotOptimizeAway(sum);
    std.mem.doNotOptimizeAway(buf);
}

fn benchStd() void {
    var buf: [BUF_SIZE]u8 = undefined;
    var sum: usize = 0;

    for (0..iterations) |i| {
        const result = std.fmt.bufPrint(&buf, "{d}", .{@as(u64, i)}) catch unreachable;
        sum += result.len;
    }

    std.mem.doNotOptimizeAway(sum);
    std.mem.doNotOptimizeAway(buf);
}

test "benchmark format_uint" {
    var timer = try std.time.Timer.start();

    timer.reset();
    benchCustom();
    const custom_ns = timer.read();

    timer.reset();
    benchStd();
    const std_ns = timer.read();

    std.debug.print(
        \\
        \\custom: {d} ns
        \\std:    {d} ns
        \\ratio:  {d:.2}x
        \\
    , .{
        custom_ns,
        std_ns,
        @as(f64, @floatFromInt(std_ns)) /
            @as(f64, @floatFromInt(custom_ns)),
    });
}

test "format_int vs std.fmt (signed)" {
    var buf_a: [BUF_SIZE]u8 = undefined;
    var buf_b: [BUF_SIZE]u8 = undefined;

    const tests = [_]i64{
        0,                    1,    -1,  9,    -9,    10,     -10,   99,            -99,            100,                       -100,
        127,                  -128, 128, -129, 32767, -32768, 32768, 2_147_483_647, -2_147_483_648, 9_223_372_036_854_775_807, -9_223_372_036_854_775_807,
        std.math.minInt(i64),
    };

    for (tests) |v| {
        const len_a = format_int(i64, &buf_a, v);
        const ref = try std.fmt.bufPrint(&buf_b, "{d}", .{v});

        try std.testing.expectEqual(ref.len, len_a);
        try std.testing.expectEqualSlices(u8, ref, buf_a[0..len_a]);
    }
}

test "format_int vs std.fmt (i8 exhaustive)" {
    var buf_a: [BUF_SIZE]u8 = undefined;
    var buf_b: [BUF_SIZE]u8 = undefined;

    var v: i16 = std.math.minInt(i8);
    while (v <= std.math.maxInt(i8)) : (v += 1) {
        const x: i8 = @intCast(v);
        const len_a = format_int(i8, &buf_a, x);
        const ref = try std.fmt.bufPrint(&buf_b, "{d}", .{x});
        try std.testing.expectEqual(ref.len, len_a);
        try std.testing.expectEqualSlices(u8, ref, buf_a[0..len_a]);
    }
}

const Bench = struct {
    name: []const u8,
    iterations: usize,
    values: []const u64,
};

fn benchRange(name: []const u8, values: []const u64, iters: usize) !void {
    var buf_a: [BUF_SIZE]u8 = undefined;
    var buf_b: [BUF_SIZE]u8 = undefined;
    var sum_a: usize = 0;
    var sum_b: usize = 0;

    for (values[0..@min(values.len, 4096)]) |v| {
        sum_a +%= format_uint(u64, &buf_a, v);
        const r = std.fmt.bufPrint(&buf_b, "{d}", .{v}) catch unreachable;
        sum_b +%= r.len;
    }

    var timer = try std.time.Timer.start();

    timer.reset();
    {
        var i: usize = 0;
        while (i < iters) : (i += 1) {
            for (values) |v| {
                sum_a +%= format_uint(u64, &buf_a, v);
            }
        }
    }
    const custom_ns = timer.read();

    timer.reset();
    {
        var i: usize = 0;
        while (i < iters) : (i += 1) {
            for (values) |v| {
                const r = std.fmt.bufPrint(&buf_b, "{d}", .{v}) catch unreachable;
                sum_b +%= r.len;
            }
        }
    }
    const std_ns = timer.read();

    std.mem.doNotOptimizeAway(sum_a);
    std.mem.doNotOptimizeAway(sum_b);

    const n_ops = iters * values.len;
    const custom_per = @as(f64, @floatFromInt(custom_ns)) / @as(f64, @floatFromInt(n_ops));
    const std_per = @as(f64, @floatFromInt(std_ns)) / @as(f64, @floatFromInt(n_ops));

    std.debug.print(
        "{s:<20} custom {d:>10.2} ns/op   std {d:>10.2} ns/op   ratio {d:.2}x\n",
        .{ name, custom_per, std_per, std_per / custom_per },
    );
}

fn benchRangeSigned(name: []const u8, values: []const i64, iters: usize) !void {
    var buf_a: [BUF_SIZE]u8 = undefined;
    var buf_b: [BUF_SIZE]u8 = undefined;
    var sum_a: usize = 0;
    var sum_b: usize = 0;

    for (values[0..@min(values.len, 4096)]) |v| {
        sum_a +%= format_int(i64, &buf_a, v);
        const r = std.fmt.bufPrint(&buf_b, "{d}", .{v}) catch unreachable;
        sum_b +%= r.len;
    }

    var timer = try std.time.Timer.start();

    timer.reset();
    {
        var i: usize = 0;
        while (i < iters) : (i += 1) {
            for (values) |v| {
                sum_a +%= format_int(i64, &buf_a, v);
            }
        }
    }
    const custom_ns = timer.read();

    timer.reset();
    {
        var i: usize = 0;
        while (i < iters) : (i += 1) {
            for (values) |v| {
                const r = std.fmt.bufPrint(&buf_b, "{d}", .{v}) catch unreachable;
                sum_b +%= r.len;
            }
        }
    }
    const std_ns = timer.read();

    std.mem.doNotOptimizeAway(sum_a);
    std.mem.doNotOptimizeAway(sum_b);

    const n_ops = iters * values.len;
    const custom_per = @as(f64, @floatFromInt(custom_ns)) / @as(f64, @floatFromInt(n_ops));
    const std_per = @as(f64, @floatFromInt(std_ns)) / @as(f64, @floatFromInt(n_ops));

    std.debug.print(
        "{s:<20} custom {d:>10.2} ns/op   std {d:>10.2} ns/op   ratio {d:.2}x\n",
        .{ name, custom_per, std_per, std_per / custom_per },
    );
}

fn randI64InRange(rand: std.Random, lo: i64, hi: i64) i64 {
    if (lo == std.math.minInt(i64) and hi == std.math.maxInt(i64)) {
        return @bitCast(rand.int(u64));
    }

    const span: u64 = @as(u64, @bitCast(hi -% lo)) + 1;
    return lo +% @as(i64, @bitCast(rand.int(u64) % span));
}

test "benchmark vs std.fmt" {
    const allocator = std.testing.allocator;

    var prng = std.Random.DefaultPrng.init(0xC0FFEE);
    const rand = prng.random();

    var small: [1024]u64 = undefined;
    for (&small) |*x| x.* = rand.intRangeAtMost(u64, 0, 999);

    var mid: [1024]u64 = undefined;
    for (&mid) |*x| x.* = rand.intRangeAtMost(u64, 1_000, 999_999);

    var large: [1024]u64 = undefined;
    for (&large) |*x| x.* = rand.intRangeAtMost(u64, 1_000_000, 999_999_999_999);

    var huge: [1024]u64 = undefined;
    for (&huge) |*x| x.* = rand.intRangeAtMost(u64, 1_000_000_000_000, std.math.maxInt(u64));

    var full: [1024]u64 = undefined;
    for (&full) |*x| x.* = rand.int(u64);

    // --- signed ---
    var s_small: [1024]i64 = undefined;
    for (&s_small) |*x| x.* = randI64InRange(rand, -999, 999);

    var s_mid: [1024]i64 = undefined;
    for (&s_mid) |*x| x.* = randI64InRange(rand, -999_999, 999_999);

    var s_large: [1024]i64 = undefined;
    for (&s_large) |*x| x.* = randI64InRange(rand, -999_999_999_999, 999_999_999_999);

    var s_huge: [1024]i64 = undefined;
    for (&s_huge) |*x| x.* = randI64InRange(
        rand,
        std.math.minInt(i64),
        std.math.maxInt(i64),
    );

    var s_full: [1024]i64 = undefined;
    for (&s_full) |*x| x.* = @bitCast(rand.int(u64));

    std.debug.print("\n=== bench format_uint vs std.fmt ===\n", .{});
    try benchRange("0..999", &small, 20_000);
    try benchRange("1e3..1e6", &mid, 20_000);
    try benchRange("1e6..1e12", &large, 20_000);
    try benchRange("1e12..u64max", &huge, 20_000);
    try benchRange("random u64", &full, 20_000);

    std.debug.print("\n=== bench format_int (i64) vs std.fmt ===\n", .{});
    try benchRangeSigned("i -999..999", &s_small, 20_000);
    try benchRangeSigned("i -1e6..1e6", &s_mid, 20_000);
    try benchRangeSigned("i -1e12..1e12", &s_large, 20_000);
    try benchRangeSigned("i minInt..maxInt", &s_huge, 20_000);
    try benchRangeSigned("i random bits", &s_full, 20_000);

    _ = allocator;
}

test "parse_uint matches std.fmt.parseInt (random u64)" {
    var prng = std.Random.DefaultPrng.init(0xDEADBEEF);
    const rand = prng.random();

    var fmt_buf: [24]u8 = undefined;

    var i: usize = 0;
    while (i < 1_000_000) : (i += 1) {
        const v = rand.int(u64);
        const s = try std.fmt.bufPrint(&fmt_buf, "{d}", .{v});

        const a = try parse_uint(u64, s);
        const b = try std.fmt.parseInt(u64, s, 10);

        try std.testing.expectEqual(b, a);
    }
}

test "parse_uint leading zeros" {
    const cases = [_]struct { s: []const u8, v: u64 }{
        .{ .s = "00000000000000000000000001", .v = 1 },
        .{ .s = "0000000000000000000", .v = 0 },
        .{ .s = "000000000000000000000000", .v = 0 },
        .{ .s = "000000000000000000000000009223372036854775807", .v = 9_223_372_036_854_775_807 },
    };
    for (cases) |c| {
        try std.testing.expectEqual(c.v, try parse_uint(u64, c.s));
    }
}

test "parse_uint overflow" {
    try std.testing.expectError(error.Overflow, parse_uint(u64, "18446744073709551616")); // 2^64
    try std.testing.expectError(error.Overflow, parse_uint(u64, "99999999999999999999"));
    try std.testing.expectError(error.Overflow, parse_uint(u32, "4294967296"));
    try std.testing.expectError(error.Overflow, parse_uint(u8, "256"));

    try std.testing.expectEqual(@as(u64, std.math.maxInt(u64)), try parse_uint(u64, "18446744073709551615"));
    try std.testing.expectEqual(@as(u32, std.math.maxInt(u32)), try parse_uint(u32, "4294967295"));
    try std.testing.expectEqual(@as(u8, 255), try parse_uint(u8, "255"));
}

test "parse_uint invalid / empty" {
    try std.testing.expectError(error.EmptyString, parse_uint(u64, ""));
    try std.testing.expectError(error.InvalidCharacter, parse_uint(u64, "12a34"));
    try std.testing.expectError(error.InvalidCharacter, parse_uint(u64, " 123"));
    try std.testing.expectError(error.InvalidCharacter, parse_uint(u64, "12-34"));
    try std.testing.expectError(error.InvalidCharacter, parse_uint(u64, "12.5"));
}

test "parse_int matches std.fmt.parseInt (random i64)" {
    var prng = std.Random.DefaultPrng.init(0xC0FFEE);
    const rand = prng.random();

    var fmt_buf: [24]u8 = undefined;

    var i: usize = 0;
    while (i < 1_000_000) : (i += 1) {
        const v: i64 = @bitCast(rand.int(u64));
        const s = try std.fmt.bufPrint(&fmt_buf, "{d}", .{v});

        const a = try parse_int(i64, s);
        const b = try std.fmt.parseInt(i64, s, 10);

        try std.testing.expectEqual(b, a);
    }
}

test "parse_int boundaries" {
    inline for (.{ i8, i16, i32, i64 }) |T| {
        var fmt_buf: [24]u8 = undefined;

        const checks = [_]T{
            0,                  1,                  -1,
            std.math.maxInt(T), std.math.minInt(T),
        };
        for (checks) |v| {
            const s = try std.fmt.bufPrint(&fmt_buf, "{d}", .{v});
            try std.testing.expectEqual(v, try parse_int(T, s));
        }
        // +1 к maxInt — overflow
        const s_over = try std.fmt.bufPrint(&fmt_buf, "{d}", .{@as(i128, std.math.maxInt(T)) + 1});
        try std.testing.expectError(error.Overflow, parse_int(T, s_over));
    }
}

test "parse_int sign handling" {
    try std.testing.expectEqual(@as(i32, 123), try parse_int(i32, "+123"));
    try std.testing.expectEqual(@as(i32, -123), try parse_int(i32, "-123"));
    try std.testing.expectEqual(@as(i32, 0), try parse_int(i32, "-0"));
    try std.testing.expectEqual(@as(i32, 0), try parse_int(i32, "+0"));

    try std.testing.expectError(error.InvalidString, parse_int(i32, "-"));
    try std.testing.expectError(error.InvalidString, parse_int(i32, "+"));
    try std.testing.expectError(error.EmptyString, parse_int(i32, ""));
    try std.testing.expectError(error.InvalidCharacter, parse_int(i32, "-12-3"));
}

test "parse_8_digits_swar correctness" {
    var buf: [8]u8 = undefined;
    var i: u64 = 0;
    while (i < 1000) : (i += 1) {
        const s = try std.fmt.bufPrint(&buf, "{d:0>8}", .{i});
        try std.testing.expectEqual(i, parse_8_digits_swar(s, 0).?);
    }
    try std.testing.expectEqual(@as(u64, 12_345_678), parse_8_digits_swar("12345678", 0).?);
    try std.testing.expectEqual(@as(u64, 0), parse_8_digits_swar("00000000", 0).?);
    try std.testing.expectEqual(@as(u64, 99_999_999), parse_8_digits_swar("99999999", 0).?);
    try std.testing.expect(parse_8_digits_swar("12345a78", 0) == null);
    try std.testing.expect(parse_8_digits_swar("1234567:", 0) == null);
    try std.testing.expect(parse_8_digits_swar("12 45678", 0) == null);
}

fn benchParse(
    comptime T: type,
    name: []const u8,
    strings: []const []const u8,
    iters: usize,
) !void {
    var sum: u64 = 0;

    for (strings[0..@min(strings.len, 256)]) |s| {
        if (comptime @typeInfo(T).int.signedness == .signed) {
            sum +%= @bitCast(parse_int(T, s) catch 0);
        } else {
            sum +%= parse_uint(T, s) catch 0;
        }
    }

    var timer = try std.time.Timer.start();

    timer.reset();
    {
        var i: usize = 0;
        while (i < iters) : (i += 1) {
            for (strings) |s| {
                if (comptime @typeInfo(T).int.signedness == .signed) {
                    sum +%= @bitCast(parse_int(T, s) catch 0);
                } else {
                    sum +%= parse_uint(T, s) catch 0;
                }
            }
        }
    }
    const custom_ns = timer.read();

    timer.reset();
    {
        var i: usize = 0;
        while (i < iters) : (i += 1) {
            for (strings) |s| {
                sum +%= @bitCast(std.fmt.parseInt(T, s, 10) catch 0);
            }
        }
    }
    const std_ns = timer.read();

    std.mem.doNotOptimizeAway(sum);

    const n_ops = iters * strings.len;
    const custom_per = @as(f64, @floatFromInt(custom_ns)) / @as(f64, @floatFromInt(n_ops));
    const std_per = @as(f64, @floatFromInt(std_ns)) / @as(f64, @floatFromInt(n_ops));

    std.debug.print(
        "{s:<22} custom {d:>8.2} ns/op   std {d:>8.2} ns/op   ratio {d:.2}x\n",
        .{ name, custom_per, std_per, std_per / custom_per },
    );
}

fn generateUnsignedStrings(
    allocator: std.mem.Allocator,
    rand: std.Random,
    count: usize,
    min_digits: usize,
    max_digits: usize,
) ![]const []const u8 {
    const list = try allocator.alloc([]const u8, count);
    for (list) |*s| {
        const nd = rand.intRangeAtMost(usize, min_digits, max_digits);
        const buf = try allocator.alloc(u8, nd);
        buf[0] = '1' + @as(u8, @intCast(rand.intRangeAtMost(u8, 0, 8)));
        for (buf[1..]) |*c| {
            c.* = '0' + @as(u8, @intCast(rand.intRangeAtMost(u8, 0, 9)));
        }
        s.* = buf;
    }
    return list;
}

fn generateSignedStrings(
    allocator: std.mem.Allocator,
    rand: std.Random,
    count: usize,
    min_digits: usize,
    max_digits: usize,
) ![]const []const u8 {
    const list = try allocator.alloc([]const u8, count);
    for (list) |*s| {
        const nd = rand.intRangeAtMost(usize, min_digits, max_digits);
        const neg = rand.boolean();
        const len = nd + @as(usize, if (neg) 1 else 0);
        const buf = try allocator.alloc(u8, len);
        var pos: usize = 0;
        if (neg) {
            buf[0] = '-';
            pos = 1;
        }
        buf[pos] = '1' + @as(u8, @intCast(rand.intRangeAtMost(u8, 0, 8)));
        for (buf[pos + 1 ..]) |*c| {
            c.* = '0' + @as(u8, @intCast(rand.intRangeAtMost(u8, 0, 9)));
        }
        s.* = buf;
    }
    return list;
}

test "benchmark parse vs std.fmt.parseInt" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var prng = std.Random.DefaultPrng.init(0xBADC0FFE);
    const rand = prng.random();

    const N = 4096;
    const iters = 5_000;

    const u_small = try generateUnsignedStrings(allocator, rand, N, 1, 3);
    const u_mid = try generateUnsignedStrings(allocator, rand, N, 4, 9);
    const u_large = try generateUnsignedStrings(allocator, rand, N, 10, 15);
    const u_huge = try generateUnsignedStrings(allocator, rand, N, 16, 19);
    const u_over20 = try generateUnsignedStrings(allocator, rand, N, 20, 20);

    const i_small = try generateSignedStrings(allocator, rand, N, 1, 3);
    const i_mid = try generateSignedStrings(allocator, rand, N, 4, 9);
    const i_large = try generateSignedStrings(allocator, rand, N, 10, 15);
    const i_huge = try generateSignedStrings(allocator, rand, N, 16, 19);

    std.debug.print("\n=== bench parse vs std.fmt.parseInt ===\n", .{});
    try benchParse(u64, "u 1..3 digits", u_small, iters);
    try benchParse(u64, "u 4..9 digits", u_mid, iters);
    try benchParse(u64, "u 10..15 digits", u_large, iters);
    try benchParse(u64, "u 16..19 digits", u_huge, iters);
    try benchParse(u64, "u 20 digits", u_over20, iters);

    std.debug.print("\n", .{});
    try benchParse(i64, "i 1..3 digits", i_small, iters);
    try benchParse(i64, "i 4..9 digits", i_mid, iters);
    try benchParse(i64, "i 10..15 digits", i_large, iters);
    try benchParse(i64, "i 16..19 digits", i_huge, iters);
}
