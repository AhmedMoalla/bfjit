const std = @import("std");

const OpKind = enum(u8) {
    inc = '+',
    dec = '-',
    left = '<',
    right = '>',
    output = '.',
    input = ',',
    jump_if_zero = '[',
    jump_if_nonzero = ']',
};
const Op = struct {
    kind: OpKind,
    operand: usize,
};

const Lexer = struct {
    content: []const u8,
    pos: usize = 0,

    pub fn next(self: *Lexer) ?u8 {
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

pub fn main() !u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    const program = args.next().?;
    const input = args.next();
    if (input == null) {
        std.log.err("usage: {s} <input.bf>", .{program});
        std.log.err("no input is provided", .{});
        return 1;
    }

    const content = try std.fs.cwd().readFileAlloc(allocator, input.?, 1024 * 1024);

    var ops = std.ArrayList(Op).init(allocator);
    defer ops.deinit();
    var stack = std.ArrayList(usize).init(allocator);
    defer stack.deinit();

    // Tokenization
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
                    std.log.err("{s} [{d}] unbalanced loop\n", .{ input.?, lexer.pos });
                    return 1;
                }

                const addr: usize = stack.pop().?;
                try ops.append(Op{ .kind = @enumFromInt(char.?), .operand = addr + 1 });
                ops.items[addr].operand = ops.items.len;

                char = lexer.next();
            },
            else => continue,
        }
    }

    // Interpretation
    // try interpret(allocator, ops.items);

    // Compilation
    var jitted = try jitCompile(allocator, ops.items);
    defer std.posix.munmap(jitted.machine_code);

    const memory = try allocator.alloc(u8, 10 * 1000 * 1000);
    defer allocator.free(memory);
    @memset(memory, 0);
    jitted.run(memory.ptr);

    return 0;
}

const Backpatch = struct {
    operand_byte_addr: usize,
    src_byte_addr: usize,
    dst_op_index: usize,
};

const JittedCode = struct {
    machine_code: []align(std.heap.page_size_min) u8,

    pub fn run(self: *JittedCode, memory: [*]u8) void {
        const runFn: *const fn (memory: [*]u8) callconv(.c) void = @ptrCast(self.machine_code);
        runFn(memory);
    }
};

