const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // =========================================================================
    // SQLite (shared by zawinski and tissue)
    // =========================================================================

    const sqlite_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
    });
    sqlite_mod.addIncludePath(b.path("../../zawinski/vendor/sqlite"));
    sqlite_mod.addCSourceFile(.{
        .file = b.path("../../zawinski/vendor/sqlite/sqlite3.c"),
        .flags = &.{
            "-DSQLITE_ENABLE_FTS5",
            "-DSQLITE_ENABLE_JSON1",
            "-DSQLITE_OMIT_LOAD_EXTENSION",
        },
    });
    const sqlite = b.addLibrary(.{
        .name = "sqlite3",
        .root_module = sqlite_mod,
        .linkage = .static,
    });
    sqlite.linkLibC();

    // =========================================================================
    // zawinski (messaging)
    // =========================================================================

    const zawinski_mod = b.addModule("zawinski", .{
        .root_source_file = b.path("../../zawinski/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    zawinski_mod.addIncludePath(b.path("../../zawinski/vendor/sqlite"));

    // =========================================================================
    // tissue (issues)
    // =========================================================================

    const tissue_mod = b.addModule("tissue", .{
        .root_source_file = b.path("../../tissue/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    tissue_mod.addIncludePath(b.path("../../tissue/vendor/sqlite"));

    // =========================================================================
    // idle library module (our core logic)
    // =========================================================================

    const lib_mod = b.addModule("idle", .{
        .root_source_file = b.path("src/lib/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // =========================================================================
    // Executable: idle-hook
    // =========================================================================

    const exe = b.addExecutable(.{
        .name = "idle-hook",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "idle", .module = lib_mod },
                .{ .name = "zawinski", .module = zawinski_mod },
                .{ .name = "tissue", .module = tissue_mod },
            },
        }),
    });
    exe.root_module.addIncludePath(b.path("../../zawinski/vendor/sqlite"));
    exe.linkLibrary(sqlite);

    b.installArtifact(exe);

    // =========================================================================
    // Run step
    // =========================================================================

    const run_step = b.step("run", "Run idle-hook");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // =========================================================================
    // Test step
    // =========================================================================

    const lib_tests = b.addTest(.{
        .root_module = lib_mod,
    });
    const run_lib_tests = b.addRunArtifact(lib_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_tests.step);
}
