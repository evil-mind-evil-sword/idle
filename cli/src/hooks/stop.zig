const std = @import("std");
const idle = @import("idle");
const zawinski = @import("zawinski");
const extractJsonString = idle.event_parser.extractString;

/// Stop hook - core loop mechanism
/// Implements the self-referential loop via zawinski messaging
pub fn run(allocator: std.mem.Allocator) !u8 {
    // Read hook input from stdin
    const stdin = std.fs.File.stdin();
    var buf: [65536]u8 = undefined;
    const n = try stdin.readAll(&buf);
    const input_json = buf[0..n];

    // Extract fields
    const transcript_path = extractJsonString(input_json, "\"transcript_path\"");
    const session_id = extractJsonString(input_json, "\"session_id\"");
    const cwd = extractJsonString(input_json, "\"cwd\"") orelse ".";

    // Change to project directory
    std.posix.chdir(cwd) catch {};

    // Sync transcript to zawinski (always, regardless of loop state)
    if (transcript_path != null and session_id != null) {
        syncTranscript(allocator, transcript_path.?, session_id.?, cwd);
    }

    // Check file-based escape hatch
    if (std.fs.cwd().access(".idle-disabled", .{})) |_| {
        return 0; // Escape hatch active
    } else |_| {}

    // Read loop state from jwz (shell out for now)
    const state_json = try readJwzState(allocator);
    defer if (state_json) |s| allocator.free(s);

    if (state_json == null or state_json.?.len == 0) {
        return 0; // No loop active
    }

    // Parse state
    var parsed = idle.parseEvent(allocator, state_json.?) catch return 0;
    defer if (parsed) |*p| p.deinit();

    if (parsed == null) {
        return 0;
    }

    const state = &parsed.?.state;

    // Check for ABORT event
    if (state.event == .ABORT) {
        return 0;
    }

    // Check empty stack
    if (state.stack.len == 0) {
        return 0;
    }

    // Get current time
    const now_ts = std.time.timestamp();

    // Detect completion signal from transcript
    var completion_signal: ?idle.CompletionReason = null;
    const frame = &state.stack[state.stack.len - 1];

    if (transcript_path) |path| {
        const text = idle.transcript.extractLastAssistantText(allocator, path) catch null;
        defer if (text) |t| allocator.free(t);

        if (text) |t| {
            completion_signal = idle.StateMachine.detectCompletionSignal(frame.mode, t);
        }
    }

    // Evaluate state machine
    var machine = idle.StateMachine.init(allocator);
    const result = machine.evaluate(state, now_ts, completion_signal);

    // Handle result
    switch (result.decision) {
        .allow_exit => {
            // Check if this is a completion signal that needs alice review
            if (result.completion_reason) |reason| {
                // Only trigger alice review for COMPLETE or STUCK signals, and only if not already reviewed
                const needs_review = (reason == .COMPLETE or reason == .STUCK) and !frame.reviewed;

                if (needs_review) {
                    // Block exit and request alice review
                    const ts = formatIso8601(now_ts);

                    // Build state with reviewed = true
                    var state_buf: [2048]u8 = undefined;
                    var state_len = (std.fmt.bufPrint(&state_buf,
                        \\{{"schema":1,"event":"STATE","run_id":"{s}","updated_at":"{s}","stack":[{{"id":"{s}","mode":"{s}","iter":{},"max":{},"prompt_file":"{s}","reviewed":true
                    , .{
                        state.run_id,
                        &ts,
                        frame.id,
                        @tagName(frame.mode),
                        frame.iter,
                        frame.max,
                        frame.prompt_file,
                    }) catch return 0).len;

                    // Add optional fields
                    if (frame.issue_id) |id| {
                        state_len += (std.fmt.bufPrint(state_buf[state_len..],
                            ",\"issue_id\":\"{s}\"", .{id}) catch return 0).len;
                    }
                    if (frame.worktree_path) |path| {
                        state_len += (std.fmt.bufPrint(state_buf[state_len..],
                            ",\"worktree_path\":\"{s}\"", .{path}) catch return 0).len;
                    }
                    if (frame.branch) |branch| {
                        state_len += (std.fmt.bufPrint(state_buf[state_len..],
                            ",\"branch\":\"{s}\"", .{branch}) catch return 0).len;
                    }
                    if (frame.base_ref) |base_ref| {
                        state_len += (std.fmt.bufPrint(state_buf[state_len..],
                            ",\"base_ref\":\"{s}\"", .{base_ref}) catch return 0).len;
                    }
                    state_len += (std.fmt.bufPrint(state_buf[state_len..], "}}]}}", .{}) catch return 0).len;

                    try postJwzMessage(allocator, "loop:current", state_buf[0..state_len]);

                    // Build alice review instruction
                    const reason_str = @tagName(reason);
                    var reason_buf: [8192]u8 = undefined;
                    const reason_len = (std.fmt.bufPrint(&reason_buf,
                        \\[REVIEW REQUIRED] You signaled {s}. Before completing, invoke the alice agent to review your work.
                        \\
                        \\Use the Task tool with subagent_type="idle:alice" to request adversarial review. Alice will:
                        \\1. Systematically verify your implementation using domain-specific checklists
                        \\2. Create tissue issues (tagged `alice-review`) for each problem found
                        \\3. Get second opinions from Codex/Gemini on critical findings
                        \\4. Give verdict: APPROVE (no issues) or NEEDS_WORK (issues created)
                        \\
                        \\After alice's review:
                        \\- If APPROVE: Signal completion again
                        \\- If NEEDS_WORK: Address each issue in `tissue list -t alice-review --status open`
                        \\  - Fix the issue
                        \\  - Close it: `tissue status <id> closed`
                        \\  - Repeat until all alice-review issues are closed
                        \\  - Signal completion again for re-review
                        \\
                        \\Alice will re-review and verify each fix. Loop continues until alice approves.
                    , .{reason_str}) catch return 0).len;

                    // Output block decision
                    var stdout_buf: [8192]u8 = undefined;
                    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
                    const stdout = &stdout_writer.interface;

                    var escaped_buf: [8192]u8 = undefined;
                    const escaped = escapeJson(reason_buf[0..reason_len], &escaped_buf);

                    try stdout.print("{{\"decision\":\"block\",\"reason\":\"{s}\"}}\n", .{escaped});
                    try stdout.flush();

                    return 2; // Block exit for review
                }

                // Already reviewed or doesn't need review - proceed with exit
                if (reason == .COMPLETE and frame.mode == .issue) {
                    if (frame.worktree_path) |wt_path| {
                        if (frame.branch) |branch| {
                            if (frame.issue_id) |issue_id| {
                                const base_ref = frame.base_ref orelse "main";
                                _ = idle.autoland.autoLand(allocator, issue_id, wt_path, branch, base_ref);
                            }
                        }
                    }
                }

                // Post completion state
                const reason_str = @tagName(reason);
                var done_buf: [256]u8 = undefined;
                const done_json = std.fmt.bufPrint(&done_buf,
                    \\{{"schema":1,"event":"DONE","reason":"{s}","stack":[]}}
                , .{reason_str}) catch return 0;

                try postJwzMessage(allocator, "loop:current", done_json);
            }
            return 0;
        },
        .block_exit => {
            // Update iteration
            const new_iter = result.new_iteration orelse frame.iter + 1;

            // Build continuation message
            var reason_buf: [4096]u8 = undefined;
            var reason_len: usize = 0;

            reason_len += (std.fmt.bufPrint(reason_buf[reason_len..],
                "[ITERATION {}/{}] Continue working on the task. Check your progress and either complete the task or keep iterating.", .{ new_iter, frame.max }) catch return 0).len;

            // Add worktree context if available
            if (frame.worktree_path) |wt_path| {
                reason_len += (std.fmt.bufPrint(reason_buf[reason_len..],
                    "\n\nWORKTREE CONTEXT:\n- Working directory: {s}", .{wt_path}) catch return 0).len;

                if (frame.branch) |branch| {
                    reason_len += (std.fmt.bufPrint(reason_buf[reason_len..],
                        "\n- Branch: {s}", .{branch}) catch return 0).len;
                }
                if (frame.issue_id) |issue_id| {
                    reason_len += (std.fmt.bufPrint(reason_buf[reason_len..],
                        "\n- Issue: {s}", .{issue_id}) catch return 0).len;
                }

                reason_len += (std.fmt.bufPrint(reason_buf[reason_len..],
                    "\n\nIMPORTANT: All file operations must use absolute paths under {s}", .{wt_path}) catch return 0).len;
            }

            // Update state with new iteration (reset reviewed to false since new work will be done)
            var state_buf: [2048]u8 = undefined;
            const ts = formatIso8601(now_ts);
            var state_len = (std.fmt.bufPrint(&state_buf,
                \\{{"schema":1,"event":"STATE","run_id":"{s}","updated_at":"{s}","stack":[{{"id":"{s}","mode":"{s}","iter":{},"max":{},"prompt_file":"{s}","reviewed":false
            , .{
                state.run_id,
                &ts,
                frame.id,
                @tagName(frame.mode),
                new_iter,
                frame.max,
                frame.prompt_file,
            }) catch return 0).len;

            // Add optional fields
            if (frame.issue_id) |id| {
                state_len += (std.fmt.bufPrint(state_buf[state_len..],
                    ",\"issue_id\":\"{s}\"", .{id}) catch return 0).len;
            }
            if (frame.worktree_path) |path| {
                state_len += (std.fmt.bufPrint(state_buf[state_len..],
                    ",\"worktree_path\":\"{s}\"", .{path}) catch return 0).len;
            }
            if (frame.branch) |branch| {
                state_len += (std.fmt.bufPrint(state_buf[state_len..],
                    ",\"branch\":\"{s}\"", .{branch}) catch return 0).len;
            }
            if (frame.base_ref) |base_ref| {
                state_len += (std.fmt.bufPrint(state_buf[state_len..],
                    ",\"base_ref\":\"{s}\"", .{base_ref}) catch return 0).len;
            }
            state_len += (std.fmt.bufPrint(state_buf[state_len..], "}}]}}", .{}) catch return 0).len;

            try postJwzMessage(allocator, "loop:current", state_buf[0..state_len]);

            // Output block decision
            var stdout_buf: [8192]u8 = undefined;
            var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
            const stdout = &stdout_writer.interface;

            // Escape reason for JSON
            var escaped_buf: [8192]u8 = undefined;
            const escaped = escapeJson(reason_buf[0..reason_len], &escaped_buf);

            try stdout.print("{{\"decision\":\"block\",\"reason\":\"{s}\"}}\n", .{escaped});
            try stdout.flush();

            return 2; // Block exit
        },
    }
}

/// Read loop state from zawinski store directly
fn readJwzState(allocator: std.mem.Allocator) !?[]u8 {
    // Discover and open the store
    const store_dir = zawinski.store.discoverStoreDir(allocator) catch return null;
    defer allocator.free(store_dir);

    var store = zawinski.store.Store.open(allocator, store_dir) catch return null;
    defer store.deinit();

    // Get the latest message from loop:current topic (limit 1, ordered by created_at DESC)
    const messages = store.listMessages("loop:current", 1) catch return null;
    defer {
        for (messages) |*m| {
            var msg = m.*;
            msg.deinit(allocator);
        }
        allocator.free(messages);
    }

    if (messages.len == 0) return null;

    // Return a copy of the body
    const body = try allocator.dupe(u8, messages[0].body);
    return body;
}

/// Sync Claude transcript to zawinski store
fn syncTranscript(allocator: std.mem.Allocator, transcript_path: []const u8, session_id: []const u8, project_path: []const u8) void {
    // Discover and open the store
    const store_dir = zawinski.store.discoverStoreDir(allocator) catch return;
    defer allocator.free(store_dir);

    var store = zawinski.store.Store.open(allocator, store_dir) catch return;
    defer store.deinit();

    // Sync transcript entries to SQLite
    _ = store.syncTranscript(transcript_path, session_id, project_path) catch return;
}

/// Post message to zawinski store directly
fn postJwzMessage(allocator: std.mem.Allocator, topic: []const u8, message: []const u8) !void {
    // Discover and open the store
    const store_dir = zawinski.store.discoverStoreDir(allocator) catch return error.StoreNotFound;
    defer allocator.free(store_dir);

    var store = zawinski.store.Store.open(allocator, store_dir) catch return error.StoreOpenFailed;
    defer store.deinit();

    // Ensure topic exists (create if needed)
    _ = store.fetchTopic(topic) catch |err| {
        if (err == zawinski.store.StoreError.TopicNotFound) {
            const topic_id = store.createTopic(topic, "") catch return error.TopicCreateFailed;
            allocator.free(topic_id);
        } else {
            return error.TopicFetchFailed;
        }
    };

    // Create sender identity
    const sender = zawinski.store.Sender{
        .id = "idle",
        .name = "idle",
        .model = null,
        .role = "loop",
    };

    // Post the message
    const msg_id = try store.createMessage(topic, null, message, .{ .sender = sender });
    allocator.free(msg_id);
}

/// Format Unix timestamp as ISO 8601
fn formatIso8601(ts: i64) [20]u8 {
    const epoch_secs: std.time.epoch.EpochSeconds = .{ .secs = @intCast(ts) };
    const day_secs = epoch_secs.getDaySeconds();
    const year_day = epoch_secs.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    var buf: [20]u8 = undefined;
    _ = std.fmt.bufPrint(&buf, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
        year_day.year,
        month_day.month.numeric(),
        month_day.day_index + 1, // day_index is 0-based, ISO 8601 uses 1-based
        day_secs.getHoursIntoDay(),
        day_secs.getMinutesIntoHour(),
        day_secs.getSecondsIntoMinute(),
    }) catch unreachable;
    return buf;
}

/// Escape string for JSON
fn escapeJson(input: []const u8, output: []u8) []const u8 {
    var out_pos: usize = 0;
    for (input) |c| {
        switch (c) {
            '"' => {
                if (out_pos + 2 > output.len) break;
                output[out_pos] = '\\';
                output[out_pos + 1] = '"';
                out_pos += 2;
            },
            '\\' => {
                if (out_pos + 2 > output.len) break;
                output[out_pos] = '\\';
                output[out_pos + 1] = '\\';
                out_pos += 2;
            },
            '\n' => {
                if (out_pos + 2 > output.len) break;
                output[out_pos] = '\\';
                output[out_pos + 1] = 'n';
                out_pos += 2;
            },
            '\r' => {
                if (out_pos + 2 > output.len) break;
                output[out_pos] = '\\';
                output[out_pos + 1] = 'r';
                out_pos += 2;
            },
            '\t' => {
                if (out_pos + 2 > output.len) break;
                output[out_pos] = '\\';
                output[out_pos + 1] = 't';
                out_pos += 2;
            },
            else => {
                if (out_pos >= output.len) break;
                output[out_pos] = c;
                out_pos += 1;
            },
        }
    }
    return output[0..out_pos];
}


test "escapeJson: basic" {
    var buf: [100]u8 = undefined;
    const result = escapeJson("hello\nworld", &buf);
    try std.testing.expectEqualStrings("hello\\nworld", result);
}

test "escapeJson: quotes" {
    var buf: [100]u8 = undefined;
    const result = escapeJson("say \"hello\"", &buf);
    try std.testing.expectEqualStrings("say \\\"hello\\\"", result);
}
