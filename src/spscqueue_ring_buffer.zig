const std = @import("std");
const lib = @import("lib.zig");
const assert = std.debug.assert;
const mem = std.mem;
const Allocator = std.mem.Allocator;
const testing = std.testing;

//THREAD SAFE
fn SPSCQueue(comptime T: type, comptime _max_size: ?usize) type {
    comptime if (_max_size) |n| {
        assert(n > 0);
    };
    return struct {
        const Self = @This();

        write_index: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
        _pad: [std.atomic.cache_line - @sizeOf(usize)]u8 = undefined,
        read_index: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),

        buffer: if (_max_size) |n| [n + 1]T else []T = undefined,
        allocator: if (_max_size == null) Allocator else void = if (_max_size == null) undefined else {},

        /// Initialize a dynamic-sized queue with given allocator and max_size.
        /// For zero-sized T, returns an empty slice with correct capacity.
        pub fn init(allocator: Allocator, max_size: usize) !Self {
            const capacity = max_size + 1;
            const buffer = try allocator.alloc(T, capacity);
            if (@sizeOf(T) > 0) {
                @memset(buffer, std.mem.zeroes(T));
            }
            return .{
                .buffer = buffer,
                .allocator = allocator,
            };
        }
        /// Free allocated memory for dynamic-sized queue.
        pub fn deinit(self: *Self) void {
            if (@sizeOf(T) > 0 and _max_size == null) {
                self.allocator.free(self.buffer);
            }
        }

        /// Pushes object item to the ringbuffer.
        ///
        /// Only one thread is allowed to push data to the spsc_queue.
        /// Object will be pushed to the spsc_queue, unless it is full.
        ///
        /// Return: true, if the push operation is successful.
        ///
        /// Note: thread-safe and wait-free
        pub fn push(self: *Self, item: T) bool {
            const write_index = self.write_index.load(.monotonic);
            const next = self.nextIndex(write_index);

            if (next == self.read_index.load(.acquire)) {
                return false; // ringbuffer is full
            }

            self.buffer[write_index] = item; // copy
            self.write_index.store(next, .release);

            return true;
        }

        /// Push multiple items to the queue. Thread-safe, wait-free.
        /// Returns number of items successfully pushed.
        pub fn pushMany(self: *Self, items: []const T) usize {
            const write_index = self.write_index.load(.monotonic);
            const read_index = self.read_index.load(.acquire);
            const available = self.writeAvailable(write_index, read_index);
            const to_write = @min(items.len, available);
            if (to_write == 0) return 0;

            const end = write_index + to_write;
            const split = @min(end, self.buffer.len);
            const first_chunk = items[0..@min(to_write, split - write_index)];
            const second_chunk = if (end > self.buffer.len) items[first_chunk.len..to_write] else &[_]T{};

            lib.move(T, self.buffer[write_index..split], first_chunk);
            if (second_chunk.len > 0) {
                lib.move(T, self.buffer[0..second_chunk.len], second_chunk);
            }
            self.write_index.store(self.nextIndexN(write_index, to_write), .release);
            return to_write;
        }

        /// Pops one object from ringbuffer.
        ///
        /// Only one thread is allowed to pop data to the spsc_queue,
        /// if ringbuffer is not empty, object will be discarded.
        ///
        /// Return: item, if the pop operation is successful, null if ringbuffer was empty.
        ///
        /// Note: thread-safe and wait-free
        pub fn pop(self: *Self) ?T {
            const read_index = self.read_index.load(.monotonic);

            if (read_index == self.write_index.load(.acquire)) {
                return null;
            }

            const item = self.buffer[read_index];
            const next = self.nextIndex(read_index);
            self.read_index.store(next, .release);

            return item;
        }

        /// Pop multiple items from the queue. Thread-safe, wait-free.
        /// Fills items slice and returns number of items popped.
        pub fn popMany(self: *Self, items: []T) usize {
            const read_index = self.read_index.load(.monotonic);
            const write_index = self.write_index.load(.acquire);
            const available = self.readAvailable(read_index, write_index);
            const to_read = @min(items.len, available);
            if (to_read == 0) return 0;

            const end = read_index + to_read;
            const split = @min(end, self.buffer.len);
            const first_chunk = items[0..@min(to_read, split - read_index)];
            const second_chunk = if (end > self.buffer.len) items[first_chunk.len..to_read] else &[_]T{};

            lib.move(T, first_chunk, self.buffer[read_index..split]);
            if (second_chunk.len > 0) {
                lib.move(T, second_chunk, self.buffer[0..second_chunk.len]);
            }
            self.read_index.store(self.nextIndexN(read_index, to_read), .release);
            return to_read;
        }

        /// Get reference to element in the front of the queue.
        /// Availability of front element can be checked using readAvailable().
        /// Only a consuming thread is allowed to check front element
        /// read_available() > 0. If ringbuffer is empty, it's undefined behaviour to invoke this method.
        ///
        /// Return: reference to the first element in the queue
        ///
        /// Note: thread-safe and wait-free.
        pub fn peek(self: *Self) *T {
            assert(self.read() > 0);
            const read_index = self.read_index.load(.monotonic);
            return &self.buffer[read_index];
        }

        /// Get number of elements that are available for read.
        ///
        /// Return: number of available elements that can be popped from the spsc_queue.
        ///
        /// Note: thread-safe and wait-free, should only be called from the consumer thread.
        pub fn read(self: *Self) usize {
            const write_index = self.write_index.load(.acquire);
            const read_index = self.read_index.load(.monotonic);
            if (write_index >= read_index) {
                return write_index - read_index;
            }
            return write_index + self.buffer.len - read_index;
        }

        /// Get write space to write elements.
        ///
        /// Return: number of elements that can be pushed to the spsc_queue.
        ///
        /// Note: thread-safe and wait-free, should only be called from the producer thread.
        pub fn write(self: *Self) usize {
            const write_index = self.write_index.load(.monotonic);
            const read_index = self.read_index.load(.acquire);
            if (write_index < read_index) {
                return read_index - write_index - 1;
            }
            return self.buffer.len - write_index + read_index - 1;
        }

        /// Check if the ringbuffer is empty.
        ///
        /// Return: true, if the ringbuffer is empty, false otherwise.
        ///
        /// Note: Due to the concurrent nature of the ringbuffer the result may be inaccurate.
        pub fn empty(self: *Self) bool {
            return self.write_index.load(.monotonic) == self.read_index.load(.monotonic);
        }

        inline fn writeAvailable(self: *Self, write_index: usize, read_index: usize) usize {
            if (write_index < read_index) {
                return read_index - write_index - 1;
            }
            return self.buffer.len - write_index + read_index - 1;
        }

        inline fn readAvailable(self: *Self, read_index: usize, write_index: usize) usize {
            if (write_index >= read_index) {
                return write_index - read_index;
            }
            return write_index + self.buffer.len - read_index;
        }

        /// Reset the ringbuffer.
        ///
        /// Note: not thread-safe.
        pub fn reset(self: *Self) void {
            self.write_index.store(0, .monotonic);
            self.read_index.store(0, .release);
        }

        inline fn nextIndex(self: *Self, arg: usize) usize {
            var ret: usize = arg + 1;
            if (ret >= self.buffer.len) {
                ret -= self.buffer.len;
            }
            return ret;
        }
    };
}

