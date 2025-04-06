const std = @import("std");
const builtin = @import("builtin");
const lexer = @import("../lexer.zig");

const log = @import("../logger.zig").scoped(.compiler);

const inner = switch (builtin.cpu.arch) {
    .x86_64 => @import("x86_64.zig"),
    else => |arch| struct {
        pub const return_instruction = 0;
        pub fn compileOp(_: std.mem.Allocator, _: lexer.Op) ![]u8 {
            log.err(@tagName(arch) ++ " architecture is unsupported by compiler.", .{});
            std.process.exit(1);
        }
    },
};

pub fn compile(allocator: std.mem.Allocator, ops: []lexer.Op) ![]u8 {
    var code = std.ArrayList(u8).init(allocator);
    defer code.deinit();
    var jump_tbl = std.ArrayList(usize).init(allocator);
    defer jump_tbl.deinit();

    for (ops) |op| {
        const op_code = try inner.compileOp(allocator, op);
        defer allocator.free(op_code);
        try code.appendSlice(op_code);

        switch (op) {
            .jump_if_zero => try jump_tbl.append(code.items.len),
            .jump_if_nonzero => {
                const left = jump_tbl.pop().?;
                const right = code.items.len;
                const offset: i32 = @intCast(right - left);

                @memcpy(code.items[left - 4 .. left], &std.mem.toBytes(offset));
                @memcpy(code.items[right - 4 .. right], &std.mem.toBytes(-offset));
            },
            else => {},
        }
    }

    try code.append(inner.return_instruction);
    return code.toOwnedSlice();
}

test compile {}
