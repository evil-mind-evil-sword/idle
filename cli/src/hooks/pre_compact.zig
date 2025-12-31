const std = @import("std");
const idle = @import("idle");
const extractJsonString = idle.event_parser.extractString;
const jwz = idle.jwz_utils;

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
    const state_json = try jwz.readJwzState(allocator);
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
    const goal = std.fmt.bufPrint(&goal_buf, "{s} loop in progress", .{@tagName(frame.mode)}) catch "Loop in progress";

    // Get recent git info (simplified - just note it's available)
    const progress = "See git log for recent commits";
    const modified = "See git status for modified files";

    // Build anchor JSON with alice reminder
    var anchor_buf: [2048]u8 = undefined;
    const anchor = std.fmt.bufPrint(&anchor_buf,
        \\{{"goal":"{s}","mode":"{s}","iteration":"{}/{}","progress":"{s}","modified_files":"{s}","next_step":"Continue working on the task. Check git status and loop state.","alice_reminder":"Use Task tool with subagent_type=idle:alice for design review, debugging help, or completion review. Alice consults multiple models for second opinions."}}
    , .{ goal, @tagName(frame.mode), frame.iter, frame.max, progress, modified }) catch return 0;

    // Post anchor to jwz
    try jwz.postJwzMessage(allocator, "loop:anchor", anchor);

    // Output context that survives compaction
    var stdout_buf: [512]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_writer.interface;
    try stdout.writeAll(
        \\IDLE: Recovery anchor saved before compaction.
        \\
        \\After compaction, recover context with: jwz read loop:anchor
        \\
        \\Remember: idle:alice is available for deep reasoning and review.
        \\Use Task tool with subagent_type="idle:alice" when stuck or need review.
        \\
    );
    try stdout.flush();

    return 0;
}


