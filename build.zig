const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    var gpa = std.heap.GeneralPurposeAllocator(.{ .enable_memory_limit = true, .safety = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const strip = b.option(bool, "strip", "") orelse false;

    // https://ziglang.org/documentation/master/std/src/target.zig.html
    const os_table = [_][]const u8{ "freestanding", "ananas", "cloudabi", "dragonfly", "freebsd", "fuchsia", "ios", "kfreebsd", "linux", "lv2", "macos", "netbsd", "openbsd", "solaris", "windows", "zos", "haiku", "minix", "rtems", "nacl", "aix", "cuda", "nvcl", "amdhsa", "ps4", "ps5", "elfiamcu", "tvos", "watchos", "driverkit", "mesa3d", "contiki", "amdpal", "hermit", "hurd", "wasi", "emscripten", "shadermodel", "uefi", "opencl", "glsl450", "vulkan", "plan9", "other" };
    const arch_table = [_][]const u8{ "arm", "armeb", "aarch64", "aarch64_be", "aarch64_32", "arc", "avr", "bpfel", "bpfeb", "csky", "dxil", "hexagon", "loongarch32", "loongarch64", "m68k", "mips", "mipsel", "mips64", "mips64el", "msp430", "powerpc", "powerpcle", "powerpc64", "powerpc64le", "r600", "amdgcn", "riscv32", "riscv64", "sparc", "sparc64", "sparcel", "s390x", "tce", "tcele", "thumb", "thumbeb", "x86", "x86_64", "xcore", "nvptx", "nvptx64", "le32", "le64", "amdil", "amdil64", "hsail", "hsail64", "spir", "spir64", "spirv32", "spirv64", "kalimba", "shave", "lanai", "wasm32", "wasm64", "renderscript32", "renderscript64", "ve", "spu_2" };

    var os = os_table[@enumToInt(target.getOsTag())];
    var arch = arch_table[@enumToInt(target.getCpuArch())];

    var name = std.fmt.allocPrint(allocator, "entreepy-{s}-{s}", .{ os, arch }) catch "e";
    defer allocator.free(name);

    const exe = b.addExecutable(.{
        .name = name,

        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.strip = strip;

    exe.install();

    const run_cmd = exe.run();

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}
