const std = @import("std");
const lexer = @import("../lexer.zig");

pub const return_instruction = 0xC3; // ret

pub fn compileOp(_: std.mem.Allocator, _: lexer.Op) ![]u8 {
    unreachable;
}
