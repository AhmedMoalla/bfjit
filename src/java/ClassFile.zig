const std = @import("std");
const log = std.log.scoped(.classfile);

const ClassFile = @This();

pub const classfile = @embedFile("./BrainfuckProgram.class");
const public = 0x0001;
const static = 0x0008;
const code_attribute_name = "Code";
const main_method_name = "main";
const main_method_type = "([Ljava/lang/String;)V";
// Fields
const head_value_field_name = "headValue";
const next_in_field_name = "nextIn";
// Methods
const inc_head_method_name = "incHead";
const dec_head_method_name = "decHead";
const inc_at_head_method_name = "incAtHead";
const dec_at_head_method_name = "decAtHead";
const get_at_head_method_name = "getAtHead";
const set_at_head_method_name = "setAtHead";

// TODO: Read Classfile bytes to locate the byte index at which we can start writing our own bytecode
// The position should be at the location of the `Code` attribute of the main method.
// After the code is pushed the attribute_length field of the `Code` attribute should be incremented by
// the size of the bytes we inserted.
// TODO: On the final version, just hardcode the byte index that we can compute using the code above
// and directly start inserting bytecode from that position. The file should be cut in half at the byte
// index into a head and a tail. The final byte code should be head + braifuck bytecode + tail.
// TODO: Don't forget to add all local variables usable in the brainfuck bytecode in the constant pool
// in advance so I don't have to add them later.
// TODO: Detect java in path an start classfile with it as parameter

pub fn create(gpa: std.mem.Allocator, bytecode: []u8) ![]u8 {
    var bytes = try gpa.dupe(u8, classfile);
    const info = try introspectClassFile();
    std.debug.print("{}\n", .{info});
    const location = info.code_location;
    const array: *const [4]u8 = @ptrCast(bytes[location.attribute_length_index .. location.attribute_length_index + 4]);
    const attribute_length = std.mem.readInt(u32, array, .big);

    const head = try gpa.dupe(u8, bytes[0..location.code_start]);
    const tail = try gpa.dupe(u8, bytes[location.code_end..]);

    const new_length: u32 = @intCast(attribute_length + bytecode.len);
    @memcpy(head[location.attribute_length_index .. location.attribute_length_index + 4], &std.mem.toBytes(@byteSwap(new_length)));

    return std.mem.concat(gpa, u8, &[_][]u8{ head, bytecode, tail });
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
};

const ConstantPoolFields = struct {
    head_value: u16,
    next_in: u16,
};

const ByteCodeLocation = struct {
    code_start: usize,
    code_end: usize,
    attribute_length_index: usize,
};

const ClassFileInfo = struct {
    code_location: ByteCodeLocation,
    constant_pool_indices: ConstantPoolIndices,
};

pub fn introspectClassFile() !ClassFileInfo {
    var location: ByteCodeLocation = undefined;
    var fields: ConstantPoolFields = undefined;
    var methods: ConstantPoolMethods = undefined;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

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

    const CpRef = struct {
        self: usize,
        target: usize,
    };
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
            .NameAndType => {
                const name_index = try reader.readU16();
                try nameandtypes.append(.{ .self = i, .target = name_index });
                try reader.skipBytes(2); // descriptor_index
            },
            else => try tag.skipBytes(reader),
        }
    }

    var field_name_index = utf8.get(head_value_field_name).?;
    var nt_index = for (nameandtypes.items) |nt| {
        if (nt.target == field_name_index) break nt.self;
    } else unreachable;
    var fr_index = for (fieldrefs.items) |fr| {
        if (fr.target == nt_index) break fr.self;
    } else unreachable;
    fields.head_value = @intCast(fr_index);

    field_name_index = utf8.get(next_in_field_name).?;
    nt_index = for (nameandtypes.items) |nt| {
        if (nt.target == field_name_index) break nt.self;
    } else unreachable;
    fr_index = for (fieldrefs.items) |fr| {
        if (fr.target == nt_index) break fr.self;
    } else unreachable;
    fields.next_in = @intCast(fr_index);

    log.debug("Main Method: Name Index: {d} Type Index: {d}", .{ utf8.get(main_method_name).?, utf8.get(main_method_type).? });

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
        if ((method_access_flags & public) != 0 and (method_access_flags & static != 0) and name_index == utf8.get(main_method_name).? and type_index == utf8.get(main_method_type).?) {
            log.debug("Main Method Index: {d}", .{i});
            for (0..attributes_count) |_| {
                const attribute_name_index = try reader.readU16();
                const current_attribute_length_index = counting_reader.bytes_read;
                const attribute_length = try reader.readU32();

                if (attribute_name_index == utf8.get(code_attribute_name).?) {
                    location.attribute_length_index = current_attribute_length_index;
                    try reader.skipBytes(4); // max_locals + max_stacks
                    const code_length = try reader.readU32();
                    location.code_start = counting_reader.bytes_read;
                    location.code_end = counting_reader.bytes_read + code_length;
                    log.debug("Code Length: {d}", .{code_length});
                    log.debug("Code Start: {d}", .{counting_reader.bytes_read});
                    log.debug("Code End: {d}", .{counting_reader.bytes_read + code_length});
                    try reader.skipBytes(code_length);
                    const exception_table_length = try reader.readU16();
                    try reader.skipBytes(exception_table_length * 8);
                    const code_attributes_count = try reader.readU16();
                    for (0..code_attributes_count) |_| {
                        try reader.skipBytes(2); // attribute_name_index
                        const code_attribute_length = try reader.readU32();
                        try reader.skipBytes(code_attribute_length);
                    }
                } else {
                    try reader.skipBytes(attribute_length);
                }
            }
        } else {
            if (name_index == utf8.get(inc_head_method_name).?) {
                methods.inc_head = name_index;
            } else if (name_index == utf8.get(dec_head_method_name).?) {
                methods.dec_head = name_index;
            } else if (name_index == utf8.get(inc_at_head_method_name).?) {
                methods.inc_at_head = name_index;
            } else if (name_index == utf8.get(dec_at_head_method_name).?) {
                methods.dec_at_head = name_index;
            } else if (name_index == utf8.get(get_at_head_method_name).?) {
                methods.get_at_head = name_index;
            } else if (name_index == utf8.get(set_at_head_method_name).?) {
                methods.set_at_head = name_index;
            }
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
            .Methodref, .InterfaceMethodref => 4,
            .String, .Class => 2,
            inline else => |tag| @panic("unhandled skipBytes for tag " ++ @tagName(tag)),
        });
    }
};
