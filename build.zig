const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    // const optimize = b.standardOptimizeOption(.{});
    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });

    const has_avx2 = std.Target.x86.featureSetHas(builtin.cpu.features, .avx2);

    if (has_avx2 and builtin.cpu.arch == .x86_64) {
        lib_mod.addAssemblyFile(b.path("src/asm_folly.S"));
        lib_mod.addAssemblyFile(b.path("src/asm_folly_memset.S"));
    }

    b.modules.put("stdx", lib_mod) catch @panic("OOM");
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "stdx",
        .root_module = lib_mod,
        .use_llvm = true,
    });
    b.installArtifact(lib);

    const bench_mod = b.createModule(.{
        .root_source_file = b.path("benchmarks/bench.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    bench_mod.addImport("stdx", lib_mod);

    const bench_exe = b.addExecutable(.{
        .name = "bench",
        .root_module = bench_mod,
    });
    bench_exe.linkLibrary(lib);
    b.installArtifact(bench_exe);

    const bench_cmd = b.addRunArtifact(bench_exe);
    bench_cmd.step.dependOn(b.getInstallStep());
    const bench_step = b.step("bench", "Run benchmarks");
    bench_step.dependOn(&bench_cmd.step);

    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
        .use_llvm = true,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
