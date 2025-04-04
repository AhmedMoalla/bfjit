const std = @import("std");
const lexer = @import("../lexer.zig");

pub const return_instruction = 0xC3; // ret

pub fn compileOp(allocator: std.mem.Allocator, op: lexer.Op) ![]u8 {
    const machine_code = sw: switch (op) {
        .set_zero => &[_]u8{ 0xc6, 0x07, 0x00 }, // mov byte [rdi], 0
        .inc => |count| &[_]u8{ 0x80, 0x07, @intCast(count & 0xFF) }, // add byte[rdi], operand
        .dec => |count| &[_]u8{ 0x80, 0x2f, @intCast(count & 0xFF) }, // sub byte[rdi], operand
        .left => |count| try std.mem.concat(allocator, u8, &[_][]const u8{
            &[_]u8{ 0x48, 0x81, 0xef }, // sub rdi,
            std.mem.sliceAsBytes(&[_]u32{@intCast(count)}), // operand
        }),
        .right => |count| try std.mem.concat(allocator, u8, &[_][]const u8{
            &[_]u8{ 0x48, 0x81, 0xc7 }, // add rdi,
            std.mem.sliceAsBytes(&[_]u32{@intCast(count)}), // operand
        }),
        .output => |count| {
            const syscall = &[_]u8{
                0x57, // push rdi
                0x48, 0xc7, 0xc0, 0x01, 0x00, 0x00, 0x00, // mov rax, 1
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

            break :sw try buffer.toOwnedSlice();
        },
        .input => |count| {
            const syscall = &[_]u8{
                0x57, // push rdi
                0x48, 0xc7, 0xc0, 0x0, 0x0, 0x0, 0x0, // mov rax, 0
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

            break :sw try buffer.toOwnedSlice();
        },
        .jump_if_zero => &[_]u8{
            0x8a, 0x07, // mov al, byte [rdi]
            0x84, 0xc0, // test al, al
            0x0f, 0x84, // jz
            0x0,  0x0,
            0x0, 0x0, // 4 bytes address when we reach ']'
        },
        .jump_if_nonzero => &[_]u8{
            0x8a, 0x07, // mov al, byte [rdi]
            0x84, 0xc0, // test al, al
            0x0f, 0x85, // jnz
            0x0, 0x0, 0x0, 0x0, // 4 bytes address filled from jumb_tbl
        },
    };

    return allocator.dupe(u8, machine_code);
}
