const std = @import("std");
const lexer = @import("lexer.zig");

pub const JittedCode = struct {
    machine_code: []align(std.heap.page_size_min) u8,

    pub fn run(self: *JittedCode, memory: [*]u8) void {
        const runFn: *const fn (memory: [*]u8) callconv(.c) void = @ptrCast(self.machine_code);
        runFn(memory);
    }

    pub fn deinit(self: *JittedCode) void {
        std.posix.munmap(self.machine_code);
    }
};

pub fn compile(allocator: std.mem.Allocator, ops: []lexer.Op) !JittedCode {
    var code = std.ArrayList(u8).init(allocator);
    defer code.deinit();
    var addresses = std.ArrayList(usize).init(allocator);
    defer addresses.deinit();
    var jump_tbl = std.ArrayList(usize).init(allocator);
    defer jump_tbl.deinit();

    for (ops) |op| {
        try addresses.append(code.items.len);
        switch (op.kind) {
            .inc => {
                if (op.operand > 255) {
                    return error.OperandTooBig;
                }
                try code.appendSlice(&[_]u8{ 0x80, 0x07, @intCast(op.operand & 0xFF) }); // add byte[rdi], operand
            },
            .dec => {
                if (op.operand > 255) {
                    return error.OperandTooBig;
                }
                try code.appendSlice(&[_]u8{ 0x80, 0x2f, @intCast(op.operand & 0xFF) }); // sub byte[rdi], operand
            },
            .left => {
                try code.appendSlice(&[_]u8{ 0x48, 0x81, 0xef }); // sub rdi,
                try code.appendSlice(std.mem.sliceAsBytes(&[_]u32{@intCast(op.operand)})); // operand
            },
            .right => {
                try code.appendSlice(&[_]u8{ 0x48, 0x81, 0xc7 }); // add rdi,
                try code.appendSlice(std.mem.sliceAsBytes(&[_]u32{@intCast(op.operand)})); // operand
            },
            .output => {
                for (0..op.operand) |_| {
                    try code.appendSlice(&[_]u8{
                        0x57, // push rdi
                        0x48, 0xc7, 0xc0, 0x01, 0x00, 0x00, 0x00, // mov rax, 1
                        0x48, 0x89, 0xfe, // mov rsi, rdi
                        0x48, 0xc7, 0xc7, 0x01, 0x00, 0x00, 0x00, // mov rdi, 1
                        0x48, 0xc7, 0xc2, 0x01, 0x00, 0x00, 0x00, // mov rdx, 1
                        0x0f, 0x05, // syscall
                        0x5f, // pop rdi
                    });
                }
            },
            .input => {
                for (0..op.operand) |_| {
                    try code.appendSlice(&[_]u8{
                        0x57, // push rdi
                        0x48, 0xc7, 0xc0, 0x0, 0x0, 0x0, 0x0, // mov rax, 0
                        0x48, 0x89, 0xfe, // mov rsi, rdi
                        0x48, 0xc7, 0xc7, 0x00, 0x0, 0x0, 0x0, // mov rdi, 0
                        0x48, 0xc7, 0xc2, 0x01, 0x0, 0x0, 0x0, // mov rdx, 1
                        0x0f, 0x05, // syscall
                        0x5f, // pop rdi
                    });
                }
            },
            .jump_if_zero => {
                try code.appendSlice(&[_]u8{
                    0x8a, 0x07, // mov al, byte [rdi]
                    0x84, 0xc0, // test al, al
                    0x0f, 0x84, // jz
                    0x0,  0x0,
                    0x0, 0x0, // 4 bytes address when we reach ']'
                });
                try jump_tbl.append(code.items.len);
            },
            .jump_if_nonzero => {
                try code.appendSlice(&[_]u8{
                    0x8a, 0x07, // mov al, byte [rdi]
                    0x84, 0xc0, // test al, al
                    0x0f, 0x85, // jnz
                    0x0, 0x0, 0x0, 0x0, // 4 bytes address filled from jumb_tbl
                });

                const left = jump_tbl.pop().?;
                const right = code.items.len;
                const offset: i32 = @intCast(right - left);

                @memcpy(code.items[left - 4 .. left], &std.mem.toBytes(offset));
                @memcpy(code.items[right - 4 .. right], &std.mem.toBytes(-offset));
            },
        }
    }

    try addresses.append(code.items.len);

    try code.append(0xC3); // ret

    const content = code.items;
    const jitted = try std.posix.mmap(
        null,
        content.len,
        std.posix.PROT.READ | std.posix.PROT.WRITE,
        .{ .TYPE = .PRIVATE, .ANONYMOUS = true },
        -1,
        0,
    );
    @memcpy(jitted[0..content.len], content);

    try std.posix.mprotect(jitted, std.posix.PROT.READ | std.posix.PROT.EXEC);
    return JittedCode{ .machine_code = jitted };
}

test compile {}
