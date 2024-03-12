const std = @import("std");

const encode = @import("encode.zig").encode;
const decode = @import("decode.zig").decode;

const print = std.debug.print;
const log = std.log;
const fs = std.fs;
const mem = std.mem;
const Allocator = mem.Allocator;

const Mode = enum {
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
    var options = Options{ .print = false, .debug = false, .dry = false, .mode = .None, .file_in_path = undefined, .file_out_path = undefined };

    const help_text =
        \\Entreepy - Text compression tool
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
    _ = args.skip(); // skip exe path
    var hasUserArgs = false;

    const CLIParsingState = enum { reading_normal, reading_out_path, reading_in_path };

    var cli_parsing_state: CLIParsingState = .reading_normal;

    while (args.next()) |arg| {
        hasUserArgs = true;
        switch (cli_parsing_state) {
            .reading_normal => {
                switch (arg[0]) {
                    '-' => {
                        for (arg[1..]) |c| {
                            switch (c) {
                                'h' => {
                                    std_out.writeAll(help_text) catch {};
                                    options.mode = .None;
                                    return options;
                                },
                                'p' => options.print = true,
                                'd' => options.debug = true,
                                't' => options.dry = true,
                                'o' => cli_parsing_state = .reading_out_path,
                                '-' => {
                                    if (mem.eql(u8, arg[2..], "help")) {
                                        std_out.writeAll(help_text) catch {};
                                        options.mode = .None;
                                        return options;
                                    } else if (mem.eql(u8, arg[2..], "print")) {
                                        options.print = true;
                                        break;
                                    } else if (mem.eql(u8, arg[2..], "debug")) {
                                        options.debug = true;
                                        break;
                                    } else if (mem.eql(u8, arg[2..], "test")) {
                                        options.dry = true;
                                        break;
                                    } else if (mem.eql(u8, arg[2..], "output")) {
                                        cli_parsing_state = .reading_out_path;
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
                    },
                    'c', 'd' => {
                        if (arg[0] == 'c') {
                            options.mode = .Compress;
                        } else {
                            options.mode = .Decompress;
                        }
                        cli_parsing_state = .reading_in_path;
                    },
                    else => {
                        log.err("invalid command: {s}\n", .{arg});
                        return error.InvalidCommand;
                    },
                }
            },
            .reading_in_path => {
                options.file_in_path = arg;
                cli_parsing_state = .reading_normal;
            },
            .reading_out_path => {
                options.file_out_path = try allocator.dupe(u8, arg);
                cli_parsing_state = .reading_normal;
            },
        }
    }

    if (!hasUserArgs) {
        std_out.writeAll(help_text) catch {};
        options.mode = .None;
        return options;
    }

    if (options.file_out_path.len == 0) {
        if (options.mode == .Compress) {
            options.file_out_path =
                try mem.concat(allocator, u8, &[2][]const u8{ options.file_in_path, ".et" });
        } else {
            // removes the ".et" extension if it's there and adds "decoded_" to the front of the file name
            const file_in_dir = fs.path.dirname(options.file_in_path) orelse "";
            var new_file_name = fs.path.basename(options.file_in_path);
            if (mem.eql(u8, new_file_name[new_file_name.len - 3 ..], ".et"))
                new_file_name = new_file_name[0 .. new_file_name.len - 3];
            const decoded_file_name = try mem.concat(allocator, u8, &[2][]const u8{ "decoded_", new_file_name });
            defer allocator.free(decoded_file_name);
            options.file_out_path =
                try fs.path.join(allocator, &[_][]const u8{ file_in_dir, decoded_file_name });
        }
    }

    return options;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const std_out = std.io.getStdOut();
    defer std_out.close();

    const options = try run_cli(allocator, std_out);
    defer allocator.free(options.file_out_path);
    if (options.mode == .None) return;

    const text_in = try read_text_file(allocator, options.file_in_path);
    defer allocator.free(text_in);

    var out_file: std.fs.File = undefined;
    var out_writer: std.fs.File.Writer = undefined;
    if (!options.dry) {
        out_file = try std.fs.cwd().createFile(
            options.file_out_path,
            .{ .read = true },
        );
        out_writer = out_file.writer();
    }

    // TODO: Add checks for to error if it isnt in valid .et file format file format version, min length, magic number,

    if (options.mode == .Compress) {
        _ = try encode(allocator, text_in, out_writer, std_out, .{ .write_output = !options.dry, .print_output = options.print, .debug = options.debug });
    } else {
        _ = try decode(allocator, text_in[4..], out_writer, std_out, .{ .write_output = !options.dry, .print_output = options.print, .debug = options.debug });
    }

    if (!options.dry) out_file.close();
}
