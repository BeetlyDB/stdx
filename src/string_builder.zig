const std = @import("std");
const lib = @import("lib.zig");
const builtin = @import("builtin");

const string_builder = @This();

const Mutex = std.Thread.Mutex;
const Endian = std.builtin.Endian;
const Allocator = std.mem.Allocator;

pub const StringBuilder = struct {
    buf: []u8,
    pos: usize,
    static: []u8,
    pool: ?*string_builder.Pool = null,
    endian: Endian = builtin.cpu.arch.endian(),
    allocator: Allocator,

    pub const Pool = string_builder.Pool;

    // This is for one-off use. It's like creating an std.ArrayList(u8). We won't
    // use static at all, and everything will just be dynamic.
    pub fn init(allocator: Allocator) StringBuilder {
        return .{
            .pos = 0,
            .pool = null,
            .buf = &[_]u8{},
            .static = &[_]u8{},
            .allocator = allocator,
        };
    }

    // This is being created by our Pool, either in Pool.init or lazily in
    // pool.acquire(). The idea is that this buffer will get re-used so it has
    // a static buffer that will get used, and we'll only need to dynamically
    // allocate memory beyond static if we try to write more than static.len.
    fn initForPool(allocator: Allocator, pool: *string_builder.Pool, static_size: usize) !StringBuilder {
        const static = try allocator.alloc(u8, static_size);
        return .{
            .pos = 0,
            .pool = pool,
            .buf = static,
            .static = static,
            .allocator = allocator,
        };
    }

    // buf must be created with allocator
    pub fn fromOwnedSlice(allocator: Allocator, buf: []u8) StringBuilder {
        return .{
            .buf = buf,
            .pool = null,
            .pos = buf.len,
            .static = &[_]u8{},
            .allocator = allocator,
        };
    }

    pub const FromReaderOpts = struct {
        max_size: usize = std.math.maxInt(usize),
        buffer_size: usize = 8192,
    };

    pub fn fromReader(allocator: Allocator, reader: *std.Io.Reader, opts: FromReaderOpts) !StringBuilder {
        const max_size = opts.max_size;
        const buffer_size = if (opts.buffer_size < 64) 64 else opts.buffer_size;

        var buf = try allocator.alloc(u8, buffer_size);
        errdefer allocator.free(buf);

        var pos: usize = 0;
        while (true) {
            var read_slice = buf[pos..];
            if (read_slice.len < 512) {
                const new_capacity = buf.len + buffer_size;
                if (allocator.resize(buf, new_capacity)) {
                    buf = buf.ptr[0..new_capacity];
                } else {
                    const new_buffer = try allocator.alloc(u8, new_capacity);
                    lib.move(new_buffer[0..buf.len], buf);
                    allocator.free(buf);
                    buf = new_buffer;
                }
                read_slice = buf[pos..];
            }

            const n = try reader.readSliceShort(read_slice);
            if (n == 0) {
                break;
            }

            pos += n;
            if (pos > max_size) {
                return error.TooBig;
            }
        }

        var sb = fromOwnedSlice(allocator, buf);
        sb.pos = pos;
        return sb;
    }

    pub fn deinit(self: *const StringBuilder) void {
        self.allocator.free(self.buf);
    }

    // it's a mistake to call release if this string builder isn't from a pool
    pub fn release(self: *StringBuilder) void {
        const p = self.pool orelse unreachable;
        p.release(self);
    }

    pub fn clearRetainingCapacity(self: *StringBuilder) void {
        self.pos = 0;
    }

    pub fn len(self: *const StringBuilder) usize {
        return self.pos;
    }

    pub fn string(self: *const StringBuilder) []u8 {
        return self.buf[0..self.pos];
    }

    pub fn stringZ(self: *StringBuilder) ![:0]u8 {
        const pos = self.pos;
        try self.writeByte(0);
        self.pos = pos;
        return self.buf[0..pos :0];
    }

    pub fn copy(self: *const StringBuilder, allocator: Allocator) ![]u8 {
        const pos = self.pos;
        const c = try allocator.alloc(u8, pos);
        @memcpy(c, self.buf[0..pos]);
        return c;
    }

    pub fn truncate(self: *StringBuilder, n: usize) void {
        const pos = self.pos;
        if (n >= pos) {
            self.pos = 0;
            return;
        }
        self.pos = pos - n;
    }

    pub fn skip(self: *StringBuilder, n: usize) !View {
        try self.ensureUnusedCapacity(n);
        const pos = self.pos;
        self.pos = pos + n;
        return .{
            .pos = pos,
            .sb = self,
        };
    }

    pub fn writeByte(self: *StringBuilder, b: u8) !void {
        try self.ensureUnusedCapacity(1);
        self.writeByteAssumeCapacity(b);
    }

    pub fn writeByteAssumeCapacity(self: *StringBuilder, b: u8) void {
        const pos = self.pos;
        writeByteInto(self.buf, pos, b);
        self.pos = pos + 1;
    }

    pub fn writeByteNTimes(self: *StringBuilder, b: u8, n: usize) !void {
        try self.ensureUnusedCapacity(n);
        const pos = self.pos;
        writeByteNTimesInto(self.buf, pos, b, n);
        self.pos = pos + n;
    }

    pub fn write(self: *StringBuilder, data: []const u8) !void {
        try self.ensureUnusedCapacity(data.len);
        self.writeAssumeCapacity(data);
    }

    pub fn writeAssumeCapacity(self: *StringBuilder, data: []const u8) void {
        const pos = self.pos;
        writeInto(self.buf, pos, data);
        self.pos = pos + data.len;
    }

    pub fn writeU16(self: *StringBuilder, value: u16) !void {
        return self.writeIntT(u16, value, self.endian);
    }

    pub fn writeI16(self: *StringBuilder, value: i16) !void {
        return self.writeIntT(i16, value, self.endian);
    }

    pub fn writeU32(self: *StringBuilder, value: u32) !void {
        return self.writeIntT(u32, value, self.endian);
    }

    pub fn writeI32(self: *StringBuilder, value: i32) !void {
        return self.writeIntT(i32, value, self.endian);
    }

    pub fn writeU64(self: *StringBuilder, value: u64) !void {
        return self.writeIntT(u64, value, self.endian);
    }

    pub fn writeI64(self: *StringBuilder, value: i64) !void {
        return self.writeIntT(i64, value, self.endian);
    }

    pub fn writeU16Little(self: *StringBuilder, value: u16) !void {
        return self.writeIntT(u16, value, .little);
    }

    pub fn writeI16Little(self: *StringBuilder, value: i16) !void {
        return self.writeIntT(i16, value, .little);
    }

    pub fn writeU32Little(self: *StringBuilder, value: u32) !void {
        return self.writeIntT(u32, value, .little);
    }

    pub fn writeI32Little(self: *StringBuilder, value: i32) !void {
        return self.writeIntT(i32, value, .little);
    }

    pub fn writeU64Little(self: *StringBuilder, value: u64) !void {
        return self.writeIntT(u64, value, .little);
    }

    pub fn writeI64Little(self: *StringBuilder, value: i64) !void {
        return self.writeIntT(i64, value, .little);
    }

    pub fn writeU16Big(self: *StringBuilder, value: u16) !void {
        return self.writeIntT(u16, value, .big);
    }

    pub fn writeI16Big(self: *StringBuilder, value: i16) !void {
        return self.writeIntT(i16, value, .big);
    }

    pub fn writeU32Big(self: *StringBuilder, value: u32) !void {
        return self.writeIntT(u32, value, .big);
    }

    pub fn writeI32Big(self: *StringBuilder, value: i32) !void {
        return self.writeIntT(i32, value, .big);
    }

    pub fn writeU64Big(self: *StringBuilder, value: u64) !void {
        return self.writeIntT(u64, value, .big);
    }

    pub fn writeI64Big(self: *StringBuilder, value: i64) !void {
        return self.writeIntT(i64, value, .big);
    }

    fn writeIntT(self: *StringBuilder, comptime T: type, value: T, endian: Endian) !void {
        const l = @divExact(@typeInfo(T).int.bits, 8);
        try self.ensureUnusedCapacity(l);
        const pos = self.pos;
        writeIntInto(T, self.buf, pos, value, l, endian);
        self.pos = pos + l;
    }

    pub fn writeInt(self: *StringBuilder, value: anytype) !void {
        return self.writeIntAs(value, self.endian);
    }

    pub fn writeIntAs(self: *StringBuilder, value: anytype, endian: Endian) !void {
        const T = @TypeOf(value);
        switch (@typeInfo(T)) {
            .comptime_int => @compileError("Writing a comptime_int is slightly ambiguous, please cast to a specific type: sb.writeInt(@as(i32, 9001))"),
            .int => |int| {
                if (int.signedness == .signed) {
                    switch (int.bits) {
                        8 => return self.writeByte(value),
                        16 => return self.writeIntT(i16, value, endian),
                        32 => return self.writeIntT(i32, value, endian),
                        64 => return self.writeIntT(i64, value, endian),
                        else => {},
                    }
                } else {
                    switch (int.bits) {
                        8 => return self.writeByte(value),
                        16 => return self.writeIntT(u16, value, endian),
                        32 => return self.writeIntT(u32, value, endian),
                        64 => return self.writeIntT(u64, value, endian),
                        else => {},
                    }
                }
            },
            else => {},
        }
        @compileError("Unsupported integer type: " ++ @typeName(T));
    }

    pub fn ensureUnusedCapacity(self: *StringBuilder, n: usize) !void {
        return self.ensureTotalCapacity(self.pos + n);
    }

    pub fn ensureTotalCapacity(self: *StringBuilder, required_capacity: usize) !void {
        const buf = self.buf;
        if (required_capacity <= buf.len) {
            return;
        }

        // from std.ArrayList
        var new_capacity = buf.len;
        while (true) {
            new_capacity +|= new_capacity / 2 + 8;
            if (new_capacity >= required_capacity) break;
        }

        const is_static = self.buf.ptr == self.static.ptr;

        const allocator = self.allocator;
        if (is_static and allocator.resize(buf, new_capacity)) {
            self.buf = buf.ptr[0..new_capacity];
            return;
        }
        const new_buffer = try allocator.alloc(u8, new_capacity);
        @memcpy(new_buffer[0..buf.len], buf);

        if (!is_static) {
            // we don't free the static buffer
            allocator.free(buf);
        }
        self.buf = new_buffer;
    }

    pub fn writer(self: *StringBuilder) Writer {
        return .init(self);
    }

    pub const Writer = struct {
        sb: *StringBuilder,
        interface: std.io.Writer,

        pub const Error = Allocator.Error;

        fn init(sb: *StringBuilder) Writer {
            return .{
                .sb = sb,
                .interface = .{
                    .vtable = &.{
                        .drain = drain,
                    },
                    .buffer = &.{},
                },
            };
        }

        pub fn drain(io_w: *std.io.Writer, data: []const []const u8, splat: usize) error{WriteFailed}!usize {
            _ = splat;
            const self: *Writer = @alignCast(@fieldParentPtr("interface", io_w));
            self.sb.write(data[0]) catch return error.WriteFailed;
            return data[0].len;
        }

        pub fn print(self: *Writer, comptime fmt: []const u8, args: anytype) !void {
            return self.interface.print(fmt, args) catch return error.OutOfMemory;
        }

        pub fn write(self: Writer, data: []const u8) Allocator.Error!usize {
            try self.sb.write(data);
            return data.len;
        }

        pub fn writeAll(self: Writer, data: []const u8) Allocator.Error!void {
            try self.sb.write(data);
        }

        pub fn writeByte(self: Writer, b: u8) Allocator.Error!void {
            try self.sb.writeByte(b);
        }
        pub fn writeByteNTimes(self: Writer, b: u8, n: usize) !void {
            return self.sb.writeByteNTimes(b, n);
        }

        pub fn adaptToNewApi(self: Writer) Adapter {
            return .{ .new_interface = self.interface };
        }

        pub const Adapter = struct {
            err: ?Error = null,
            new_interface: std.Io.Writer,
        };
    };
};

