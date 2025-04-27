const std = @import("std");
const log = std.log.scoped(.classfile);

const classfile = @embedFile("./BrainfuckProgram.class");
const public = 0x0001;
const static = 0x0008;

// TODO: Detect java in path an start classfile with it as parameter

// TODO: Try to compute these values at compile time using comptime or the build system (maybe generate .zon file at build time ?)
// For now just run the main function in here to compute them.
pub const info = ClassFileInfo{
    .code_location = ByteCodeLocation{
        .code_start = 1961,
        .code_end = 1999,
        .code_length_index = 1957,
        .attribute_length_index = 1949,
        .code_attributes_count_index = 2001,
        .stack_map_table_start = 2003,
        .stack_map_table_end = 2013,
    },
    .constant_pool_indices = ConstantPoolIndices{
        .fields = ConstantPoolFields{
            .head_value = 58,
            .next_in = 83,
        },
        .methods = ConstantPoolMethods{
            .inc_head = 99,
            .dec_head = 96,
            .inc_at_head = 90,
            .dec_at_head = 93,
            .get_at_head = 54,
            .set_at_head = 86,
            .output_at_head = 105,
            .input_at_head = 102,
            .head_not_zero = 108,
        },
    },
};

pub fn main() !void {
    const i = try introspect();
    std.debug.print("{}\n", .{i});
}

pub fn create(gpa: std.mem.Allocator, bytecode: []u8) ![]u8 {
    var bytes = try gpa.dupe(u8, classfile);

    const location = info.code_location;

    const attribute_length_bytes: *const [4]u8 = @ptrCast(bytes[location.attribute_length_index .. location.attribute_length_index + 4]);
    const attribute_length = std.mem.readInt(u32, attribute_length_bytes, .big);

    const initial_code_length = location.code_end - location.code_start;
    const stack_map_table_length = location.stack_map_table_end - location.stack_map_table_start;
    const new_attribute_length: u32 = @intCast(attribute_length - initial_code_length + bytecode.len - stack_map_table_length);
    @memcpy(bytes[location.attribute_length_index .. location.attribute_length_index + 4], &std.mem.toBytes(@byteSwap(new_attribute_length)));

    const new_code_length: u32 = @intCast(bytecode.len);
    @memcpy(bytes[location.code_length_index .. location.code_length_index + 4], &std.mem.toBytes(@byteSwap(new_code_length)));

    const old_code_attributes_count_bytes: *const [2]u8 = @ptrCast(bytes[location.code_attributes_count_index .. location.code_attributes_count_index + 2]);
    const old_code_attributes_count = std.mem.readInt(u16, old_code_attributes_count_bytes, .big);
    const new_code_attributes_count = old_code_attributes_count - 1;
    @memcpy(bytes[location.code_attributes_count_index .. location.code_attributes_count_index + 2], &std.mem.toBytes(@byteSwap(new_code_attributes_count)));

    const head = try gpa.dupe(u8, bytes[0..location.code_start]);
    const mid = try gpa.dupe(u8, bytes[location.code_end..location.stack_map_table_start]);
    const tail = try gpa.dupe(u8, bytes[location.stack_map_table_end..]);

    return std.mem.concat(gpa, u8, &[_][]u8{ head, bytecode, mid, tail });
}

const ConstantPoolIndices = struct {
    fields: ConstantPoolFields,
    methods: ConstantPoolMethods,
};

const ConstantPoolMethods = struct {
    inc_head: u16,
    dec_head: u16,
    inc_at_head: u16,
    dec_at_head: u16,
    get_at_head: u16,
    set_at_head: u16,
    output_at_head: u16,
    input_at_head: u16,
    head_not_zero: u16,
};

const ConstantPoolFields = struct {
    head_value: u16,
    next_in: u16,
};

const ByteCodeLocation = struct {
    code_start: usize,
    code_end: usize,
    code_length_index: usize,
    attribute_length_index: usize,
    code_attributes_count_index: usize,
    stack_map_table_start: usize,
    stack_map_table_end: usize,
};

const ClassFileInfo = struct {
    code_location: ByteCodeLocation,
    constant_pool_indices: ConstantPoolIndices,
};

const CpRef = struct {
    self: usize,
    target: usize,
};

