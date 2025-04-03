const std = @import("std");

const lexer = @import("lexer.zig");

pub fn interpret(allocator: std.mem.Allocator, ops: []lexer.Op, in: std.io.AnyReader, out: std.io.AnyWriter) !void {
    var memory = std.ArrayList(u8).init(allocator);
    defer memory.deinit();
    var head: usize = 0;
    var ip: usize = 0;

    while (ip < ops.len) {
        const op = ops[ip];
        switch (op) {
            .set_zero => {
                if (head >= memory.items.len) {
                    try memory.appendNTimes(0, head - memory.items.len + 1);
                }
                memory.items[head] = 0;
                ip += 1;
            },
            .inc => |count| {
                if (head >= memory.items.len) {
                    try memory.appendNTimes(0, head - memory.items.len + 1);
                }
                memory.items[head] = @addWithOverflow(memory.items[head], count)[0];
                ip += 1;
            },
            .dec => |count| {
                if (head >= memory.items.len) {
                    try memory.appendNTimes(0, head - memory.items.len + 1);
                }
                memory.items[head] = @subWithOverflow(memory.items[head], count)[0];
                ip += 1;
            },
            .left => |count| {
                if (head < count) {
                    std.log.err("memory underflow at instruction: {d} (count: {d})", .{ ip, count });
                    return error.MemoryUnderflow;
                }
                head -= count;
                ip += 1;
            },
            .right => |count| {
                head += count;
                if (head >= memory.items.len) {
                    try memory.appendNTimes(0, head - memory.items.len + 1);
                }
                ip += 1;
            },
            .input => |count| {
                if (head >= memory.items.len) {
                    try memory.appendNTimes(0, head - memory.items.len + 1);
                }

                for (0..count) |_| {
                    const byte = in.readByte() catch |err| {
                        switch (err) {
                            error.EndOfStream => {},
                            else => std.log.err("error occurred while reading from stdin {s}", .{@errorName(err)}),
                        }
                        continue;
                    };
                    memory.items[head] = byte;
                }
                ip += 1;
            },
            .output => |count| {
                if (head < memory.items.len) {
                    for (0..count) |_| {
                        try out.print("{c}", .{memory.items[head]});
                    }
                }

                ip += 1;
            },
            .jump_if_zero => |addr| {
                if (memory.items.len == 0) {
                    try memory.append(0);
                }
                if (memory.items[head] == 0) {
                    ip = addr;
                } else {
                    ip += 1;
                }
            },
            .jump_if_nonzero => |addr| {
                if (memory.items.len == 0) {
                    try memory.append(0);
                }
                if (memory.items[head] != 0) {
                    ip = addr;
                } else {
                    ip += 1;
                }
            },
        }
    }
}

test interpret {
    const allocator = std.testing.allocator;

    var testcases = try @import("tests/TestCases.zig").init(allocator);
    defer testcases.deinit();

    var failureCount: usize = 0;
    for (testcases.cases) |case| {
        std.debug.print("Case '{s}': ", .{case.name});
        const ops = try lexer.tokenize(allocator, case.bf);
        defer allocator.free(ops);

        var out = std.ArrayList(u8).init(allocator);
        defer out.deinit();

        var in = std.io.fixedBufferStream(case.in);

        interpret(allocator, ops, in.reader().any(), out.writer().any()) catch |err| {
            std.debug.print("FAILURE => {s}\n", .{@errorName(err)});
            failureCount += 1;
            continue;
        };

        if (!std.mem.eql(u8, case.expected, out.items)) {
            std.debug.print("FAILURE\n", .{});
            failureCount += 1;
        } else {
            std.debug.print("SUCCESS\n", .{});
        }
    }

    try std.testing.expectEqual(0, failureCount);
}
