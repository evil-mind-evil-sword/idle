const std = @import("std");
const idle = @import("idle");
const extractJsonString = idle.event_parser.extractString;

/// PreCompact hook - persist recovery anchor before context compaction
pub fn run(allocator: std.mem.Allocator) !u8 {
    // Read hook input from stdin
    const stdin = std.fs.File.stdin();
    var buf: [4096]u8 = undefined;
    const n = try stdin.readAll(&buf);
    const input_json = buf[0..n];

    // Extract cwd
    const cwd = extractJsonString(input_json, "\"cwd\"") orelse ".";

    // Change to project directory
    std.posix.chdir(cwd) catch {};

    // Read current loop state from jwz
    const state_json = try readJwzState(allocator);
    defer if (state_json) |s| allocator.free(s);

    if (state_json == null or state_json.?.len == 0) {
        return 0; // No loop active
    }

    // Parse state
    var parsed = idle.parseEvent(allocator, state_json.?) catch return 0;
    defer if (parsed) |*p| p.deinit();

    if (parsed == null) return 0;

    const state = parsed.?.state;
    if (state.stack.len == 0) {
        return 0; // No active loop
    }

    const frame = state.stack[state.stack.len - 1];

    // Build goal description
    var goal_buf: [256]u8 = undefined;
    const goal = blk: {
        if (frame.issue_id) |id| {
            break :blk std.fmt.bufPrint(&goal_buf, "Working on issue: {s}", .{id}) catch "Loop in progress";
        }
        break :blk std.fmt.bufPrint(&goal_buf, "{s} loop in progress", .{@tagName(frame.mode)}) catch "Loop in progress";
    };

    // Get recent git info (simplified - just note it's available)
    const progress = "See git log for recent commits";
    const modified = "See git status for modified files";

    // Build anchor JSON
    var anchor_buf: [1024]u8 = undefined;
    const anchor = std.fmt.bufPrint(&anchor_buf,
        \\{{"goal":"{s}","mode":"{s}","iteration":"{}/{}","progress":"{s}","modified_files":"{s}","next_step":"Continue working on the task. Check git status and loop state."}}
    , .{ goal, @tagName(frame.mode), frame.iter, frame.max, progress, modified }) catch return 0;

    // Post anchor to jwz
    try postJwzMessage(allocator, "loop:anchor", anchor);

    // Output minimal pointer
    var stdout_buf: [128]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_writer.interface;
    try stdout.writeAll("IDLE: Recovery anchor saved. After compaction: jwz read loop:anchor\n");
    try stdout.flush();

    return 0;
}

/// Read loop state from jwz
fn readJwzState(allocator: std.mem.Allocator) !?[]u8 {
    var child = std.process.Child.init(&.{ "sh", "-c", "jwz read loop:current 2>/dev/null | tail -1" }, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;

    try child.spawn();

    if (child.stdout) |stdout| {
        var read_buf: [65536]u8 = undefined;
        const n_read = try stdout.readAll(&read_buf);
        _ = try child.wait();

        if (n_read == 0) return null;

        const result = try allocator.alloc(u8, n_read);
        @memcpy(result, read_buf[0..n_read]);
        return result;
    }

    _ = try child.wait();
    return null;
}

/// Post message to jwz
fn postJwzMessage(allocator: std.mem.Allocator, topic: []const u8, message: []const u8) !void {
    // Write message to temp file with thread ID to avoid race conditions
    var path_buf: [64]u8 = undefined;
    const tid = std.Thread.getCurrentId();
    const ts = std.time.timestamp();
    const tmp_path = std.fmt.bufPrint(&path_buf, "/tmp/idle-anchor-{d}-{d}.json", .{ tid, ts }) catch "/tmp/idle-anchor.json";

    const file = try std.fs.createFileAbsolute(tmp_path, .{});
    defer file.close();
    defer std.fs.deleteFileAbsolute(tmp_path) catch {};
    try file.writeAll(message);

    var cmd_buf: [512]u8 = undefined;
    const cmd = try std.fmt.bufPrint(&cmd_buf, "jwz topic new {s} 2>/dev/null; jwz post {s} -f {s} 2>/dev/null", .{ topic, topic, tmp_path });

    var child = std.process.Child.init(&.{ "sh", "-c", cmd }, allocator);
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    try child.spawn();
    _ = try child.wait();
}

