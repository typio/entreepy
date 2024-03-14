const std = @import("std");

const Color = struct { r: i32, g: i32, b: i32 };

const stdout = std.io.getStdOut().writer();
const bar_length: usize = 30;
const steps_per_color: i32 = 60;

pub fn print_progress(theme: u8, progress: *usize, state_msg: *const []const u8) !void {
    var stops: [4]Color = undefined;
    switch (theme) {
        0 => {
            stops = [_]Color{ Color{ .r = 0x00, .g = 0xb4, .b = 0xd8 }, Color{ .r = 0x90, .g = 0xe0, .b = 0xef }, Color{ .r = 0xca, .g = 0xc0, .b = 0xf8 }, Color{ .r = 0x90, .g = 0xe0, .b = 0xef } };
        },
        else => {
            stops = [_]Color{ Color{ .r = 0x83, .g = 0x3a, .b = 0xb4 }, Color{ .r = 0xe7, .g = 0x22, .b = 0x38 }, Color{ .r = 0xfc, .g = 0xb0, .b = 0x45 }, Color{ .r = 0xe7, .g = 0x22, .b = 0x38 } };
        },
    }

    var step: usize = 0;

    std.debug.print("\n\n\n\n", .{});

    while (progress.* <= 100) : (step += 1) {
        const bar_done = progress.* * bar_length / 100;

        std.debug.print("\x1B[4F\x1B[4K", .{});
        std.debug.print("{s}\t\t\t\t\t\t\n", .{state_msg.*});
        std.debug.print("╔", .{});
        inline for (0..bar_length + 2) |_| {
            std.debug.print("═", .{});
        }

        std.debug.print("╗\n║ ", .{});

        for (0..bar_done) |j| {
            const stop = stops[@divTrunc(step + j, steps_per_color) % 3];
            const stop_next = stops[(@divTrunc(step + j, steps_per_color) + 1) % 3];

            var c: Color = undefined;

            c = Color{
                .r = stop.r + @divTrunc((stop_next.r - stop.r) * @rem(@as(i32, @intCast(step + j)), steps_per_color), steps_per_color),
                .g = stop.g + @divTrunc((stop_next.g - stop.g) * @rem(@as(i32, @intCast(step + j)), steps_per_color), steps_per_color),
                .b = stop.b + @divTrunc((stop_next.b - stop.b) * @rem(@as(i32, @intCast(step + j)), steps_per_color), steps_per_color),
            };
            std.debug.print("\x1B[38;2;{};{};{}m█\x1B[m", .{ c.r, c.g, c.b });
        }

        for (bar_done..@max(bar_done, bar_length)) |_| {
            std.debug.print(" ", .{});
        }

        std.debug.print(" ║\n╚", .{});

        inline for (0..bar_length + 2) |_| {
            std.debug.print("═", .{});
        }

        std.debug.print("╝\n", .{});

        if (bar_done == bar_length) {
            break;
        }
        std.time.sleep(10_000_000);
    }
}
