const std = @import("std");
const assert = std.debug.assert;

pub const StackLink = extern struct {
    next: ?*StackLink = null,
};

/// An intrusive last in/first out linked list (LIFO).
/// The element type T must have a field called "next" of type StackType(T).Link.
pub fn StackType(comptime T: type) type {
    return struct {
        any: StackAny,

        pub const Link = StackLink;
        const Stack = @This();

        pub inline fn init(cp: u32) Stack {
            return .{ .any = .{
                .capacity = cp,
            } };
        }

        pub inline fn count(self: *Stack) u32 {
            return self.any.count;
        }

        pub inline fn capacity(self: *Stack) u32 {
            return self.any.capacity;
        }

        /// Pushes a new node to the first position of the Stack.
        pub inline fn push(self: *Stack, node: *T) void {
            self.any.push(&node.link);
        }

        /// Returns the first element of the Stack list, and removes it.
        pub inline fn pop(self: *Stack) ?*T {
            const link = self.any.pop() orelse return null;
            return @fieldParentPtr("link", link);
        }

        /// Returns the first element of the Stack list, but does not remove it.
        pub inline fn peek(self: *const Stack) ?*T {
            const link = self.any.peek() orelse return null;
            return @fieldParentPtr("link", link);
        }

        /// Checks if the Stack is empty.
        pub inline fn empty(self: *const Stack) bool {
            return self.any.empty();
        }

        /// Returns whether the linked list contains the given *exact element* (pointer comparison).
        inline fn contains(self: *const Stack, needle: *const T) bool {
            return self.any.contains(&needle.link);
        }
    };
}

// Non-generic implementation for smaller binary and faster compile times.
const StackAny = struct {
    head: ?*StackLink = null,
    count: u32 = 0,
    capacity: u32,
    fn push(self: *StackAny, link: *StackLink) void {
        assert((self.count == 0) == (self.head == null));
        assert(link.next == null);
        assert(self.count < self.capacity);

        // Insert the new element at the head.
        link.next = self.head;
        self.head = link;
        self.count += 1;
    }

    fn pop(self: *StackAny) ?*StackLink {
        assert((self.count == 0) == (self.head == null));

        const link = self.head orelse return null;
        self.head = link.next;
        link.next = null;
        self.count -= 1;
        return link;
    }

    fn peek(self: *const StackAny) ?*StackLink {
        return self.head;
    }

    fn empty(self: *const StackAny) bool {
        assert((self.count == 0) == (self.head == null));
        return self.head == null;
    }

    fn contains(self: *const StackAny, needle: *const StackLink) bool {
        assert(self.count <= self.capacity);
        var next = self.head;
        for (0..self.count + 1) |_| {
            const link = next orelse return false;
            if (link == needle) return true;
            next = link.next;
        } else unreachable;
    }
};
