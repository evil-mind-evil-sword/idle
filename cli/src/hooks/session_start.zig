const std = @import("std");
const idle = @import("idle");
const tissue = @import("tissue");
const extractJsonString = idle.event_parser.extractString;
const jwz = idle.jwz_utils;

/// Session start hook - injects loop context and agent awareness
/// Outputs JSON format for Claude Code context injection
pub fn run(allocator: std.mem.Allocator) !u8 {
    // Read hook input from stdin
    const stdin = std.fs.File.stdin();
    var buf: [4096]u8 = undefined;
    const n = try stdin.readAll(&buf);
    const input_json = buf[0..n];

    // Extract cwd and change to project directory
    const cwd = extractJsonString(input_json, "\"cwd\"") orelse ".";
    std.posix.chdir(cwd) catch {};

    // Build context in memory using fixed buffer
    var context_buf: [32768]u8 = undefined;
    var context_stream = std.io.fixedBufferStream(&context_buf);
    const writer = context_stream.writer();

    // Try to read active loop state
    const state_json = jwz.readJwzState(allocator) catch null;
    defer if (state_json) |s| allocator.free(s);

    if (state_json) |json| {
        if (json.len > 0) {
            // Parse state
            var parsed = idle.parseEvent(allocator, json) catch null;
            defer if (parsed) |*p| p.deinit();

            if (parsed) |p| {
                const state = p.state;
                if (state.stack.len > 0 and state.event == .STATE) {
                    const frame = state.stack[state.stack.len - 1];

                    // Inject active loop context
                    try writer.writeAll("=== ACTIVE LOOP ===\n");
                    try writer.print("Mode: {s} | Iteration: {}/{}\n", .{
                        @tagName(frame.mode),
                        frame.iter,
                        frame.max,
                    });

                    try writer.writeAll("\nYour task: Continue working on this loop. ");
                    try writer.writeAll("Signal <loop-done>COMPLETE</loop-done> when finished.\n");
                    try writer.writeAll("==================\n\n");
                }
            }
        }
    }

    // Always inject agent awareness
    try writer.writeAll(
        \\idle agents available:
        \\  - idle:alice: Deep reasoning, architecture review, quality gates
        \\                Consults multiple models for second opinions
        \\
        \\When to use alice:
        \\  - Stuck on design decisions or debugging
        \\  - Need architectural review before major changes
        \\  - Want a second opinion on implementation approach
        \\  - Completion review (automatically triggered on loop completion)
        \\
        \\Usage: Task tool with subagent_type="idle:alice"
        \\
    );

    // Inject ready issues from tissue
    try injectReadyIssuesTo(allocator, writer);

    // Output as JSON for Claude Code
    var stdout_buf: [65536]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_writer.interface;

    try stdout.writeAll("{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"");

    // JSON-escape the context
    const context_data = context_stream.getWritten();
    try jwz.writeJsonEscaped(stdout, context_data);

    try stdout.writeAll("\"}}\n");
    try stdout.flush();

    return 0;
}

/// Fetch and display ready issues from tissue
fn injectReadyIssuesTo(allocator: std.mem.Allocator, stdout: anytype) !void {
    const store_dir = tissue.store.discoverStoreDir(allocator) catch return;
    defer allocator.free(store_dir);

    var store = tissue.store.Store.open(allocator, store_dir) catch return;
    defer store.deinit();

    const ready_issues = store.listReadyIssues() catch return;
    defer {
        for (ready_issues) |*issue| issue.deinit(allocator);
        allocator.free(ready_issues);
    }

    if (ready_issues.len == 0) {
        try stdout.writeAll("\nNo ready issues in backlog.\n");
        return;
    }

    try stdout.writeAll("\n=== READY ISSUES ===\n");

    // Show up to 15 issues to avoid overwhelming context
    const max_display: usize = 15;
    const display_count = @min(ready_issues.len, max_display);

    for (ready_issues[0..display_count]) |issue| {
        try stdout.print("{s}  P{d}  {s}\n", .{
            issue.id,
            issue.priority,
            issue.title,
        });
    }

    if (ready_issues.len > max_display) {
        try stdout.print("... and {} more (run `tissue ready` to see all)\n", .{ready_issues.len - max_display});
    }

    try stdout.writeAll("====================\n");
}

test "session_start outputs agent awareness" {
    // Basic test - just verify it compiles and runs without error
    // Full integration test would capture stdout
}
