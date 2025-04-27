const std = @import("std");
const ClassFile = @import("bfclass.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const info = ClassFile.info;
    std.debug.print("{}\n", .{info});
    // const fields = info.constant_pool_indices.fields;
    const methods = info.constant_pool_indices.methods;
    const class_bytes = try ClassFile.create(gpa, ByteCode.init(gpa)
        .iconst_0()
        .invokestatic(methods.set_at_head)
        .@"return"()
        .toOwnedSlice());

    std.debug.print("{d} {d}\n", .{ std.math.minInt(i16), std.math.maxInt(i16) });

    const file = try std.fs.cwd().createFile("BrainfuckProgram.class", .{ .truncate = true });
    const bytes = try file.write(class_bytes);
    std.debug.print("{d} bytes written\n", .{bytes});
}

const ByteCode = struct {
    const Self = @This();

    gpa: std.mem.Allocator,
    bytes: std.ArrayList(u8),

    pub fn init(gpa: std.mem.Allocator) *Self {
        const self_ptr = gpa.create(Self) catch unreachable;
        self_ptr.* = Self{ .gpa = gpa, .bytes = std.ArrayList(u8).init(gpa) };
        return self_ptr;
    }

    pub fn deinit(self: *Self) void {
        self.bytes.deinit();
        self.gpa.destroy(self);
    }

    pub fn @"return"(self: *Self) *Self {
        self.bytes.append(0xB1) catch {};
        return self;
    }

    pub fn iconst_0(self: *Self) *Self {
        self.bytes.append(0x3) catch {};
        return self;
    }

    pub fn invokestatic(self: *Self, method_ref_index: u16) *Self {
        self.bytes.append(0xB8) catch {};
        self.bytes.appendSlice(&std.mem.toBytes(@byteSwap(method_ref_index))) catch {};
        return self;
    }

    pub fn toOwnedSlice(self: *Self) []u8 {
        return self.bytes.toOwnedSlice() catch &[_]u8{};
    }
};
