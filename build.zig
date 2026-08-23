const std = @import("std");
const Build = std.Build;
const Module = std.Build.Module;

pub fn build(b: *std.Build) void {
    const name = "sub";
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const mod = b.addModule("sub", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    var root_module_opts: Module.CreateOptions = .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "sub", .module = mod },
        },
    };

    const exe = b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(root_module_opts),
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    const all_step = b.step("all", "Create executables for all optimize modes");

    const modes = @typeInfo(std.builtin.OptimizeMode).@"enum".fields;

    inline for (modes) |mode| {
        root_module_opts.optimize = @enumFromInt(mode.value);
        const executable = b.addExecutable(.{
            .name = name ++ "-" ++ mode.name,
            .root_module = b.createModule(root_module_opts),
        });
        all_step.dependOn(&b.addInstallArtifact(executable, .{}).step);
    }

    const msg = [_][]const u8{ "Benchmark all executables in ", b.install_path };
    const bench_help = std.mem.concat(b.allocator, u8, &msg) catch @panic("OOM");
    const bench_step = b.step("bench", bench_help);
    const bench_cmd = b.addRunArtifact(b.addExecutable(.{
        .name = "bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/bench.zig"),
            .target = target,
            .optimize = optimize,
        }),
    }));

    bench_cmd.step.dependOn(all_step);
    bench_step.dependOn(&bench_cmd.step);
}
