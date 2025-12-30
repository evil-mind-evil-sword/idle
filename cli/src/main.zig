const std = @import("std");
const idle = @import("idle");

const hooks = struct {
    const stop = @import("hooks/stop.zig");
    const subagent_stop = @import("hooks/subagent_stop.zig");
    const pre_tool_use = @import("hooks/pre_tool_use.zig");
    const pre_compact = @import("hooks/pre_compact.zig");
    const session_start = @import("hooks/session_start.zig");
};

const usage =
    \\Usage: idle-hook <command> [options]
    \\
    \\Commands:
    \\  stop           Stop hook (core loop mechanism)
    \\  subagent-stop  Subagent stop hook (alice second-opinion gate)
    \\  pre-tool-use   Pre-tool-use hook (safety guardrails)
    \\  pre-compact    Pre-compact hook (recovery anchors)
    \\  session-start  Session start hook (agent awareness)
    \\  status         Show loop status (JSON or human-readable)
    \\  version        Show version information
    \\
    \\Exit codes:
    \\  0  Allow (hook passes)
    \\  2  Block (hook rejects, inject reason)
    \\
;

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        var stderr_buf: [4096]u8 = undefined;
        var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
        const stderr = &stderr_writer.interface;
        try stderr.writeAll(usage);
        try stderr.flush();
        return 1;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "stop")) {
        return hooks.stop.run(allocator);
    } else if (std.mem.eql(u8, command, "subagent-stop")) {
        return hooks.subagent_stop.run(allocator);
    } else if (std.mem.eql(u8, command, "pre-tool-use")) {
        return hooks.pre_tool_use.run(allocator);
    } else if (std.mem.eql(u8, command, "pre-compact")) {
        return hooks.pre_compact.run(allocator);
    } else if (std.mem.eql(u8, command, "session-start")) {
        return hooks.session_start.run(allocator);
    } else if (std.mem.eql(u8, command, "status")) {
        return runStatus(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "version")) {
        var stdout_buf: [256]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
        const stdout = &stdout_writer.interface;
        try stdout.writeAll("idle-hook 0.1.0\n");
        try stdout.flush();
        return 0;
    } else if (std.mem.eql(u8, command, "help") or std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "-h")) {
        var stdout_buf: [4096]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
        const stdout = &stdout_writer.interface;
        try stdout.writeAll(usage);
        try stdout.flush();
        return 0;
    } else {
        var stderr_buf: [4096]u8 = undefined;
        var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
        const stderr = &stderr_writer.interface;
        try stderr.print("Unknown command: {s}\n\n", .{command});
        try stderr.writeAll(usage);
        try stderr.flush();
        return 1;
    }
}

fn runStatus(allocator: std.mem.Allocator, args: []const []const u8) !u8 {
    const json_output = for (args) |arg| {
        if (std.mem.eql(u8, arg, "--json")) break true;
    } else false;

    // For now, shell out to jwz until we link zawinski
    var child = std.process.Child.init(&.{ "sh", "-c", "jwz read loop:current 2>/dev/null | tail -1" }, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;

    try child.spawn();

    var stdout_buf: [65536]u8 = undefined;
    const n = if (child.stdout) |stdout| try stdout.readAll(&stdout_buf) else 0;
    _ = try child.wait();

    var output_buf: [65536]u8 = undefined;
    var output_writer = std.fs.File.stdout().writer(&output_buf);
    const stdout_writer = &output_writer.interface;
    defer stdout_writer.flush() catch {};

    if (n == 0) {
        if (json_output) {
            try stdout_writer.writeAll("{\"status\":\"idle\"}\n");
        } else {
            try stdout_writer.writeAll("No active loop\n");
        }
        return 0;
    }

    const state_json = stdout_buf[0..n];

    if (json_output) {
        try stdout_writer.print("{s}\n", .{std.mem.trim(u8, state_json, " \t\n\r")});
    } else {
        // Parse and display
        var parsed = idle.parseEvent(allocator, state_json) catch null;
        defer if (parsed) |*p| p.deinit();

        if (parsed) |p| {
            const state = p.state;
            if (state.stack.len == 0) {
                try stdout_writer.writeAll("No active loop\n");
            } else {
                const frame = state.stack[state.stack.len - 1];
                try stdout_writer.print("Mode: {s}\n", .{@tagName(frame.mode)});
                try stdout_writer.print("Iteration: {}/{}\n", .{ frame.iter, frame.max });
                if (frame.issue_id) |id| {
                    try stdout_writer.print("Issue: {s}\n", .{id});
                }
                if (frame.worktree_path) |path| {
                    try stdout_writer.print("Worktree: {s}\n", .{path});
                }
            }
        } else {
            try stdout_writer.writeAll("Could not parse loop state\n");
        }
    }

    return 0;
}

test {
    std.testing.refAllDecls(@This());
}
