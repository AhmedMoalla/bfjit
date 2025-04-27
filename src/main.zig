const std = @import("std");
const builtin = @import("builtin");
const lexer = @import("lexer.zig");
const interpreter = @import("interpreter.zig");
const jit = @import("jit.zig");

pub fn main() !u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const raw_args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, raw_args);

    const args = parseArgs(raw_args) catch |err| {
        std.log.err(
            \\Usage: bfjit [-i] <input.bf>
            \\Options:
            \\  -i              use the interpreter instead of the default JIT compilation (optional) (default=jit)
            \\  -b16, -b32      16 or 32 bit cell width (default=8-bit)
            \\  -c <format>     compile program to given format without running it. (values=jvm)
        , .{});
        switch (err) {
            error.InputRequired => std.log.err("no input is provided", .{}),
            error.InvalidCellWidth => std.log.err("invalid cell width", .{}),
        }
        return 1;
    };

    const content = try std.fs.cwd().readFileAlloc(allocator, args.input, 1024 * 1024 * 1024);

    const ops = lexer.tokenize(allocator, content) catch |err| {
        std.log.err("error occured in tokenizer: {s}\n", .{@errorName(err)});
        return 1;
    };

    std.log.info("JIT: {s}", .{if (args.do_jit) "on" else "off"});
    if (args.do_jit) {
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
        const in = std.io.getStdIn().reader().any();
        const out = std.io.getStdOut().writer().any();

        try switch (args.cell_width) {
            inline 8, 16, 32 => |bits| blk: {
                const T = std.meta.Int(.unsigned, bits);
                break :blk interpreter.interpret(allocator, T, ops, in, out);
            },
            else => unreachable,
        };
    }

    return 0;
}

const Args = struct {
    input: []const u8,
    do_jit: bool = true,
    cell_width: u8 = 8,
};

fn parseArgs(args: [][:0]u8) !Args {
    var program: ?[]const u8 = null;
    var input: ?[]const u8 = null;
    var do_jit = true;
    var cell_width: u8 = 8;

    for (args) |arg| {
        if (program == null) {
            program = arg;
            continue;
        }

        if (std.mem.eql(u8, arg, "-i")) {
            do_jit = false;
            continue;
        }

        if (std.mem.startsWith(u8, arg, "-b")) {
            if (std.mem.eql(u8, arg, "-b16")) {
                cell_width = 16;
            } else if (std.mem.eql(u8, arg, "-b32")) {
                cell_width = 32;
            } else return error.InvalidCellWidth;
        }

        input = arg;
    }

    if (input == null) {
        return error.InputRequired;
    }

    return Args{ .input = input.?, .do_jit = do_jit, .cell_width = cell_width };
}

test {
    _ = @import("lexer.zig");
    _ = @import("interpreter.zig");
}
