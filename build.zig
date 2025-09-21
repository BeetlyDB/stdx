const std = @import("std");
const builtin = @import("builtin");

fn addDep(
    artifact: *std.Build.Step.Compile,
    b: *std.Build,
) void {
    const has_avx2 = std.Target.x86.featureSetHas(builtin.cpu.features, .avx2);
    if (has_avx2) {
        const folly_obj = b.pathJoin(&.{ b.cache_root.path.?, "folly.o" });
        const folly_memset_obj = b.pathJoin(&.{ b.cache_root.path.?, "folly_memset.o" });

        const asm_step = b.addSystemCommand(&.{
            "zig",
            "cc",
            "-c",
            "src/asm_folly.S",
            "-o",
            folly_obj,
            "-D__AVX2__",
            "-mtune=native",
            "-fno-exceptions",
            "-g0",
        });
        artifact.step.dependOn(&asm_step.step);
        artifact.addObjectFile(.{ .cwd_relative = folly_obj });

        const asm_step2 = b.addSystemCommand(&.{
            "zig",
            "cc",
            "-c",
            "src/asm_folly_memset.S",
            "-o",
            folly_memset_obj,
            "-D__AVX2__",
            "-mtune=native",
            "-fno-exceptions",
            "-g0",
        });
        artifact.step.dependOn(&asm_step2.step);
        artifact.addObjectFile(.{ .cwd_relative = folly_memset_obj });
    }
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.modules.put("stdx", lib_mod) catch @panic("OOM");
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "stdx",
        .root_module = lib_mod,
    });

    addDep(lib, b);
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
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
