const std = @import("std");

const Thread = std.Thread;
const Allocator = std.mem.Allocator;

pub const GrowingOpts = struct {
    count: usize,
};

pub fn Growing(comptime T: type, comptime C: type) type {
    return struct {
        _ctx: C,
        _items: []*T,
        _available: usize,
        _mutex: Thread.Mutex,
        _allocator: Allocator,

        const Self = @This();

        pub fn init(allocator: Allocator, ctx: C, opts: GrowingOpts) !Self {
            const count = opts.count;

            const items = try allocator.alloc(*T, count);
            errdefer allocator.free(items);

            var initialized: usize = 0;
            errdefer {
                for (0..initialized) |i| {
                    items[i].deinit();
                    allocator.destroy(items[i]);
                }
            }

            for (0..count) |i| {
                items[i] = try allocator.create(T);
                errdefer allocator.destroy(items[i]);
                items[i].* = if (C == void) try T.init(allocator) else try T.init(allocator, ctx);
                initialized += 1;
            }

            return .{
                ._ctx = ctx,
                ._mutex = .{},
                ._items = items,
                ._available = count,
                ._allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            const allocator = self._allocator;
            for (self._items) |item| {
                item.deinit();
                allocator.destroy(item);
            }
            allocator.free(self._items);
        }

        pub fn acquire(self: *Self) !*T {
            const items = self._items;

            self._mutex.lock();
            const available = self._available;
            if (available == 0) {
                // dont hold the lock over factory
                self._mutex.unlock();

                const allocator = self._allocator;
                const item = try allocator.create(T);
                item.* = if (C == void) try T.init(allocator) else try T.init(allocator, self._ctx);
                return item;
            }

            const index = available - 1;
            const item = items[index];
            self._available = index;
            self._mutex.unlock();
            return item;
        }

        pub fn release(self: *Self, item: *T) void {
            item.reset();

            var items = self._items;
            self._mutex.lock();
            const available = self._available;
            if (available == items.len) {
                self._mutex.unlock();
                item.deinit();
                self._allocator.destroy(item);
                return;
            }
            items[available] = item;
            self._available = available + 1;
            self._mutex.unlock();
        }
    };
}

pub const TraitFn = fn (type) bool;

fn isStringArray(comptime T: type) bool {
    if (!is(.array)(T) and !isPtrTo(.array)(T)) {
        return false;
    }
    return std.meta.Elem(T) == u8;
}

pub fn isPtrTo(comptime id: std.builtin.TypeId) TraitFn {
    const Closure = struct {
        pub fn trait(comptime T: type) bool {
            if (!comptime isSingleItemPtr(T)) return false;
            return id == @typeInfo(std.meta.Child(T));
        }
    };
    return Closure.trait;
}

pub fn isSingleItemPtr(comptime T: type) bool {
    if (comptime is(.pointer)(T)) {
        return @typeInfo(T).pointer.size == .one;
    }
    return false;
}

pub fn is(comptime id: std.builtin.TypeId) TraitFn {
    const Closure = struct {
        pub fn trait(comptime T: type) bool {
            return id == @typeInfo(T);
        }
    };
    return Closure.trait;
}

fn expectStrings(expected: []const []const u8, actual: anytype) !void {
    try expectEqual(expected.len, actual.len);
    for (expected, actual) |e, a| {
        try std.testing.expectEqualStrings(e, a);
    }
}

pub fn expectEqual(expected: anytype, actual: anytype) !void {
    switch (@typeInfo(@TypeOf(actual))) {
        .array => |arr| if (arr.child == u8) {
            return std.testing.expectEqualStrings(expected, &actual);
        },
        .pointer => |ptr| if (ptr.child == u8) {
            return std.testing.expectEqualStrings(expected, actual);
        } else if (comptime isStringArray(ptr.child)) {
            return std.testing.expectEqualStrings(expected, actual);
        } else if (ptr.child == []u8 or ptr.child == []const u8) {
            return expectStrings(expected, actual);
        },
        .@"struct" => |structType| {
            inline for (structType.fields) |field| {
                try expectEqual(@field(expected, field.name), @field(actual, field.name));
            }
            return;
        },
        .@"union" => |union_info| {
            if (union_info.tag_type == null) {
                @compileError("Unable to compare untagged union values");
            }
            const Tag = std.meta.Tag(@TypeOf(expected));

            const expectedTag = @as(Tag, expected);
            const actualTag = @as(Tag, actual);
            try expectEqual(expectedTag, actualTag);

            inline for (std.meta.fields(@TypeOf(actual))) |fld| {
                if (std.mem.eql(u8, fld.name, @tagName(actualTag))) {
                    try expectEqual(@field(expected, fld.name), @field(actual, fld.name));
                    return;
                }
            }
            unreachable;
        },
        else => {},
    }
    return std.testing.expectEqual(@as(@TypeOf(actual), expected), actual);
}

test "pool: acquire and release" {
    var p = try Growing(TestPoolItem, void).init(std.testing.allocator, {}, .{ .count = 2 });
    defer p.deinit();

    const i1a = try p.acquire();
    try expectEqual(0, i1a.data[0]);
    i1a.data[0] = 250;

    const i2a = try p.acquire();
    const i3a = try p.acquire(); // this should be dynamically generated

    try expectEqual(false, i1a.data.ptr == i2a.data.ptr);
    try expectEqual(false, i2a.data.ptr == i3a.data.ptr);

    p.release(i1a);

    const i1b = try p.acquire();
    try expectEqual(0, i1b.data[0]);
    try expectEqual(true, i1a.data.ptr == i1b.data.ptr);

    p.release(i3a);
    p.release(i2a);
    p.release(i1b);
}

fn testPool(p: *Growing(TestPoolItem, void)) void {
    const random = std.Random.DefaultPrng.init(0);

    for (0..5000) |_| {
        var sb = p.acquire() catch unreachable;
        // no other thread should have set this to 255
        std.debug.assert(sb.data[0] == 0);

        sb.data[0] = 255;
        std.Thread.sleep(random.uintAtMost(u32, 100000));
        sb.data[0] = 0;
        p.release(sb);
    }
}

const TestPoolItem = struct {
    data: []u8,
    allocator: Allocator,

    fn init(allocator: Allocator) !TestPoolItem {
        const data = try allocator.alloc(u8, 1);
        data[0] = 0;

        return .{
            .data = data,
            .allocator = allocator,
        };
    }

    fn deinit(self: *TestPoolItem) void {
        self.allocator.free(self.data);
    }

    fn reset(self: *TestPoolItem) void {
        self.data[0] = 0;
    }
};
