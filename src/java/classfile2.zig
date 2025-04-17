const std = @import("std");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var builder = try ClassFileBuilder.init(allocator, "BrainfuckProgram");
    try builder.addMethod(.{
        .owner_class_name = "BrainfuckProgram",
        .name = "main",
        .java_type = "(Ljava/lang/String;)V",
    });

    builder.printConstantPool();

    const classfile = try builder.build(allocator);
    const classBytes = try classfile.toBytes(allocator);

    for (classBytes) |byte| {
        std.debug.print("{X:0<2} ", .{byte});
    }
    std.debug.print("\n", .{});
}

const ClassFileBuilder = struct {
    const Self = @This();

    class_name: []const u8,
    constant_pool: std.ArrayList(CpInfo),

    pub fn init(allocator: std.mem.Allocator, class_name: []const u8) !Self {
        var builder = Self{
            .class_name = class_name,
            .constant_pool = std.ArrayList(CpInfo).init(allocator),
        };

        try builder.addClass("java/lang/Object");
        // try builder.addMethod(.{ .owner_class_name = "java/lang/Object", .name = "<init>", .java_type = "()V" });
        try builder.addClass(class_name);

        return builder;
    }

    pub fn deinit(self: *Self) void {
        self.constant_pool.deinit();
    }

    pub fn addClass(self: *Self, class_name: []const u8) !void {
        var cp = &self.constant_pool;

        try cp.append(ConstantUtf8Info.fromString(class_name));
        const class_name_index: u16 = @intCast(cp.items.len);
        try cp.append(.{ .class_info = .{ .name_index = class_name_index } });
    }

    const AddMethodParams = struct {
        owner_class_name: []const u8,
        name: []const u8,
        java_type: []const u8,
    };

    pub fn addMethod(self: *Self, params: AddMethodParams) !void {
        var cp = &self.constant_pool;

        try cp.append(ConstantUtf8Info.fromString(params.java_type));
        // const type_index: u16 = @intCast(cp.items.len);
        try cp.append(ConstantUtf8Info.fromString(params.name));
        // const name_index: u16 = @intCast(cp.items.len);

        // try cp.append(.{ .name_and_type_info = .{ .name_index = name_index, .descriptor_index = type_index } });
        // const name_and_type_index: u16 = @intCast(cp.items.len);
        // const class_index = try self.cpIndexOf(.Class, params.owner_class_name);
        // try cp.append(.{ .methodref_info = .{ .class_index = class_index, .name_and_type_index = name_and_type_index } });
    }

    fn cpIndexOf(self: *Self, tag: ConstantPoolTag, name: []const u8) !u16 {
        const cp = &self.constant_pool;
        for (cp.items, 0..) |item, i| {
            switch (item) {
                .class_info => |info| {
                    if (tag != .Class) break;

                    const found_name: *ConstantUtf8Info = @ptrCast(&self.constant_pool.items[info.name_index - 1]);
                    if (std.mem.eql(u8, found_name.bytes, name)) return @intCast(i + 1);
                },
                else => continue,
            }
        }
        return error.NotFoundInConstantPool;
    }

    pub fn printConstantPool(self: *Self) void {
        const print = std.debug.print;
        for (self.constant_pool.items, 0..) |info, i| {
            switch (info) {
                .class_info => |v| print("[{d:>3}] .tag = Class, .name_index = {d}", .{ i + 1, v.name_index }),
                .methodref_info => |v| print("[{d:>3}] .tag = Methodref, .class_index = {d}, .name_and_type_index = {d}", .{ i + 1, v.class_index, v.name_and_type_index }),
                .utf8_info => |v| print("[{d:>3}] .tag = Utf8, .length = {d}, .bytes = {s}", .{ i + 1, v.length, v.bytes }),
                .name_and_type_info => |v| print("[{d:>3}] .tag = NameAndType, .name_index = {d}, .descriptor_index = {d}", .{ i + 1, v.name_index, v.descriptor_index }),
            }
            print("\n", .{});
        }
    }

    pub fn build(self: *Self, allocator: std.mem.Allocator) !*ClassFile {
        const cf = try allocator.create(ClassFile);
        cf.* = ClassFile{
            .constant_pool_count = @intCast(self.constant_pool.items.len),
        };
        return cf;
    }
};

const ClassFile = struct {
    magic: u32 = 0xCAFEBABE,
    minor_version: u16 = 0,
    major_version: u16 = 52, // Java 8
    constant_pool_count: u16,
    // constant_pool: []CpInfo,
    // access_flags: u16,
    // this_class: u16,
    // super_class: u16,
    // interfaces_count: u16,
    // interfaces: []u16,
    // fields_count: u16,
    // fields: []FieldInfo,
    // methods_count: u16,
    // methods: []MethodInfo,
    // attributes_count: u16,
    // attributes: []AttributeInfo,

    pub fn toBytes(self: *ClassFile, allocator: std.mem.Allocator) ![]u8 {
        const buffer = try allocator.alloc(u8, @sizeOf(ClassFile));
        var stream = std.io.fixedBufferStream(buffer);
        const writer = stream.writer();

        try writer.writeInt(u32, self.magic, .big);
        try writer.writeInt(u16, self.minor_version, .big);
        try writer.writeInt(u16, self.major_version, .big);
        try writer.writeInt(u16, self.constant_pool_count, .big);

        return buffer;
    }
};

const CpInfo = union(enum) {
    class_info: ConstantClassInfo,
    methodref_info: ConstantMethodrefInfo,
    utf8_info: ConstantUtf8Info,
    name_and_type_info: ConstantNameAndTypeInfo,
};

const ConstantClassInfo = packed struct {
    tag: ConstantPoolTag = .Class,
    name_index: u16,
};

const ConstantMethodrefInfo = packed struct {
    tag: ConstantPoolTag = .Methodref,
    class_index: u16,
    name_and_type_index: u16,
};

const ConstantUtf8Info = struct {
    tag: ConstantPoolTag = .Utf8,
    length: u16,
    bytes: []u8,

    pub fn fromString(str: []const u8) CpInfo {
        return .{ .utf8_info = .{ .length = @intCast(str.len), .bytes = @constCast(str) } };
    }
};

const ConstantNameAndTypeInfo = struct {
    tag: ConstantPoolTag = .NameAndType,
    name_index: u16,
    descriptor_index: u16,
};

const FieldInfo = struct {
    access_flags: u16,
    name_index: u16,
    descriptor_index: u16,
    attributes_count: u16,
    attributes: []AttributeInfo,
};
const MethodInfo = struct {
    access_flags: u16,
    name_index: u16,
    descriptor_index: u16,
    attributes_count: u16,
    attributes: []AttributeInfo,
};
const AttributeInfo = struct {
    attribute_name_index: u16,
    attribute_length: u32,
    info: []u8,
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
