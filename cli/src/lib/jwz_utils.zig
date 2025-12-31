// Shared utilities for zawinski (jwz) store operations
//
// Consolidates common functions used across hooks to avoid duplication.

const std = @import("std");
const zawinski = @import("zawinski");

/// Read loop state from zawinski store
/// Returns the body of the latest message in loop:current topic, or null if none
pub fn readJwzState(allocator: std.mem.Allocator) !?[]u8 {
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

/// Post message to zawinski store
/// Creates topic if it doesn't exist
pub fn postJwzMessage(allocator: std.mem.Allocator, topic: []const u8, message: []const u8) !void {
    const store_dir = zawinski.store.discoverStoreDir(allocator) catch return error.StoreNotFound;
    defer allocator.free(store_dir);

    var store = zawinski.store.Store.open(allocator, store_dir) catch return error.StoreOpenFailed;
    defer store.deinit();

    // Ensure topic exists (create if needed)
    if (store.fetchTopic(topic)) |*fetched_topic| {
        // Topic exists, free the allocated strings to avoid leak
        var t = fetched_topic.*;
        t.deinit(allocator);
    } else |err| {
        if (err == zawinski.store.StoreError.TopicNotFound) {
            const topic_id = store.createTopic(topic, "") catch return error.TopicCreateFailed;
            allocator.free(topic_id);
        } else {
            return error.TopicFetchFailed;
        }
    }

    const sender = zawinski.store.Sender{
        .id = "idle",
        .name = "idle",
        .model = null,
        .role = "loop",
    };

    const msg_id = try store.createMessage(topic, null, message, .{ .sender = sender });
    allocator.free(msg_id);
}

/// Sync Claude transcript to zawinski store
pub fn syncTranscript(allocator: std.mem.Allocator, transcript_path: []const u8, session_id: []const u8, project_path: []const u8) void {
    const store_dir = zawinski.store.discoverStoreDir(allocator) catch return;
    defer allocator.free(store_dir);

    var store = zawinski.store.Store.open(allocator, store_dir) catch return;
    defer store.deinit();

    _ = store.syncTranscript(transcript_path, session_id, project_path) catch return;
}

/// Format Unix timestamp as ISO 8601 (returns fixed 20-byte array)
pub fn formatIso8601(ts: i64) [20]u8 {
    // Guard against negative timestamps
    if (ts < 0) {
        return "1970-01-01T00:00:00Z".*;
    }

    const epoch_secs: std.time.epoch.EpochSeconds = .{ .secs = @intCast(ts) };
    const day_secs = epoch_secs.getDaySeconds();
    const year_day = epoch_secs.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();

    var buf: [20]u8 = undefined;
    _ = std.fmt.bufPrint(&buf, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
        year_day.year,
        month_day.month.numeric(),
        month_day.day_index + 1,
        day_secs.getHoursIntoDay(),
        day_secs.getMinutesIntoHour(),
        day_secs.getSecondsIntoMinute(),
    }) catch return "1970-01-01T00:00:00Z".*;

    return buf;
}

/// Format Unix timestamp as ISO 8601 into provided buffer
pub fn formatIso8601ToBuf(ts: i64, buf: []u8) []const u8 {
    if (ts < 0 or buf.len < 20) {
        if (buf.len >= 20) {
            @memcpy(buf[0..20], "1970-01-01T00:00:00Z");
            return buf[0..20];
        }
        return "1970-01-01T00:00:00Z";
    }

    const epoch_secs: std.time.epoch.EpochSeconds = .{ .secs = @intCast(ts) };
    const day_secs = epoch_secs.getDaySeconds();
    const year_day = epoch_secs.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();

    return std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
        year_day.year,
        month_day.month.numeric(),
        month_day.day_index + 1,
        day_secs.getHoursIntoDay(),
        day_secs.getMinutesIntoHour(),
        day_secs.getSecondsIntoMinute(),
    }) catch "1970-01-01T00:00:00Z";
}

/// Escape string for JSON output (to fixed buffer)
pub fn escapeJson(input: []const u8, output: []u8) []const u8 {
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

/// Write JSON-escaped string to a writer
pub fn writeJsonEscaped(writer: anytype, input: []const u8) !void {
    for (input) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => try writer.writeByte(c),
        }
    }
}

// ============================================================================
// Tests
// ============================================================================

test "formatIso8601 basic" {
    const result = formatIso8601(0);
    try std.testing.expectEqualStrings("1970-01-01T00:00:00Z", &result);
}

test "formatIso8601 negative returns epoch" {
    const result = formatIso8601(-100);
    try std.testing.expectEqualStrings("1970-01-01T00:00:00Z", &result);
}

test "escapeJson basic" {
    var buf: [100]u8 = undefined;
    const result = escapeJson("hello\nworld", &buf);
    try std.testing.expectEqualStrings("hello\\nworld", result);
}

test "escapeJson quotes" {
    var buf: [100]u8 = undefined;
    const result = escapeJson("say \"hi\"", &buf);
    try std.testing.expectEqualStrings("say \\\"hi\\\"", result);
}