fn findEntryIndex(utf8: std.StringHashMap(usize), nameandtypes: std.ArrayList(CpRef), target_refs: std.ArrayList(CpRef), field_name: []const u8) u16 {
    const field_name_index = utf8.get(field_name).?;
    const nt_index = for (nameandtypes.items) |nt| {
        if (nt.target == field_name_index) break nt.self;
    } else unreachable;
    const ref_index = for (target_refs.items) |fr| {
        if (fr.target == nt_index) break fr.self;
    } else unreachable;
    return @intCast(ref_index);
}

fn introspect() !ClassFileInfo {
    var location: ByteCodeLocation = undefined;
    var fields: ConstantPoolFields = undefined;
    var methods: ConstantPoolMethods = undefined;

    const gpa = std.heap.page_allocator;

    var bytes = std.io.fixedBufferStream(classfile);
    var counting_reader = std.io.countingReader(bytes.reader().any());
    var reader = ClassFileReader.init(counting_reader.reader().any());

    const magic = try reader.readU32();
    std.debug.assert(magic == 0xCAFEBABE);
    log.debug("Magic: {X}", .{magic});

    const minor_version = try reader.readU16();
    const major_version = try reader.readU16();
    log.debug("Version: {d}.{d}", .{ major_version, minor_version });

    const constant_pool_count = try reader.readU16();
    log.debug("Constant Pool Count: {d}", .{constant_pool_count});

    var methodrefs = std.ArrayList(CpRef).init(gpa);
    var fieldrefs = std.ArrayList(CpRef).init(gpa);
    var nameandtypes = std.ArrayList(CpRef).init(gpa);
    var utf8 = std.StringHashMap(usize).init(gpa);
    for (1..constant_pool_count) |i| {
        const tag = try reader.readConstantPoolTag();
        switch (tag) {
            .Utf8 => {
                const length = try reader.readU16();
                const buffer = try gpa.alloc(u8, length);
                try reader.readNoEof(buffer);
                try utf8.put(buffer, i);
            },
            .Fieldref => {
                try reader.skipBytes(2); // class_index
                const name_and_type_index = try reader.readU16();
                try fieldrefs.append(.{ .self = i, .target = name_and_type_index });
            },
            .Methodref => {
                try reader.skipBytes(2); // class_index
                const name_and_type_index = try reader.readU16();
                try methodrefs.append(.{ .self = i, .target = name_and_type_index });
            },
            .NameAndType => {
                const name_index = try reader.readU16();
                try nameandtypes.append(.{ .self = i, .target = name_index });
                try reader.skipBytes(2); // descriptor_index
            },
            else => try tag.skipBytes(reader),
        }
    }

    fields.head_value = findEntryIndex(utf8, nameandtypes, fieldrefs, "headValue");
    fields.next_in = findEntryIndex(utf8, nameandtypes, fieldrefs, "nextIn");

    methods.inc_head = findEntryIndex(utf8, nameandtypes, methodrefs, "incHead");
    methods.dec_head = findEntryIndex(utf8, nameandtypes, methodrefs, "decHead");
    methods.inc_at_head = findEntryIndex(utf8, nameandtypes, methodrefs, "incAtHead");
    methods.dec_at_head = findEntryIndex(utf8, nameandtypes, methodrefs, "decAtHead");
    methods.get_at_head = findEntryIndex(utf8, nameandtypes, methodrefs, "getAtHead");
    methods.set_at_head = findEntryIndex(utf8, nameandtypes, methodrefs, "setAtHead");
    methods.input_at_head = findEntryIndex(utf8, nameandtypes, methodrefs, "inputAtHead");
    methods.output_at_head = findEntryIndex(utf8, nameandtypes, methodrefs, "outputAtHead");
    methods.head_not_zero = findEntryIndex(utf8, nameandtypes, methodrefs, "headNotZero");

    const access_flags = try reader.readU16();
    log.debug("Access Flags: {X}", .{access_flags});

    const this_class = try reader.readU16();
    log.debug("Class Index: {d}", .{this_class});

    const super_class = try reader.readU16();
    log.debug("Super Class Index: {d}", .{super_class});

    const interfaces_count = try reader.readU16();
    log.debug("Interfaces Count: {d}", .{interfaces_count});

    const fields_count = try reader.readU16();
    log.debug("Fields Count: {d}", .{fields_count});

    // Skip
    for (0..fields_count) |_| {
        try reader.skipBytes(6);
        const attributes_count = try reader.readU16();
        for (0..attributes_count) |_| {
            try reader.skipBytes(2);
            const attribute_length = try reader.readU32();
            try reader.skipBytes(attribute_length);
        }
    }

    const methods_count = try reader.readU16();
    log.debug("Methods Count: {d}", .{methods_count});

    for (0..methods_count) |i| {
        const method_access_flags = try reader.readU16();
        const name_index = try reader.readU16();
        const type_index = try reader.readU16();
        const attributes_count = try reader.readU16();
        if ((method_access_flags & public) != 0 and (method_access_flags & static != 0) and name_index == utf8.get("main").? and type_index == utf8.get("([Ljava/lang/String;)V").?) {
            log.debug("Main Method Index: {d}", .{i});
            for (0..attributes_count) |_| {
                const attribute_name_index = try reader.readU16();
                const attribute_length = try reader.readU32();

                if (attribute_name_index == utf8.get("Code").?) {
                    location.attribute_length_index = counting_reader.bytes_read - @sizeOf(u32);
                    try reader.skipBytes(4); // max_locals + max_stacks
                    const code_length = try reader.readU32();
                    location.code_length_index = counting_reader.bytes_read - @sizeOf(u32);
                    location.code_start = counting_reader.bytes_read;
                    location.code_end = counting_reader.bytes_read + code_length;
                    log.debug("Code Length: {d}", .{code_length});
                    log.debug("Code Start: {d}", .{counting_reader.bytes_read});
                    log.debug("Code End: {d}", .{counting_reader.bytes_read + code_length});
                    try reader.skipBytes(code_length);
                    const exception_table_length = try reader.readU16();
                    try reader.skipBytes(exception_table_length * 8);

                    location.code_attributes_count_index = counting_reader.bytes_read;
                    const code_attributes_count = try reader.readU16();
                    log.debug("Code Attributes Count: {d}", .{code_attributes_count});
                    for (0..code_attributes_count) |_| {
                        const code_attribute_name_index = try reader.readU16();
                        const code_attribute_length = try reader.readU32();

                        if (code_attribute_name_index == utf8.get("StackMapTable").?) {
                            location.stack_map_table_start = counting_reader.bytes_read - @sizeOf(u16) - @sizeOf(u32);
                            location.stack_map_table_end = counting_reader.bytes_read + code_attribute_length;
                        }

                        try reader.skipBytes(code_attribute_length);
                    }
                } else {
                    try reader.skipBytes(attribute_length);
                }
            }
        } else {
            for (0..attributes_count) |_| {
                try reader.skipBytes(2); // attribute_name_index
                const attribute_length = try reader.readU32();
                try reader.skipBytes(attribute_length);
            }
        }
    }
    return ClassFileInfo{
        .code_location = location,
        .constant_pool_indices = .{
            .fields = fields,
            .methods = methods,
        },
    };
}

const ClassFileReader = struct {
    const Self = @This();

    child_reader: std.io.AnyReader,

    pub fn init(reader: std.io.AnyReader) Self {
        return .{ .child_reader = reader };
    }

    pub fn readU32(self: Self) !u32 {
        return self.child_reader.readInt(u32, .big);
    }

    pub fn readU16(self: Self) !u16 {
        return self.child_reader.readInt(u16, .big);
    }

    pub fn readConstantPoolTag(self: Self) !ConstantPoolTag {
        return self.child_reader.readEnum(ConstantPoolTag, .big);
    }

    pub fn readNoEof(self: Self, buffer: []u8) !void {
        try self.child_reader.readNoEof(buffer);
    }

    pub fn skipBytes(self: Self, num_bytes: u64) !void {
        try self.child_reader.skipBytes(num_bytes, .{});
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

    pub fn skipBytes(self: ConstantPoolTag, reader: ClassFileReader) !void {
        try reader.skipBytes(switch (self) {
            .InterfaceMethodref => 4,
            .String, .Class => 2,
            inline else => |tag| @panic("unhandled skipBytes for tag " ++ @tagName(tag)),
        });
    }
};
