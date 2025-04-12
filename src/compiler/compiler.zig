const std = @import("std");
const builtin = @import("builtin");
const lexer = @import("../lexer.zig");

const log = @import("../logger.zig").scoped(.compiler);

const UnsupportedArch = struct {
    pub const return_instruction = &[_]u8{};
    pub fn compileOp(_: std.mem.Allocator, _: lexer.Op) ![]u8 {
        log.err(@tagName(builtin.cpu.arch) ++ " architecture is unsupported by compiler.", .{});
        std.process.exit(1);
    }
    pub fn backPatchMatchingBrackets(left_last_byte_index: usize, left_op: []u8, right_last_byte_index: usize, right_op: []u8) void {
        _ = left_last_byte_index;
        _ = left_op;
        _ = right_last_byte_index;
        _ = right_op;
        log.err(@tagName(builtin.cpu.arch) ++ " architecture is unsupported by compiler.", .{});
        std.process.exit(1);
    }
};

const inner = switch (builtin.cpu.arch) {
    .x86_64 => @import("x86_64.zig"),
    .aarch64 => @import("aarch64.zig"),
    else => UnsupportedArch,
};

pub fn compile(allocator: std.mem.Allocator, ops: []lexer.Op) ![]u8 {
    var code = std.ArrayList(u8).init(allocator);
    defer code.deinit();
    var jump_tbl = std.ArrayList(struct { start: usize, end: usize }).init(allocator);
    defer jump_tbl.deinit();

    for (ops) |op| {
        const op_code = try inner.compileOp(allocator, op);
        defer allocator.free(op_code);
        try code.appendSlice(op_code);

        switch (op) {
            .jump_if_zero => try jump_tbl.append(.{ .start = code.items.len - op_code.len, .end = code.items.len }),
            .jump_if_nonzero => {
                const left = jump_tbl.pop().?;
                const right = code.items.len;

                inner.backPatchMatchingBrackets(
                    left.end,
                    code.items[left.start..left.end],
                    right,
                    code.items[right - op_code.len .. right],
                );
            },
            else => {},
        }
    }

    try code.appendSlice(inner.return_instruction);
    return code.toOwnedSlice();
}
