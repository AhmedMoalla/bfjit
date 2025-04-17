const std = @import("std");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var classfile = ClassFile.init("BrainfuckProgram", allocator);

    const class_bytes = classfile
        .withVersion(.java_1, 0)
        .withMethod(
            "main",
            MethodSignature.of(JavaType.void, .{JavaType.String.array()}),
            .{ .public = true, .static = true },
            .{.@"return"},
        )
        .build();
    _ = class_bytes;
}

const ClassFile = struct {
    const Self = @This();
    allocator: std.mem.Allocator,

    pub fn init(class_name: []const u8, allocator: std.mem.Allocator) Self {
        _ = class_name;
        _ = allocator;
        unreachable;
    }

    pub fn withVersion(self: *Self, major_version: JavaVersion, minor_version: u2) *Self {
        _ = self;
        _ = major_version;
        _ = minor_version;
        unreachable;
    }

    pub fn withMethod(self: *Self, name: []const u8, signature: MethodSignature, access_flags: AccessFlags, code: anytype) *Self {
        _ = self;
        _ = name;
        _ = signature;
        _ = access_flags;
        _ = code;
        unreachable;
    }

    pub fn build(self: *Self) []u8 {
        _ = self;
        unreachable;
    }
};

const JavaType = struct {
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

    pub fn of(type_name: []const u8) JavaType {
        _ = type_name;
        return .{};
    }

    pub fn array(self: JavaType) JavaType {
        _ = self;
        unreachable;
    }
};

const Method = struct {};

const MethodSignature = struct {
    returns: JavaType,
    args: []JavaType,

    pub fn of(returns: JavaType, args: anytype) MethodSignature {
        _ = returns;
        _ = args;
        unreachable;
    }
};

const AccessFlags = struct {
    public: bool,
    static: bool,
};

const JavaVersion = enum(u8) {
    java_1 = 45,
};
