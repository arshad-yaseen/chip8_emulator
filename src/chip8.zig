// my own implementation by reading https://tobiasvl.github.io/blog/write-a-chip-8-emulator/

const std = @import("std");
const Display = @import("display.zig");

const memory_size = 4096;
const stack_size = 16;
const register_size = 16;

pub const Self = @This();

const Chip8Error = error {} || Display.DisplayError;

memory: [memory_size]u8,

PC: u16,
I: u16,
stack: [stack_size]u16,
V: [register_size]u8,

delay_timer: u8,
sound_timer: u8,

display: Display,

allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) Chip8Error!Self {
    var chip8 = Self{
        .memory = [_]u8{0} ** memory_size,

        .PC = 0x200,
        .I = 0,

        .stack = [_]u16{0} ** stack_size,
        .V = [_]u8{0} ** register_size,

        .display = try Display.init(allocator, 10),

        .delay_timer = 0,
        .sound_timer = 0,

        .allocator = allocator,
    };

    chip8.loadFonts();

    return chip8;
}

pub fn run(self: *Self) Chip8Error!void {
    try self.display.open();
    defer self.display.close();

    while (!self.display.shouldClose()) {
        // do stuff
    }
}

fn loadFonts(self: *Self) void {
    const font_set = [80]u8{
        0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
        0x20, 0x60, 0x20, 0x20, 0x70, // 1
        0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
        0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
        0x90, 0x90, 0xF0, 0x10, 0x10, // 4
        0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
        0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
        0xF0, 0x10, 0x20, 0x40, 0x40, // 7
        0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
        0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
        0xF0, 0x90, 0xF0, 0x90, 0x90, // A
        0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
        0xF0, 0x80, 0x80, 0x80, 0xF0, // C
        0xE0, 0x90, 0x90, 0x90, 0xE0, // D
        0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
        0xF0, 0x80, 0xF0, 0x80, 0x80, // F
    };

    for (font_set, 0..) |pixel, i| {
        self.memory[0x50 + i] = pixel;
    }
}
