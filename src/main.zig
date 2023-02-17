const std = @import("std");
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

    var leaf_queue = Queue(*Node, 256){};
    var sapling_queue = Queue(*Node, 256){};

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
        data: [12] u1,
        length: u8,
    };

    var dictionary: [256]Code = [_]Code {Code{.data = [_]u1 {0} ** 12, .length = 0}} ** 256;

    const HistoryNode = struct {
        node: *Node,
        path: Code,
    };

    var traversal_stack: [513]?HistoryNode = [_]?HistoryNode {null} ** 513;
    var traversal_stack_top: usize = 1;
    traversal_stack[0] = HistoryNode {
        .node = root_node,
        .path = Code {
            .data = [_]u1{0} ** 12,
            .length = 0,
        },
    };
    var traverser: HistoryNode = undefined;
    while (traversal_stack_top > 0) {
        traverser = traversal_stack[traversal_stack_top - 1].?;
        traversal_stack_top -= 1;

        if (traverser.node.right != null) {
            // const new_path: usize = (traverser.path << 1) | 1;

            var new_traverser = HistoryNode {
                .node = traverser.node.right.?,
                .path = traverser.path,
            };
            new_traverser.path.data[traverser.path.length] = 0b1;
            new_traverser.path.length += 1;

            traversal_stack[traversal_stack_top] = new_traverser;

            traversal_stack_top += 1;
        }

        if (traverser.node.left != null) {
            var new_traverser = HistoryNode {
                .node = traverser.node.left.?,
                .path = traverser.path,
            };
            new_traverser.path.data[traverser.path.length] = 0b0;
            new_traverser.path.length += 1;

            traversal_stack[traversal_stack_top] = new_traverser;

            traversal_stack_top += 1;
        }

        if (traverser.node.right == null and traverser.node.left == null) {
            print("{c} - ", .{traverser.node.symbol orelse 0});
            for (traverser.path.data[0..traverser.path.length]) |b| {
                print("{b}", .{b});
            }
            print("\n", .{});
            dictionary[traverser.node.symbol orelse unreachable] = traverser.path;
        }
    }

    //
    // WRITE OUTPUT (COMPRESS)
    //
    const outfile = try std.fs.cwd().createFile(
        "res/out.et",
        .{ .read = true },
    );
    var out_writer = outfile.writer();
    defer outfile.close();

    var out_buffer = try allocator.alloc(u8, text.len * 4);
    defer allocator.free(out_buffer);
    var out_buffer_out = std.io.fixedBufferStream(out_buffer);
    var bit_stream_writer = std.io.bitWriter(.Big, out_buffer_out.writer());

    var bits_written: usize = 0;

    // write magic number
    try bit_stream_writer.writeBits(@as(u24, 0xe7c0de), 24);
    bits_written += 24;

    // write dictionary length
    var dictionary_length: u8 = 0;
    for (dictionary) |code| {
        if (code.length > 0) dictionary_length += 1;
    }
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
             for (code.data[0..code.length]) |b| {
                try bit_stream_writer.writeBits(b, 1);
                bits_written += 1;
             }
        }
    }
    try bit_stream_writer.flushBits();
    // bits_written = bits_written + (8 - bits_written % 10);

    // write compressed bits
    for (text) |char| {
        var code = dictionary[char];
        for (code.data[0..code.length]) |b| {
           try bit_stream_writer.writeBits(b, 1);
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

    const longest_allowed_code: u8 = 12;

    const DecodeTableEntry = struct {
         length: u8,
         symbols: [longest_allowed_code+1]u8,
    };

    var compressed_text = try read_text_file(&allocator, "res/out.et");
    defer allocator.free(compressed_text);

    var reading_dict_letter: bool = true;
    var reading_dict_code_len: bool = false;
    var reading_dict_code: bool = false;

    var decode_dictionary: [256]Code = [_]Code {Code{.data = [_]u1 {0} ** 12, .length = 0}} ** 256;
    var decode_dictionary_length: u8 = compressed_text[3];

    var decode_body_length: u32 = compressed_text[4];
    decode_body_length <<= 8;
    decode_body_length |= compressed_text[5];
    decode_body_length <<= 8;
    decode_body_length |= compressed_text[6];
    decode_body_length <<= 8;
    decode_body_length |= compressed_text[7];


    var longest_code: u8 = 0;
    var shortest_code: usize = std.math.maxInt(usize);

    const table_entries: usize = comptime std.math.pow(usize, 2, longest_allowed_code);
    var decode_table: [table_entries]DecodeTableEntry = [_]DecodeTableEntry {
        DecodeTableEntry {
            .length = undefined,
            .symbols = [_]u8 {0} ** (longest_allowed_code + 1),
        }
    } ** table_entries;

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

                decode_dictionary[current_letter].length = current_code_length;


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

                    decode_dictionary[current_letter].data[i] = @truncate(
                        u1,
                        (byte >> @truncate(u3, 7 - pos)) & 1
                    );

                    pos += 1;
                    i += 1;
                }

                current_code_data = build_bits;

                decode_table[current_code_data].length = current_code_length;

                decode_table[current_code_data].symbols[current_code_length] =
                    current_letter;

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

    for (decode_dictionary) |e, j| {
        if (e.length > 0) {
            print("{c} - ", .{@truncate(u8, j)});
            for (e.data) |b, bi| {
               if (bi == e.length) break;
               print("{b}", .{b});
            }
            print("\n", .{});
        }
    }

    var window: u32 = 0;
    var window_len: usize = 0;
    var checking_code_len: usize = 2;
    var testing_code: usize = 0;
    var decoded_letters_read: usize = 0;

    // print("short{d}\n", .{shortest_code});
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

                //print("{b} {d} {d} {b}\n", .{window, window_len, checking_code_len, testing_code});
                //print("-{c}-\n",.{decode_table[0b111].symbol});

                if (decode_table[testing_code].symbols[checking_code_len] > 0) {

                    decoded_letters_read += 1;

                    print("{c}", .{decode_table[testing_code].symbols[checking_code_len]});

                    window = window & ((@as(u32, 0b1) <<
                        @truncate(u5, window_len - checking_code_len)) - 1);

                    window_len -= checking_code_len;

                    checking_code_len = shortest_code;
                }
                checking_code_len += 1;
            }
        }
    }
    print("\n", .{});
}

