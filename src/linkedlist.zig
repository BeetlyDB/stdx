const std = @import("std");
const assert = std.debug.assert;

const List_Link = extern struct {
    next: ?*List_Link = null,
};

/// An intrusive first in/first out linked list.
/// The element type T must have a field called "link" of type ListType(T).Link.
pub fn ListType(comptime T: type) type {
    return struct {
        any: ListAny,

        pub const Link = List_Link;
        const List = @This();

        pub inline fn init() List {
            return .{ .any = .{} };
        }

        pub inline fn push(self: *List, link: *T) void {
            self.any.push(&link.link);
        }

        pub inline fn pop(self: *List) ?*T {
            const link = self.any.pop() orelse return null;
            return @alignCast(@fieldParentPtr("link", link));
        }

        pub inline fn peek_last(self: *const List) ?*T {
            const link = self.any.peek_last() orelse return null;
            return @alignCast(@fieldParentPtr("link", link));
        }

        pub inline fn peek(self: *const List) ?*T {
            const link = self.any.peek() orelse return null;
            return @alignCast(@fieldParentPtr("link", link));
        }

        pub fn count(self: *const List) u64 {
            return self.any.count;
        }

        pub inline fn empty(self: *const List) bool {
            return self.any.empty();
        }

        /// Returns whether the linked list contains the given *exact element* (pointer comparison).
        pub inline fn contains(self: *const List, elem_needle: *const T) bool {
            return self.any.contains(&elem_needle.link);
        }

        /// Remove an element from the Queue. Asserts that the element is
        /// in the Queue. This operation is O(N), if this is done often you
        /// probably want a different data structure.
        pub inline fn remove(self: *List, to_remove: *T) void {
            self.any.remove(&to_remove.link);
        }

        pub inline fn reset(self: *List) void {
            self.any.reset();
        }

        pub inline fn iterate(self: *const List) Iterator {
            return .{ .any = self.any.iterate() };
        }

        pub const Iterator = struct {
            any: ListAny.Iterator,
            pub inline fn next(iterator: *@This()) ?*T {
                const link = iterator.any.next() orelse return null;
                return @alignCast(@fieldParentPtr("link", link));
            }
        };
    };
}

// Non-generic implementation for smaller binary and faster compile times.
const ListAny = struct {
    in: ?*List_Link = null,
    out: ?*List_Link = null,
    count: u64 = 0,
    pub fn push(self: *ListAny, link: *List_Link) void {
        assert(link.next == null);
        if (self.in) |in| {
            in.next = link;
            self.in = link;
        } else {
            assert(self.out == null);
            self.in = link;
            self.out = link;
        }
        self.count += 1;
    }

    pub fn pop(self: *ListAny) ?*List_Link {
        const result = self.out orelse return null;
        self.out = result.next;
        result.next = null;
        if (self.in == result) self.in = null;
        self.count -= 1;
        return result;
    }

    pub fn peek_last(self: *const ListAny) ?*List_Link {
        return self.in;
    }

    pub fn peek(self: *const ListAny) ?*List_Link {
        return self.out;
    }

    pub fn empty(self: *const ListAny) bool {
        return self.peek() == null;
    }

    pub fn contains(self: *const ListAny, needle: *const List_Link) bool {
        var iterator = self.peek();
        while (iterator) |link| : (iterator = link.next) {
            if (link == needle) return true;
        }
        return false;
    }

    pub fn remove(self: *ListAny, to_remove: *List_Link) void {
        if (to_remove == self.out) {
            _ = self.pop();
            return;
        }
        var it = self.out;
        while (it) |link| : (it = link.next) {
            if (to_remove == link.next) {
                if (to_remove == self.in) self.in = link;
                link.next = to_remove.next;
                to_remove.next = null;
                self.count -= 1;
                break;
            }
        } else unreachable;
    }

    pub fn reset(self: *ListAny) void {
        self.* = .{
            .in = null,
            .out = null,
            .count = 0,
        };
    }
    pub fn iterate(self: *const ListAny) Iterator {
        return .{
            .head = self.out,
        };
    }

    const Iterator = struct {
        head: ?*List_Link,

        fn next(iterator: *Iterator) ?*List_Link {
            const head = iterator.head orelse return null;
            iterator.head = head.next;
            return head;
        }
    };
};
