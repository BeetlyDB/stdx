const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;

pub const StringView = struct {
    ptr: [*]const u8,
    len: usize,

    pub fn init(slice: []const u8) StringView {
        return .{ .ptr = slice.ptr, .len = slice.len };
    }

    pub fn fromCStr(cstr: [*:0]const u8) StringView {
        return .{ .ptr = cstr, .len = mem.len(cstr) };
    }

    //  string literal (comptime)
    pub fn fromLiteral(comptime literal: []const u8) StringView {
        return .{ .ptr = literal.ptr, .len = literal.len };
    }

    pub fn empty() StringView {
        return .{ .ptr = undefined, .len = 0 };
    }

    // get slice Zig API
    pub fn asSlice(self: StringView) []const u8 {
        return self.ptr[0..self.len];
    }

    // len string
    pub fn size(self: StringView) usize {
        return self.len;
    }

    pub fn isEmpty(self: StringView) bool {
        return self.len == 0;
    }

    pub fn at(self: StringView, index: usize) error{IndexOutOfBounds}!u8 {
        if (index >= self.len) return error.IndexOutOfBounds;
        return self.ptr[index];
    }

    pub fn substr(self: StringView, pos: usize, len: ?usize) error{IndexOutOfBounds}!StringView {
        if (pos > self.len) return error.IndexOutOfBounds;
        const max_len = self.len - pos;
        const sub_len = @min(len orelse max_len, max_len);
        return .{ .ptr = self.ptr + pos, .len = sub_len };
    }

    pub fn startsWith(self: StringView, prefix: StringView) bool {
        if (prefix.len > self.len) return false;
        return mem.eql(u8, self.ptr[0..prefix.len], prefix.ptr[0..prefix.len]);
    }

    pub fn endsWith(self: StringView, suffix: StringView) bool {
        if (suffix.len > self.len) return false;
        return mem.eql(u8, self.ptr[self.len - suffix.len .. self.len], suffix.ptr[0..suffix.len]);
    }

    pub inline fn find(self: StringView, needle: StringView) ?usize {
        if (needle.len == 0 or needle.len > self.len) return null;
        return mem.indexOf(u8, self.asSlice(), needle.asSlice());
    }

    pub inline fn rfind(self: StringView, needle: StringView) ?usize {
        if (needle.len == 0 or needle.len > self.len) return null;
        return mem.lastIndexOf(u8, self.asSlice(), needle.asSlice());
    }

    pub inline fn removePrefix(self: *StringView, n: usize) error{IndexOutOfBounds}!void {
        if (n > self.len) return error.IndexOutOfBounds;
        self.ptr += n;
        self.len -= n;
    }

    pub inline fn removeSuffix(self: *StringView, n: usize) error{IndexOutOfBounds}!void {
        if (n > self.len) return error.IndexOutOfBounds;
        self.len -= n;
    }

    pub inline fn compare(self: StringView, other: StringView) std.math.Order {
        return mem.order(u8, self.asSlice(), other.asSlice());
    }

    pub inline fn eql(self: StringView, other: StringView) bool {
        return self.len == other.len and mem.eql(u8, self.asSlice(), other.asSlice());
    }
};

// Тесты
test "StringView basics" {
    const expect = std.testing.expect;
    const expectEqual = std.testing.expectEqual;
    const expectError = std.testing.expectError;

    const str = StringView.init("hello, world");
    try expectEqual(12, str.size());
    try expect(!str.isEmpty());

    try expectEqual('h', try str.at(0));
    try expectEqual('d', try str.at(11));
    try expectError(error.IndexOutOfBounds, str.at(12));

    const sub = try str.substr(7, 5);
    try expect(sub.eql(StringView.init("world")));
    try expectError(error.IndexOutOfBounds, str.substr(13, 1));

    try expect(str.startsWith(StringView.init("hello")));
    try expect(str.endsWith(StringView.init("world")));
    try expect(!str.startsWith(StringView.init("world")));
    try expect(!str.endsWith(StringView.init("hello")));

    try expectEqual(7, str.find(StringView.init("world")));
    try expectEqual(0, str.find(StringView.init("hello")));
    try expectEqual(null, str.find(StringView.init("notfound")));
    try expectEqual(7, str.rfind(StringView.init("world")));
    try expectEqual(0, str.rfind(StringView.init("hello")));

    var mutable = str;
    try mutable.removePrefix(7);
    try expect(mutable.eql(StringView.init("world")));
    try mutable.removeSuffix(2);
    try expect(mutable.eql(StringView.init("wor")));
    try expectError(error.IndexOutOfBounds, mutable.removePrefix(4));

    const other = StringView.init("hello, world");
    try expect(str.eql(other));
    try expect(str.compare(StringView.init("hello")) == .gt);
    try expect(str.compare(StringView.init("z")) == .lt);
}