// basic circular buffer queue  NOTE: .front and .back ranges are questionable
fn Queue(comptime T: type, comptime length: usize) type {
    const QueueError = error {
        OutOfBounds,
        QueueOverflow,
        QueueUnderflow,
    };

    return struct {
        count: usize = 0,
        front: usize = 0,
        back: usize = 0,
        data: [length]?T = [_]?T{null} ** length,

        const Self = @This();

        fn enqueue(self: *Self, new_value: T) QueueError!void {
            if ((self.back + 1) % (self.data.len + 1) == self.front) {
                return QueueError.QueueOverflow;
            }

            if (self.count == 0) {
                self.front = 0;
                self.back = 1;
            } else {
                self.back = (self.back) % self.data.len + 1;
            }

            if (self.back > self.data.len) return QueueError.OutOfBounds;
            self.data[self.back - 1] = new_value;
            self.count += 1;
        }

        fn dequeue(self: *Self) QueueError!T {
            if (self.count == 0) {
                return QueueError.QueueUnderflow;
            }

            if (self.front == self.back - 1) {
                const value = self.data[self.front] orelse QueueError.OutOfBounds;
                self.front = 0;
                self.back = 0;
                self.count -= 1;
                return value;
            } else {
                const value = self.data[self.front] orelse QueueError.OutOfBounds;
                self.front = (self.front + 1) % self.data.len;
                self.count -= 1;
                return value;
            }
        }

        fn get_front(self: Self) T {
            return self.data[self.front].?;
        }
    };
}

test "queue" {
    var q = Queue(u8, 4){};

    // test filling partway then going back to empty
    try q.enqueue(4);
    try q.enqueue(8);
    try std.testing.expectEqual(try q.dequeue(), 4);
    try std.testing.expectEqual(try q.dequeue(), 8);

    // test filling completely
    try q.enqueue(7);
    try q.enqueue(2);
    try q.enqueue(3);
    try q.enqueue(5);
    try std.testing.expectEqual(try q.dequeue(), 7);
    try std.testing.expectEqual(try q.dequeue(), 2);
    try std.testing.expectEqual(try q.dequeue(), 3);
    try std.testing.expectEqual(try q.dequeue(), 5);

    // test wrapping
    try q.enqueue(1);
    try q.enqueue(2);
    try std.testing.expectEqual(try q.dequeue(), 1);
    try q.enqueue(3);
    try q.enqueue(4);
    try q.enqueue(5); // wraps and goes in index 0
    try std.testing.expectEqual(try q.dequeue(), 2);
    try std.testing.expectEqual(try q.dequeue(), 3);
    try std.testing.expectEqual(try q.dequeue(), 4);
    try std.testing.expectEqual(try q.dequeue(), 5);

    try q.enqueue(42);
    try std.testing.expectEqual(try q.dequeue(), 42);
}


