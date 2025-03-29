const std = @import("std");
const builtin = @import("builtin");
const log = @import("logger.zig").scoped(.lexer);

pub const Op = struct {
    kind: OpKind,
    operand: usize,
};

pub const OpKind = enum(u8) {
    inc = '+',
    dec = '-',
    left = '<',
    right = '>',
    output = '.',
    input = ',',
    jump_if_zero = '[',
    jump_if_nonzero = ']',
};

const Lexer = struct {
    content: []const u8,
    pos: usize = 0,
    fn next(self: *Lexer) ?u8 {
        while (self.pos < self.content.len and !isBfCmd(self.content[self.pos])) {
            self.pos += 1;
        }

        if (self.pos >= self.content.len) return null;

        defer self.pos += 1;
        return self.content[self.pos];
    }

    fn isBfCmd(char: u8) bool {
        return std.mem.containsAtLeastScalar(u8, "+-<>,.[]", 1, char);
    }
};

pub const LexerError = error{UnbalancedLoop} || ValidationError || std.mem.Allocator.Error;

pub fn tokenize(allocator: std.mem.Allocator, content: []const u8) LexerError![]Op {
    var ops = std.ArrayList(Op).init(allocator);
    defer ops.deinit();
    var stack = std.ArrayList(usize).init(allocator);
    defer stack.deinit();

    var lexer = Lexer{ .content = content };
    var char = lexer.next();
    while (char != null) {
        switch (char.?) {
            '+', '-', '<', '>', '.', ',' => {
                var count: usize = 1;
                var next_char_in_streak = lexer.next();
                while (next_char_in_streak == char.?) : (next_char_in_streak = lexer.next()) {
                    count += 1;
                }
                try ops.append(Op{ .kind = @enumFromInt(char.?), .operand = count });
                char = next_char_in_streak;
            },
            '[' => {
                const addr: usize = ops.items.len;
                try ops.append(Op{ .kind = @enumFromInt(char.?), .operand = addr });
                try stack.append(addr);

                char = lexer.next();
            },
            ']' => {
                if (stack.items.len == 0) {
                    log.err("Op (]) at position {d} is unbalanced (no matching '[' found)", .{lexer.pos});
                    return LexerError.UnbalancedLoop;
                }

                const addr: usize = stack.pop().?;
                try ops.append(Op{ .kind = @enumFromInt(char.?), .operand = addr + 1 });
                ops.items[addr].operand = ops.items.len;

                char = lexer.next();
            },
            else => continue,
        }
    }

    try validate(ops.items);

    return ops.toOwnedSlice();
}

pub const ValidationError = error{InvalidJumpAddress};

fn validate(ops: []Op) ValidationError!void {
    for (ops, 0..) |op, i| {
        switch (op.kind) {
            .jump_if_zero, .jump_if_nonzero => {
                if (op.operand == 0) {
                    log.err("Op ({c}) at position {d} has invalid jump address: {d}", .{ @intFromEnum(op.kind), i + 1, op.operand });
                    return ValidationError.InvalidJumpAddress;
                }
            },
            else => {},
        }
    }
}

pub fn printTokens(ops: []Op) void {
    for (ops, 0..) |op, i| {
        std.debug.print("[{d:>2}] ({c}) {d}\n", .{ i + 1, @intFromEnum(op.kind), op.operand });
    }
}

fn expectOps(input: []const u8, expected: anytype) !void {
    const tokens = try tokenize(std.testing.allocator, input);
    errdefer std.testing.allocator.free(tokens);
    try std.testing.expectEqualSlices(Op, opsArgs(expected), tokens);
    std.testing.allocator.free(tokens);
}

fn opsArgs(args: anytype) []const Op {
    var array: [args.len]Op = undefined;
    inline for (args, 0..) |t, i| {
        array[i] = switch (@typeInfo(@TypeOf(t))) {
            .@"struct" => |s| switch (s.fields.len) {
                1 => .{ .kind = t.@"0", .operand = 1 },
                2 => .{ .kind = t.@"0", .operand = t.@"1" },
                else => @compileError("you can only pass tuples with 1 or 2 fields. 1st field is Op.kind and 2nd field is Op.operand"),
            },
            .enum_literal => .{ .kind = t, .operand = 1 },
            else => @compileError("only support tuples(size 1 or 2) or enum_literal of type OpKind"),
        };
    }
    return &array;
}

test tokenize {
    try expectOps(">", .{.right});
    try expectOps("<", .{.left});
    try expectOps("+", .{.inc});
    try expectOps("-", .{.dec});
    try expectOps(".", .{.output});
    try expectOps(",", .{.input});
    expectOps("[", .{.jump_if_zero}) catch |err| {
        try std.testing.expectEqual(LexerError.InvalidJumpAddress, err);
    };
    expectOps("]", .{.jump_if_nonzero}) catch |err| {
        try std.testing.expectEqual(LexerError.UnbalancedLoop, err);
    };
    try expectOps("[]", .{ .{ .jump_if_zero, 2 }, .{ .jump_if_nonzero, 1 } });
    try expectOps("++++[------]", .{
        .{ .inc, 4 },
        .{ .jump_if_zero, 4 },
        .{ .dec, 6 },
        .{ .jump_if_nonzero, 2 },
    });
    try expectOps("++++[------]<<>..,--", .{
        .{ .inc, 4 },
        .{ .jump_if_zero, 4 },
        .{ .dec, 6 },
        .{ .jump_if_nonzero, 2 },
        .{ .left, 2 },
        .right,
        .{ .output, 2 },
        .input,
        .{ .dec, 2 },
    });
}
