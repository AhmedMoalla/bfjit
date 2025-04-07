const std = @import("std");
const builtin = @import("builtin");
const lexer = @import("../lexer.zig");

pub const return_instruction = &[_]u8{ 0xc0, 0x03, 0x5f, 0xd6 }; // ret

pub fn compileOp(allocator: std.mem.Allocator, op: lexer.Op) ![]u8 {
    const machine_code = switch (op) {
        .set_zero => @panic("not implemented"),
        .inc => |count| try std.mem.concat(allocator, u8, &[_][]const u8{
            &[_]u8{ 0x08, 0x00, 0x40, 0x39 }, // ldrb w8, [x0]
            &std.mem.toBytes(0x11000108 | (@as(u32, count) & 0xFF) << 10), // add w8, w8,
            &[_]u8{ 0x08, 0x00, 0x00, 0x39 }, // strb w8, [x0]
        }),
        .dec => |count| try std.mem.concat(allocator, u8, &[_][]const u8{
            &[_]u8{ 0x08, 0x00, 0x40, 0x39 }, // ldrb w8, [x0]
            &std.mem.toBytes(0x51000108 | (@as(u32, count) & 0xFF) << 10), // add w8, w8,
            &[_]u8{ 0x08, 0x00, 0x00, 0x39 }, // strb w8, [x0]
        }),
        .left => |count| &std.mem.toBytes(0xd1000000 | (@as(u32, count) & 0xFF) << 10), // sub x0, x0,
        .right => |count| &std.mem.toBytes(0x91000000 | (@as(u32, count) & 0xFF) << 10), // add x0, x0,
        .output => |count| {
            const syscall = &[_]u8{
                0xe1, 0x03, 0x00, 0xaa, // mov x1, x0
                0xe4, 0x03, 0x00, 0xaa, // mov x4, x0
                0x20, 0x00, 0x80, 0xd2, // mov x0, 1
                0x22, 0x00, 0x80, 0xd2, // mov x2, 1
            } ++
                if (builtin.os.tag == .macos) &[_]u8{ 0x90, 0x00, 0x80, 0xd2 } // mov x16, 4
                else &[_]u8{ 0x08, 0x08, 0x80, 0xd2 } // mov x8, 64
                ++ &[_]u8{
                    0x01, 0x00, 0x00, 0xd4, // svc 0
                    0xe0, 0x03, 0x04, 0xaa, // mov x0, x4
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
                0xe1, 0x03, 0x00, 0xaa, // mov x1, x0
                0xe4, 0x03, 0x00, 0xaa, // mov x4, x0
                0x20, 0x00, 0x80, 0xd2, // mov x0, 1
                0x22, 0x00, 0x80, 0xd2, // mov x2, 0
            } ++
                if (builtin.os.tag == .macos) &[_]u8{ 0x70, 0x00, 0x80, 0xd2 } // mov x16, 3
                else &[_]u8{ 0xe8, 0x07, 0x80, 0xd2 } // mov x8, 63
                ++ &[_]u8{
                    0x01, 0x00, 0x00, 0xd4, // svc 0
                    0xe0, 0x03, 0x04, 0xaa, // mov x0, x4
                };

            var buffer = try std.ArrayList(u8).initCapacity(allocator, count * syscall.len);
            defer buffer.deinit();

            for (0..count) |_| {
                try buffer.appendSlice(syscall);
            }

            return buffer.toOwnedSlice();
        },
        // cbz: https://developer.arm.com/documentation/ddi0596/2020-12/Base-Instructions/CBZ--Compare-and-Branch-on-Zero-?lang=en#sa_wt
        .jump_if_zero => &[_]u8{
            0x08, 0x00, 0x40, 0x39, // ldrb w8, [x0]
            0x08, 0x00, 0x00, 0x34, // cbz w8, <loc>
        },
        // cbnz: https://developer.arm.com/documentation/ddi0596/2020-12/Base-Instructions/CBNZ--Compare-and-Branch-on-Nonzero-?lang=en
        .jump_if_nonzero => &[_]u8{
            0x08, 0x00, 0x40, 0x39, // ldrb w8, [x0]
            0x08, 0x00, 0x00, 0x35, // cbnz w8, <loc>
        },
    };

    return allocator.dupe(u8, machine_code);
}

pub fn backPatchMatchingBrackets(left_last_byte_index: usize, left_op: []u8, right_last_byte_index: usize, right_op: []u8) void {
    const register_offset = 4; // 4 first bits is for the register to be tested
    const offset: i32 = @intCast(right_last_byte_index - left_last_byte_index);

    const leftAsInt: *const u32 = @alignCast(@ptrCast(left_op[left_op.len - 4 .. left_op.len]));
    const leftAsU32: u32 = @intCast((@divExact(offset + register_offset, 4) & 0x7ffff) << 5);
    const leftResult = leftAsInt.* | leftAsU32;
    @memcpy(left_op[left_op.len - 4 .. left_op.len], &std.mem.toBytes(leftResult));

    const rightAsInt: *const u32 = @alignCast(@ptrCast(right_op[right_op.len - 4 .. right_op.len]));
    const rightAsU32: u32 = @intCast((@divExact(-offset + register_offset, 4) & 0x7ffff) << 5);
    const rightResult = rightAsInt.* | rightAsU32;
    @memcpy(right_op[right_op.len - 4 .. right_op.len], &std.mem.toBytes(rightResult));
}
