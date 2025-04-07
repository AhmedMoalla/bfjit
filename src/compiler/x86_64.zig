const std = @import("std");
const builtin = @import("builtin");
const lexer = @import("../lexer.zig");

pub const return_instruction = &[_]u8{0xC3}; // ret

pub fn compileOp(allocator: std.mem.Allocator, op: lexer.Op) ![]u8 {
    const machine_code = switch (op) {
        .set_zero => &[_]u8{ 0xc6, 0x07, 0x00 }, // mov byte [rdi], 0
        .inc => |count| &[_]u8{ 0x80, 0x07, count }, // add byte[rdi], operand
        .dec => |count| &[_]u8{ 0x80, 0x2f, count }, // sub byte[rdi], operand
        .left => |count| try std.mem.concat(allocator, u8, &[_][]const u8{
            &[_]u8{ 0x48, 0x81, 0xef }, // sub rdi,
            &std.mem.toBytes(@as(u32, count)), // operand
        }),
        .right => |count| try std.mem.concat(allocator, u8, &[_][]const u8{
            &[_]u8{ 0x48, 0x81, 0xc7 }, // add rdi,
            &std.mem.toBytes(@as(u32, count)), // operand
        }),
        .output => |count| {
            const syscall = &[_]u8{
                0x57, // push rdi
            } ++
                if (builtin.os.tag == .macos) &[_]u8{ 0x48, 0xc7, 0xc0, 0x04, 0x00, 0x00, 0x02 } // mov rax, 2000004
                else &[_]u8{ 0x48, 0xc7, 0xc0, 0x01, 0x00, 0x00, 0x00 } // mov rax, 1
                ++ &[_]u8{
                    0x48, 0x89, 0xfe, // mov rsi, rdi
                    0x48, 0xc7, 0xc7, 0x01, 0x00, 0x00, 0x00, // mov rdi, 1
                    0x48, 0xc7, 0xc2, 0x01, 0x00, 0x00, 0x00, // mov rdx, 1
                    0x0f, 0x05, // syscall
                    0x5f, // pop rdi
                };

            var buffer = try std.ArrayList(u8).initCapacity(allocator, count * syscall.len);
            defer buffer.deinit();

            for (0..count) |_| {
                try buffer.appendSlice(syscall);
            }

            return buffer.toOwnedSlice();
        },
        .input => |count| {
            const syscall = &[_]u8{
                0x57, // push rdi
            } ++
                if (builtin.os.tag == .macos) &[_]u8{ 0x48, 0xc7, 0xc0, 0x03, 0x00, 0x00, 0x02 } // mov rax, 2000003
                else &[_]u8{ 0x48, 0xc7, 0xc0, 0x0, 0x0, 0x0, 0x0 } // mov rax, 0
                ++ &[_]u8{
                    0x48, 0x89, 0xfe, // mov rsi, rdi
                    0x48, 0xc7, 0xc7, 0x00, 0x0, 0x0, 0x0, // mov rdi, 0
                    0x48, 0xc7, 0xc2, 0x01, 0x0, 0x0, 0x0, // mov rdx, 1
                    0x0f, 0x05, // syscall
                    0x5f, // pop rdi
                };

            var buffer = try std.ArrayList(u8).initCapacity(allocator, count * syscall.len);
            defer buffer.deinit();

            for (0..count) |_| {
                try buffer.appendSlice(syscall);
            }

            return buffer.toOwnedSlice();
        },
        .jump_if_zero => &[_]u8{
            0x8a, 0x07, // mov al, byte [rdi]
            0x84, 0xc0, // test al, al
            0x0f, 0x84, // jz
            0x0, 0x0, 0x0, 0x0, // 4 bytes address filled while back patching when we reach ']'
        },
        .jump_if_nonzero => &[_]u8{
            0x8a, 0x07, // mov al, byte [rdi]
            0x84, 0xc0, // test al, al
            0x0f, 0x85, // jnz
            0x0, 0x0, 0x0, 0x0, // 4 bytes address filled while back patching
        },
    };

    return allocator.dupe(u8, machine_code);
}

pub fn backPatchMatchingBrackets(left_last_byte_index: usize, left_op: []u8, right_last_byte_index: usize, right_op: []u8) void {
    const offset: i32 = @intCast(right_last_byte_index - left_last_byte_index);
    @memcpy(left_op[left_op.len - 4 .. left_op.len], &std.mem.toBytes(offset));
    @memcpy(right_op[right_op.len - 4 .. right_op.len], &std.mem.toBytes(-offset));
}
