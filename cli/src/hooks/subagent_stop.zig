const std = @import("std");
const idle = @import("idle");
const extractJsonString = idle.event_parser.extractString;

/// SubagentStop hook - enforce second opinion requirement for alice
pub fn run(allocator: std.mem.Allocator) !u8 {
    // Read hook input from stdin
    const stdin = std.fs.File.stdin();
    var buf: [65536]u8 = undefined;
    const n = try stdin.readAll(&buf);
    const input_json = buf[0..n];

    // Extract transcript path
    const transcript_path = extractJsonString(input_json, "\"agent_transcript_path\"") orelse {
        return 0; // No transcript, can't check
    };

    // Extract cwd and change to it
    if (extractJsonString(input_json, "\"cwd\"")) |cwd| {
        std.posix.chdir(cwd) catch {};
    }

    // Read last assistant message from transcript
    const last_text = idle.transcript.extractLastAssistantText(allocator, transcript_path) catch |err| {
        if (err == error.FileNotFound) return 0;
        return err;
    } orelse return 0;
    defer allocator.free(last_text);

    // Check if this is alice output
    if (!idle.transcript.isAliceOutput(last_text)) {
        return 0; // Not alice, allow completion
    }

    // Check for second opinion invocation in transcript
    const has_invocation = idle.transcript.hasSecondOpinionInvocation(transcript_path) catch false;
    if (!has_invocation) {
        return blockWithReason();
    }

    // Check for second opinion section with content
    if (!idle.transcript.hasSecondOpinion(last_text)) {
        return blockWithReason();
    }

    // Second opinion obtained, allow completion
    return 0;
}

fn blockWithReason() !u8 {
    var stderr_buf: [2048]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    const stderr = &stderr_writer.interface;

    try stderr.writeAll(
        \\[SUBAGENT GATE] Analysis incomplete - second opinion required.
        \\
        \\You MUST consult another model before completing the analysis:
        \\
        \\1. Run the second opinion command:
        \\   ```bash
        \\   $SECOND_OPINION "You are helping debug/design a software project.
        \\
        \\   Problem: [DESCRIBE THE PROBLEM]
        \\
        \\   My hypotheses (ranked):
        \\   1. [Most likely]
        \\   2. [Alternative]
        \\
        \\   Relevant code: [PASTE KEY SNIPPETS]
        \\
        \\   Do you agree? What would you add?
        \\
        \\   ---
        \\   End with:
        \\   ---SUMMARY---
        \\   [Your final analysis]
        \\   " > "$STATE_DIR/opinion-1.log" 2>&1
        \\   sed -n '/---SUMMARY---/,$ p' "$STATE_DIR/opinion-1.log"
        \\   ```
        \\
        \\2. Read and integrate their findings into your ## Second Opinion section
        \\
        \\3. Reconcile any disagreements
        \\
        \\4. Then emit your final recommendation
        \\
        \\DO NOT skip the second opinion - single-model analysis has blind spots.
        \\
    );
    try stderr.flush();

    return 2; // Block exit
}

