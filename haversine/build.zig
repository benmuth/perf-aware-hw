const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // const lib = b.addStaticLibrary(.{
    //     .name = "haversine",
    //     // In this case the main source file is merely a path, however, in more
    //     // complicated build scripts, this could be a generated file.
    //     .root_source_file = .{ .path = "src/root.zig" },
    //     .target = target,
    //     .optimize = optimize,
    // });

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    // b.installArtifact(lib);

    const generate_exe = b.addExecutable(.{
        .name = "generate_data",
        .root_source_file = .{ .path = "src/generate_data.zig" },
        .target = target,
        .optimize = optimize,
    });

    // const parser_exe = b.addExecutable(.{
    //     .name = "parse_json",
    //     .root_source_file = .{ .path = "src/json_parse.zig" },
    //     .target = target,
    //     .optimize = optimize,
    // });

    const main_exe = b.addExecutable(.{
        .name = "main",
        .root_source_file = .{ .path = "src/simple_haversine.zig" },
        .target = target,
        .optimize = optimize,
    });

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(generate_exe);
    // b.installArtifact(parser_exe);
    b.installArtifact(main_exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const generate_run_cmd = b.addRunArtifact(generate_exe);
    // const parser_run_cmd = b.addRunArtifact(parser_exe);
    const main_run_cmd = b.addRunArtifact(main_exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    generate_run_cmd.step.dependOn(b.getInstallStep());
    // parser_run_cmd.step.dependOn(b.getInstallStep());
    main_run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        generate_run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const generate_step = b.step("generate", "Generate point data");
    generate_step.dependOn(&generate_run_cmd.step);

    // const parse_step = b.step("parse", "Parse JSON point data and calculate Haversine distance");
    // parse_step.dependOn(&parser_run_cmd.step);

    const main_step = b.step("main", "main JSON point data and calculate Haversine distance");
    main_step.dependOn(&main_run_cmd.step);
    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    // const lib_unit_tests = b.addTest(.{
    //     .root_source_file = .{ .path = "src/root.zig" },
    //     .target = target,
    //     .optimize = optimize,
    // });

    // const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const generate_unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/generate_data.zig" },
        .target = target,
        .optimize = optimize,
    });

    const parser_unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/json_parse.zig" },
        .target = target,
        .optimize = optimize,
    });

    const main_unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/simple_haversine.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_generate_unit_tests = b.addRunArtifact(generate_unit_tests);
    const run_parser_unit_tests = b.addRunArtifact(parser_unit_tests);
    const run_main_unit_tests = b.addRunArtifact(main_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    // test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_generate_unit_tests.step);
    test_step.dependOn(&run_parser_unit_tests.step);
    test_step.dependOn(&run_main_unit_tests.step);
}
