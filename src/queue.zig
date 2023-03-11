const std = @import("std");

// basic circular buffer queue  NOTE: .front and .back ranges are questionable
pub fn Queue(comptime T: type, comptime length: usize) type {
    const QueueError = error{
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

        pub fn enqueue(self: *Self, new_value: T) QueueError!void {
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

        pub fn dequeue(self: *Self) QueueError!T {
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

        pub fn get_front(self: Self) T {
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