test "zero_size_T" {
    var f = try SPSCQueue(void, null).init(testing.failing_allocator, 2);
    defer f.deinit();

    try testing.expect(f.empty());
    try testing.expect(f.push({}));
    try testing.expect(f.push({}));
    try testing.expect(!f.push({}));

    try testing.expect(f.pop() == {});
    try testing.expect(f.pop() == {});
    try testing.expect(f.pop() == null);
    try testing.expect(f.empty());

    const T = SPSCQueue(void, 100000000);
    try testing.expectEqual(std.atomic.cache_line + @sizeOf(usize), @sizeOf(T));
}

test "comptime_sized" {
    var f = SPSCQueue(i32, 2){};

    try testing.expect(f.empty());
    try testing.expect(f.push(1));
    try testing.expect(f.push(2));
    try testing.expect(!f.push(3));

    try testing.expect(f.pop() == 1);
    try testing.expect(f.pop() == 2);
    try testing.expect(f.pop() == null);
    try testing.expect(f.empty());
}

test "simple_spsc_queue_test" {
    var f = try SPSCQueue(i32, null).init(testing.allocator, 64);
    defer f.deinit();
    try testing.expect(f.empty());
    try testing.expect(f.push(1));
    try testing.expect(f.push(2));

    try testing.expect(f.pop() == 1);
    try testing.expect(f.pop() == 2);
    try testing.expect(f.pop() == null);
    try testing.expect(f.empty());
}
