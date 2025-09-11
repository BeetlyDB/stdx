const std = @import("std");
const testing = std.testing;
const lib = @import("lib.zig");

pub const RingBufferError = error{
    BufferFull,
};

pub fn RingBuffer(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        capacity: usize,
        buffer: []T,
        head: usize,
        tail: usize,
        count: usize,

        pub fn init(allocator: std.mem.Allocator, capacity: usize) !Self {
            const buffer = try allocator.alloc(T, capacity);
            errdefer allocator.free(buffer);

            return Self{
                .allocator = allocator,
                .capacity = capacity,
                .buffer = buffer,
                .head = 0,
                .tail = 0,
                .count = 0,
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.buffer);
        }

        pub fn available(self: *Self) usize {
            return self.capacity - self.count;
        }

        pub fn prepend(self: *Self, value: T) RingBufferError!void {
            if (self.isFull()) return RingBufferError.BufferFull;
            self.head = (self.head + self.capacity - 1) % self.capacity;
            self.buffer[self.head] = value;
            self.count += 1;
        }

        pub fn enqueue(self: *Self, value: T) RingBufferError!void {
            if (self.isFull()) return RingBufferError.BufferFull;
            self.buffer[self.tail] = value;
            self.tail = (self.tail + 1) % self.capacity;
            self.count += 1;
        }

        pub fn dequeue(self: *Self) ?T {
            if (self.isEmpty()) return null;
            const value = self.buffer[self.head];
            self.head = (self.head + 1) % self.capacity;
            self.count -= 1;
            return value;
        }

        // Helper: copy up to `n` items from `src` (starting at src_head) to `dst` (starting at dst_tail).
        // Advances src_head and dst_tail by number of copied items and updates counts externally.
        inline fn copy_chunks_from_to(
            comptime ElemT: type,
            dst: []ElemT,
            dst_tail: *usize,
            dst_cap: usize,
            src: []const ElemT,
            src_head: *usize,
            src_cap: usize,
            _n: usize,
        ) usize {
            var copied: usize = 0;
            var n = _n;
            while (n > 0) {
                const dst_cont = @min(n, dst_cap - dst_tail.*);
                const src_cont = @min(n, src_cap - src_head.*);
                const len = @min(dst_cont, src_cont);
                if (len == 0) break;

                // slices to copy
                const dst_slice = dst[dst_tail.* .. dst_tail.* + len];
                const src_slice = src[src_head.* .. src_head.* + len];
                lib.move(ElemT, dst_slice, src_slice);

                dst_tail.* = (dst_tail.* + len) % dst_cap;
                src_head.* = (src_head.* + len) % src_cap;
                copied += len;
                n -= len;
            }
            return copied;
        }

        pub fn enqueueMany(self: *Self, values: []const T) usize {
            const to_write = @min(values.len, self.available());
            if (to_write == 0) return 0;

            // copy possibly in two parts into tail
            var copied: usize = 0;
            var src_idx: usize = 0;
            while (copied < to_write) {
                const dst_cont = self.capacity - self.tail;
                const src_cont = to_write - copied;
                const len = @min(dst_cont, src_cont);
                lib.move(T, self.buffer[self.tail .. self.tail + len], values[src_idx .. src_idx + len]);
                self.tail = (self.tail + len) % self.capacity;
                self.count += len;
                copied += len;
                src_idx += len;
            }
            return copied;
        }

        pub fn dequeueMany(self: *Self, out: []T) usize {
            const to_read = @min(out.len, self.count);
            if (to_read == 0) return 0;

            var copied: usize = 0;
            var dst_idx: usize = 0;
            while (copied < to_read) {
                const src_cont = self.capacity - self.head;
                const dst_cont = to_read - copied;
                const len = @min(src_cont, dst_cont);
                lib.move(T, out[dst_idx .. dst_idx + len], self.buffer[self.head .. self.head + len]);
                self.head = (self.head + len) % self.capacity;
                self.count -= len;
                copied += len;
                dst_idx += len;
            }
            return copied;
        }

        pub fn concatenate(self: *Self, other: *Self) !void {
            if (self.available() < other.count) return RingBufferError.BufferFull;
            const num = other.count;
            if (num == 0) return;

            // copy in chunks from other into self.tail
            var remaining = num;
            while (remaining > 0) {
                const chunk = copy_chunks_from_to(
                    T,
                    self.buffer,
                    &self.tail,
                    self.capacity,
                    other.buffer,
                    &other.head,
                    other.capacity,
                    remaining,
                );
                remaining -= chunk;
                self.count += chunk;
            }

            // other becomes empty
            other.reset();
        }

        pub fn concatenateAvailable(self: *Self, other: *Self) void {
            const num_to_copy = @min(self.available(), other.count);
            if (num_to_copy == 0) return;

            var remaining = num_to_copy;
            while (remaining > 0) {
                const chunk = copy_chunks_from_to(
                    T,
                    self.buffer,
                    &self.tail,
                    self.capacity,
                    other.buffer,
                    &other.head,
                    other.capacity,
                    remaining,
                );
                remaining -= chunk;
                self.count += chunk;
                other.count -= chunk;
            }
        }

        pub fn copy(self: *Self, other: *Self) !void {
            if (self.available() < other.count) return RingBufferError.BufferFull;
            const num = other.count;
            if (num == 0) return;

            // copy without modifying other: we need a local copy of source head
            var src_head_local = other.head;
            var remaining = num;
            while (remaining > 0) {
                const dst_cont = self.capacity - self.tail;
                const src_cont = other.capacity - src_head_local;
                const len = @min(remaining, @min(dst_cont, src_cont));
                lib.move(T, self.buffer[self.tail .. self.tail + len], other.buffer[src_head_local .. src_head_local + len]);
                self.tail = (self.tail + len) % self.capacity;
                src_head_local = (src_head_local + len) % other.capacity;
                remaining -= len;
            }

            self.count += num;
        }

        pub fn copyMinToOthers(self: *Self, others: []*Self) usize {
            if (others.len == 0 or self.count == 0) return 0;

            var min_available = std.math.maxInt(usize);
            for (others) |other| {
                const other_available = other.available();
                if (other_available < min_available) {
                    min_available = other_available;
                }
            }

            const num_to_copy = @min(self.count, min_available);
            if (num_to_copy == 0) return 0;

            // We will copy the same chunks to each other. Use a local read-head.
            var src_head_local: usize = self.head;
            var remaining: usize = num_to_copy;
            while (remaining > 0) {
                const src_cont = self.capacity - src_head_local;
                const len = @min(remaining, src_cont);

                // For each target, copy the same contiguous block
                for (others) |other| {
                    // If destination wraps, we may need to split; reuse copy_chunks_from_to for each other
                    // but copy_chunks_from_to mutates dst tail & src head, so call lib.move directly with slices:
                    const dst_cont = other.capacity - other.tail;
                    const copy_len = @min(len, dst_cont);
                    lib.move(T, other.buffer[other.tail .. other.tail + copy_len], self.buffer[src_head_local .. src_head_local + copy_len]);
                    other.tail = (other.tail + copy_len) % other.capacity;
                    other.count += copy_len;

                    // if chunk didn't fully fit, copy rest to beginning
                    if (copy_len < len) {
                        const rest = len - copy_len;
                        lib.move(T, other.buffer[0..rest], self.buffer[src_head_local + copy_len .. src_head_local + copy_len + rest]);
                        other.tail = rest;
                        other.count += rest;
                    }
                }

                src_head_local = (src_head_local + len) % self.capacity;
                remaining -= len;
            }

            // Advance self
            self.head = (self.head + num_to_copy) % self.capacity;
            self.count -= num_to_copy;

            return num_to_copy;
        }

        pub fn copyMaxToOthers(self: *Self, others: []*Self) usize {
            if (others.len == 0 or self.count == 0) return 0;

            var max_copy = self.count;
            for (others) |other| {
                const other_available = other.available();
                if (other_available < max_copy) {
                    max_copy = other_available;
                }
            }

            if (max_copy == 0) return 0;

            var src_head_local: usize = self.head;
            var remaining: usize = max_copy;
            while (remaining > 0) {
                const src_cont = self.capacity - src_head_local;
                const len = @min(remaining, src_cont);

                for (others) |other| {
                    const dst_cont = other.capacity - other.tail;
                    const copy_len = @min(len, dst_cont);
                    lib.move(T, other.buffer[other.tail .. other.tail + copy_len], self.buffer[src_head_local .. src_head_local + copy_len]);
                    other.tail = (other.tail + copy_len) % other.capacity;
                    other.count += copy_len;

                    if (copy_len < len) {
                        const rest = len - copy_len;
                        lib.move(T, other.buffer[0..rest], self.buffer[src_head_local + copy_len .. src_head_local + copy_len + rest]);
                        other.tail = rest;
                        other.count += rest;
                    }
                }

                src_head_local = (src_head_local + len) % self.capacity;
                remaining -= len;
            }

            self.head = (self.head + max_copy) % self.capacity;
            self.count -= max_copy;

            return max_copy;
        }

        pub inline fn isEmpty(self: *Self) bool {
            return self.available() == self.capacity;
        }

        pub inline fn isFull(self: *Self) bool {
            return self.available() == 0;
        }

        pub inline fn reset(self: *Self) void {
            self.head = 0;
            self.tail = 0;
            self.count = 0;
        }

        pub inline fn fill(self: *Self, value: T) void {
            const to_fill = self.available();
            if (to_fill == 0) return;

            // small fast path: build on-stack buffer and copy
            if (to_fill <= 64) {
                var stack_buf: [64]T = undefined;
                // for (stack_buf[0..to_fill]) |*s| s.* = value;
                lib.set(T, &stack_buf, value);

                const first_chunk_len = @min(to_fill, self.capacity - self.tail);
                if (first_chunk_len > 0) {
                    lib.move(T, self.buffer[self.tail .. self.tail + first_chunk_len], stack_buf[0..first_chunk_len]);
                    self.tail = (self.tail + first_chunk_len) % self.capacity;
                    self.count += first_chunk_len;
                }

                const rest = to_fill - first_chunk_len;
                if (rest > 0) {
                    lib.move(T, self.buffer[0..rest], stack_buf[first_chunk_len .. first_chunk_len + rest]);
                    self.tail = rest;
                    self.count += rest;
                }
                return;
            }

            // large path: allocate temporary buffer
            var tmp_buf = self.allocator.alloc(T, to_fill) catch unreachable;
            // for (tmp_buf) |*s| s.* = value;
            lib.set(T, tmp_buf, value);
            var remaining = to_fill;
            var src_idx: usize = 0;
            while (remaining > 0) {
                const dst_cont = self.capacity - self.tail;
                const len = @min(remaining, dst_cont);
                lib.move(T, self.buffer[self.tail .. self.tail + len], tmp_buf[src_idx .. src_idx + len]);
                self.tail = (self.tail + len) % self.capacity;
                self.count += len;
                remaining -= len;
                src_idx += len;
            }

            self.allocator.free(tmp_buf);
        }
    };
}

