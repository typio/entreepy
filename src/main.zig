const std = @import("std");

const encode = @import("encode.zig").encode;
const decode = @import("decode.zig").decode;

const print = std.debug.print;
const log = std.log;
const fs = std.fs;
const mem = std.mem;
const Allocator = mem.Allocator;

const Mode = enum(u2) {
    None,
    Compress,
    Decompress,
};

const Options = struct {
    print: bool,
    debug: bool,
    dry: bool,
    mode: Mode,
    file_in_path: []const u8,
    file_out_path: []const u8,
};

const CliError = error{
    InvalidOption,
    InvalidCommand,
    NoInputFile,
    InvalidCommandArgument,
};

fn read_text_file(allocator: Allocator, filepath: []const u8) ![]const u8 {
    var file = try fs.cwd().openFile(filepath, .{});
    defer file.close();
    const buffer = try allocator.alloc(u8, (try file.stat()).size);
    try file.reader().readNoEof(buffer);
    return buffer;
}

fn run_cli(allocator: Allocator, std_out: std.fs.File) !Options {
    var options = Options{
        .print = false,
        .debug = false,
        .dry = false,
        .mode = Mode.None,
        .file_in_path = undefined,
        .file_out_path = undefined,
    };

    const help_text =
        \\File compression tool using huffman compression
        \\
        \\Usage: entreepy [options] [command] [file] [command options]
        \\
        \\Options:
        \\    -h, --help     show help
        \\    -p, --print    print decompressed text to stdout
        \\    -t, --test     test/dry run, does not write to file
        \\    -d, --debug    print huffman code dictionary and performance times to stdout
        \\
        \\Commands:
        \\    c    compress a file
        \\    d    decompress a file
        \\
        \\Command Options:
        \\    -o, --output    output file (default: [file].et or decoded_[file])
        \\
        \\Examples:
        \\    entreepy -d c text.txt -o text.txt.et
        \\    entreepy -ptd d text.txt.et -o decoded_text.txt
        \\
    ;
    var args = try std.process.argsWithAllocator(allocator);
    // skip exe path
    _ = args.skip();

    const arg1 = args.next() orelse {
        std_out.writeAll(help_text) catch {};
        return options;
    };

    if (mem.eql(u8, arg1, "-h") or mem.eql(u8, arg1, "--help")) {
        try std_out.writeAll(help_text);
        return options;
    }

    var arg = arg1;
    while (true) {
        // parse initial options
        if (arg[0] == '-') {
            for (arg[1..]) |c| {
                switch (c) {
                    'p' => options.print = true,
                    'd' => options.debug = true,
                    't' => options.dry = true,
                    '-' => {
                        if (mem.eql(u8, arg[2..], "print")) {
                            options.print = true;
                            break;
                        } else if (mem.eql(u8, arg[2..], "debug")) {
                            options.debug = true;
                            break;
                        } else if (mem.eql(u8, arg[2..], "test")) {
                            options.dry = true;
                            break;
                        } else {
                            log.err("invalid option: {s}\n", .{arg});
                            return error.InvalidOption;
                        }
                    },
                    else => {
                        log.err("invalid option: {s}\n", .{arg});
                        return error.InvalidOption;
                    },
                }
            }
            arg = args.next() orelse break;
            continue;
        }

        // parse commands
        if (arg[0] == 'c' or arg[0] == 'd') {
            if (arg[0] == 'c') {
                options.mode = Mode.Compress;
            } else if (arg[0] == 'd') {
                options.mode = Mode.Decompress;
            }
            options.file_in_path = args.next() orelse return error.NoInputFile;
            arg = args.next() orelse break;
            if (arg[0] == '-') {
                for (arg[1..]) |c| {
                    switch (c) {
                        'o' => {
                            // allocate it unnecessarily so we can free it unconditionally
                            options.file_out_path =
                                try allocator.dupe(u8, args.next() orelse {
                                log.err("missing file_in_name after -o\n", .{});
                                return error.InvalidCommandArgument;
                            });
                            break;
                        },
                        '-' => {
                            if (mem.eql(u8, arg[2..], "output")) {
                                options.file_out_path = try allocator.dupe(u8, args.next() orelse {
                                    log.err("missing file_in_name after --output\n", .{});
                                    return error.InvalidCommandArgument;
                                });
                            } else {
                                log.err("invalid option: {s}\n", .{arg});
                                return error.InvalidOption;
                            }
                        },
                        else => {
                            log.err("invalid option: {c}\n", .{c});
                            return error.InvalidOption;
                        },
                    }
                } else {
                    log.err("invalid option: {s}\n", .{arg});
                    return error.InvalidOption;
                }
            } else {
                log.err("invalid command: {s}\n", .{arg});
                return error.InvalidCommand;
            }

            arg = args.next() orelse {
                break;
            };
        }
    }

    // NOTE: weirdish field access on an undefined []const u8
    if (options.file_out_path.len == 0) {
        if (options.mode == Mode.Compress) {
            options.file_out_path =
                try mem.concat(allocator, u8, &[2][]const u8{ options.file_in_path, ".et" });
        } else {
            // NOTE: hard to read but it just adds "decoded_" to the front of the file name and
            // removes the ".et" extension if its there
            var file_in_dir = fs.path.dirname(options.file_in_path) orelse "";
            var new_file_name = fs.path.basename(options.file_in_path);
            if (mem.eql(u8, new_file_name[new_file_name.len - 3 ..], ".et"))
                new_file_name = new_file_name[0 .. new_file_name.len - 3];
            var decoded_file_name = try mem.concat(allocator, u8, &[2][]const u8{ "decoded_", new_file_name });
            defer allocator.free(decoded_file_name);
            options.file_out_path =
                try fs.path.join(allocator, &[_][]const u8{ file_in_dir, decoded_file_name });
        }
    }

    return options;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .enable_memory_limit = true, .safety = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const std_out = std.io.getStdOut();

    const options = try run_cli(allocator, std_out);
    defer allocator.free(options.file_out_path);
    if (options.mode == Mode.None) return;

    var text_in = try read_text_file(allocator, options.file_in_path);
    defer allocator.free(text_in);

    // Reading seems to add an extra \n at end... not sure actually,
    // also this code has the issue of freeing the wrong amount
    // if (text_in.len > 0) text_in = text_in[0 .. text_in.len - 1];

    var out_file: std.fs.File = undefined;
    var out_writer: std.fs.File.Writer = undefined;
    if (!options.dry) {
        out_file = try std.fs.cwd().createFile(
            options.file_out_path,
            .{ .read = true },
        );
        out_writer = out_file.writer();
    }

    if (options.mode == Mode.Compress) {
        try encode(allocator, text_in, out_writer, std_out, .{ .write_output = !options.dry, .print_output = options.print, .debug = options.debug });
    } else {
        try decode(allocator, text_in, out_writer, std_out, .{ .write_output = !options.dry, .print_output = options.print, .debug = options.debug });
    }

    if (!options.dry) out_file.close();
}
