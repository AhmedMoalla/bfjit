const std = @import("std");
const builtin = @import("builtin");
const lexer = @import("./lexer.zig");
const interpreter = @import("./interpreter.zig");
const jit = @import("./jit.zig");

pub fn main() !u8 {
    if (builtin.os.tag != .linux or builtin.cpu.arch != .x86_64) {
        std.debug.print("Only x86_64-linux is supported.\n", .{});
        return;
    }

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const input, const do_jit = parseArgs(args) catch |err| {
        std.log.err("usage: bfjit [--no-jit] <input.bf>", .{});
        switch (err) {
            error.InputRequired => std.log.err("no input is provided", .{}),
        }
        return 1;
    };

    const content = try std.fs.cwd().readFileAlloc(allocator, input, 1024 * 1024);

    const ops = lexer.tokenize(allocator, content) catch |err| {
        std.log.err("error occured in tokenizer: {s}\n", .{@errorName(err)});
        return 1;
    };

    std.log.info("JIT: {s}", .{if (do_jit) "on" else "off"});
    if (do_jit) {
        var jitted = jit.compile(allocator, ops) catch |err| {
            std.log.err("error occured in JIT compiler: {s}\n", .{@errorName(err)});
            return 1;
        };
        defer jitted.deinit();

        const memory = try allocator.alloc(u8, 10 * 1000 * 1000);
        @memset(memory, 0);
        defer allocator.free(memory);

        jitted.run(memory.ptr);
    } else {
        interpreter.interpret(allocator, ops) catch |err| {
            std.log.err("error occured in interpreter: {s}\n", .{@errorName(err)});
            return 1;
        };
    }

    return 0;
}

fn parseArgs(args: [][:0]u8) !struct { []const u8, bool } {
    var program: ?[]const u8 = null;
    var input: ?[]const u8 = null;
    var do_jit = true;
    for (args) |arg| {
        if (program == null) {
            program = arg;
            continue;
        }

        if (std.mem.eql(u8, arg, "--no-jit")) {
            do_jit = false;
            continue;
        }

        input = arg;
    }

    if (input == null) {
        return error.InputRequired;
    }

    return .{ input.?, do_jit };
}
