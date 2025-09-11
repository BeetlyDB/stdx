const std = @import("std");
const assert = std.debug.assert;
const lib = @import("lib.zig");
const Allocator = std.mem.Allocator;

//THREAD SAFE
// https://github.com/facebook/folly/blob/298084542d0fb2261376a915f4e5cd3b8a7d93d4/folly/concurrency/container/LockFreeRingBuffer.h
pub fn LockFreeRingBuffer(comptime T: type, comptime capacity: u32) type {
    comptime {
        assert(@sizeOf(T) > 0); // T must be non-zero size (ZST not supported)
        assert(capacity > 0 and capacity <= std.math.maxInt(u32));
    }

    return struct {
        const Self = @This();
        pub const Cursor = struct {
            ticket: u64,

            pub fn init(ticket: u64) Cursor {
                return .{ .ticket = ticket };
            }

            pub fn moveForward(self: *Cursor, steps: u64) bool {
                const prev = self.ticket;
                self.ticket +|= steps;
                return prev != self.ticket;
            }

            pub fn moveBackward(self: *Cursor, steps: u64) bool {
                const prev = self.ticket;
                if (steps > self.ticket) {
                    self.ticket = 0;
                } else {
                    self.ticket -|= steps;
                }
                return prev != self.ticket;
            }

            pub fn equals(self: Cursor, other: Cursor) bool {
                return self.ticket == other.ticket;
            }

            pub fn lessThan(self: Cursor, other: Cursor) bool {
                return self.ticket < other.ticket;
            }
        };

        //  sequencer + storage
        const Slot = struct {
            sequencer: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
            storage: T align(std.atomic.cache_line) = undefined,

            inline fn write(self: *Slot, slot_turn: u32, value: T) void {
                // Wait for slot_turn * 2 (start write)
                while (self.sequencer.load(.acquire) != slot_turn * 2) {
                    std.atomic.spinLoopHint();
                }
                // Mark write in progress (odd turn)
                self.sequencer.store(slot_turn * 2 + 1, .release);
                // Store value (memcpy for trivial T)
                lib.move(u8, std.mem.asBytes(&self.storage), std.mem.asBytes(&value));
                // Complete write (next even turn)
                self.sequencer.store((slot_turn + 1) * 2, .release);
            }

            inline fn tryRead(self: *const Slot, dest: *T, slot_turn: u32) bool {
                const desired_turn = (slot_turn + 1) * 2;
                if (self.sequencer.load(.acquire) != desired_turn) {
                    return false;
                }
                // Load value (memcpy)
                lib.move(u8, std.mem.asBytes(dest), std.mem.asBytes(&self.storage));
                return self.sequencer.load(.acquire) == desired_turn;
            }

            inline fn waitAndTryRead(self: *const Slot, dest: *T, slot_turn: u32) bool {
                const desired_turn = (slot_turn + 1) * 2;
                while (self.sequencer.load(.acquire) != desired_turn) {
                    std.atomic.spinLoopHint();
                }
                lib.move(u8, std.mem.asBytes(dest), std.mem.asBytes(&self.storage));
                return self.sequencer.load(.acquire) == desired_turn;
            }
        };

        slots: []Slot,
        ticket: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        allocator: Allocator,

        pub fn init(allocator: Allocator) !Self {
            const slots = try allocator.alloc(Slot, capacity);
            errdefer allocator.free(slots);

            var i: usize = 0;
            while (i < slots.len) : (i += 1) {
                slots[i].sequencer.store(0, .monotonic);
            }

            return .{
                .slots = slots,
                .allocator = allocator,
                .ticket = std.atomic.Value(u64).init(0),
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.slots);
        }

        pub inline fn cap(self: Self) u32 {
            return @intCast(self.slots.len);
        }

        pub inline fn write(self: *Self, value: T) void {
            const ticket = self.ticket.fetchAdd(1, .monotonic);
            self.slots[self.idx(ticket)].write(self.turn(ticket), value);
        }

        pub inline fn writeAndGetCursor(self: *Self, value: T) Cursor {
            const ticket = self.ticket.fetchAdd(1, .monotonic);
            self.slots[self.idx(ticket)].write(self.turn(ticket), value);
            return Cursor.init(ticket);
        }

        pub inline fn tryRead(self: *const Self, dest: *T, cursor: Cursor) bool {
            return self.slots[self.idx(cursor.ticket)].tryRead(dest, self.turn(cursor.ticket));
        }

        pub inline fn waitAndTryRead(self: *const Self, dest: *T, cursor: Cursor) bool {
            return self.slots[self.idx(cursor.ticket)].waitAndTryRead(dest, self.turn(cursor.ticket));
        }

        pub inline fn currentHead(self: Self) Cursor {
            return Cursor.init(self.ticket.load(.acquire));
        }

        pub inline fn currentTail(self: Self) Cursor {
            const ticket = self.ticket.load(.acquire);
            const back_step = @min(ticket, @as(u64, capacity));
            return Cursor.init(ticket -% back_step);
        }

        pub inline fn internalBufferLocation(self: Self) struct { ptr: *const anyopaque, size: usize } {
            return .{
                .ptr = @ptrCast(self.slots.ptr),
                .size = capacity * @sizeOf(Slot),
            };
        }

        inline fn idx(_: Self, ticket: u64) u32 {
            return @intCast(ticket % @as(u64, capacity));
        }

        inline fn turn(_: Self, ticket: u64) u32 {
            return @intCast(ticket / @as(u64, capacity));
        }
    };
}

test "LockFreeRingBuffer" {
    var buffer = try LockFreeRingBuffer(i32, 4).init(std.testing.allocator);
    defer buffer.deinit();

    try std.testing.expectEqual(@as(u32, 4), buffer.cap());

    var cursor = buffer.writeAndGetCursor(42);
    try std.testing.expect(cursor.moveForward(1));
    try std.testing.expect(cursor.moveBackward(1));

    var value: i32 = undefined;
    try std.testing.expect(buffer.tryRead(&value, cursor));
    try std.testing.expectEqual(42, value);

    try std.testing.expect(buffer.waitAndTryRead(&value, cursor));
    try std.testing.expectEqual(42, value);

    const head = buffer.currentHead();
    const tail = buffer.currentTail();
    try std.testing.expect(head.ticket >= tail.ticket);
}
