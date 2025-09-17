const std = @import("std");

pub fn ComptimeArrayList(comptime T: type) type {
    return struct {
        items: []T,
        capacity: usize,

        const Self = @This();

        pub const empty: Self = .{ .items = &.{}, .capacity = 0 };

        pub fn append(cal: *Self, val: T) void {
            cal.ensureCapacity(cal.items.len + 1);
            cal.items.ptr[cal.items.len] = val;
            cal.items.len += 1;
        }

        pub fn appendSlice(cal: *Self, vals: []const T) void {
            cal.ensureCapacity(cal.items.len + vals.len);
            @memcpy(cal.items.ptr[cal.items.len..], vals);
            cal.items.len += vals.len;
        }

        pub fn ensureCapacity(cal: *Self, need_capacity: usize) void {
            if (cal.capacity >= need_capacity) return;
            var cap: usize = @max(cal.capacity, 16);
            while (cap < need_capacity) cap *= 2;
            var new_items: [cap]T = undefined;
            @memcpy(new_items[0..cal.items.len], cal.items);
            cal.items = new_items[0..cal.items.len];
            cal.capacity = cap;
        }
    };
}
