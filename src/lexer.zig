const std = @import("std");

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

pub fn tokenize(allocator: std.mem.Allocator, content: []const u8) ![]Op {
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
                    std.log.err("[{d}] unbalanced loop\n", .{lexer.pos});
                    return error.UnbalancedLoop;
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
                    std.log.err("Op ({c}) at position {d} has invalid jump address: {d}", .{ @intFromEnum(op.kind), i + 1, op.operand });
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
