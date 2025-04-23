const std = @import("std");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const String = try JavaType.of(gpa, "java.lang.String");

    var classfile = try ClassFile.init("BrainfuckProgram", gpa);
    defer classfile.deinit();

    var bytecode = ByteCode.init(gpa);
    defer bytecode.deinit();

    var class_bytes = std.ArrayList(u8).init(gpa);
    defer class_bytes.deinit();

    classfile.withVersion(.java_8, 0);
    try classfile.withMethod(
        "main",
        try MethodSignature.of(gpa, JavaType.void, .{try String.array(gpa)}),
        .{ .public = true, .static = true },
        bytecode
            .@"return"(),
    );
    try classfile.build(class_bytes.writer().any());

    classfile.debugLog();

    std.debug.print("\n", .{});
    for (class_bytes.items) |b| {
        std.debug.print("{X:0>2} ", .{b});
    }
    std.debug.print("\n", .{});

    const file = try std.fs.cwd().createFile("out.class", .{ .truncate = true });
    const bytes = try file.write(class_bytes.items);
    std.debug.print("{d} bytes written\n", .{bytes});
}

const MethodInfo = struct {
    const Self = @This();

    access_flags: u16,
    name_index: u16,
    descriptor_index: u16,
    attributes: []const AttributeInfo,

    pub fn write(self: *const Self, writer: std.io.AnyWriter) !void {
        try writer.writeInt(u16, self.access_flags, .big);
        try writer.writeInt(u16, self.name_index, .big);
        try writer.writeInt(u16, self.descriptor_index, .big);
        try writer.writeInt(u16, @intCast(self.attributes.len), .big);
        for (self.attributes) |attribute| {
            try attribute.write(writer);
        }
    }
};

const ClassFile = struct {
    const Self = @This();

    const magic: u32 = 0xCAFEBABE;
    minor_version: u16 = undefined,
    major_version: u16 = undefined,
    pool: ConstantPool,
    access_flags: u16 = 0x00000001, // PUBLIC
    this_class: u16 = undefined,
    super_class: u16 = undefined,
    interfaces_count: u16 = 0,
    fields_count: u16 = 0,
    fields: []const u8 = undefined,
    methods: std.ArrayList(MethodInfo),
    attributes_count: u16 = 0,
    attributes: []AttributeInfo = undefined,

    gpa: std.mem.Allocator,

    pub fn init(class_name: []const u8, gpa: std.mem.Allocator) !Self {
        var classfile = Self{
            .gpa = gpa,
            .pool = ConstantPool.init(gpa),
            .methods = std.ArrayList(MethodInfo).init(gpa),
        };
        classfile.super_class = try classfile.pool.classEntry(try JavaType.of(gpa, "java.lang.Object"));
        classfile.this_class = try classfile.pool.classEntry(try JavaType.of(gpa, class_name));
        return classfile;
    }

    pub fn deinit(self: *Self) void {
        self.pool.deinit();
    }

    pub fn withVersion(self: *Self, major_version: JavaVersion, minor_version: u16) void {
        self.major_version = @intFromEnum(major_version);
        self.minor_version = minor_version;
    }

    pub fn withMethod(self: *Self, name: []const u8, signature: MethodSignature, access_flags: AccessFlags, code: anytype) !void {
        const name_index = try self.pool.utf8Entry(name);
        const descriptor_index = try self.pool.utf8Entry(signature.descriptor);
        try self.methods.append(MethodInfo{
            .access_flags = access_flags.asU16(),
            .name_index = name_index,
            .descriptor_index = descriptor_index,
            .attributes = &[_]AttributeInfo{
                .{ .code = try CodeAttribute.init(&self.pool, code) },
            },
        });
    }

    pub fn build(self: *Self, writer: std.io.AnyWriter) !void {
        try writer.writeInt(u32, magic, .big);
        try writer.writeInt(u16, self.minor_version, .big);
        try writer.writeInt(u16, self.major_version, .big);
        try self.pool.write(writer);
        try writer.writeInt(u16, self.access_flags, .big);
        try writer.writeInt(u16, self.this_class, .big);
        try writer.writeInt(u16, self.super_class, .big);
        try writer.writeInt(u16, self.interfaces_count, .big);
        try writer.writeInt(u16, self.fields_count, .big);
        try writer.writeInt(u16, @intCast(self.methods.items.len), .big);
        for (self.methods.items) |method| {
            try method.write(writer);
        }
        try writer.writeInt(u16, self.attributes_count, .big);
    }

    pub fn debugLog(self: *Self) void {
        var class: *ConstantClassInfo = @ptrCast(&self.pool.pool.items[self.this_class - 1]);
        var utf8: *ConstantUtf8Info = @ptrCast(&self.pool.pool.items[class.name_index - 1]);
        std.debug.print("class name: {s}\n", .{utf8.bytes});
        std.debug.print("version: {d}.{d}\n", .{ self.major_version, self.minor_version });
        std.debug.print("flags: {X:0>4}\n", .{self.access_flags});
        class = @ptrCast(&self.pool.pool.items[self.super_class - 1]);
        utf8 = @ptrCast(&self.pool.pool.items[class.name_index - 1]);
        std.debug.print("superclass: {s}\n", .{utf8.bytes});
        std.debug.print("interfaces: []\n", .{});
        std.debug.print("attributes: []\n", .{});
        std.debug.print("constant pool:\n", .{});
        self.pool.debugLog();
        std.debug.print("fields:\n", .{});
        std.debug.print("methods:\n", .{});
    }
};

