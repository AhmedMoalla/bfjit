const std = @import("std");

const lexer = @import("../lexer.zig");
const class = @import("jvm/bfclass.zig");

const methods = class.info.constant_pool_indices.methods;

pub const return_instruction = &[_]u8{0xB1}; // return

fn invokestatic(method_ref_index: u16, operand: u8) [6]u8 {
    const index_bytes: [2]u8 = std.mem.toBytes(@byteSwap(method_ref_index));
    return [_]u8{
        0x11, 0x0, operand, // sipush operand(as u16)
        0xB8, index_bytes[0], index_bytes[1], // invokestatic method
    };
}

pub fn compileOp(gpa: std.mem.Allocator, op: lexer.Op) ![]u8 {
    const machine_code = switch (op) {
        .set_zero => &invokestatic(methods.set_at_head, 0),
        .inc => |count| &invokestatic(methods.inc_at_head, count),
        .dec => |count| &invokestatic(methods.dec_at_head, count),
        .left => |count| &invokestatic(methods.dec_head, count),
        .right => |count| &invokestatic(methods.inc_head, count),
        .output => |count| &invokestatic(methods.output_at_head, count),
        .input => |count| &invokestatic(methods.input_at_head, count),
        .jump_if_zero => try std.mem.concat(gpa, u8, &[_][]const u8{
            &[_]u8{0xB8}, &std.mem.toBytes(@byteSwap(methods.head_not_zero)),
            &[_]u8{
                0x99, // ifeq
                0x0, 0x0, // 2 bytes address filled while backpatching
            },
        }),
        .jump_if_nonzero => &[_]u8{
            0xA7, //goto
            0x0, 0x0, // 2 bytes address filled while backpatching
        },
    };

    return gpa.dupe(u8, machine_code);
}

pub fn backPatchMatchingBrackets(left_last_byte_index: usize, left_op: []u8, right_last_byte_index: usize, right_op: []u8) void {
    _ = left_last_byte_index;
    _ = left_op;
    _ = right_last_byte_index;
    _ = right_op;
    std.process.exit(1);
}
