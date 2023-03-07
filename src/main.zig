const std = @import("std");
// const cli = @import("zig-cli");

const queue = @import("queue.zig");

const print = std.debug.print;
const Allocator = std.mem.Allocator;

const Node = struct {
    symbol: ?u8,
    weight: usize,
    parent: ?*Node,
    left: ?*Node,
    right: ?*Node,
    visited: bool,
};

fn read_text_file(allocator: *const Allocator, filepath: []const u8) ![]const u8 {
    //
    // ALLOCATE TEXT FILE
    //
    var file = try std.fs.cwd().openFile(filepath, .{});
    defer file.close();
    const buffer = try allocator.alloc(u8, (try file.stat()).size);
    try file.reader().readNoEof(buffer);
    return buffer;
}

pub fn main() !void {
    print("doing compression\n", .{});
    const start_compression_time = std.time.microTimestamp();
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .enable_memory_limit = false,
        .safety = false
    }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    _ = args.skip();

    const filepath: []const u8 = args.next() orelse "res/nice.shakespeare.txt";

    // find file name
    var filename_index: usize = filepath.len - 1;
    while (filename_index > 0 and filepath[filename_index-1] != '/') {
        filename_index -= 1;
    }
    const filename: []const u8 = filepath[filename_index..];

    var text = try read_text_file(&allocator, filepath);

    // NOTE: Does this still free the full amount since I mutate it?
    defer allocator.free(text);

    // Reading seems to add an extra \n at end
    if (text.len > 0) text = text[0..text.len - 1];

    //
    // CONSTRUCT ARRAY OF SYMBOL FREQUENCIES
    //

    // array where index is the ascii char and value is number of occurences
    var occurences_book = [_]usize{0} ** 256;

    for (text) |c| {
        occurences_book[c] += 1;
    }

    //
    // SORT LETTER BOOK
    //

    // an array of ascii chars sorted from least to most frequent then
    // alphabetically, 0 occurence ascii chars at the end
    var sorted_letter_book = [_]u8{0} ** 256;

    // my naive custom sort, <256 passes, ~100 microseconds
    var book_index: u8 = 0;
    var min_value: usize = 1;
    var next_min_value: usize = undefined;
    while (next_min_value != std.math.maxInt(usize)) {
        next_min_value = std.math.maxInt(usize);
        for (occurences_book) |o, c| {
            if (o < next_min_value and o > min_value) {
                next_min_value = o;
            }
            // occurences is definitionally sorted in ASCII alphabetical order
            // so ties (1+ c's with same o) with be resolved alphabetically
            if (o == min_value) {
                sorted_letter_book[book_index] = @intCast(u8, c);
                if (book_index < 255) book_index += 1;
            }
        }
        min_value = next_min_value;
    }

    //
    // BUILD BINARY TREE
    //

    const symbols_length = book_index; // exclusive index

    // max amt of nodes is 256 leaves + 257 internal? not for huffman...?
    var nodes: [513]?Node = [_]?Node{null} ** 513;
    var nodes_index: u16 = 0;

    var leaf_queue = queue.Queue(*Node, 256){};
    var sapling_queue = queue.Queue(*Node, 256){};

    // add every letter as a leaf node to the leaf_queue
    for (sorted_letter_book[0..symbols_length]) |c, i| {
        nodes[i] = Node {
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
        var lowest_nodes: [2]*Node = [2]*Node{undefined,undefined};

        for (lowest_nodes) |_, i| {
            // this ones first because ties going to leaf queue is more optimal
            // for minimizing code length variance
            if (sapling_queue.count == 0) {
                lowest_nodes[i] = try leaf_queue.dequeue();
            } else if (leaf_queue.count == 0) {
                lowest_nodes[i] = try sapling_queue.dequeue();
            } else if (leaf_queue.get_front().weight <= sapling_queue.get_front().weight) {
                lowest_nodes[i] = try leaf_queue.dequeue();
            } else {
                lowest_nodes[i] = try sapling_queue.dequeue();
            }
        }

        nodes[nodes_index] = Node {
            .symbol = null,
            .weight = lowest_nodes[0].weight + lowest_nodes[1].weight,
            .parent = null,
            .left = lowest_nodes[0],
            .right = lowest_nodes[1],
            .visited = false,
        };
        var internal_parent = &nodes[nodes_index].?;
        nodes_index += 1;

        lowest_nodes[0].parent = internal_parent;
        lowest_nodes[1].parent = internal_parent;

        try sapling_queue.enqueue(internal_parent);
    }

    const root_node: *Node =
        if (leaf_queue.count > 0) try leaf_queue.dequeue()
        else try sapling_queue.dequeue();

    //
    // BUILD HUFFMAN TREE AND DICTIONARY
    //

    // index number is ascii char, value is huffman code
    const Code = struct {
        data: u32,
        length: u8,
    };

    var dictionary: [256]Code = [_]Code {Code{.data = 0, .length = 0}} ** 256;

    const HistoryNode = struct {
        node: *Node,
        path: Code,
    };

    var traversal_stack: [513]?HistoryNode = [_]?HistoryNode {null} ** 513;
    var traversal_stack_top: usize = 1;
    traversal_stack[0] = HistoryNode {
        .node = root_node,
        .path = Code {
            .data = 0,
            .length = 0,
        },
    };
    var traverser: HistoryNode = undefined;
    while (traversal_stack_top > 0) {
        traverser = traversal_stack[traversal_stack_top - 1].?;
        traversal_stack_top -= 1;

        if (traverser.node.right != null) {
            var new_traverser = HistoryNode {
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
            var new_traverser = HistoryNode {
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
             print("{c} - ", .{traverser.node.symbol orelse 0});
             var j: u8 = traverser.path.length;
             while (j > 0) : (j -= 1) {
                print("{b}", .{traverser.path.data >>
                @truncate(u4, j - 1) & 1});
             }
             print("\n", .{});
            dictionary[traverser.node.symbol orelse unreachable] = traverser.path;
        }
    }

    //
    // WRITE OUTPUT (COMPRESS)
    //
    const outfile_path: []const u8 = try std.fmt.allocPrint(
        allocator,
        "{s}.et",
        .{ filepath },
    );
    defer allocator.free(outfile_path);
    const outfile = try std.fs.cwd().createFile(
        outfile_path,
        .{ .read = true },
    );
    var out_writer = outfile.writer();
    defer outfile.close();

    // estimate for header length when every unique char is used
    const max_header_length: usize = 7200;
    var out_buffer = try allocator.alloc(u8, max_header_length + text.len);
    defer allocator.free(out_buffer);
    var out_buffer_out = std.io.fixedBufferStream(out_buffer);
    var bit_stream_writer = std.io.bitWriter(.Big, out_buffer_out.writer());

    var bits_written: usize = 0;

    // write magic number
    try bit_stream_writer.writeBits(@as(u24, 0xe7c0de), 24);
    bits_written += 24;

    // write dictionary length
    var dictionary_length: usize = 0; // dictionary length - 1
    for (dictionary) |code| {
        if (code.length > 0) dictionary_length += 1;
    }
    if (dictionary_length > 0) dictionary_length -= 1;
    try bit_stream_writer.writeBits(dictionary_length, 8);
    bits_written += 8;

    try bit_stream_writer.writeBits(@truncate(u32, text.len), 32);
    bits_written += 32;

    // write dictionary
    // write dictionary as:
    // | ascii value - u8 | length of code - u8 | code - n bits |
    for (dictionary) |code, i| {
        if (code.length > 0) {
            try bit_stream_writer.writeBits(i, 8);
            bits_written += 8;
            try bit_stream_writer.writeBits(code.length, 8);
            bits_written += 8;
            var j: usize = code.length;
            while (j > 0) : (j -= 1) {
                try bit_stream_writer.writeBits((code.data >> @truncate(u4, j - 1)) & 1, 1);
                bits_written += 1;
            }
        }
    }
    try bit_stream_writer.flushBits();
    // bits_written = bits_written + (8 - bits_written % 10);

    // write compressed bits
    for (text) |char| {
        var code = dictionary[char];
        var j: usize = code.length;
            while (j > 0) : (j -= 1) {
                try bit_stream_writer.writeBits((code.data >> @truncate(u4, j - 1)) & 1, 1);
                bits_written += 1;
            }
    }

    try bit_stream_writer.flushBits();
    // bits_written = bits_written + (8 - bits_written % 10);
    try out_writer.writeAll(out_buffer[0.. bits_written / 8 + 3]);
    //try out_writer.writeAll(out_buffer[0..]);

    print("\ntime taken: {d}μs\n", .{std.time.microTimestamp() - start_compression_time});

    //
    // READ FILE (DECOMPRESS)
    //
    const start_decompression_time = std.time.microTimestamp();
    defer print("\ntime taken: {d}μs\n", .{std.time.microTimestamp() - start_decompression_time});

    print("doing decompression\n", .{});

    var compressed_text = try read_text_file(&allocator, outfile_path);
    defer allocator.free(compressed_text);

    const decode_file_path: []const u8 = try std.fmt.allocPrint(
        allocator,
        "res/decoded_{s}",
        .{ filename },
    );
    defer allocator.free(decode_file_path);
    const decode_file = try std.fs.cwd().createFile(
        decode_file_path,
        .{ .read = true },
    );
    defer decode_file.close();

    var decode_writer = decode_file.writer();

    var reading_dict_letter: bool = true;
    var reading_dict_code_len: bool = false;
    var reading_dict_code: bool = false;

    var decode_dictionary_length: usize = compressed_text[3] + 1;

    var decode_body_length: u32 = compressed_text[4];
    decode_body_length <<= 8;
    decode_body_length |= compressed_text[5];
    decode_body_length <<= 8;
    decode_body_length |= compressed_text[6];
    decode_body_length <<= 8;
    decode_body_length |= compressed_text[7];

    var longest_code: u8 = 0;
    var shortest_code: usize = std.math.maxInt(usize);

    // value is an array of symbols of same integer value indexed by code length
    // (allows for distinguishing between 00 and 000 for example)
    var decode_table = std.AutoHashMap(usize, [32]u8).init(
        allocator,
    );
    defer decode_table.deinit();

    var current_letter: u8 = 0;
    var current_code_length: u8 = 0;
    var current_code_data: usize = 0;

    var global_pos: usize = 0;
    var pos: usize = 0;  // bit pos in byte
    var build_bits: usize = 0b0;
    var i: usize = 0; // bit pos in current read
    var letters_read: u8 = 0;
    for (compressed_text[8..]) |byte| {
        pos = 0;

        read: while (true) {
            if (reading_dict_letter) {
                while (i <= 7) {
                    if (pos > 7) break :read;
                    build_bits <<= 1;
                    build_bits |= (byte >> @truncate(u3, 7 - pos)) & 1;
                    pos += 1;
                    i += 1;
                }

                current_letter = @truncate(u8, build_bits);

                reading_dict_letter = false;
                reading_dict_code_len = true;

                build_bits = 0b0;
                i = 0;
            }

            if (reading_dict_code_len) {
                while (i <= 7) {
                    if (pos > 7) break :read;
                    build_bits <<= 1;
                    build_bits |= (byte >> @truncate(u3, 7 - pos)) & 1;
                    pos += 1;
                    i += 1;
                }

                current_code_length = @truncate(u8, build_bits);

                if (current_code_length > longest_code) longest_code = current_code_length;
                if (current_code_length < shortest_code) shortest_code = current_code_length;

                reading_dict_code_len = false;
                reading_dict_code = true;

                build_bits = 0b0;
                i = 0;
            }

            if (reading_dict_code) {
                while (i < current_code_length) {
                    if (pos > 7) break :read;
                    build_bits <<= 1;
                    build_bits |= (byte >> @truncate(u3, 7 - pos)) & 1;

                    pos += 1;
                    i += 1;
                }

                current_code_data = build_bits;

                // if table has code add another letter to entry orelse
                // add new entry with new letter
                var decode_entry = decode_table.get(current_code_data) orelse [_]u8{0} ** 32;
                decode_entry[current_code_length - 1] = current_letter;
                try decode_table.put(current_code_data, decode_entry);

                letters_read += 1;

                reading_dict_code = false;
                reading_dict_letter = true;

                build_bits = 0b0;
                i = 0;
            }
        }
        global_pos += 1;

        if (letters_read == decode_dictionary_length) {
            break;
        }
    }

    var window: u32 = 0;
    var window_len: usize = 0;
    var checking_code_len: usize = 2;
    var testing_code: usize = 0;
    var decoded_letters_read: usize = 0;

    for (compressed_text[8 + global_pos..]) |byte| {
        window <<= 8;
        window |= byte;
        window_len += 8;

        // while there are potential matches in window
        decode_text: while (window_len >= longest_code) {
            // loop through all possible code lengths, checking start of window for match
            checking_code_len = shortest_code;
            while (checking_code_len <= longest_code and window_len >= longest_code) {
                if (decoded_letters_read >= decode_body_length) {
                    break :decode_text;
                }

                if (window_len < checking_code_len) {
                     break :decode_text;
                }

                testing_code = window &
                    ((@as(u32, 0b1) << @truncate(u5, checking_code_len)) - 1)
                    << @truncate(u5, window_len - checking_code_len);


                testing_code >>= @truncate(u6, window_len - checking_code_len);

                if (decode_table.contains(testing_code) and
                  decode_table.get(testing_code).?[checking_code_len - 1] > 0) {
                    decoded_letters_read += 1;

                    var c = decode_table.get(testing_code).?[checking_code_len -
                    1];
                    try decode_writer.writeByte(c);
                    // print("{c}", .{c});

                    window = window & ((@as(u32, 0b1) <<
                        @truncate(u5, window_len - checking_code_len)) - 1);

                    window_len -= checking_code_len;

                    checking_code_len = shortest_code;
                }
                checking_code_len += 1;
            }
        }
    }
}