// TODO: Refactor class to avoid passing gpa to every function call. Maybe a JavaTypeBuilder ?
const JavaType = struct {
    const @"void" = JavaType.ofDefault("V");
    const byte = JavaType.ofDefault("B");
    const short = JavaType.ofDefault("S");
    const int = JavaType.ofDefault("I");
    const long = JavaType.ofDefault("J");
    const float = JavaType.ofDefault("F");
    const double = JavaType.ofDefault("D");
    const boolean = JavaType.ofDefault("Z");
    const char = JavaType.ofDefault("C");

    isArray: bool = false,
    descriptor: []const u8,
    internal_name: []const u8,

    pub fn of(gpa: std.mem.Allocator, type_name: []const u8) !JavaType {
        const internal_name = try gpa.dupe(u8, type_name);
        std.mem.replaceScalar(u8, internal_name, '.', '/');
        return .{
            .descriptor = try std.fmt.allocPrint(gpa, "L{s};", .{internal_name}),
            .internal_name = internal_name,
        };
    }

    fn ofDefault(type_name: []const u8) JavaType {
        return .{ .descriptor = type_name, .internal_name = type_name };
    }

    pub fn array(self: JavaType, gpa: std.mem.Allocator) !JavaType {
        return .{
            .isArray = true,
            .descriptor = try std.fmt.allocPrint(gpa, "[{s}", .{self.descriptor}),
            .internal_name = self.internal_name,
        };
    }
};

test "java_type_correct" {
    const gpa = std.testing.allocator;
    const String = try JavaType.of(gpa, "java.lang.String");
    try std.testing.expectEqualSlices(u8, "java/lang/String", String.internal_name);
    try std.testing.expectEqualSlices(u8, "Ljava/lang/String;", String.descriptor);

    const array = try String.array(gpa);
    try std.testing.expectEqualSlices(u8, "java/lang/String", array.internal_name);
    try std.testing.expectEqualSlices(u8, "[Ljava/lang/String;", array.descriptor);
}

const AttributeInfo = union(enum) {
    const Self = @This();

    code: CodeAttribute,

    pub fn write(self: Self, writer: std.io.AnyWriter) !void {
        switch (self) {
            inline else => |value| try value.write(writer),
        }
    }
};