fn jitCompile(allocator: std.mem.Allocator, ops: []Op) !JittedCode {
    var code = std.ArrayList(u8).init(allocator);
    defer code.deinit();
    var backpatches = std.ArrayList(Backpatch).init(allocator);
    defer backpatches.deinit();
    var addresses = std.ArrayList(usize).init(allocator);
    defer addresses.deinit();

    for (ops) |op| {
        try addresses.append(code.items.len);
        switch (op.kind) {
            .inc => {
                if (op.operand > 255) {
                    return error.OperandTooBig;
                }
                try code.appendSlice(&[_]u8{ 0x80, 0x07, @intCast(op.operand & 0xFF) }); // add byte[rdi], operand
                // for (code.items) |byte| {
                //     std.debug.print("{x}", .{byte});
                // }
                // std.process.exit(0);
            },
            .dec => {
                if (op.operand > 255) {
                    return error.OperandTooBig;
                }
                try code.appendSlice(&[_]u8{ 0x80, 0x2f, @intCast(op.operand & 0xFF) }); // sub byte[rdi], operand
            },
            .left => {
                try code.appendSlice(&[_]u8{ 0x48, 0x81, 0xef }); // sub rdi,
                // var bytes: [4]u8 = undefined;
                // std.mem.writeInt(u32, &bytes, @intCast(op.operand), .little);
                try code.appendSlice(std.mem.sliceAsBytes(&[_]u32{@intCast(op.operand)})); // operand
            },
            .right => {
                try code.appendSlice(&[_]u8{ 0x48, 0x81, 0xc7 }); // add rdi,
                // var bytes: [4]u8 = undefined;
                // std.mem.writeInt(u32, &bytes, @intCast(op.operand), .little);
                try code.appendSlice(std.mem.sliceAsBytes(&[_]u32{@intCast(op.operand)})); // operand
            },
            .output => {
                for (0..op.operand) |_| {
                    try code.append(0x57); // push rdi
                    try code.appendSlice(&[_]u8{ 0x48, 0xc7, 0xc0, 0x01, 0x00, 0x00, 0x00 }); // mov rax, 1
                    try code.appendSlice(&[_]u8{ 0x48, 0x89, 0xfe }); // mov rsi, rdi
                    try code.appendSlice(&[_]u8{ 0x48, 0xc7, 0xc7, 0x01, 0x00, 0x00, 0x00 }); // mov rdi, 1
                    try code.appendSlice(&[_]u8{ 0x48, 0xc7, 0xc2, 0x01, 0x00, 0x00, 0x00 }); // mov rdx, 1
                    try code.appendSlice(&[_]u8{ 0x0f, 0x05 }); // syscall
                    try code.append(0x5f); // pop rdi
                }
            },
            .input => unreachable,
            .jump_if_zero => {
                try code.appendSlice(&[_]u8{ 0x8a, 0x07 }); // mov al, byte [rdi]
                try code.appendSlice(&[_]u8{ 0x84, 0xc0 }); // test al, al
                try code.appendSlice(&[_]u8{ 0x0f, 0x84 }); // jz
                const operand_byte_addr = code.items.len;
                try code.appendNTimes(0, 4); // 4 bytes address to override with backpatches
                const src_byte_addr = code.items.len;

                try backpatches.append(Backpatch{
                    .operand_byte_addr = operand_byte_addr,
                    .src_byte_addr = src_byte_addr,
                    .dst_op_index = op.operand,
                });
            },
            .jump_if_nonzero => {
                try code.appendSlice(&[_]u8{ 0x8a, 0x07 }); // mov al, byte [rdi]
                try code.appendSlice(&[_]u8{ 0x84, 0xc0 }); // test al, al
                try code.appendSlice(&[_]u8{ 0x0f, 0x85 }); // jnz
                const operand_byte_addr = code.items.len;
                try code.appendNTimes(0, 4); // 4 bytes address to override with backpatches
                const src_byte_addr = code.items.len;

                try backpatches.append(Backpatch{
                    .operand_byte_addr = operand_byte_addr,
                    .src_byte_addr = src_byte_addr,
                    .dst_op_index = op.operand,
                });
            },
        }
    }

    try addresses.append(code.items.len);

    for (backpatches.items) |patch| {
        const src_addr: i32 = @intCast(patch.src_byte_addr);
        const dst_addr: i32 = @intCast(addresses.items[patch.dst_op_index]);
        const operand: i32 = dst_addr - src_addr;

        const bytes = std.mem.sliceAsBytes(&[_]i32{operand});
        code.items[patch.operand_byte_addr] = bytes[0];
        code.items[patch.operand_byte_addr + 1] = bytes[1];
        code.items[patch.operand_byte_addr + 2] = bytes[2];
        code.items[patch.operand_byte_addr + 3] = bytes[3];
    }

    try code.append(0xC3); // ret

    const content = code.items;
    const jitted = try std.posix.mmap(
        null,
        content.len,
        std.posix.PROT.EXEC | std.posix.PROT.READ | std.posix.PROT.WRITE,
        .{ .TYPE = .PRIVATE, .ANONYMOUS = true },
        -1,
        0,
    );
    @memcpy(jitted[0..content.len], content);

    return JittedCode{ .machine_code = jitted };
}

fn interpret(allocator: std.mem.Allocator, ops: []Op) !void {
    var memory = std.ArrayList(u8).init(allocator);
    defer memory.deinit();
    var head: usize = 0;
    var ip: usize = 0;

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
                    std.log.err("memory underflow", .{});
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
            .input => unreachable,
            .output => {
                if (head < memory.items.len) {
                    for (0..op.operand) |_| {
                        std.debug.print("{c}", .{memory.items[head]});
                    }
                }

                ip += 1;
            },
            .jump_if_zero => {
                if (memory.items[head] == 0) {
                    ip = op.operand;
                } else {
                    ip += 1;
                }
            },
            .jump_if_nonzero => {
                if (memory.items[head] != 0) {
                    ip = op.operand;
                } else {
                    ip += 1;
                }
            },
        }
    }
}
