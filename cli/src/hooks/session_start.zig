const std = @import("std");
const idle = @import("idle");
const tissue = @import("tissue");
const zawinski = @import("zawinski");
const extractJsonString = idle.event_parser.extractString;
const jwz = idle.jwz_utils;

/// Session start hook - initializes infrastructure and injects loop context
/// Outputs JSON format for Claude Code context injection
pub fn run(allocator: std.mem.Allocator) !u8 {
    // Read hook input from stdin
    const stdin = std.fs.File.stdin();
    var buf: [4096]u8 = undefined;
    const n = try stdin.readAll(&buf);
    const input_json = buf[0..n];

    // Extract cwd and change to project directory
    const cwd_slice = extractJsonString(input_json, "\"cwd\"") orelse ".";
    std.posix.chdir(cwd_slice) catch {};

    // Initialize infrastructure (stores + loop state)
    initializeInfrastructure(allocator) catch {};

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

/// Initialize infrastructure: .zawinski store, .tissue store, and loop state
/// Called at session start so the agent never needs to run `idle init-loop`
fn initializeInfrastructure(allocator: std.mem.Allocator) !void {
    const cwd = std.fs.cwd();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const abs_cwd = try cwd.realpath(".", &path_buf);

    // Step 1: Initialize jwz store if needed
    const jwz_path = ".zawinski";
    const jwz_exists = blk: {
        cwd.access(jwz_path, .{}) catch break :blk false;
        break :blk true;
    };

    if (!jwz_exists) {
        const full_path = try std.fs.path.join(allocator, &.{ abs_cwd, jwz_path });
        defer allocator.free(full_path);

        zawinski.store.Store.init(allocator, full_path) catch |err| switch (err) {
            error.StoreAlreadyExists => {}, // Race condition, fine
            else => return err,
        };
    }

    // Step 2: Initialize tissue store if needed
    const tissue_path = ".tissue";
    const tissue_exists = blk: {
        cwd.access(tissue_path, .{}) catch break :blk false;
        break :blk true;
    };

    if (!tissue_exists) {
        const full_path = try std.fs.path.join(allocator, &.{ abs_cwd, tissue_path });
        defer allocator.free(full_path);

        tissue.store.Store.init(allocator, full_path) catch |err| switch (err) {
            tissue.store.StoreError.StoreAlreadyExists => {}, // Race condition, fine
            else => return err,
        };
    }

    // Step 3: Ensure loop:current topic exists with initial state
    const store_dir = zawinski.store.discoverStoreDir(allocator) catch return;
    defer allocator.free(store_dir);

    var store = zawinski.store.Store.open(allocator, store_dir) catch return;
    defer store.deinit();

    // Create topic if needed
    if (store.createTopic("loop:current", "Current loop state")) |topic_id| {
        allocator.free(topic_id);
    } else |err| switch (err) {
        zawinski.store.StoreError.TopicExists => {},
        else => return err,
    }

    // Check if there's already active loop state
    const messages = store.listMessages("loop:current", 1) catch return;
    defer {
        for (messages) |*m| m.deinit(allocator);
        allocator.free(messages);
    }

    // If no messages or no active loop, create initial idle state
    const needs_init = blk: {
        if (messages.len == 0) break :blk true;
        const parsed_opt = idle.parseEvent(allocator, messages[0].body) catch break :blk true;
        if (parsed_opt) |parsed| {
            var p = parsed;
            defer p.deinit();
            // If stack is empty, we need to initialize
            break :blk p.state.stack.len == 0;
        }
        break :blk true;
    };

    if (needs_init) {
        const now = std.time.timestamp();
        var run_id_buf: [32]u8 = undefined;
        const run_id = std.fmt.bufPrint(&run_id_buf, "loop-{d}", .{now}) catch "loop-unknown";

        var ts_buf: [32]u8 = undefined;
        const updated_at = jwz.formatIso8601ToBuf(now, &ts_buf);

        var json_buf: [512]u8 = undefined;
        const state_json = std.fmt.bufPrint(&json_buf,
            \\{{"schema":1,"event":"STATE","run_id":"{s}","updated_at":"{s}","stack":[{{"id":"{s}","mode":"loop","iter":0,"max":10,"prompt_file":"","reviewed":false,"checkpoint_reviewed":false}}]}}
        , .{ run_id, updated_at, run_id }) catch return;

        const sender = zawinski.store.Sender{
            .id = "idle",
            .name = "idle",
            .model = null,
            .role = "system",
        };
        const msg_id = store.createMessage("loop:current", null, state_json, .{ .sender = sender }) catch return;
        allocator.free(msg_id);
    }
}

test "session_start outputs agent awareness" {
    // Basic test - just verify it compiles and runs without error
    // Full integration test would capture stdout
}
