const std = @import("std");

const Allocator = std.mem.Allocator;

pub const DecodeFlags = packed struct {
    write_output: bool = false,
    print_output: bool = false,
    debug: bool = false,
    _padding: u30 = 0,
};

pub fn decode(allocator: Allocator, compressed_text: []const u8, out_writer: std.fs.File.Writer,
std_out: std.fs.File, flags: DecodeFlags) !void {
    const start_time = std.time.microTimestamp();
    defer if (flags.debug) std_out.writer().print("\ntime taken: {d}μs\n", .{std.time.microTimestamp() -
        start_time}) catch {};

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
    var pos: usize = 0; // bit pos in byte
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

    for (compressed_text[8 + global_pos ..]) |byte| {
        window <<= 8;
        window |= byte;
        window_len += 8;

        // while there are potential matches in window
        decode_text: while (window_len >= longest_code) {
            // loop through all possible code lengths, checking start of window for match
            checking_code_len = shortest_code;
            while (checking_code_len <= longest_code and window_len >= longest_code) {
                if (decoded_letters_read >= decode_body_length or
                    window_len < checking_code_len)
                {
                    break :decode_text;
                }

                testing_code = window &
                    ((@as(u32, 0b1) << @truncate(u5, checking_code_len)) - 1) << @truncate(u5, window_len - checking_code_len);

                testing_code >>= @truncate(u6, window_len - checking_code_len);

                if (decode_table.get(testing_code)) |entry| {
                    if (entry[checking_code_len - 1] > 0) {
                        var c = entry[checking_code_len - 1];

                        if (flags.write_output) try out_writer.writeByte(c);
                        if (flags.print_output) try std_out.writer().print("{c}", .{c});

                        decoded_letters_read += 1;

                        window = window & ((@as(u32, 0b1) <<
                            @truncate(u5, window_len - checking_code_len)) - 1);
                        window_len -= checking_code_len;
                        checking_code_len = shortest_code;
                    }
                }
                checking_code_len += 1;
            }
        }
    }
}
