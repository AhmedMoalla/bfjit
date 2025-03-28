const std = @import("std");

const supported_targets = [_]std.Target.Query{
    .{ .os_tag = .linux, .cpu_arch = .x86_64 },
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{ .whitelist = &supported_targets });
    const optimize = b.standardOptimizeOption(.{});

    const resolved = target.result;
    if (!isTargetSupported(resolved)) {
        b.default_step.addError("{s}-{s} is not supported.", .{ @tagName(resolved.os.tag), @tagName(resolved.cpu.arch) }) catch unreachable;
        return;
    }

    const exe_mod = b.createModule(.{ .root_source_file = b.path("src/main.zig"), .target = target, .optimize = optimize, .single_threaded = true });

    const exe = b.addExecutable(.{
        .name = "bfjit",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    // Adds `zig build run` to run the built executable
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Adds `zig build test` to run all tests
    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}

fn isTargetSupported(resolved: std.Target) bool {
    for (supported_targets) |t| {
        if (resolved.os.tag == t.os_tag and resolved.cpu.arch == t.cpu_arch) {
            return true;
        }
    }
    return false;
}
