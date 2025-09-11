const std = @import("std");
const lib = @import("lib.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const assert = std.debug.assert;
const math = std.math;
const testing = std.testing;

pub fn AlignedList(comptime T: type, comptime alignment: ?mem.Alignment) type {
    const init_capacity = @as(comptime_int, @max(1, std.atomic.cache_line / @sizeOf(T)));

    if (alignment) |a| {
        if (a.toByteUnits() == @alignOf(T)) {
            return AlignedList(T, null);
        }
    }
    return struct {
        const Self = @This();
        items: Slice,
        /// How many T values this list can hold without allocating
        /// additional memory.
        capacity: usize,
        allocator: Allocator,

        pub const Slice = if (alignment) |a| ([]align(a.toByteUnits()) T) else []T;

        pub fn SentinelSlice(comptime s: T) type {
            return if (alignment) |a| ([:s]align(a.toByteUnits()) T) else [:s]T;
        }

        pub fn initBuffer(buffer: Slice) Self {
            return .{
                .items = buffer[0..0],
                .capacity = buffer.len,
            };
        }

        /// Deinitialize with `deinit` or use `toOwnedSlice`.
        pub fn init(gpa: Allocator) Self {
            return Self{
                .items = &[_]T{},
                .capacity = 0,
                .allocator = gpa,
            };
        }

        /// Initialize with capacity to hold `num` elements.
        /// The resulting capacity will equal `num` exactly.
        /// Deinitialize with `deinit` or use `toOwnedSlice`.
        pub fn initCapacity(gpa: Allocator, num: usize) Allocator.Error!Self {
            var self = Self.init(gpa);
            try self.ensureTotalCapacityPrecise(num);
            return self;
        }

        /// Release all allocated memory.
        pub fn deinit(self: Self) void {
            if (@sizeOf(T) > 0) {
                self.allocator.free(self.allocatedSlice());
            }
        }

        /// ArrayList takes ownership of the passed in slice. The slice must have been
        /// allocated with `gpa`.
        /// Deinitialize with `deinit` or use `toOwnedSlice`.
        pub fn fromOwnedSlice(gpa: Allocator, slice: Slice) Self {
            return Self{
                .items = slice,
                .capacity = slice.len,
                .allocator = gpa,
            };
        }

        /// ArrayList takes ownership of the passed in slice. The slice must have been
        /// allocated with `gpa`.
        /// Deinitialize with `deinit` or use `toOwnedSlice`.
        pub fn fromOwnedSliceSentinel(gpa: Allocator, comptime sentinel: T, slice: [:sentinel]T) Self {
            return Self{
                .items = slice,
                .capacity = slice.len + 1,
                .allocator = gpa,
            };
        }

        /// Initializes an ArrayList with the `items` and `capacity` fields
        /// of this ArrayList. Empties this ArrayList.
        pub fn moveToUnmanaged(self: *Self) AlignedList(T, alignment) {
            const allocator = self.allocator;
            const result: AlignedList(T, alignment) = .{ .items = self.items, .capacity = self.capacity };
            self.* = init(allocator);
            return result;
        }

        /// The caller owns the returned memory. Empties this ArrayList.
        /// Its capacity is cleared, making `deinit` safe but unnecessary to call.
        pub fn toOwnedSlice(self: *Self) Allocator.Error!Slice {
            const allocator = self.allocator;

            const old_memory = self.allocatedSlice();
            if (allocator.remap(old_memory, self.items.len)) |new_items| {
                self.* = init(allocator);
                return new_items;
            }

            const new_memory = try allocator.alignedAlloc(T, alignment, self.items.len);
            lib.copy(T, new_memory, self.items);
            self.clearAndFree();
            return new_memory;
        }

        /// The caller owns the returned memory. Empties this ArrayList.
        pub fn toOwnedSliceSentinel(self: *Self, comptime sentinel: T) Allocator.Error!SentinelSlice(sentinel) {
            // This addition can never overflow because `self.items` can never occupy the whole address space
            try self.ensureTotalCapacityPrecise(self.items.len + 1);
            self.appendAssumeCapacity(sentinel);
            const result = try self.toOwnedSlice();
            return result[0 .. result.len - 1 :sentinel];
        }

        /// Creates a copy of this ArrayList, using the same allocator.
        pub fn clone(self: Self) Allocator.Error!Self {
            var cloned = try Self.initCapacity(self.allocator, self.capacity);
            cloned.appendSliceAssumeCapacity(self.items);
            return cloned;
        }

        /// Insert `item` at index `i`. Moves `list[i .. list.len]` to higher indices to make room.
        /// If `i` is equal to the length of the list this operation is equivalent to append.
        /// This operation is O(N).
        /// Invalidates element pointers if additional memory is needed.
        /// Asserts that the index is in bounds or equal to the length.
        pub fn insert(self: *Self, i: usize, item: T) Allocator.Error!void {
            const dst = try self.addManyAt(i, 1);
            dst[0] = item;
        }

        /// Insert `item` at index `i`. Moves `list[i .. list.len]` to higher indices to make room.
        /// If `i` is equal to the length of the list this operation is
        /// equivalent to appendAssumeCapacity.
        /// This operation is O(N).
        /// Asserts that there is enough capacity for the new item.
        /// Asserts that the index is in bounds or equal to the length.
        pub fn insertAssumeCapacity(self: *Self, i: usize, item: T) void {
            assert(self.items.len < self.capacity);
            self.items.len += 1;

            lib.move(T, self.items[i + 1 .. self.items.len], self.items[i .. self.items.len - 1]);
            self.items[i] = item;
        }

        inline fn addOrOom(a: usize, b: usize) error{OutOfMemory}!usize {
            const result, const overflow = @addWithOverflow(a, b);
            if (overflow != 0) return error.OutOfMemory;
            return result;
        }

        /// Add `count` new elements at position `index`, which have
        /// `undefined` values. Returns a slice pointing to the newly allocated
        /// elements, which becomes invalid after various `ArrayList`
        /// operations.
        /// Invalidates pre-existing pointers to elements at and after `index`.
        /// Invalidates all pre-existing element pointers if capacity must be
        /// increased to accommodate the new elements.
        /// Asserts that the index is in bounds or equal to the length.
        pub fn addManyAt(self: *Self, index: usize, count: usize) Allocator.Error![]T {
            const new_len = try addOrOom(self.items.len, count);

            if (self.capacity >= new_len)
                return addManyAtAssumeCapacity(self, index, count);

            // Here we avoid copying allocated but unused bytes by
            // attempting a resize in place, and falling back to allocating
            // a new buffer and doing our own copy. With a realloc() call,
            // the allocator implementation would pointlessly copy our
            // extra capacity.
            const new_capacity = AlignedList(T, alignment).growCapacity(self.capacity, new_len);
            const old_memory = self.allocatedSlice();
            if (self.allocator.remap(old_memory, new_capacity)) |new_memory| {
                self.items.ptr = new_memory.ptr;
                self.capacity = new_memory.len;
                return addManyAtAssumeCapacity(self, index, count);
            }

            // Make a new allocation, avoiding `ensureTotalCapacity` in order
            // to avoid extra memory copies.
            const new_memory = try self.allocator.alignedAlloc(T, alignment, new_capacity);
            const to_move = self.items[index..];
            lib.move(T, new_memory[0..index], self.items[0..index]);
            lib.move(T, new_memory[index + count ..][0..to_move.len], to_move);
            self.allocator.free(old_memory);
            self.items = new_memory[0..new_len];
            self.capacity = new_memory.len;
            // The inserted elements at `new_memory[index..][0..count]` have
            // already been set to `undefined` by memory allocation.
            return new_memory[index..][0..count];
        }

        /// Add `count` new elements at position `index`, which have
        /// `undefined` values. Returns a slice pointing to the newly allocated
        /// elements, which becomes invalid after various `ArrayList`
        /// operations.
        /// Asserts that there is enough capacity for the new elements.
        /// Invalidates pre-existing pointers to elements at and after `index`, but
        /// does not invalidate any before that.
        /// Asserts that the index is in bounds or equal to the length.
        pub fn addManyAtAssumeCapacity(self: *Self, index: usize, count: usize) []T {
            const new_len = self.items.len + count;
            assert(self.capacity >= new_len);
            const to_move = self.items[index..];
            self.items.len = new_len;
            lib.move(T, self.items[index + count ..][0..to_move.len], to_move);
            const result = self.items[index..][0..count];
            lib.set(u8, std.mem.asBytes(result), 0);
            return result;
        }

        /// Insert slice `items` at index `i` by moving `list[i .. list.len]` to make room.
        /// This operation is O(N).
        /// Invalidates pre-existing pointers to elements at and after `index`.
        /// Invalidates all pre-existing element pointers if capacity must be
        /// increased to accommodate the new elements.
        /// Asserts that the index is in bounds or equal to the length.
        pub fn insertSlice(
            self: *Self,
            index: usize,
            items: []const T,
        ) Allocator.Error!void {
            const dst = try self.addManyAt(index, items.len);
            lib.move(T, dst, items);
        }

        /// Grows or shrinks the list as necessary.
        /// Invalidates element pointers if additional capacity is allocated.
        /// Asserts that the range is in bounds.
        pub fn replaceRange(self: *Self, start: usize, len: usize, new_items: []const T) Allocator.Error!void {
            var unmanaged = self.moveToUnmanaged();
            defer self.* = unmanaged.toManaged(self.allocator);
            return unmanaged.replaceRange(self.allocator, start, len, new_items);
        }

        /// Grows or shrinks the list as necessary.
        /// Never invalidates element pointers.
        /// Asserts the capacity is enough for additional items.
        pub fn replaceRangeAssumeCapacity(self: *Self, start: usize, len: usize, new_items: []const T) void {
            var unmanaged = self.moveToUnmanaged();
            defer self.* = unmanaged.toManaged(self.allocator);
            return unmanaged.replaceRangeAssumeCapacity(start, len, new_items);
        }

        /// Extends the list by 1 element. Allocates more memory as necessary.
        /// Invalidates element pointers if additional memory is needed.
        pub inline fn append(self: *Self, item: T) Allocator.Error!void {
            const new_item_ptr = try self.addOne();
            new_item_ptr.* = item;
        }

        /// Extends the list by 1 element.
        /// Never invalidates element pointers.
        /// Asserts that the list can hold one additional item.
        pub fn appendAssumeCapacity(self: *Self, item: T) void {
            self.addOneAssumeCapacity().* = item;
        }

        /// Remove the element at index `i`, shift elements after index
        /// `i` forward, and return the removed element.
        /// Invalidates element pointers to end of list.
        /// This operation is O(N).
        /// This preserves item order. Use `swapRemove` if order preservation is not important.
        /// Asserts that the index is in bounds.
        /// Asserts that the list is not empty.
        pub fn orderedRemove(self: *Self, i: usize) T {
            const old_item = self.items[i];
            self.replaceRangeAssumeCapacity(i, 1, &.{});
            return old_item;
        }

        /// Removes the element at the specified index and returns it.
        /// The empty slot is filled from the end of the list.
        /// This operation is O(1).
        /// This may not preserve item order. Use `orderedRemove` if you need to preserve order.
        /// Asserts that the list is not empty.
        /// Asserts that the index is in bounds.
        pub fn swapRemove(self: *Self, i: usize) T {
            if (self.items.len - 1 == i) return self.pop().?;

            const old_item = self.items[i];
            self.items[i] = self.pop().?;
            return old_item;
        }

        /// Append the slice of items to the list. Allocates more
        /// memory as necessary.
        /// Invalidates element pointers if additional memory is needed.
        pub fn appendSlice(self: *Self, items: []const T) Allocator.Error!void {
            try self.ensureUnusedCapacity(items.len);
            self.appendSliceAssumeCapacity(items);
        }

        /// Append the slice of items to the list.
        /// Never invalidates element pointers.
        /// Asserts that the list can hold the additional items.
        pub fn appendSliceAssumeCapacity(self: *Self, items: []const T) void {
            const old_len = self.items.len;
            const new_len = old_len + items.len;
            assert(new_len <= self.capacity);
            self.items.len = new_len;
            lib.move(T, self.items[old_len..][0..items.len], items);
        }

        /// Append an unaligned slice of items to the list. Allocates more
        /// memory as necessary. Only call this function if calling
        /// `appendSlice` instead would be a compile error.
        /// Invalidates element pointers if additional memory is needed.
        pub fn appendUnalignedSlice(self: *Self, items: []align(1) const T) Allocator.Error!void {
            try self.ensureUnusedCapacity(items.len);
            self.appendUnalignedSliceAssumeCapacity(items);
        }

        /// Append the slice of items to the list.
        /// Never invalidates element pointers.
        /// This function is only needed when calling
        /// `appendSliceAssumeCapacity` instead would be a compile error due to the
        /// alignment of the `items` parameter.
        /// Asserts that the list can hold the additional items.
        pub inline fn appendUnalignedSliceAssumeCapacity(self: *Self, items: []align(1) const T) void {
            const old_len = self.items.len;
            const new_len = old_len + items.len;
            assert(new_len <= self.capacity);
            self.items.len = new_len;
            @memmove(self.items[old_len..][0..items.len], items);
        }

        pub fn print(self: *Self, comptime fmt: []const u8, args: anytype) error{OutOfMemory}!void {
            const gpa = self.allocator;
            var unmanaged = self.moveToUnmanaged();
            defer self.* = unmanaged.toManaged(gpa);
            try unmanaged.print(gpa, fmt, args);
        }

        pub const Writer = if (T != u8) void else std.io.GenericWriter(*Self, Allocator.Error, appendWrite);

        /// Initializes a Writer which will append to the list.
        pub fn writer(self: *Self) Writer {
            return .{ .context = self };
        }

        /// Same as `append` except it returns the number of bytes written, which is always the same
        /// as `m.len`. The purpose of this function existing is to match `std.io.GenericWriter` API.
        /// Invalidates element pointers if additional memory is needed.
        fn appendWrite(self: *Self, m: []const u8) Allocator.Error!usize {
            try self.appendSlice(m);
            return m.len;
        }

        pub const FixedWriter = std.io.GenericWriter(*Self, Allocator.Error, appendWriteFixed);

        /// Initializes a Writer which will append to the list but will return
        /// `error.OutOfMemory` rather than increasing capacity.
        pub fn fixedWriter(self: *Self) FixedWriter {
            return .{ .context = self };
        }

        /// The purpose of this function existing is to match `std.io.GenericWriter` API.
        fn appendWriteFixed(self: *Self, m: []const u8) error{OutOfMemory}!usize {
            const available_capacity = self.capacity - self.items.len;
            if (m.len > available_capacity)
                return error.OutOfMemory;

            self.appendSliceAssumeCapacity(m);
            return m.len;
        }

        /// Append a value to the list `n` times.
        /// Allocates more memory as necessary.
        /// Invalidates element pointers if additional memory is needed.
        /// The function is inline so that a comptime-known `value` parameter will
        /// have a more optimal memset codegen in case it has a repeated byte pattern.
        pub inline fn appendNTimes(self: *Self, value: T, n: usize) Allocator.Error!void {
            const old_len = self.items.len;
            try self.resize(try addOrOom(old_len, n));
            @memset(self.items[old_len..self.items.len], value);
        }

        /// Append a value to the list `n` times.
        /// Never invalidates element pointers.
        /// The function is inline so that a comptime-known `value` parameter will
        /// have a more optimal memset codegen in case it has a repeated byte pattern.
        /// Asserts that the list can hold the additional items.
        pub inline fn appendNTimesAssumeCapacity(self: *Self, value: T, n: usize) void {
            const new_len = self.items.len + n;
            assert(new_len <= self.capacity);
            @memset(self.items.ptr[self.items.len..new_len], value);
            self.items.len = new_len;
        }

        /// Adjust the list length to `new_len`.
        /// Additional elements contain the value `undefined`.
        /// Invalidates element pointers if additional memory is needed.
        pub fn resize(self: *Self, new_len: usize) Allocator.Error!void {
            try self.ensureTotalCapacity(new_len);
            self.items.len = new_len;
        }

        /// Reduce allocated capacity to `new_len`.
        /// May invalidate element pointers.
        /// Asserts that the new length is less than or equal to the previous length.
        pub fn shrinkAndFree(self: *Self, new_len: usize) void {
            var unmanaged = self.moveToUnmanaged();
            unmanaged.shrinkAndFree(self.allocator, new_len);
            self.* = unmanaged.toManaged(self.allocator);
        }

        /// Reduce length to `new_len`.
        /// Invalidates element pointers for the elements `items[new_len..]`.
        /// Asserts that the new length is less than or equal to the previous length.
        pub fn shrinkRetainingCapacity(self: *Self, new_len: usize) void {
            assert(new_len <= self.items.len);
            self.items.len = new_len;
        }

        /// Invalidates all element pointers.
        pub fn clearRetainingCapacity(self: *Self) void {
            self.items.len = 0;
        }

        /// Invalidates all element pointers.
        pub fn clearAndFree(self: *Self) void {
            self.allocator.free(self.allocatedSlice());
            self.items.len = 0;
            self.capacity = 0;
        }

        inline fn growCapacity(current: usize, minimum: usize) usize {
            var new = current;
            while (true) {
                new +|= new / 2 + init_capacity;
                if (new >= minimum)
                    return new;
            }
        }

        /// If the current capacity is less than `new_capacity`, this function will
        /// modify the array so that it can hold at least `new_capacity` items.
        /// Invalidates element pointers if additional memory is needed.
        pub inline fn ensureTotalCapacity(self: *Self, new_capacity: usize) Allocator.Error!void {
            if (@sizeOf(T) == 0) {
                self.capacity = math.maxInt(usize);
                return;
            }
            if (self.capacity >= new_capacity) return;
            const better_capacity = growCapacity(self.capacity, new_capacity);
            return self.ensureTotalCapacityPrecise(better_capacity);
        }

        /// If the current capacity is less than `new_capacity`, this function will
        /// modify the array so that it can hold exactly `new_capacity` items.
        /// Invalidates element pointers if additional memory is needed.
        pub inline fn ensureTotalCapacityPrecise(self: *Self, new_capacity: usize) Allocator.Error!void {
            if (@sizeOf(T) == 0) {
                self.capacity = math.maxInt(usize);
                return;
            }

            if (self.capacity >= new_capacity) return;

            // Here we avoid copying allocated but unused bytes by
            // attempting a resize in place, and falling back to allocating
            // a new buffer and doing our own copy. With a realloc() call,
            // the allocator implementation would pointlessly copy our
            // extra capacity.
            const old_memory = self.allocatedSlice();
            if (self.allocator.remap(old_memory, new_capacity)) |new_memory| {
                self.items.ptr = new_memory.ptr;
                self.capacity = new_memory.len;
            } else {
                const new_memory = try self.allocator.alignedAlloc(T, alignment, new_capacity);
                lib.move(T, new_memory[0..self.items.len], self.items);
                self.allocator.free(old_memory);
                self.items.ptr = new_memory.ptr;
                self.capacity = new_memory.len;
            }
        }

        /// Modify the array so that it can hold at least `additional_count` **more** items.
        /// Invalidates element pointers if additional memory is needed.
        pub fn ensureUnusedCapacity(self: *Self, additional_count: usize) Allocator.Error!void {
            return self.ensureTotalCapacity(try addOrOom(self.items.len, additional_count));
        }

        /// Increases the array's length to match the full capacity that is already allocated.
        /// The new elements have `undefined` values.
        /// Never invalidates element pointers.
        pub fn expandToCapacity(self: *Self) void {
            self.items.len = self.capacity;
        }

        /// Increase length by 1, returning pointer to the new item.
        /// The returned pointer becomes invalid when the list resized.
        pub inline fn addOne(self: *Self) Allocator.Error!*T {
            // This can never overflow because `self.items` can never occupy the whole address space
            const newlen = self.items.len + 1;
            try self.ensureTotalCapacity(newlen);
            return self.addOneAssumeCapacity();
        }

        /// Increase length by 1, returning pointer to the new item.
        /// The returned pointer becomes invalid when the list is resized.
        /// Never invalidates element pointers.
        /// Asserts that the list can hold one additional item.
        pub inline fn addOneAssumeCapacity(self: *Self) *T {
            assert(self.items.len < self.capacity);
            self.items.len += 1;
            return &self.items[self.items.len - 1];
        }

        /// Resize the array, adding `n` new elements, which have `undefined` values.
        /// The return value is an array pointing to the newly allocated elements.
        /// The returned pointer becomes invalid when the list is resized.
        /// Resizes list if `self.capacity` is not large enough.
        pub fn addManyAsArray(self: *Self, comptime n: usize) Allocator.Error!*[n]T {
            const prev_len = self.items.len;
            try self.resize(try addOrOom(self.items.len, n));
            return self.items[prev_len..][0..n];
        }

        /// Resize the array, adding `n` new elements, which have `undefined` values.
        /// The return value is an array pointing to the newly allocated elements.
        /// Never invalidates element pointers.
        /// The returned pointer becomes invalid when the list is resized.
        /// Asserts that the list can hold the additional items.
        pub inline fn addManyAsArrayAssumeCapacity(self: *Self, comptime n: usize) *[n]T {
            assert(self.items.len + n <= self.capacity);
            const prev_len = self.items.len;
            self.items.len += n;
            return self.items[prev_len..][0..n];
        }

        /// Resize the array, adding `n` new elements, which have `undefined` values.
        /// The return value is a slice pointing to the newly allocated elements.
        /// The returned pointer becomes invalid when the list is resized.
        /// Resizes list if `self.capacity` is not large enough.
        pub inline fn addManyAsSlice(self: *Self, n: usize) Allocator.Error![]T {
            const prev_len = self.items.len;
            try self.resize(try addOrOom(self.items.len, n));
            return self.items[prev_len..][0..n];
        }

        /// Resize the array, adding `n` new elements, which have `undefined` values.
        /// The return value is a slice pointing to the newly allocated elements.
        /// Never invalidates element pointers.
        /// The returned pointer becomes invalid when the list is resized.
        /// Asserts that the list can hold the additional items.
        pub fn addManyAsSliceAssumeCapacity(self: *Self, n: usize) []T {
            assert(self.items.len + n <= self.capacity);
            const prev_len = self.items.len;
            self.items.len += n;
            return self.items[prev_len..][0..n];
        }

        /// Remove and return the last element from the list, or return `null` if list is empty.
        /// Invalidates element pointers to the removed element, if any.
        pub fn pop(self: *Self) ?T {
            if (self.items.len == 0) return null;
            const val = self.items[self.items.len - 1];
            self.items.len -= 1;
            return val;
        }

        /// Returns a slice of all the items plus the extra capacity, whose memory
        /// contents are `undefined`.
        pub inline fn allocatedSlice(self: Self) Slice {
            // `items.len` is the length, not the capacity.
            return self.items.ptr[0..self.capacity];
        }

        /// Returns a slice of only the extra capacity after items.
        /// This can be useful for writing directly into an ArrayList.
        /// Note that such an operation must be followed up with a direct
        /// modification of `self.items.len`.
        pub inline fn unusedCapacitySlice(self: Self) []T {
            return self.allocatedSlice()[self.items.len..];
        }

        /// Returns the last element from the list.
        /// Asserts that the list is not empty.
        pub inline fn getLast(self: Self) T {
            const val = self.items[self.items.len - 1];
            return val;
        }

        /// Returns the last element from the list, or `null` if list is empty.
        pub inline fn getLastOrNull(self: Self) ?T {
            if (self.items.len == 0) return null;
            return self.getLast();
        }
    };
}

test "init" {
    {
        var list = AlignedList(i32, null).init(testing.allocator);
        defer list.deinit();

        try testing.expect(list.items.len == 0);
        try testing.expect(list.capacity == 0);
    }
}

test "initCapacity" {
    const a = testing.allocator;
    {
        var list = try AlignedList(i8, null).initCapacity(a, 200);
        defer list.deinit();
        try testing.expect(list.items.len == 0);
        try testing.expect(list.capacity >= 200);
    }
}

test "clone" {
    const a = testing.allocator;
    {
        var array = AlignedList(i32, null).init(a);
        try array.append(-1);
        try array.append(3);
        try array.append(5);

        const cloned = try array.clone();
        defer cloned.deinit();

        try testing.expectEqualSlices(i32, array.items, cloned.items);
        try testing.expectEqual(array.allocator, cloned.allocator);
        try testing.expect(cloned.capacity >= array.capacity);

        array.deinit();

        try testing.expectEqual(@as(i32, -1), cloned.items[0]);
        try testing.expectEqual(@as(i32, 3), cloned.items[1]);
        try testing.expectEqual(@as(i32, 5), cloned.items[2]);
    }
}

test "basic" {
    const a = testing.allocator;
    {
        var list = AlignedList(i32, null).init(a);
        defer list.deinit();

        {
            var i: usize = 0;
            while (i < 10) : (i += 1) {
                list.append(@as(i32, @intCast(i + 1))) catch unreachable;
            }
        }

        {
            var i: usize = 0;
            while (i < 10) : (i += 1) {
                try testing.expect(list.items[i] == @as(i32, @intCast(i + 1)));
            }
        }

        for (list.items, 0..) |v, i| {
            try testing.expect(v == @as(i32, @intCast(i + 1)));
        }

        try testing.expect(list.pop() == 10);
        try testing.expect(list.items.len == 9);

        list.appendSlice(&[_]i32{ 1, 2, 3 }) catch unreachable;
        try testing.expect(list.items.len == 12);
        try testing.expect(list.pop() == 3);
        try testing.expect(list.pop() == 2);
        try testing.expect(list.pop() == 1);
        try testing.expect(list.items.len == 9);

        var unaligned: [3]i32 align(1) = [_]i32{ 4, 5, 6 };
        list.appendUnalignedSlice(&unaligned) catch unreachable;
        try testing.expect(list.items.len == 12);
        try testing.expect(list.pop() == 6);
        try testing.expect(list.pop() == 5);
        try testing.expect(list.pop() == 4);
        try testing.expect(list.items.len == 9);

        list.appendSlice(&[_]i32{}) catch unreachable;
        try testing.expect(list.items.len == 9);

        // can only set on indices < self.items.len
        list.items[7] = 33;
        list.items[8] = 42;

        try testing.expect(list.pop() == 42);
        try testing.expect(list.pop() == 33);
    }
}
