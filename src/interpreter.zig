const std = @import("std");

const lexer = @import("lexer.zig");
const log = @import("logger.zig").scoped(.interpreter);

pub fn interpret(allocator: std.mem.Allocator, cell_width: type, ops: []lexer.Op, in: std.io.AnyReader, out: std.io.AnyWriter) !void {
    var memory = try Memory(cell_width).init(allocator);
    defer memory.deinit();
    var ip: usize = 0;

    while (ip < ops.len) {
        const op = ops[ip];
        switch (op) {
            .set_zero => {
                try memory.setAtHead(0);
                ip += 1;
            },
            .inc => |count| {
                try memory.incAtHead(count);
                ip += 1;
            },
            .dec => |count| {
                try memory.decAtHead(count);
                ip += 1;
            },
            .left => |count| {
                memory.decHead(count) catch |err| {
                    log.err("memory underflow at instruction: {d} (count: {d})", .{ ip, count });
                    return err;
                };
                ip += 1;
            },
            .right => |count| {
                try memory.incHead(count);
                ip += 1;
            },
            .input => |count| {
                for (0..count) |_| {
                    const byte = in.readByte() catch |err| {
                        switch (err) {
                            error.EndOfStream => {},
                            else => log.err("error occurred while reading from stdin {s}", .{@errorName(err)}),
                        }
                        continue;
                    };
                    try memory.setAtHead(byte);
                }
                ip += 1;
            },
            .output => |count| {
                if (memory.getAtHead()) |value| {
                    for (0..count) |_| {
                        const char: u8 = @intCast(value);
                        try out.print("{c}", .{char});
                    }
                }

                ip += 1;
            },
            .jump_if_zero => |addr| {
                if (memory.getAtHead() == 0) {
                    ip = addr;
                } else {
                    ip += 1;
                }
            },
            .jump_if_nonzero => |addr| {
                if (memory.getAtHead() != 0) {
                    ip = addr;
                } else {
                    ip += 1;
                }
            },
        }
    }
}

fn Memory(T: type) type {
    return struct {
        const Self = @This();

        bytes: std.ArrayList(T),
        head: usize = 0,

        pub fn init(allocator: std.mem.Allocator) !Self {
            var bytes = try std.ArrayList(T).initCapacity(allocator, 1000);
            try bytes.appendNTimes(0, bytes.capacity);
            return Self{ .bytes = bytes };
        }

        pub fn deinit(self: *Self) void {
            self.bytes.deinit();
        }

        pub fn incHead(self: *Self, count: usize) !void {
            self.head += count;
            try self.appendZerosToReachHead();
        }

        pub fn decHead(self: *Self, count: usize) !void {
            if (self.head < count) {
                return error.MemoryUnderflow;
            }
            self.head -= count;
        }

        pub fn incAtHead(self: *Self, count: T) !void {
            try self.appendZerosToReachHead();
            self.bytes.items[self.head] = @addWithOverflow(self.bytes.items[self.head], count)[0];
        }

        pub fn decAtHead(self: *Self, count: T) !void {
            try self.appendZerosToReachHead();
            self.bytes.items[self.head] = @subWithOverflow(self.bytes.items[self.head], count)[0];
        }

        pub fn getAtHead(self: *Self) ?T {
            if (self.head >= self.bytes.items.len) return null;
            return self.bytes.items[self.head];
        }

        pub fn setAtHead(self: *Self, value: T) !void {
            try self.appendZerosToReachHead();
            self.bytes.items[self.head] = value;
        }

        fn appendZerosToReachHead(self: *Self) !void {
            if (self.head >= self.bytes.items.len) {
                try self.bytes.appendNTimes(0, self.head - self.bytes.items.len + 1);
            }
        }
    };
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
