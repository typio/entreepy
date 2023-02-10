const std = @import("std");
const print = std.debug.print;

const Node = struct {
    symbol: ?u8,
    weight: u8,
    parent: ?*Node,
    left: ?*Node,
    right: ?*Node,
};

pub fn main() !void {
    const start_time = std.time.microTimestamp();

    var args_gpa = std.heap.GeneralPurposeAllocator(.{
        .enable_memory_limit = false,
        .safety = false
    }){};
    defer _ = args_gpa.deinit();
    const args_allocator = args_gpa.allocator();
    var args = try std.process.argsWithAllocator(args_allocator);
    _ = args.skip();
    const filepath: []const u8 = args.next() orelse "res/nice.shakespeare.txt";

    //
    // ALLOCATE TEXT FILE (PRETTY SLOW) [NOT TOO BAD...]
    //

    // want to put this in a function but also want to defer free in main scope
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .enable_memory_limit = false,
        .safety = false
    }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    // var file = try std.fs.cwd().openFile(.{});
     var file = try std.fs.cwd().openFile(filepath, .{});
    defer file.close();
    const buffer = try allocator.alloc(u8, (try file.stat()).size);
    defer allocator.free(buffer);
    try file.reader().readNoEof(buffer);

    //
    // CONSTRUCT ARRAY OF SYMBOL FREQUENCIES
    //

    // array where index is the ascii char and value is number of occurences
    var occurences_book = [_]usize{0} ** 256;

    for (buffer) |c| {
        occurences_book[c] += 1;
    }

//       defer for (occurences_book) |f, c| {
         // if (f > 0)
             // print("char: \"{c}\",\tascii: {d},\toccurences: {d}\n",
                 // .{@intCast(u8, c), @intCast(u8, c), f});
     //};

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
                book_index += 1;
            }
        }
        min_value = next_min_value;
    }


    //  defer for (sorted_letter_book) |c, i| {
    //      if (c > 0)
    //          print("char: \"{c}\",\tascii: {d},\tindex: {d}\n", .{c, c, i});
    // };

    // TODO: Build binary tree

    const end_time = std.time.microTimestamp();
    print("\ntime taken: {d}μs\n", .{end_time - start_time});
}

test "simple test" {
    try std.testing.expectEqual(1, 1);
}
