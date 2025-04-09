const std = @import("std");
const builtin = @import("builtin");
const lexer = @import("lexer.zig");
const compiler = @import("compiler/compiler.zig");

pub fn compile(allocator: std.mem.Allocator, ops: []lexer.Op) !JittedCode {
    const code = try compiler.compile(allocator, ops);
    defer allocator.free(code);
    return JittedCode.init(code);
}

pub const JittedCode = if (builtin.os.tag == .windows) WindowsJittedCode else PosixJittedCode;

const WindowsJittedCode = struct {
    machine_code: [*]u8,

    const windows = std.os.windows;

    pub fn init(code: []u8) !WindowsJittedCode {
        const ptr = try windows.VirtualAlloc(
            null,
            code.len,
            windows.MEM_RESERVE | windows.MEM_COMMIT,
            windows.PAGE_READWRITE,
        );
        const jitted: [*]u8 = @ptrCast(ptr);
        @memcpy(jitted[0..code.len], code);

        var old: windows.DWORD = undefined;
        windows.VirtualProtect(ptr, code.len, windows.PAGE_EXECUTE_READ, &old) catch |err| switch (err) {
            error.InvalidAddress => return error.AccessDenied,
            error.Unexpected => return error.Unexpected,
        };
        return WindowsJittedCode{ .machine_code = jitted };
    }

    pub fn run(self: *WindowsJittedCode, memory: [*]u8) void {
        const runFn: *const fn (memory: [*]u8) callconv(.c) void = @ptrCast(self.machine_code);
        runFn(memory);
    }

    pub fn deinit(self: *WindowsJittedCode) void {
        windows.VirtualFree(self.machine_code, 0, windows.MEM_RELEASE);
    }
};

const PosixJittedCode = struct {
    machine_code: []align(std.heap.page_size_min) u8,
    const posix = std.posix;

    // https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.allow-jit
    const mmap_flags: posix.MAP = if (builtin.os.tag == .macos and builtin.cpu.arch == .aarch64)
        .{ .TYPE = .PRIVATE, .ANONYMOUS = true, .JIT = true }
    else
        .{ .TYPE = .PRIVATE, .ANONYMOUS = true };

    pub fn init(code: []u8) !PosixJittedCode {
        const jitted = try posix.mmap(
            null,
            code.len,
            posix.PROT.READ | .PROT.WRITE,
            mmap_flags,
            -1,
            0,
        );
        @memcpy(jitted[0..code.len], code);

        try posix.mprotect(jitted, posix.PROT.READ | posix.PROT.EXEC);
        return PosixJittedCode{ .machine_code = jitted };
    }

    pub fn run(self: *PosixJittedCode, memory: [*]u8) void {
        const runFn: *const fn (memory: [*]u8) callconv(.c) void = @ptrCast(self.machine_code);
        runFn(memory);
    }

    pub fn deinit(self: *PosixJittedCode) void {
        posix.munmap(self.machine_code);
    }
};
