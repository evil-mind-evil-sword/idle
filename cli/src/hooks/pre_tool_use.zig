const std = @import("std");
const idle = @import("idle");
const extractJsonString = idle.event_parser.extractString;

/// PreToolUse hook - safety guardrails for Bash commands
/// Blocks dangerous git/rm/database operations
pub fn run(allocator: std.mem.Allocator) !u8 {
    // Read hook input from stdin
    const stdin = std.fs.File.stdin();
    var buf: [65536]u8 = undefined;
    const n = try stdin.readAll(&buf);
    const input_json = buf[0..n];

    // Parse tool_name
    const tool_name = extractJsonString(input_json, "\"tool_name\"") orelse return 0;

    // Only check Bash commands
    if (!std.mem.eql(u8, tool_name, "Bash")) {
        return 0;
    }

    // Extract command from tool_input
    const command = extractNestedCommand(allocator, input_json) orelse return 0;
    defer allocator.free(command);

    // Check for dangerous patterns
    if (idle.safety.checkCommand(command)) |reason| {
        // Block the command
        var stdout_buf: [512]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
        const stdout = &stdout_writer.interface;
        try stdout.print("{{\"decision\":\"block\",\"reason\":\"SAFETY: {s}\"}}\n", .{reason});
        try stdout.flush();
        return 0; // Note: exit 0, decision is in JSON
    }

    // Allow silently (no output = allow)
    return 0;
}

/// Extract the command string from nested tool_input JSON
fn extractNestedCommand(allocator: std.mem.Allocator, json: []const u8) ?[]u8 {
    // Find "tool_input"
    const tool_input_pos = std.mem.indexOf(u8, json, "\"tool_input\"") orelse return null;
    const after_tool_input = json[tool_input_pos..];

    // Find the nested object start
    const obj_start = std.mem.indexOf(u8, after_tool_input, "{") orelse return null;
    const tool_input_json = after_tool_input[obj_start..];

    // Find "command" within tool_input
    const cmd_str = extractJsonString(tool_input_json, "\"command\"") orelse return null;

    // Allocate and return copy
    const result = allocator.alloc(u8, cmd_str.len) catch return null;
    @memcpy(result, cmd_str);
    return result;
}


test "extractNestedCommand: basic" {
    const json = "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git push --force main\"}}";
    const cmd = extractNestedCommand(std.testing.allocator, json);
    try std.testing.expect(cmd != null);
    defer std.testing.allocator.free(cmd.?);
    try std.testing.expectEqualStrings("git push --force main", cmd.?);
}
