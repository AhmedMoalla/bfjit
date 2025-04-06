const std = @import("std");
const lexer = @import("lexer.zig");
const compiler = @import("compiler/compiler.zig");

pub fn compile(allocator: std.mem.Allocator, ops: []lexer.Op) !JittedCode {
    const code = try compiler.compile(allocator, ops);
    defer allocator.free(code);
    return JittedCode.init(code);
}

pub const JittedCode = struct {
    machine_code: []align(std.heap.page_size_min) u8,

    pub fn init(code: []u8) !JittedCode {
        const jitted = try std.posix.mmap(
            null,
            code.len,
            std.posix.PROT.READ | std.posix.PROT.WRITE,
            .{ .TYPE = .PRIVATE, .ANONYMOUS = true },
            -1,
            0,
        );
        @memcpy(jitted[0..code.len], code);

        try std.posix.mprotect(jitted, std.posix.PROT.READ | std.posix.PROT.EXEC);
        return JittedCode{ .machine_code = jitted };
    }

    pub fn run(self: *JittedCode, memory: [*]u8) void {
        const runFn: *const fn (memory: [*]u8) callconv(.c) void = @ptrCast(self.machine_code);
        runFn(memory);
    }

    pub fn deinit(self: *JittedCode) void {
        std.posix.munmap(self.machine_code);
    }
};
