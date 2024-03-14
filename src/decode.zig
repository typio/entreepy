const std = @import("std");

const Allocator = std.mem.Allocator;
const print_progress = @import("progress_bar.zig").print_progress;
const format_file_size = @import("utils.zig").format_file_size;

pub const DecodeFlags = struct {
    write_output: bool = false,
    print_output: bool = false,
    debug: bool = false,
};

pub fn decode(allocator: Allocator, compressed_text: []const u8, out_writer: anytype, std_out: std.fs.File, flags: DecodeFlags) !usize {
    var bytes_written: u32 = 0;
    const start_time = std.time.microTimestamp();
    defer if (flags.debug) std_out.writer().print("time taken: {d}μs\n", .{std.time.microTimestamp() -
        start_time}) catch {};

    var decoding_progress: usize = 0;
    var decoding_state_msg: []const u8 = "Decoding file...";

    var print_progress_thread: ?std.Thread = null;
    if (!flags.print_output) {
        print_progress_thread = try std.Thread.spawn(.{}, print_progress, .{ 1, &decoding_progress, &decoding_state_msg });
    }

    decoding_progress = 5;
    decoding_state_msg = "Reading file header...";

    var reading_dict_letter: bool = true;
    var reading_dict_code_len: bool = false;
    var reading_dict_code: bool = false;

    const decode_dictionary_length: u8 = compressed_text[0] + 1;

    var decode_body_length: u32 = compressed_text[1];
    decode_body_length <<= 8;
    decode_body_length |= compressed_text[2];
    decode_body_length <<= 8;
    decode_body_length |= compressed_text[3];
    decode_body_length <<= 8;
    decode_body_length |= compressed_text[4];

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

    decoding_progress = 10;
    decoding_state_msg = "Reading prefix code dictionary...";

    var global_pos: usize = 0;
    var pos: usize = 0; // bit pos in byte
    var build_bits: usize = 0b0;
    var i: usize = 0; // bit pos in current read
    var letters_read: u8 = 0;
    for (compressed_text[5..]) |byte| {
        pos = 0;

        read: while (true) {
            if (reading_dict_letter) {
                while (i <= 7) {
                    if (pos > 7) break :read;
                    build_bits <<= 1;
                    build_bits |= (byte >> @as(u3, @truncate(7 - pos))) & 1;
                    pos += 1;
                    i += 1;
                }

                current_letter = @as(u8, @truncate(build_bits));

                reading_dict_letter = false;
                reading_dict_code_len = true;

                build_bits = 0b0;
                i = 0;
            }

            if (reading_dict_code_len) {
                while (i <= 7) {
                    if (pos > 7) break :read;
                    build_bits <<= 1;
                    build_bits |= (byte >> @as(u3, @truncate(7 - pos))) & 1;
                    pos += 1;
                    i += 1;
                }

                current_code_length = @as(u8, @truncate(build_bits));

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
                    build_bits |= (byte >> @as(u3, @truncate(7 - pos))) & 1;

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

    decoding_progress = 20;
    decoding_state_msg = "Decoding text...";

    const decoding_sections = 30;
    for (0..decoding_sections) |s| {
        decoding_progress = 30 + (100 - 30) * s / decoding_sections;

        const body_start = 5 + global_pos;
        const body_length = compressed_text.len - body_start;

        for (compressed_text[body_start + s * body_length / decoding_sections .. body_start + (s + 1) * body_length / decoding_sections]) |byte| {
            // for (compressed_text[5 + global_pos ..]) |byte| {
            window <<= 8;
            window |= byte;
            window_len += 8;

            // while there are potential matches in window
            decode_text: while (window_len >= longest_code) {
                // loop through all possible code lengths, checking start of window for match
                checking_code_len = shortest_code;
                while (window_len >= checking_code_len) {
                    if (decoded_letters_read >= decode_body_length or
                        window_len < checking_code_len)
                    {
                        break :decode_text;
                    }

                    testing_code = window &
                        ((@as(u32, 0b1) << @as(u5, @truncate(checking_code_len))) - 1) << @as(u5, @truncate(window_len - checking_code_len));

                    testing_code >>= @as(u6, @truncate(window_len - checking_code_len));

                    if (decode_table.get(testing_code)) |entry| {
                        if (entry[checking_code_len - 1] > 0) {
                            const c = entry[checking_code_len - 1];

                            if (flags.write_output) {
                                try out_writer.writeByte(c);
                                bytes_written += 1;
                            }
                            if (flags.print_output) try std_out.writer().print("{c}", .{c});

                            decoded_letters_read += 1;

                            window = window & ((@as(u32, 0b1) <<
                                @as(u5, @truncate(window_len - checking_code_len))) - 1);
                            window_len -= checking_code_len;
                            checking_code_len = shortest_code;
                        }
                    }
                    checking_code_len += 1;
                }
            }
        }
    }

    if (!flags.print_output) {
        decoding_progress = 100;
        decoding_state_msg = "Done decompressing!";
        print_progress_thread.?.join();
    }

    const formatted_original_size = format_file_size(allocator, @floatFromInt(compressed_text.len)) catch unreachable;
    defer allocator.free(formatted_original_size);

    const formatted_decompressed_size = format_file_size(allocator, @floatFromInt(bytes_written)) catch unreachable;
    defer allocator.free(formatted_decompressed_size);

    std.debug.print("{s} => {s}\n", .{ formatted_original_size, formatted_decompressed_size });

    return bytes_written;
}
