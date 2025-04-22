const std = @import("std");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var classfile = ClassFile.init("BrainfuckProgram", allocator);
    defer classfile.deinit();

    var bytecode = ByteCode.init(allocator);
    defer bytecode.deinit();

    var class_bytes = std.ArrayList(u8).init(allocator);
    defer class_bytes.deinit();

    try classfile
        .withVersion(.java_1, 0)
        .withMethod(
            "main",
            MethodSignature.of(@"void", .{String.array()}),
            .{ .public = true, .static = true },
            bytecode
                .@"return"(),
        )
        .build(class_bytes.writer().any());

    for (class_bytes.items) |b| {
        std.debug.print("{X:0<2} ", .{b});
    }
}

const ClassFile = struct {
    const Self = @This();

    const magic: u32 = 0xCAFEBABE;
    minor_version: u16 = undefined,
    major_version: u16 = undefined,

    allocator: std.mem.Allocator,

    pub fn init(class_name: []const u8, allocator: std.mem.Allocator) Self {
        _ = class_name;
        return Self{ .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn withVersion(self: *Self, major_version: JavaVersion, minor_version: u16) *Self {
        self.major_version = @intFromEnum(major_version);
        self.minor_version = minor_version;
        return self;
    }

    pub fn withMethod(self: *Self, name: []const u8, signature: MethodSignature, access_flags: AccessFlags, code: anytype) *Self {
        _ = name;
        _ = signature;
        _ = access_flags;
        _ = code;
        return self;
    }

    pub fn build(self: *Self, writer: std.io.AnyWriter) !void {
        try writer.writeInt(u32, magic, .big);
        try writer.writeInt(@TypeOf(self.minor_version), self.minor_version, .big);
        try writer.writeInt(@TypeOf(self.major_version), self.major_version, .big);
    }
};

const @"void" = JavaType.of("void");
const byte = JavaType.of("byte");
const short = JavaType.of("short");
const int = JavaType.of("int");
const long = JavaType.of("long");
const float = JavaType.of("float");
const double = JavaType.of("double");
const boolean = JavaType.of("boolean");
const char = JavaType.of("char");
const String = JavaType.of("java.lang.String");

const JavaType = struct {
    pub fn of(type_name: []const u8) JavaType {
        _ = type_name;
        return .{};
    }

    pub fn array(self: JavaType) JavaType {
        _ = self;
        return .{};
    }
};

const Method = struct {};

const MethodSignature = struct {
    returns: JavaType,
    args: []JavaType,

    pub fn of(returns: JavaType, args: anytype) MethodSignature {
        _ = args;
        return .{ .returns = returns, .args = &[_]JavaType{} };
    }
};

const AccessFlags = struct {
    public: bool,
    static: bool,
};

const JavaVersion = enum(u16) {
    java_1 = 45,
};

const ByteCode = struct {
    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        _ = allocator;
        return Self{};
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn @"return"(self: *Self) *Self {
        return self;
    }
};