test "init/deinit" {
    const allocator = testing.allocator;

    var ring_buffer = try RingBuffer(u8).init(allocator, 100);
    defer ring_buffer.deinit();
}

test "fill" {
    const allocator = testing.allocator;

    var ring_buffer = try RingBuffer(u8).init(allocator, 100);
    defer ring_buffer.deinit();

    // Assert that the ring buffer is completely empty with no items in any slots.
    try testing.expectEqual(true, ring_buffer.isEmpty());

    const test_value: u8 = 231;

    ring_buffer.fill(test_value);

    // Assert that the ring buffer is completely full with no free slots
    try testing.expectEqual(true, ring_buffer.isFull());

    // dequeue every value and ensure that they are each equal to the test_value
    while (ring_buffer.dequeue()) |v| {
        try testing.expectEqual(test_value, v);
    }

    // Assert that the ring buffer is completely empty with no items in any slots.
    try testing.expectEqual(true, ring_buffer.isEmpty());
}

test "reset" {
    const allocator = testing.allocator;

    var ring_buffer = try RingBuffer(u8).init(allocator, 100);
    defer ring_buffer.deinit();

    const test_value: u8 = 231;

    ring_buffer.fill(test_value);

    // Assert that the ring buffer is completely full with no free slots
    try testing.expectEqual(true, ring_buffer.isFull());

    // ensure that every value in the backing buffer is equal to the test_value
    for (ring_buffer.buffer) |value| {
        try testing.expectEqual(test_value, value);
    }

    // fully reset the ring buffer. Since this is an unsafe operation we
    // should expect that all values in the buffer still are equal to the
    // test value used during the fill op
    ring_buffer.reset();

    // Assert that the ring buffer is completely empty with no items in any slots.
    try testing.expectEqual(true, ring_buffer.isEmpty());

    for (ring_buffer.buffer) |value| {
        try testing.expectEqual(test_value, value);
    }
}

