const std = @import("std");

const package_version = @import("build.zig.zon").version;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const flare_dep = b.dependency("flare", .{
        .target = target,
        .optimize = optimize,
    });
    const flare = flare_dep.module("flare");
    const version_string = package_version;
    const version = std.SemanticVersion.parse(version_string) catch unreachable;

    const options = b.addOptions();
    options.addOption(usize, "version_major", version.major);
    options.addOption(usize, "version_minor", version.minor);
    options.addOption(usize, "version_patch", version.patch);
    options.addOption([]const u8, "version_string", version_string);

    const mod = b.addModule("flash", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "flare", .module = flare },
            .{ .name = "build_options", .module = options.createModule() },
        },
    });

    const exe = b.addExecutable(.{
        .name = "flash",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "flash", .module = mod },
            },
        }),
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const example_basic = b.addExecutable(.{
        .name = "example-basic",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/basic/hello.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "flash", .module = mod }},
        }),
    });

    const example_ergonomic = b.addExecutable(.{
        .name = "example-ergonomic",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/ergonomic_example.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "flash", .module = mod }},
        }),
    });

    const example_declarative = b.addExecutable(.{
        .name = "example-declarative",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/declarative_example.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "flash", .module = mod }},
        }),
    });

    const example_comprehensive = b.addExecutable(.{
        .name = "example-comprehensive",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/comprehensive_example.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "flash", .module = mod }},
        }),
    });

    const example_production = b.addExecutable(.{
        .name = "example-production",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/production_grade_example.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "flash", .module = mod }},
        }),
    });

    const examples_step = b.step("examples", "Build all shipped examples");
    examples_step.dependOn(&example_basic.step);
    examples_step.dependOn(&example_ergonomic.step);
    examples_step.dependOn(&example_declarative.step);
    examples_step.dependOn(&example_comprehensive.step);
    examples_step.dependOn(&example_production.step);

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

    const examples_test_step = b.step("test-examples", "Build all shipped examples");
    examples_test_step.dependOn(&example_basic.step);
    examples_test_step.dependOn(&example_ergonomic.step);
    examples_test_step.dependOn(&example_declarative.step);
    examples_test_step.dependOn(&example_comprehensive.step);
    examples_test_step.dependOn(&example_production.step);

    const verify_step = b.step("verify", "Run build, tests, and shipped examples");
    verify_step.dependOn(&exe.step);
    verify_step.dependOn(&run_mod_tests.step);
    verify_step.dependOn(&run_exe_tests.step);
    verify_step.dependOn(&example_basic.step);
    verify_step.dependOn(&example_ergonomic.step);
    verify_step.dependOn(&example_declarative.step);
    verify_step.dependOn(&example_comprehensive.step);
    verify_step.dependOn(&example_production.step);
}
