const std = @import("std");

pub const TestCase = struct {
    name: []const u8,
    bf: []const u8 = "",
    in: []const u8 = "",
    expected: []const u8 = "",

    pub fn isValid(self: TestCase) bool {
        return self.bf.len > 0 and self.expected.len > 0;
    }

    pub fn deinit(self: TestCase, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.bf);
        allocator.free(self.expected);
        allocator.free(self.in);
    }
};

const TestCases = @This();

cases: []TestCase,
invalid: []TestCase,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) !TestCases {
    var cases_dir = try std.fs.cwd().openDir("src/tests/cases", .{ .iterate = true });
    defer cases_dir.close();
    var iterator = cases_dir.iterateAssumeFirstIteration();

    var cases_map = std.StringHashMap(TestCase).init(allocator);
    defer cases_map.deinit();

    while (try iterator.next()) |entry| {
        if (entry.kind != .file) continue;

        const file_name = try allocator.dupe(u8, entry.name);
        defer allocator.free(file_name);
        const extension = std.fs.path.extension(file_name);
        var it = std.mem.splitScalar(u8, file_name, '.');
        const key = try allocator.dupe(u8, it.next().?);

        const file_path = try cases_dir.realpathAlloc(allocator, file_name);
        defer allocator.free(file_path);

        const case = try cases_map.getOrPut(key);
        if (!case.found_existing) {
            case.value_ptr.* = TestCase{ .name = key };
        } else {
            allocator.free(key);
        }

        if (std.mem.eql(u8, extension, ".b")) {
            case.value_ptr.bf = try readAllContents(allocator, file_path);
        } else if (std.mem.eql(u8, extension, ".out")) {
            case.value_ptr.expected = try readAllContents(allocator, file_path);
        } else if (std.mem.eql(u8, extension, ".in")) {
            case.value_ptr.in = try readAllContents(allocator, file_path);
        }
    }

    var cases = std.ArrayList(TestCase).init(allocator);
    var invalid = std.ArrayList(TestCase).init(allocator);
    var keys = cases_map.keyIterator();
    while (keys.next()) |key| {
        const case = cases_map.get(key.*).?;
        if (case.isValid()) {
            try cases.append(case);
        } else {
            try invalid.append(case);
        }
    }

    return TestCases{
        .allocator = allocator,
        .cases = try cases.toOwnedSlice(),
        .invalid = try invalid.toOwnedSlice(),
    };
}

pub fn deinit(self: *TestCases) void {
    var allocator = self.allocator;
    for (self.cases) |case| {
        case.deinit(allocator);
    }
    allocator.free(self.cases);
    for (self.invalid) |case| {
        case.deinit(allocator);
    }
    allocator.free(self.invalid);
}

fn readAllContents(allocator: std.mem.Allocator, file_path: []const u8) ![]const u8 {
    return std.fs.cwd().readFileAlloc(allocator, file_path, std.math.maxInt(usize));
}
