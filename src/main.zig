const std = @import("std");
const print = std.debug.print;

const Node = struct {
    symbol: ?u8,
    weight: usize,
    parent: ?*Node,
    left: ?*Node,
    right: ?*Node,
    visited: bool,
};

pub fn main() !void {
    const start_time = std.time.microTimestamp();
    defer print("\ntime taken: {d}μs\n", .{std.time.microTimestamp() - start_time});

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
    // ALLOCATE TEXT FILE
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
    var buffer = try allocator.alloc(u8, (try file.stat()).size);
    defer allocator.free(buffer);
    try file.reader().readNoEof(buffer);

    // reading seems to add an extra \n at end
    buffer = buffer[0..buffer.len - 1];

    //
    // CONSTRUCT ARRAY OF SYMBOL FREQUENCIES
    //

    // array where index is the ascii char and value is number of occurences
    var occurences_book = [_]usize{0} ** 256;

    for (buffer) |c| {
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
                book_index += 1;
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
    var dictionary: [256]?usize = [_]?usize {null} ** 256;

    const HistoryNode = struct {
        node: *Node,
        path: usize,
    };

    var traversal_stack: [513]?HistoryNode = [_]?HistoryNode {null} ** 513;
    var traversal_stack_top: usize = 1;
    traversal_stack[0] = HistoryNode{ .node = root_node, .path = 0b1};
    var traverser: HistoryNode = undefined;
    while (traversal_stack_top > 0) {
        traverser = traversal_stack[traversal_stack_top - 1].?;
        traversal_stack_top -= 1;

        if (traverser.node.right != null) {
            const new_path: usize = (traverser.path << 1) | 1;

            traversal_stack[traversal_stack_top] = HistoryNode {
                .node= traverser.node.right.?,
                .path= new_path,
            };

            traversal_stack_top += 1;
        }

        if (traverser.node.left != null) {
            const new_path: usize = (traverser.path << 1) | 0;

            traversal_stack[traversal_stack_top] = HistoryNode {
                .node= traverser.node.left.?,
                .path= new_path,
            };
            traversal_stack_top += 1;
        }

        if (traverser.node.right == null and traverser.node.left == null) {
            print("{c} - {b}\n", .{traverser.node.symbol orelse 0, traverser.path});
            dictionary[traverser.node.symbol orelse unreachable] = traverser.path;
        }
    }
    // print("{any}", .{dictionary});

    //
    // WRITE COMPRESSED OUTPUT
    //


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

        fn get_nth(self: Self, n: usize) T {
            return self.data[(self.front + n) % self.data.len].?;
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


