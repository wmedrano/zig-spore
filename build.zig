const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "zig-spore",
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);

    // zig build test
    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    // zig build docs
    const install_docs = b.addInstallDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    const docs_step = b.step("docs", "Install docs into zig-out/docs");
    docs_step.dependOn(&install_docs.step);

    // zig build kcov
    const kcov_bin = b.findProgram(&.{"kcov"}, &.{}) catch "kcov";
    const run_kcov = b.addSystemCommand(&.{
        kcov_bin, "--include-pattern=src/",
    });
    const kcov_out = run_kcov.addOutputFileArg(".");
    run_kcov.addArtifactArg(lib_unit_tests);
    const install_coverage = b.addInstallDirectory(.{
        .source_dir = kcov_out,
        .install_dir = .prefix,
        .install_subdir = "kcov",
    });
    const kcov_step = b.step("kcov", "Generate test coverage report.");
    kcov_step.dependOn(&install_coverage.step);

    // zig build test
    const install_site_coverage = b.addInstallDirectory(
        .{
            .source_dir = install_coverage.options.source_dir,
            .install_dir = .prefix,
            .install_subdir = "site/kcov",
        },
    );
    const install_site_docs = b.addInstallDirectory(.{
        .source_dir = install_docs.options.source_dir,
        .install_dir = .prefix,
        .install_subdir = "site",
    });
    const site_step = b.step("site", "Generate the Spore website.");
    site_step.dependOn(&install_site_coverage.step);
    site_step.dependOn(&install_site_docs.step);
}
