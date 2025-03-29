const std = @import("std");
const lexer = @import("lexer.zig");

pub fn interpret(allocator: std.mem.Allocator, ops: []lexer.Op) !void {
    var memory = std.ArrayList(u8).init(allocator);
    defer memory.deinit();
    var head: usize = 0;
    var ip: usize = 0;
    const stdin = std.io.getStdIn().reader();

    while (ip < ops.len) {
        const op = ops[ip];
        switch (op.kind) {
            .inc => {
                while (head >= memory.items.len) {
                    try memory.append(0);
                }
                memory.items[head] += @intCast(op.operand);
                ip += 1;
            },
            .dec => {
                while (head >= memory.items.len) {
                    try memory.append(0);
                }
                memory.items[head] -= @intCast(op.operand);
                ip += 1;
            },
            .left => {
                if (ip < op.operand) {
                    std.log.err("memory underflow at instruction: {d}", .{ip});
                    return error.MemoryUnderflow;
                }
                head -= op.operand;
                ip += 1;
            },
            .right => {
                head += op.operand;
                while (head >= memory.items.len) {
                    try memory.append(0);
                }
                ip += 1;
            },
            .input => {
                while (head >= memory.items.len) {
                    try memory.append(0);
                }

                for (0..op.operand) |_| {
                    const byte = stdin.readByte() catch |err| {
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
            .output => {
                if (head < memory.items.len) {
                    for (0..op.operand) |_| {
                        std.debug.print("{c}", .{memory.items[head]});
                    }
                }

                ip += 1;
            },
            .jump_if_zero => {
                if (memory.items.len == 0) {
                    try memory.append(0);
                }
                if (memory.items[head] == 0) {
                    ip = op.operand;
                } else {
                    ip += 1;
                }
            },
            .jump_if_nonzero => {
                if (memory.items.len == 0) {
                    try memory.append(0);
                }
                if (memory.items[head] != 0) {
                    ip = op.operand;
                } else {
                    ip += 1;
                }
            },
        }
    }
}

test interpret {}
