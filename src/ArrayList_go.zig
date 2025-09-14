const std = @import("std");
const Allocator = std.mem.Allocator;
const lib = @import("lib.zig");
const assert = std.debug.assert;

pub fn ArrayList(comptime T: type, comptime alignment: ?std.mem.Alignment) type {
    return struct {
        const Self = @This();
        items: Slice,
        capacity: usize,
        allocator: Allocator,

        pub const Slice = if (alignment) |a| ([]align(a.toByteUnits()) T) else []T;

        pub fn init(allocator: Allocator) Self {
            return .{
                .items = &[_]T{},
                .capacity = 0,
                .allocator = allocator,
            };
        }

        pub fn initCapacity(allocator: Allocator, cp: usize) Allocator.Error!Self {
            var list = Self.init(allocator);
            try list.ensureTotalCapacity(cp);
            return list;
        }

        pub fn deinit(self: *Self) void {
            if (@sizeOf(T) > 0) {
                self.allocator.free(self.allocatedSlice());
            }
            self.* = .{
                .items = &[_]T{},
                .capacity = 0,
                .allocator = self.allocator,
            };
        }

        // len go
        pub fn len(self: Self) usize {
            return self.items.len;
        }

        // cap go
        pub fn cap(self: Self) usize {
            return self.capacity;
        }

        // slice[:]  Go
        pub fn slice(self: Self) Slice {
            return self.items;
        }

        // slice[i:j]
        pub fn sliceRange(self: Self, start: usize, end: usize) Slice {
            assert(start <= end and end <= self.items.len);
            return self.items[start..end];
        }

        //  append(slice, x)  Go
        pub fn append(self: *Self, item: T) Allocator.Error!void {
            const new_item_ptr = try self.addOne();
            new_item_ptr.* = item;
        }

        //  append(slice, x...)  Go
        pub fn appendSlice(self: *Self, items: []const T) Allocator.Error!void {
            const old_len = self.items.len;
            try self.ensureTotalCapacity(self.items.len + items.len);
            lib.move(T, self.items[old_len..], items);
            self.items.len += items.len;
        }

        inline fn addOne(self: *Self) Allocator.Error!*T {
            try self.ensureTotalCapacity(self.items.len + 1);
            self.items.len += 1;
            return &self.items[self.items.len - 1];
        }

        inline fn ensureTotalCapacity(self: *Self, new_capacity: usize) Allocator.Error!void {
            if (@sizeOf(T) == 0) {
                self.capacity = std.math.maxInt(usize);
                return;
            }
            if (self.capacity >= new_capacity) return;

            const new_cap = growCapacity(self.capacity, new_capacity);
            const old_memory = self.allocatedSlice();
            if (self.allocator.resize(old_memory, new_cap)) |new_memory| {
                self.items.ptr = new_memory.ptr;
                self.capacity = new_memory.len;
            } else {
                const new_memory = try self.allocator.alignedAlloc(T, alignment, new_cap);
                lib.move(T, new_memory[0..self.items.len], self.items);
                self.allocator.free(old_memory);
                self.items.ptr = new_memory.ptr;
                self.capacity = new_memory.len;
            }
        }

        fn allocatedSlice(self: Self) Slice {
            return self.items.ptr[0..self.capacity];
        }

        inline fn growCapacity(current: usize, minimum: usize) usize {
            var new = current;
            const init_capacity = @max(1, std.atomic.cache_line / @sizeOf(T));
            while (true) {
                new = new * 2 + init_capacity;
                if (new >= minimum) return new;
            }
        }
    };
}
