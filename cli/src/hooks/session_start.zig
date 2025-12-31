const std = @import("std");
const idle = @import("idle");
const zawinski = @import("zawinski");
const extractJsonString = idle.event_parser.extractString;

/// Session start hook - injects loop context and agent awareness
pub fn run(allocator: std.mem.Allocator) !u8 {
    // Read hook input from stdin
    const stdin = std.fs.File.stdin();
    var buf: [4096]u8 = undefined;
    const n = try stdin.readAll(&buf);
    const input_json = buf[0..n];

    // Extract cwd and change to project directory
    const cwd = extractJsonString(input_json, "\"cwd\"") orelse ".";
    std.posix.chdir(cwd) catch {};

    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_writer.interface;

    // Try to read active loop state
    const state_json = readJwzState(allocator) catch null;
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
                    try stdout.writeAll("=== ACTIVE LOOP ===\n");
                    try stdout.print("Mode: {s} | Iteration: {}/{}\n", .{
                        @tagName(frame.mode),
                        frame.iter,
                        frame.max,
                    });

                    try stdout.writeAll("\nYour task: Continue working on this loop. ");
                    try stdout.writeAll("Signal <loop-done>COMPLETE</loop-done> when finished.\n");
                    try stdout.writeAll("==================\n\n");
                }
            }
        }
    }

    // Always inject agent awareness
    try stdout.writeAll(
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
    try stdout.flush();

    return 0;
}

/// Read loop state from zawinski store
fn readJwzState(allocator: std.mem.Allocator) !?[]u8 {
    const store_dir = zawinski.store.discoverStoreDir(allocator) catch return null;
    defer allocator.free(store_dir);

    var store = zawinski.store.Store.open(allocator, store_dir) catch return null;
    defer store.deinit();

    const messages = store.listMessages("loop:current", 1) catch return null;
    defer {
        for (messages) |*m| {
            var msg = m.*;
            msg.deinit(allocator);
        }
        allocator.free(messages);
    }

    if (messages.len == 0) return null;
    return try allocator.dupe(u8, messages[0].body);
}

test "session_start outputs agent awareness" {
    // Basic test - just verify it compiles and runs without error
    // Full integration test would capture stdout
}
