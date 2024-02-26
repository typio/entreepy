const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    var gpa = std.heap.GeneralPurposeAllocator(.{ .enable_memory_limit = true, .safety = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const os = @tagName(target.result.os.tag);
    const arch = @tagName(target.result.cpu.arch);

    const name = std.fmt.allocPrint(allocator, "entreepy-{s}-{s}", .{ os, arch }) catch "e";
    defer allocator.free(name);

    const exe = b.addExecutable(.{
        .name = name,

        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/test.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
