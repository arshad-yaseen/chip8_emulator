const std = @import("std");
const Chip8 = @import("chip8.zig");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var chip8 = try Chip8.init(allocator, .{
        .program = "roms/ibm_logo.ch8",
        .scale = 20,
    });
    defer chip8.deinit();

    try chip8.run();
}