const CodeAttribute = struct {
    const Self = @This();

    attribute_name_index: u16,
    attribute_length: u32,
    max_stack: u16 = std.math.maxInt(u16), // TODO: Calculate correctly
    max_locals: u16 = std.math.maxInt(u16), // TODO: Calculate correctly
    code: []const u8 = undefined,
    exception_table: []const u8 = undefined,
    attributes: []AttributeInfo = undefined,

    pub fn init(cp: *ConstantPool, code: anytype) !Self {
        _ = code;
        const attribute_name_index = try cp.utf8Entry("Code");
        const attribute_length = @sizeOf(u16) // max_stack
            + @sizeOf(u16) // max_locals
            + @sizeOf(u32) // code_length
            + 1 // code
            + @sizeOf(u16) // exception_table_length
            + @sizeOf(u16); // attributes_count

        return .{
            .attribute_name_index = attribute_name_index,
            .attribute_length = attribute_length,
        };
    }

    pub fn write(self: *const Self, writer: std.io.AnyWriter) !void {
        try writer.writeInt(u16, self.attribute_name_index, .big);
        try writer.writeInt(u32, self.attribute_length, .big);
        try writer.writeInt(u16, 0, .big);
        try writer.writeInt(u16, 1, .big);
        try writer.writeInt(u32, 1, .big);
        // try writer.writeInt(u32, @intCast(self.code.len), .big);
        try writer.writeByte(0xB1);
        try writer.writeInt(u16, 0, .big);
        // try writer.writeInt(u16, @intCast(self.exception_table.len), .big);
        // TODO: write exceptions
        try writer.writeInt(u16, 0, .big);
        // try writer.writeInt(u16, @intCast(self.attributes.len), .big);
        // TODO: write attributes
    }
};

const MethodSignature = struct {
    returns: JavaType,
    args: []const JavaType,
    descriptor: []const u8,

    pub fn of(gpa: std.mem.Allocator, returns: JavaType, args: anytype) !MethodSignature {
        const argsSlice = argsToSlice(args);
        return .{
            .returns = returns,
            .args = argsSlice[0..],
            .descriptor = try buildDescriptor(gpa, returns, @constCast(argsSlice[0..])),
        };
    }

    fn buildDescriptor(gpa: std.mem.Allocator, returns: JavaType, args: []JavaType) ![]const u8 {
        var descriptor = std.ArrayList(u8).init(gpa);

        try descriptor.append('(');
        for (args) |arg| {
            try descriptor.appendSlice(arg.descriptor);
        }
        try descriptor.append(')');
        try descriptor.appendSlice(returns.descriptor);

        return descriptor.toOwnedSlice();
    }

    fn argsToSlice(args: anytype) [args.len]JavaType {
        return switch (@typeInfo(@TypeOf(args))) {
            .@"struct" => {
                var array: [args.len]JavaType = undefined;
                inline for (args, 0..) |t, i| {
                    if (@TypeOf(t) != JavaType) @compileError("only supports value of type JavaType");
                    array[i] = t;
                }
                return array;
            },
            else => @compileError("only supports tuples"),
        };
    }
};

const AccessFlags = struct {
    const Self = @This();

    public: bool = false,
    private: bool = false,
    static: bool = false,

    pub fn asU16(self: Self) u16 {
        var result: u16 = 0;

        if (self.public) result |= 0x0001;
        if (self.private) result |= 0x0002;
        if (self.static) result |= 0x0008;

        return result;
    }
};

const JavaVersion = enum(u16) {
    java_1 = 45,
    java_2 = 46,
    java_3 = 47,
    java_4 = 48,
    java_5 = 49,
    java_6 = 50,
    java_7 = 51,
    java_8 = 52,
};

