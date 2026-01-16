const std = @import("std");
const Chip8 = @import("chip8.zig").Chip8;

pub fn main() !void {
    _ = try Chip8.init();
}
