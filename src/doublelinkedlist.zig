const std = @import("std");
const assert = std.debug.assert;

/// An intrusive doubly-linked list.
/// Currently it is FIFO
pub fn DoublyLinkedListType(
    comptime Node: type,
    comptime field_back_enum: std.meta.FieldEnum(Node),
    comptime field_next_enum: std.meta.FieldEnum(Node),
) type {
    assert(@typeInfo(Node) == .@"struct");
    assert(field_back_enum != field_next_enum);
    assert(@FieldType(Node, "prev") == ?*Node);
    assert(@FieldType(Node, "next") == ?*Node);

    const field_back = @tagName(field_back_enum);
    const field_next = @tagName(field_next_enum);

    return struct {
        const DoublyLinkedList = @This();

        head: ?*Node = null,
        tail: ?*Node = null,
        count: u32 = 0,

        pub inline fn empty(list: *const DoublyLinkedList) bool {
            assert((list.count == 0) == (list.head == null and list.tail == null));
            return list.count == 0;
        }

        pub inline fn contains(list: *const DoublyLinkedList, target: *const Node) bool {
            var iterator = list.head;
            var c: u32 = 0;
            while (iterator) |node| {
                if (node == target) return true;
                iterator = @field(node, field_next);
                c += 1;
            }
            assert(c == list.count);
            return false;
        }

        // push to tail (append) — O(1)
        pub inline fn push(list: *DoublyLinkedList, node: *Node) void {
            assert(@field(node, field_back) == null);
            assert(@field(node, field_next) == null);

            if (list.tail) |old_tail| {
                @field(old_tail, field_next) = node;
                @field(node, field_back) = old_tail;
                @field(node, field_next) = null;
                list.tail = node;
            } else {
                // empty list -> node becomes sole element
                list.head = node;
                list.tail = node;
                @field(node, field_back) = null;
                @field(node, field_next) = null;
            }
            list.count += 1;
        }

        // pop from tail
        pub inline fn pop(list: *DoublyLinkedList) ?*Node {
            if (list.tail == null) return null;
            const old_tail = list.tail.?;
            const before = @field(old_tail, field_back);
            if (before) |b| {
                list.tail = b;
                @field(b, field_next) = null;
            } else {
                // was only node
                list.head = null;
                list.tail = null;
            }
            @field(old_tail, field_back) = null;
            @field(old_tail, field_next) = null;
            list.count -= 1;
            return old_tail;
        }

        pub inline fn remove(list: *DoublyLinkedList, node: *Node) void {
            assert(list.count > 0);

            const prev = @field(node, field_back);
            const next = @field(node, field_next);

            if (prev) |p| {
                @field(p, field_next) = next;
            } else {
                // node was head
                list.head = next;
            }

            if (next) |n| {
                @field(n, field_back) = prev;
            } else {
                // node was tail
                list.tail = prev;
            }

            @field(node, field_back) = null;
            @field(node, field_next) = null;
            list.count -= 1;

            assert((list.count == 0) == (list.head == null and list.tail == null));
        }
    };
}
