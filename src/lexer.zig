const std = @import("std");
const builtin = @import("builtin");
const log = @import("logger.zig").scoped(.lexer);

pub const Op = union(enum(u8)) {
    inc: u8 = '+',
    dec: u8 = '-',
    left: u8 = '<',
    right: u8 = '>',
    output: u8 = '.',
    input: u8 = ',',
    jump_if_zero: usize = '[',
    jump_if_nonzero: usize = ']',
    set_zero: void = '0',
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

    fn lookAhead(self: Lexer, n: usize) ?[]const u8 {
        if (self.pos >= self.content.len) return null;
        return self.content[self.pos..@min(self.pos + n, self.content.len)];
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
                var count: u8 = 1;
                var next_char_in_streak = lexer.next();
                while (next_char_in_streak == char.?) : (next_char_in_streak = lexer.next()) {
                    count = @addWithOverflow(count, 1)[0];
                }

                // TODO: Refactor this
                try ops.append(switch (char.?) {
                    '+' => .{ .inc = count },
                    '-' => .{ .dec = count },
                    '<' => .{ .left = count },
                    '>' => .{ .right = count },
                    '.' => .{ .output = count },
                    ',' => .{ .input = count },
                    else => unreachable,
                });
                char = next_char_in_streak;
            },
            '[' => {
                if (lexer.lookAhead(2)) |next| {
                    if (std.mem.eql(u8, next, "-]") or std.mem.eql(u8, next, "+]")) {
                        try ops.append(.{ .set_zero = {} });
                        lexer.pos += 2;
                        char = lexer.next();
                        continue;
                    }
                }
                const addr: usize = ops.items.len;
                try ops.append(.{ .jump_if_zero = addr });
                try stack.append(addr);
                char = lexer.next();
            },
            ']' => {
                if (stack.items.len == 0) {
                    log.err("Op (]) at position {d} is unbalanced (no matching '[' found)", .{lexer.pos});
                    return LexerError.UnbalancedLoop;
                }

                const addr: usize = stack.pop().?;
                try ops.append(.{ .jump_if_nonzero = addr + 1 });
                ops.items[addr].jump_if_zero = ops.items.len;

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
        switch (op) {
            .jump_if_zero, .jump_if_nonzero => |addr| {
                if (addr == 0) {
                    log.err("Op ({c}) at position {d} has invalid jump address: {d}", .{ @intFromEnum(op), i + 1, addr });
                    return ValidationError.InvalidJumpAddress;
                }
            },
            else => {},
        }
    }
}

pub fn printTokens(ops: []Op) void {
    for (ops, 0..) |op, i| {
        const value: usize = switch (op) { // Get the value of the active field in the union
            .set_zero => 0,
            inline else => |_, tag| @intCast(@field(op, @tagName(tag))),
        };

        std.debug.print("[{d:>4}] ({c}) {d}\n", .{ i + 1, @intFromEnum(op), value });
    }
}

fn expectOps(input: []const u8, expected: anytype) !void {
    const tokens = try tokenize(std.testing.allocator, input);
    errdefer std.testing.allocator.free(tokens);
    try std.testing.expectEqualSlices(Op, &opsArgs(expected), tokens);
    std.testing.allocator.free(tokens);
}

test tokenize {
    try expectOps(">", .right);
    try expectOps("<", .left);
    try expectOps("+", .inc);
    try expectOps("-", .dec);
    try expectOps(".", .output);
    try expectOps(",", .input);
    expectOps("[", .jump_if_zero) catch |err| {
        try std.testing.expectEqual(LexerError.InvalidJumpAddress, err);
    };
    expectOps("]", .jump_if_nonzero) catch |err| {
        try std.testing.expectEqual(LexerError.UnbalancedLoop, err);
    };
    try expectOps("[]", .{ .{ .jump_if_zero = 2 }, .{ .jump_if_nonzero = 1 } });
    try expectOps("++++[------]", .{
        .{ .inc = 4 },
        .{ .jump_if_zero = 4 },
        .{ .dec = 6 },
        .{ .jump_if_nonzero = 2 },
    });
    try expectOps("++++[------]<<>..,--", .{
        .{ .inc = 4 },
        .{ .jump_if_zero = 4 },
        .{ .dec = 6 },
        .{ .jump_if_nonzero = 2 },
        .{ .left = 2 },
        .right,
        .{ .output = 2 },
        .input,
        .{ .dec = 2 },
    });
    try expectOps("[+]", .set_zero);
    try expectOps("[-]", .set_zero);
    try expectOps("---[-]", .{ .{ .dec = 3 }, .set_zero });
    try expectOps("---[[-]]+", .{ .{ .dec = 3 }, .{ .jump_if_zero = 4 }, .set_zero, .{ .jump_if_nonzero = 2 }, .inc });
}

// ============= Utils =============
fn OpsSlice(args: anytype) type {
    return switch (@typeInfo(@TypeOf(args))) {
        .enum_literal => [1]Op,
        .@"struct" => [args.len]Op,
        else => @compileError("only supports Op"),
    };
}

fn opsArgs(args: anytype) OpsSlice(args) {
    return outer: switch (@typeInfo(@TypeOf(args))) {
        .enum_literal => [_]Op{opFromEnumLiteral(args)},
        .@"struct" => {
            var array: [args.len]Op = undefined;
            inline for (args, 0..) |t, i| {
                array[i] = switch (@typeInfo(@TypeOf(t))) {
                    .@"struct" => |s| @unionInit(Op, s.fields[0].name, s.fields[0].defaultValue().?),
                    .enum_literal => opFromEnumLiteral(t),
                    else => @compileError("only supports Op"),
                };
            }
            break :outer array;
        },
        else => @compileError("only supports tuple or enum_literal as argument"),
    };
}

fn opFromEnumLiteral(args: anytype) Op {
    const value = switch (@typeInfo(@FieldType(Op, @tagName(args)))) {
        .void => {},
        .comptime_int, .int => 1,
        else => unreachable,
    };

    return @unionInit(Op, @tagName(args), value);
}
