const std = @import("std");

pub fn repeatSlice(allocator: std.mem.Allocator, comptime T: type, slice: []const T, count: usize) ![]T {
    var buffer = try std.ArrayList(u8).initCapacity(allocator, count * slice.len);
    defer buffer.deinit();

    for (0..count) |_| {
        try buffer.appendSlice(slice);
    }

    return buffer.toOwnedSlice();
}
