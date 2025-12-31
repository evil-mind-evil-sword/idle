const std = @import("std");
const tissue = @import("tissue");

/// Format an issue for display
pub fn formatIssue(allocator: std.mem.Allocator, issue: *const tissue.store.Issue) ![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(allocator);
    const writer = buf.writer(allocator);

    try writer.print("ID: {s}\n", .{issue.id});
    try writer.print("Title: {s}\n", .{issue.title});
    try writer.print("Status: {s}\n", .{issue.status});
    try writer.print("Priority: {d}\n", .{issue.priority});

    if (issue.tags.len > 0) {
        try writer.writeAll("Tags: ");
        for (issue.tags, 0..) |tag, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.writeAll(tag);
        }
        try writer.writeByte('\n');
    }

    if (issue.body.len > 0) {
        try writer.writeAll("\n");
        try writer.writeAll(issue.body);
        try writer.writeByte('\n');
    }

    return buf.toOwnedSlice(allocator);
}
