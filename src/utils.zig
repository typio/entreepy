const std = @import("std");

pub fn format_file_size(allocator: std.mem.Allocator, byte_count: f32) ![]const u8 {
    if (byte_count < 1024) {
        return std.fmt.allocPrint(allocator, "{d} B", .{byte_count});
    } else if (byte_count < 1024 * 1024) {
        return std.fmt.allocPrint(allocator, "{d:.2} KB", .{byte_count / 1024});
    } else if (byte_count < 1024 * 1024 * 1024) {
        return std.fmt.allocPrint(allocator, "{d:.2} MB", .{byte_count / (1024 * 1024)});
    } else {
        return std.fmt.allocPrint(allocator, "{d:.2} GB", .{byte_count / (1024 * 1024 * 1024)});
    }
}