pub const View = struct {
    pos: usize,
    sb: *StringBuilder,

    pub fn writeByte(self: *View, b: u8) void {
        const pos = self.pos;
        writeByteInto(self.sb.buf, pos, b);
        self.pos = pos + 1;
    }

    pub fn writeByteNTimes(self: *View, b: u8, n: usize) void {
        const pos = self.pos;
        writeByteNTimesInto(self.sb.buf, pos, b, n);
        self.pos = pos + n;
    }

    pub fn write(self: *View, data: []const u8) void {
        const pos = self.pos;
        writeInto(self.sb.buf, pos, data);
        self.pos = pos + data.len;
    }

    pub fn writeU16(self: *View, value: u16) void {
        return self.writeIntT(u16, value, self.endian);
    }

    pub fn writeI16(self: *View, value: i16) void {
        return self.writeIntT(i16, value, self.endian);
    }

    pub fn writeU32(self: *View, value: u32) void {
        return self.writeIntT(u32, value, self.endian);
    }

    pub fn writeI32(self: *View, value: i32) void {
        return self.writeIntT(i32, value, self.endian);
    }

    pub fn writeU64(self: *View, value: u64) void {
        return self.writeIntT(u64, value, self.endian);
    }

    pub fn writeI64(self: *View, value: i64) void {
        return self.writeIntT(i64, value, self.endian);
    }

    pub fn writeU16Little(self: *View, value: u16) void {
        return self.writeIntT(u16, value, .little);
    }

    pub fn writeI16Little(self: *View, value: i16) void {
        return self.writeIntT(i16, value, .little);
    }

    pub fn writeU32Little(self: *View, value: u32) void {
        return self.writeIntT(u32, value, .little);
    }

    pub fn writeI32Little(self: *View, value: i32) void {
        return self.writeIntT(i32, value, .little);
    }

    pub fn writeU64Little(self: *View, value: u64) void {
        return self.writeIntT(u64, value, .little);
    }

    pub fn writeI64Little(self: *View, value: i64) void {
        return self.writeIntT(i64, value, .little);
    }

    pub fn writeU16Big(self: *View, value: u16) void {
        return self.writeIntT(u16, value, .big);
    }

    pub fn writeI16Big(self: *View, value: i16) void {
        return self.writeIntT(i16, value, .big);
    }

    pub fn writeU32Big(self: *View, value: u32) void {
        return self.writeIntT(u32, value, .big);
    }

    pub fn writeI32Big(self: *View, value: i32) void {
        return self.writeIntT(i32, value, .big);
    }

    pub fn writeU64Big(self: *View, value: u64) void {
        return self.writeIntT(u64, value, .big);
    }

    pub fn writeI64Big(self: *View, value: i64) void {
        return self.writeIntT(i64, value, .big);
    }

    fn writeIntT(self: *View, comptime T: type, value: T, endian: Endian) void {
        const l = @divExact(@typeInfo(T).int.bits, 8);
        const pos = self.pos;
        writeIntInto(T, self.sb.buf, pos, value, l, endian);
        self.pos = pos + l;
    }

    pub fn writeInt(self: *View, value: anytype) void {
        return self.writeIntAs(value, self.endian);
    }

    pub fn writeIntAs(self: *View, value: anytype, endian: Endian) void {
        const T = @TypeOf(value);
        switch (@typeInfo(T)) {
            .comptime_int => @compileError("Writing a comptime_int is slightly ambiguous, please cast to a specific type: sb.writeInt(@as(i32, 9001))"),
            .int => |int| {
                if (int.signedness == .signed) {
                    switch (int.bits) {
                        8 => return self.writeByte(value),
                        16 => return self.writeIntT(i16, value, endian),
                        32 => return self.writeIntT(i32, value, endian),
                        64 => return self.writeIntT(i64, value, endian),
                        else => {},
                    }
                } else {
                    switch (int.bits) {
                        8 => return self.writeByte(value),
                        16 => return self.writeIntT(u16, value, endian),
                        32 => return self.writeIntT(u32, value, endian),
                        64 => return self.writeIntT(u64, value, endian),
                        else => {},
                    }
                }
            },
            else => {},
        }
        @compileError("Unsupported integer type: " ++ @typeName(T));
    }
};

