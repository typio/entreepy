const std = @import("std");
const testing = std.testing;

const encode = @import("encode.zig").encode;
const decode = @import("decode.zig").decode;

fn round_trip(text_in: []const u8) ![]const u8 {
    const stderr = std.io.getStdErr();

    const encoded_buffer: []u8 = try testing.allocator.alloc(u8, text_in.len * 2);
    defer testing.allocator.free(encoded_buffer);
    var encoded_stream = std.io.fixedBufferStream(encoded_buffer);
    const encoded_writer = encoded_stream.writer();

    const encoded_len = try encode(testing.allocator, text_in, encoded_writer, stderr, .{ .write_output = true, .print_output = false, .debug = false });

    const msg = try std.fmt.allocPrint(testing.allocator, "bits encoded {}", .{encoded_len});
    try stderr.writeAll(msg);
    testing.allocator.free(msg);

    const decoded_buffer: []u8 = try testing.allocator.alloc(u8, text_in.len * 2);
    defer testing.allocator.free(decoded_buffer);
    var decoded_stream = std.io.fixedBufferStream(decoded_buffer);
    const decoded_writer = decoded_stream.writer();

    const decoded_len = try decode(testing.allocator, encoded_buffer[0..encoded_len], decoded_writer, stderr, .{ .write_output = true, .print_output = false, .debug = false });

    const msg2 = try std.fmt.allocPrint(testing.allocator, "\ndecoded buffer: {s}", .{decoded_buffer[0..decoded_len]});
    try stderr.writeAll(msg2);
    testing.allocator.free(msg2);

    return try testing.allocator.dupe(u8, decoded_buffer[0..decoded_len]);
}

test "round trip basic" {
    var file = try std.fs.cwd().openFile("res/test.txt", .{});
    defer file.close();
    const text_in = try testing.allocator.alloc(u8, (try file.stat()).size);
    try file.reader().readNoEof(text_in);
    defer testing.allocator.free(text_in);

    const text_out = try round_trip(text_in);
    defer testing.allocator.free(text_out);

    try testing.expectEqualStrings(text_in, text_out);
}

test "round trip soliloquy" {
    var file = try std.fs.cwd().openFile("res/nice.shakespeare.txt", .{});
    defer file.close();
    const text_in = try testing.allocator.alloc(u8, (try file.stat()).size);
    try file.reader().readNoEof(text_in);
    defer testing.allocator.free(text_in);

    const text_out = try round_trip(text_in);
    defer testing.allocator.free(text_out);

    try testing.expectEqualStrings(text_in, text_out);
}

test "round trip play" {
    var file = try std.fs.cwd().openFile("res/a_midsummer_nights_dream.txt", .{});
    defer file.close();
    const text_in = try testing.allocator.alloc(u8, (try file.stat()).size);
    try file.reader().readNoEof(text_in);
    defer testing.allocator.free(text_in);

    const text_out = try round_trip(text_in);
    defer testing.allocator.free(text_out);

    try testing.expectEqualStrings(text_in, text_out);
}

test "queue" {
    _ = @import("queue.zig");
}
