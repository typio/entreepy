const std = @import("std");

const Queue = @import("queue.zig").Queue;
const print_progress = @import("progress_bar.zig").print_progress;
const format_file_size = @import("utils.zig").format_file_size;

const Allocator = std.mem.Allocator;

pub const EncodeFlags = packed struct {
    write_output: bool = false,
    print_output: bool = false,
    debug: bool = false,
    _padding: u30 = 0,
};

const Node = struct {
    symbol: ?u8,
    weight: usize,
    parent: ?*Node,
    left: ?*Node,
    right: ?*Node,
    visited: bool,
};

pub fn encode(allocator: Allocator, text: []const u8, out_writer: anytype, std_out: std.fs.File, flags: EncodeFlags) !usize {
    const start_time = std.time.microTimestamp();
    defer if (flags.debug) std_out.writer().print("time taken: {d}μs\n", .{std.time.microTimestamp() -
        start_time}) catch {};

    var encoding_progress: usize = 0;
    var encoding_state_msg: []const u8 = "Encoding file...";

    var print_progress_thread: ?std.Thread = null;
    // TODO: Make progress bar work with debug flag
    if (!flags.print_output and !flags.debug) {
        print_progress_thread = try std.Thread.spawn(.{}, print_progress, .{ 0, &encoding_progress, &encoding_state_msg });
    }

    encoding_progress = 10;
    encoding_state_msg = "Counting characters...";

    // array where index is the ascii char and value is number of occurences
    var occurences_book = [_]usize{0} ** 256;

    for (text) |c| {
        occurences_book[c] += 1;
    }

    encoding_progress = 20;
    encoding_state_msg = "Sorting characters...";

    // an array of ascii chars sorted from least to most frequent then
    // alphabetically, 0 occurence ascii chars at the end
    var sorted_letter_book = [_]u8{0} ** 256;

    // simple custom sort, <256 passes, ~100 microseconds
    var book_index: u8 = 0;
    var min_value: usize = 1;
    var next_min_value: usize = 0;
    while (next_min_value != std.math.maxInt(usize)) {
        next_min_value = std.math.maxInt(usize);
        for (occurences_book, 0..) |occurences, char_code| {
            if (occurences < next_min_value and occurences > min_value) {
                next_min_value = occurences;
            }
            // occurences is definitionally sorted in ASCII alphabetical order
            // so ties (different char_codes with same occurences) with be resolved alphabetically
            if (occurences == min_value) {
                sorted_letter_book[book_index] = @intCast(char_code);
                if (book_index < 255) book_index += 1;
            }
        }
        min_value = next_min_value;
    }

    encoding_progress = 25;
    encoding_state_msg = "Building code tree...";

    const symbols_length = book_index; // exclusive index

    // max amt of nodes is 256 leaves + 257 internal? not for huffman...?
    var nodes: [513]?Node = [_]?Node{null} ** 513;
    var nodes_index: u16 = 0;

    var leaf_queue = Queue(*Node, 256){};
    var sapling_queue = Queue(*Node, 256){};

    // add every letter as a leaf node to the leaf_queue
    for (sorted_letter_book[0..symbols_length], 0..) |c, i| {
        nodes[i] = Node{
            .symbol = c,
            .weight = occurences_book[c],
            .parent = null,
            .left = null,
            .right = null,
            .visited = false,
        };
        try leaf_queue.enqueue(&nodes[i].?);
    }
    nodes_index = symbols_length;

    while (leaf_queue.count + sapling_queue.count > 1) {
        // get 2 lowest nodes from either queue
        var lowest_nodes: [2]*Node = [2]*Node{ undefined, undefined };

        for (lowest_nodes, 0..) |_, i| {
            // this ones first because ties going to leaf queue is more optimal
            // for minimizing code length variance
            if (sapling_queue.count == 0) {
                lowest_nodes[i] = try leaf_queue.dequeue();
            } else if (leaf_queue.count == 0) {
                lowest_nodes[i] = try sapling_queue.dequeue();
            } else if (leaf_queue.peek().?.weight <= sapling_queue.peek().?.weight) {
                lowest_nodes[i] = try leaf_queue.dequeue();
            } else {
                lowest_nodes[i] = try sapling_queue.dequeue();
            }
        }

        nodes[nodes_index] = Node{
            .symbol = null,
            .weight = lowest_nodes[0].weight + lowest_nodes[1].weight,
            .parent = null,
            .left = lowest_nodes[0],
            .right = lowest_nodes[1],
            .visited = false,
        };
        const internal_parent = &nodes[nodes_index].?;
        nodes_index += 1;

        lowest_nodes[0].parent = internal_parent;
        lowest_nodes[1].parent = internal_parent;

        try sapling_queue.enqueue(internal_parent);
    }

    const root_node: *Node =
        if (leaf_queue.count > 0) try leaf_queue.dequeue() else try sapling_queue.dequeue();

    // index number is ascii char, value is huffman code
    const Code = struct {
        data: u32,
        length: u8,
    };

    var dictionary: [256]Code = [_]Code{Code{ .data = 0, .length = 0 }} ** 256;

    const HistoryNode = struct {
        node: *Node,
        path: Code,
    };

    encoding_progress = 30;
    encoding_state_msg = "Creating codes...";

    // clear progress bar if it's being printed ahead of printing codes
    // if (flags.debug and !flags.print_output) {
    //     try std_out.writer().print("\x1B[4F\x1B[4K", .{});
    // }

    var traversal_stack: [513]?HistoryNode = [_]?HistoryNode{null} ** 513;
    var traversal_stack_top: usize = 1;
    traversal_stack[0] = HistoryNode{
        .node = root_node,
        .path = Code{
            .data = 0,
            .length = 0,
        },
    };
    var traverser: HistoryNode = undefined;
    while (traversal_stack_top > 0) {
        traverser = traversal_stack[traversal_stack_top - 1].?;
        traversal_stack_top -= 1;

        if (traverser.node.right != null) {
            var new_traverser = HistoryNode{
                .node = traverser.node.right.?,
                .path = traverser.path,
            };

            new_traverser.path.data <<= 1;
            new_traverser.path.data |= 1;
            new_traverser.path.length += 1;

            traversal_stack[traversal_stack_top] = new_traverser;

            traversal_stack_top += 1;
        }

        if (traverser.node.left != null) {
            var new_traverser = HistoryNode{
                .node = traverser.node.left.?,
                .path = traverser.path,
            };
            new_traverser.path.data <<= 1;
            new_traverser.path.data |= 0;
            new_traverser.path.length += 1;

            traversal_stack[traversal_stack_top] = new_traverser;

            traversal_stack_top += 1;
        }

        if (traverser.node.right == null and traverser.node.left == null) {
            if (flags.debug) try std_out.writer().print("{c} {} - ", .{ traverser.node.symbol orelse 0, traverser.node.symbol orelse 0 });
            var j: u8 = traverser.path.length;
            while (j > 0) : (j -= 1) {
                if (flags.debug) try std_out.writer().print("{b}", .{traverser.path.data >>
                    @as(u5, @truncate(j - 1)) & 1});
            }
            if (flags.debug) try std_out.writer().print("\n", .{});
            dictionary[traverser.node.symbol orelse unreachable] = traverser.path;
        }
    }

    // if (flags.debug and !flags.print_output) {
    //     try std_out.writer().print("\n\n", .{});
    // }

    // debug check that there are no colliding prefixes
    if (flags.debug) {
        for (dictionary, 0..) |code_1, i| {
            for (dictionary, 0..) |code_2, j| {
                if (code_1.length == 0 or code_2.length == 0 or i == j) continue;

                var isPrefix = true;
                const shorter = @min(code_1.length, code_2.length);
                var k: usize = 0;

                while (k <= shorter) : (k += 1) {
                    const code_1_bit = (code_1.data >> @as(u5, @truncate(code_1.length - k))) & 1;
                    const code_2_bit = (code_2.data >> @as(u5, @truncate(code_2.length - k))) & 1;

                    if (code_1_bit != code_2_bit) {
                        isPrefix = false;
                        break;
                    }
                }

                if (isPrefix) {
                    const l_i = @as(u8, @truncate(i));
                    const l_j = @as(u8, @truncate(j));
                    try std_out.writer().print("Found colliding prefix codes for {} {c} and {} {c}", .{ l_i, l_i, l_j, l_j });
                }
            }
        }
    }

    encoding_progress = 35;
    encoding_state_msg = "Writing file header...";

    // estimate of header length when every unique char is used
    const max_header_length: usize = 7200;
    var out_buffer = try allocator.alloc(u8, max_header_length + text.len);
    defer allocator.free(out_buffer);
    var out_buffer_out = std.io.fixedBufferStream(out_buffer);
    var bit_stream_writer = std.io.bitWriter(.big, out_buffer_out.writer());

    var bits_written: usize = 0;

    // write magic number
    try bit_stream_writer.writeBits(@as(u24, 0xe7c0de), 24);
    bits_written += 24;

    // write format version
    try bit_stream_writer.writeBits(@as(u8, 0x01), 8);
    bits_written += 8;

    // write dictionary length
    var dictionary_length: usize = 0; // dictionary length - 1
    for (dictionary) |code| {
        if (code.length > 0) dictionary_length += 1;
    }
    if (dictionary_length > 0) dictionary_length -= 1;
    try bit_stream_writer.writeBits(dictionary_length, 8);
    bits_written += 8;

    // write body length
    try bit_stream_writer.writeBits(text.len, 32);
    bits_written += 32;

    // write dictionary
    // write dictionary as:
    // | ascii value - u8 | length of code - u8 | code - n bits |
    for (dictionary, 0..) |code, i| {
        if (code.length > 0) {
            try bit_stream_writer.writeBits(i, 8);
            bits_written += 8;
            try bit_stream_writer.writeBits(code.length, 8);
            bits_written += 8;
            var j: usize = code.length;
            while (j > 0) : (j -= 1) {
                try bit_stream_writer.writeBits((code.data >> @as(u5, @truncate(j - 1))) & 1, 1);
                bits_written += 1;
            }
        }
    }
    try bit_stream_writer.flushBits();
    bits_written = if (bits_written % 8 != 0) (bits_written / 8 + 1) * 8 else bits_written;

    encoding_progress = 40;
    encoding_state_msg = "Writing compressed text...";
    const writing_sections = 10;
    for (0..writing_sections) |i| {
        encoding_progress = 60 + (100 - 60) * i / writing_sections;
        // write compressed bits
        for (text[i * text.len / writing_sections .. (i + 1) * text.len / writing_sections]) |char| {
            const code = dictionary[char];
            var j: usize = code.length;
            while (j > 0) : (j -= 1) {
                try bit_stream_writer.writeBits((code.data >> @as(u5, @truncate(j - 1))) & 1, 1);
                bits_written += 1;
            }
        }
    }

    try bit_stream_writer.flushBits();
    bits_written = if (bits_written % 8 != 0) (bits_written / 8 + 1) * 8 else bits_written;
    if (flags.write_output) try out_writer.writeAll(out_buffer[0 .. bits_written / 8]);
    if (flags.debug) try std_out.writer().print("\nbits in output: {d}\n", .{bits_written});

    if (!flags.print_output and !flags.debug) {
        encoding_progress = 100;
        encoding_state_msg = "Done compressing!";
        print_progress_thread.?.join();
    }

    const formatted_original_size = format_file_size(allocator, @floatFromInt(text.len)) catch unreachable;
    defer allocator.free(formatted_original_size);

    const formatted_compressed_size = format_file_size(allocator, @floatFromInt(bits_written / 8)) catch unreachable;
    defer allocator.free(formatted_compressed_size);

    std.debug.print("{s} => {s}\n", .{ formatted_original_size, formatted_compressed_size });

    return bits_written / 8;
}