pub const Pool = struct {
    mutex: Mutex,
    available: usize,
    allocator: Allocator,
    static_size: usize,
    builders: []*StringBuilder,

    pub fn init(allocator: Allocator, pool_size: u16, static_size: usize) !*Pool {
        const builders = try allocator.alloc(*StringBuilder, pool_size);
        errdefer allocator.free(builders);

        const pool = try allocator.create(Pool);
        errdefer allocator.destroy(pool);

        pool.* = .{ .mutex = .{}, .builders = builders, .allocator = allocator, .available = pool_size, .static_size = static_size };

        var allocated: usize = 0;
        errdefer {
            for (0..allocated) |i| {
                var sb = builders[i];
                sb.deinit();
                allocator.destroy(sb);
            }
        }

        for (0..pool_size) |i| {
            const sb = try allocator.create(StringBuilder);
            errdefer allocator.destroy(sb);
            sb.* = try StringBuilder.initForPool(allocator, pool, static_size);
            builders[i] = sb;
            allocated += 1;
        }

        return pool;
    }

    pub fn deinit(self: *Pool) void {
        const allocator = self.allocator;
        for (self.builders) |sb| {
            sb.deinit();
            allocator.destroy(sb);
        }
        allocator.free(self.builders);
        allocator.destroy(self);
    }

    pub fn acquire(self: *Pool) !*StringBuilder {
        const builders = self.builders;

        self.mutex.lock();
        const available = self.available;
        if (available == 0) {
            // dont hold the lock over factory
            self.mutex.unlock();

            const allocator = self.allocator;
            const sb = try allocator.create(StringBuilder);
            // Intentionally not using initForPool here. There's a tradeoff.
            // If we use initForPool, than this StringBuilder could be re-added to the
            // pool on release, which would help keep our pool nice and full. However,
            // many applications will use a very large static_size to avoid or minimize
            // dynamic allocations and grows/copies. They do this thinking all of that
            // static buffers are allocated upfront, on startup. Doing it here would
            // result in an unexpected large allocation, the exact opposite of what
            // we're after.
            sb.* = StringBuilder.init(allocator);
            // even though we wont' release this back to the pool, we still want
            // sb.release() to be callable. sb.release() will call pool.release()
            // which will know what to do with this non-pooled StringBuilder.
            sb.pool = self;
            return sb;
        }
        const index = available - 1;
        const sb = builders[index];
        self.available = index;
        self.mutex.unlock();
        return sb;
    }

    pub fn release(self: *Pool, sb: *StringBuilder) void {
        const allocator = self.allocator;

        if (sb.static.len == 0) {
            // this buffer was allocated by acquire() because the pool was empty
            // it has no static buffer, so we release it
            allocator.free(sb.buf);
            allocator.destroy(sb);
            return;
        }

        sb.pos = 0;
        if (sb.buf.ptr != sb.static.ptr) {
            // If buf.ptr != static.ptr, that means we had to dymamically allocate a
            // buffer beyond static. Free that dynamically allocated buffer...
            allocator.free(sb.buf);
            // ... and restore the static buffer;
            sb.buf = sb.static;
        }

        self.mutex.lock();
        const available = self.available;
        var builders = self.builders;
        builders[available] = sb;
        self.available = available + 1;
        self.mutex.unlock();
    }
};

// Functions that write for either a *StringBuilder or a *View
inline fn writeInto(buf: []u8, pos: usize, data: []const u8) void {
    const end_pos = pos + data.len;
    lib.move(buf[pos..end_pos], data);
}

inline fn writeByteInto(buf: []u8, pos: usize, b: u8) void {
    buf[pos] = b;
}

inline fn writeByteNTimesInto(buf: []u8, pos: usize, b: u8, n: usize) void {
    for (0..n) |offset| {
        buf[pos + offset] = b;
    }
}

inline fn writeIntInto(comptime T: type, buf: []u8, pos: usize, value: T, l: usize, endian: Endian) void {
    const end_pos = pos + l;
    std.mem.writeInt(T, buf[pos..end_pos][0..l], value, endian);
}