test "prepend" {
    const allocator = testing.allocator;

    var ring_buffer = try RingBuffer(u8).init(allocator, 10);
    defer ring_buffer.deinit();

    const test_value: u8 = 231;

    // fill the remaining capacity of the ring buffer with this value
    ring_buffer.fill(33);
    try testing.expectEqual(0, ring_buffer.available());

    // Make room in the ring_buffer
    try testing.expectEqual(33, ring_buffer.dequeue().?);
    try testing.expectEqual(1, ring_buffer.available());

    try ring_buffer.prepend(test_value);

    try testing.expectEqual(0, ring_buffer.available());

    try testing.expectEqual(true, ring_buffer.isFull());
    try testing.expectError(RingBufferError.BufferFull, ring_buffer.prepend(test_value));

    // dequeue the item at the had of the queue
    try testing.expectEqual(test_value, ring_buffer.dequeue().?);
}

test "enqueue" {
    const allocator = testing.allocator;

    var ring_buffer = try RingBuffer(u8).init(allocator, 10);
    defer ring_buffer.deinit();

    const test_value: u8 = 231;

    try testing.expectEqual(0, ring_buffer.count);

    try ring_buffer.enqueue(test_value);

    try testing.expectEqual(1, ring_buffer.count);

    // fill the remaining capacity of the ring buffer with this value
    ring_buffer.fill(33);

    try testing.expectEqual(true, ring_buffer.isFull());
    try testing.expectError(RingBufferError.BufferFull, ring_buffer.enqueue(test_value));
}

