const std = @import("std");
const Chip8 = @import("chip8.zig");

pub fn main() !void {
    var chip8 = Chip8.init();

    try chip8.run();
}
