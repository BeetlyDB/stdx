const std = @import("std");

/// Type which could be borrowed or owned | Copy On Write
pub fn Cow(comptime T: type, comptime VTable: type) type {
    const info = @typeInfo(T);
    if (info == .pointer and info.pointer.size == .slice) {
        @compileError("Cow should not be used with slice types");
    }

    const Handler = struct {
        inline fn copy(this: *const T, allocator: std.mem.Allocator) T {
            if (!@hasDecl(VTable, "copy")) @compileError(@typeName(VTable) ++ " needs `copy()` function");
            return VTable.copy(this, allocator);
        }

        inline fn deinit(this: *T, allocator: std.mem.Allocator) void {
            if (!@hasDecl(VTable, "deinit")) @compileError(@typeName(VTable) ++ " needs `deinit()` function");
            return VTable.deinit(this, allocator);
        }
    };

    return union(enum) {
        borrowed: *const T,
        owned: T,

        pub inline fn borrow(val: *const T) @This() {
            return .{
                .borrowed = val,
            };
        }

        pub inline fn own(val: T) @This() {
            return .{
                .owned = val,
            };
        }

        pub inline fn replace(self: *@This(), allocator: std.mem.Allocator, newval: T) void {
            if (self.* == .owned) {
                self.deinit(allocator);
            }
            self.* = .{ .owned = newval };
        }

        pub inline fn inner(self: *const @This()) *const T {
            return switch (self.*) {
                .borrowed => self.borrowed,
                .owned => &self.owned,
            };
        }

        pub inline fn innerMut(self: *@This()) ?*T {
            return switch (self.*) {
                .borrowed => null,
                .owned => &self.owned,
            };
        }

        pub inline fn toOwned(self: *@This(), allocator: std.mem.Allocator) *T {
            switch (self.*) {
                .borrowed => {
                    const ptr = self.borrowed;
                    const copy_val = Handler.copy(ptr, allocator);
                    self.* = .{ .owned = copy_val };
                },
                .owned => {},
            }
            return &self.owned;
        }

        pub inline fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            if (self.* == .owned) {
                Handler.deinit(&self.owned, allocator);
            }
        }
    };
}

const TestStruct = struct {
    val: i32,

    pub fn init(v: i32) TestStruct {
        return .{ .val = v };
    }
};

const TestVTable = struct {
    pub inline fn copy(orig: *const TestStruct, allocator: std.mem.Allocator) TestStruct {
        _ = allocator;
        return TestStruct{ .val = orig.val };
    }

    pub inline fn deinit(obj: *TestStruct, allocator: std.mem.Allocator) void {
        _ = allocator;
        obj.val = -9999;
    }
};

const CowTS = Cow(TestStruct, TestVTable);

test "borrow stores pointer and does not copy" {
    var ts = TestStruct.init(123);
    var cow = CowTS.borrow(&ts);

    try std.testing.expect(cow.inner().val == 123);
    try std.testing.expect(cow.inner() == &ts);
    try std.testing.expect(cow.innerMut() == null);
}

test "own stores value directly" {
    var cow = CowTS.own(TestStruct.init(42));

    try std.testing.expect(cow.inner().val == 42);
    try std.testing.expect(cow.innerMut().?.val == 42);
}

test "toOwned turns borrowed into owned" {
    const allocator = std.testing.allocator;

    var ts = TestStruct.init(7);
    var cow = CowTS.borrow(&ts);

    const before_ptr = cow.inner();

    const owned_ptr = cow.toOwned(allocator);

    try std.testing.expect(cow.inner() == owned_ptr);
    try std.testing.expect(before_ptr != owned_ptr);
    try std.testing.expect(cow.inner().val == 7);

    cow.deinit(allocator);
}

test "toOwned on already-owned keeps pointer" {
    const allocator = std.testing.allocator;

    var cow = CowTS.own(TestStruct.init(9));
    const before = cow.inner();

    const after = cow.toOwned(allocator);

    try std.testing.expect(before == after);
    try std.testing.expect(after.val == 9);

    cow.deinit(allocator);
}

test "replace destroys old owned value" {
    const allocator = std.testing.allocator;

    var cow = CowTS.own(TestStruct.init(10));
    try std.testing.expect(cow.inner().val == 10);

    cow.replace(allocator, TestStruct.init(20));

    try std.testing.expect(cow.inner().val == 20);

    cow.deinit(allocator);
}

test "deinit on borrowed does nothing" {
    const allocator = std.testing.allocator;

    var ts = TestStruct.init(55);
    var cow = CowTS.borrow(&ts);

    cow.deinit(allocator);

    try std.testing.expect(ts.val == 55);
}

test "deinit on owned calls vtable deinit" {
    const allocator = std.testing.allocator;

    var cow = CowTS.own(TestStruct.init(88));

    cow.deinit(allocator);

    try std.testing.expect(cow.inner().val == -9999);
}
