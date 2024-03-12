const std = @import("std");

const QueueError = error{
    OutOfBounds,
    QueueFull,
    QueueEmpty,
};

pub fn Queue(comptime T: type, comptime length: usize) type {
    return struct {
        count: usize = 0,
        front: usize = 0,
        back: usize = 0,
        data: [length]?T = [_]?T{null} ** length,

        const Self = @This();

        pub fn enqueue(self: *Self, new_value: T) QueueError!void {
            if (self.count == self.data.len) return QueueError.QueueFull;

            self.back = (self.back % self.data.len) + 1;

            self.data[self.back - 1] = new_value;
            self.count += 1;
        }

        pub fn dequeue(self: *Self) QueueError!T {
            if (self.count == 0) {
                return QueueError.QueueEmpty;
            }

            const value = self.data[self.front] orelse QueueError.OutOfBounds;
            self.front = (self.front + 1) % self.data.len;
            self.count -= 1;
            return value;
        }

        pub fn peek(self: Self) ?T {
            if (self.count == 0) return null;
            return self.data[self.front];
        }
    };
}

test "queue enqueue and peek" {
    var q = Queue(u8, 3){};

    try q.enqueue(42);
    try std.testing.expectEqual(@as(?u8, 42), q.peek());

    try q.enqueue(24);
    try std.testing.expectEqual(@as(?u8, 42), q.peek());
}

test "queue single element" {
    var q = Queue(u8, 3){};

    try q.enqueue(1);
    try std.testing.expectEqual(try q.dequeue(), 1);
    try std.testing.expectError(QueueError.QueueEmpty, q.dequeue());
}

test "queue is full after enqueues" {
    var q = Queue(u8, 3){};

    try q.enqueue(1);
    try q.enqueue(2);
    try q.enqueue(3);

    try std.testing.expectError(QueueError.QueueFull, q.enqueue(4));
}

test "queue empty after dequeues" {
    var q = Queue(u8, 3){};

    try q.enqueue(1);
    try q.enqueue(2);
    try q.enqueue(3);
    _ = try q.dequeue();
    _ = try q.dequeue();
    _ = try q.dequeue();

    try std.testing.expectError(QueueError.QueueEmpty, q.dequeue());
}

test "queue wrap around after full cycle" {
    var q = Queue(u8, 3){};

    try q.enqueue(1);
    try q.enqueue(2);
    try q.enqueue(3);
    try std.testing.expectEqual(try q.dequeue(), 1);
    try std.testing.expectEqual(try q.dequeue(), 2);
    try q.enqueue(4);
    try q.enqueue(5);
    try std.testing.expectEqual(try q.dequeue(), 3);
    try std.testing.expectEqual(try q.dequeue(), 4);
    try std.testing.expectEqual(try q.dequeue(), 5);

    try std.testing.expectError(QueueError.QueueEmpty, q.dequeue());
}

test "queue peek after wrap around" {
    var q = Queue(u8, 3){};

    try q.enqueue(1);
    try q.enqueue(2);
    try q.enqueue(3);
    try std.testing.expectEqual(try q.dequeue(), 1);
    try q.enqueue(4);
    try std.testing.expectEqual(@as(?u8, 2), q.peek());
}
