const std = @import("std");
const builtin = @import("builtin");
const lexer = @import("../lexer.zig");
const repeatSlice = @import("utils.zig").repeatSlice;

pub const return_instruction = &[_]u8{0xC3}; // ret

const move_write_syscall = if (builtin.os.tag == .macos)
    &[_]u8{ 0x48, 0xc7, 0xc0, 0x04, 0x00, 0x00, 0x02 } // mov rax, 2000004
else
    &[_]u8{ 0x48, 0xc7, 0xc0, 0x01, 0x00, 0x00, 0x00 }; // mov rax, 1

const write_syscall = &[_]u8{
    0x57, // push rdi
} ++ move_write_syscall ++ &[_]u8{
    0x48, 0x89, 0xfe, // mov rsi, rdi
    0x48, 0xc7, 0xc7, 0x01, 0x00, 0x00, 0x00, // mov rdi, 1
    0x48, 0xc7, 0xc2, 0x01, 0x00, 0x00, 0x00, // mov rdx, 1
    0x0f, 0x05, // syscall
    0x5f, // pop rdi
};

const move_read_syscall = if (builtin.os.tag == .macos)
    &[_]u8{ 0x48, 0xc7, 0xc0, 0x03, 0x00, 0x00, 0x02 } // mov rax, 2000003
else
    &[_]u8{ 0x48, 0xc7, 0xc0, 0x0, 0x0, 0x0, 0x0 }; // mov rax, 0

const read_syscall = &[_]u8{
    0x57, // push rdi
} ++ move_read_syscall ++ &[_]u8{
    0x48, 0x89, 0xfe, // mov rsi, rdi
    0x48, 0xc7, 0xc7, 0x00, 0x0, 0x0, 0x0, // mov rdi, 0
    0x48, 0xc7, 0xc2, 0x01, 0x0, 0x0, 0x0, // mov rdx, 1
    0x0f, 0x05, // syscall
    0x5f, // pop rdi
};

// https://learn.microsoft.com/en-us/cpp/build/x64-calling-convention?view=msvc-170
const target_register = switch (builtin.os.tag) {
    .windows => 0b001, // rcx
    else => 0b111, // rdi
};

extern "c" fn getchar() c_int;
extern "c" fn putchar(char: c_int) c_int;

pub fn compileOp(allocator: std.mem.Allocator, op: lexer.Op) ![]u8 {
    const machine_code = sw: switch (op) {
        .set_zero => &[_]u8{ 0xc6, 0x0 | target_register, 0x00 }, // mov byte [REG], 0
        .inc => |count| &[_]u8{ 0x80, 0x0 | target_register, count }, // add byte[REG], operand
        .dec => |count| &[_]u8{ 0x80, 0x28 | target_register, count }, // sub byte[REG], operand
        .left => |count| try std.mem.concat(allocator, u8, &[_][]const u8{
            &[_]u8{ 0x48, 0x81, 0xe8 | target_register }, // sub REG,
            &std.mem.toBytes(@as(u32, count)), // operand
        }),
        .right => |count| try std.mem.concat(allocator, u8, &[_][]const u8{
            &[_]u8{ 0x48, 0x81, 0xc0 | target_register }, // add REG,
            &std.mem.toBytes(@as(u32, count)), // operand
        }),
        .output => |count| {
            const write_call: []const u8 = if (builtin.os.tag == .windows)
                try std.mem.concat(allocator, u8, &[_][]const u8{
                    &[_]u8{
                        0x51, // push rcx
                        0x48, 0xb8, // mov rax,
                    },
                    &std.mem.toBytes(@intFromPtr(&putchar)), // &putchar
                    &[_]u8{
                        0x0f, 0xbe, 0x09, // movsx ecx, byte [rcx]
                        0xff, 0xd0, // call rax
                        0x59, // pop rcx
                    },
                })
            else
                write_syscall;

            break :sw try repeatSlice(allocator, u8, write_call, count);
        },
        .input => |count| {
            const read_call: []const u8 = if (builtin.os.tag == .windows)
                try std.mem.concat(allocator, u8, &[_][]const u8{
                    &[_]u8{
                        0x49, 0x89, 0xc9, // mov r9, rcx
                        0x48, 0xb8, // mov rax,
                    },
                    &std.mem.toBytes(@intFromPtr(&getchar)), // &getchar
                    &[_]u8{
                        0xff, 0xd0, // call rax
                        0x4c, 0x89, 0xc9, // mov rcx, r9
                        0x88, 0x01, // mov [rcx], al
                    },
                })
            else
                read_syscall;

            break :sw try repeatSlice(allocator, u8, read_call, count);
        },
        .jump_if_zero => &[_]u8{
            0x8a, 0x0 | target_register, // mov al, byte [REG]
            0x84, 0xc0, // test al, al
            0x0f, 0x84, // jz
            0x0, 0x0, 0x0, 0x0, // 4 bytes address filled while back patching when we reach ']'
        },
        .jump_if_nonzero => &[_]u8{
            0x8a, 0x0 | target_register, // mov al, byte [REG]
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