test "dequeue" {
    const allocator = testing.allocator;

    var ring_buffer = try RingBuffer(u8).init(allocator, 10);
    defer ring_buffer.deinit();

    const test_value: u8 = 231;

    // fill the entire ring buffer with this value
    ring_buffer.fill(test_value);

    try testing.expectEqual(true, ring_buffer.isFull());

    var removed: usize = ring_buffer.capacity;
    while (ring_buffer.dequeue()) |v| : (removed -= 1) {
        try testing.expectEqual(test_value, v);
    }

    try testing.expectEqual(true, ring_buffer.isEmpty());
}

test "enqueueMany" {
    const allocator = testing.allocator;

    const test_value: u8 = 231;
    const values: [13]u8 = [_]u8{test_value} ** 13;

    var ring_buffer = try RingBuffer(u8).init(allocator, 10);
    defer ring_buffer.deinit();

    try testing.expectEqual(true, ring_buffer.isEmpty());

    const enqueued_items_count = ring_buffer.enqueueMany(&values);

    try testing.expectEqual(ring_buffer.capacity, enqueued_items_count);
    try testing.expectEqual(true, ring_buffer.isFull());
}

test "dequeueMany" {
    const allocator = testing.allocator;

    var ring_buffer = try RingBuffer(u8).init(allocator, 10);
    defer ring_buffer.deinit();

    const test_value: u8 = 231;
    ring_buffer.fill(test_value);

    try testing.expectEqual(true, ring_buffer.isFull());

    var out: [100]u8 = [_]u8{0} ** 100;
    const dequeued_items_count = ring_buffer.dequeueMany(&out);

    try testing.expectEqual(true, ring_buffer.isEmpty());

    try testing.expect(dequeued_items_count > 0);

    for (out[0..dequeued_items_count]) |v| {
        try testing.expectEqual(test_value, v);
    }
}

test "concatenate" {
    const allocator = std.testing.allocator;
    var a = try RingBuffer(usize).init(allocator, 10);
    defer a.deinit();

    var b = try RingBuffer(usize).init(allocator, 5);
    defer b.deinit();

    _ = a.enqueueMany(&.{ 1, 2, 3 });
    _ = b.enqueueMany(&.{ 4, 5 });

    try a.concatenate(&b);

    try testing.expectEqual(@as(usize, 5), a.count);
    try testing.expectEqual(@as(usize, 0), b.count);

    var buf: [5]usize = undefined;
    const n = a.dequeueMany(&buf);
    try testing.expectEqualSlices(usize, &.{ 1, 2, 3, 4, 5 }, buf[0..n]);
}

test "copy preserves other and copies all values in order" {
    const allocator = testing.allocator;

    var src = try RingBuffer(u8).init(allocator, 10);
    defer src.deinit();

    var dest = try RingBuffer(u8).init(allocator, 10);
    defer dest.deinit();

    // Fill the source buffer with predictable values
    const values: [5]u8 = .{ 10, 20, 30, 40, 50 };
    try testing.expectEqual(@as(usize, values.len), src.enqueueMany(&values));

    // Ensure destination is empty before copy
    try testing.expectEqual(true, dest.isEmpty());

    // Perform the copy
    try dest.copy(&src);

    // Ensure source is unchanged after copy
    try testing.expectEqual(@as(usize, values.len), src.count);

    for (values) |expected| {
        const actual = src.dequeue().?;
        try testing.expectEqual(expected, actual);
    }

    // Re-enqueue the values into source for the next check
    _ = src.enqueueMany(&values);

    // Now check that dest has the same values, in same order
    for (values) |expected| {
        const actual = dest.dequeue().?;
        try testing.expectEqual(expected, actual);
    }

    try testing.expectEqual(true, dest.isEmpty());
    try testing.expectEqual(@as(usize, values.len), src.count);
}

test "copy fails when not enough space in destination" {
    const allocator = testing.allocator;

    var src = try RingBuffer(u8).init(allocator, 5);
    defer src.deinit();

    var dest = try RingBuffer(u8).init(allocator, 3);
    defer dest.deinit();

    // Fill source with 5 values
    src.fill(7);

    // Try copying into a smaller destination
    const result = dest.copy(&src);
    try testing.expectError(RingBufferError.BufferFull, result);

    // Destination should still be empty
    try testing.expectEqual(true, dest.isEmpty());
}
