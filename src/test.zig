const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .enable_memory_limit = true, .safety = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    _ = allocator;

    var file_dir = std.fs.path.dirname("./main.zig") orelse unreachable;
    std.debug.print("{s}", .{file_dir});
}