const ByteCode = struct {
    const Self = @This();

    pub fn init(gpa: std.mem.Allocator) Self {
        _ = gpa;
        return Self{};
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn @"return"(self: *Self) *Self {
        return self;
    }
};

const ConstantPool = struct {
    const Self = @This();

    pool: std.ArrayList(CpInfo),

    cache: std.AutoHashMap(u64, usize),

    pub fn init(gpa: std.mem.Allocator) Self {
        return Self{
            .pool = std.ArrayList(CpInfo).init(gpa),
            .cache = std.AutoHashMap(u64, usize).init(gpa),
        };
    }

    pub fn deinit(self: *Self) void {
        self.pool.deinit();
        self.cache.deinit();
    }

    pub fn classEntry(self: *Self, class_type: JavaType) !u16 {
        const class_name_index: u16 = try self.utf8Entry(if (class_type.isArray) class_type.descriptor else class_type.internal_name);
        try self.pool.append(.{ .class_info = .{ .name_index = class_name_index } });
        return @intCast(self.pool.items.len);
    }

    pub fn utf8Entry(self: *Self, string: []const u8) !u16 {
        if (self.cache.get(hash(string))) |index| {
            return @intCast(index);
        }
        try self.pool.append(ConstantUtf8Info.fromString(string));
        const index: u16 = @intCast(self.pool.items.len);
        try self.cache.put(hash(string), index);
        return index;
    }

    pub fn write(self: *Self, writer: std.io.AnyWriter) !void {
        try writer.writeInt(u16, @intCast(self.pool.items.len + 1), .big);

        for (self.pool.items) |cpinfo| {
            try cpinfo.write(writer);
        }
    }

    pub fn debugLog(self: *Self) void {
        for (self.pool.items, 0..) |cpinfo, i| {
            std.debug.print("{d}: ", .{i + 1});
            switch (cpinfo) {
                .class_info => |class| std.debug.print("tag: Class, class name index: {d}\n", .{class.name_index}),
                .utf8_info => |utf8| std.debug.print("tag: Utf8, value: {s}\n", .{utf8.bytes}),
                else => unreachable,
            }
        }
    }

    fn hash(any: anytype) u64 {
        if (@TypeOf(any) == []const u8) {
            return std.hash_map.hashString(any);
        } else if (@TypeOf(any) == JavaType) {
            var h = std.hash.Wyhash.init(0);
            h.update(any.descriptor);
            h.update(any.internal_name);
            std.hash.autoHash(&h, any.isArray);
            return h.final();
        }

        unreachable;
    }
};

const ConstantPoolTag = enum(u8) {
    Class = 7,
    Fieldref = 9,
    Methodref = 10,
    InterfaceMethodref = 11,
    String = 8,
    Integer = 3,
    Float = 4,
    Long = 5,
    Double = 6,
    NameAndType = 12,
    Utf8 = 1,
    MethodHandle = 15,
    MethodType = 16,
    InvokeDynamic = 18,
};

const CpInfo = union(enum) {
    const Self = @This();

    class_info: ConstantClassInfo,
    methodref_info: ConstantMethodrefInfo,
    utf8_info: ConstantUtf8Info,
    name_and_type_info: ConstantNameAndTypeInfo,

    pub fn write(self: Self, writer: std.io.AnyWriter) !void {
        switch (self) {
            inline else => |value| try value.write(writer),
        }
    }
};

const ConstantClassInfo = packed struct {
    const Self = @This();

    tag: ConstantPoolTag = .Class,
    name_index: u16,

    pub fn write(self: Self, writer: std.io.AnyWriter) !void {
        try writer.writeInt(u8, @intFromEnum(self.tag), .big);
        try writer.writeInt(u16, self.name_index, .big);
    }
};

const ConstantMethodrefInfo = packed struct {
    const Self = @This();

    tag: ConstantPoolTag = .Methodref,
    class_index: u16,
    name_and_type_index: u16,

    pub fn write(self: Self, writer: std.io.AnyWriter) !void {
        try writer.writeInt(u8, @intFromEnum(self.tag), .big);
        unreachable;
    }
};

const ConstantUtf8Info = struct {
    const Self = @This();

    tag: ConstantPoolTag = .Utf8,
    length: u16,
    bytes: []u8,

    pub fn fromString(str: []const u8) CpInfo {
        return .{ .utf8_info = .{ .length = @intCast(str.len), .bytes = @constCast(str) } };
    }

    pub fn write(self: Self, writer: std.io.AnyWriter) !void {
        try writer.writeInt(u8, @intFromEnum(self.tag), .big);
        try writer.writeInt(u16, self.length, .big);
        try writer.writeAll(self.bytes);
    }
};

const ConstantNameAndTypeInfo = struct {
    const Self = @This();

    tag: ConstantPoolTag = .NameAndType,
    name_index: u16,
    descriptor_index: u16,

    pub fn write(self: Self, writer: std.io.AnyWriter) !void {
        try writer.writeInt(u8, @intFromEnum(self.tag), .big);
        unreachable;
    }
};
