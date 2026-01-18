// my own implementation by reading https://tobiasvl.github.io/blog/write-a-chip-8-emulator/

const std = @import("std");
const Display = @import("display.zig");

const memory_size = 4096;
const stack_size = 16;
const register_size = 16;

const program_start = 0x200; // from 512

pub const Self = @This();

const Chip8Error = error{ ProgramTooLarge, ProgramReadFailed, ProgramOpenFailed } || Display.DisplayError;

const font_start = 0x50;
const font_height = 5;

pub const Chip8Opts = struct {
    program: []const u8,
    scale: u32 = Display.default_scale,
    ips: u32 = Display.default_ips,
};

allocator: std.mem.Allocator,
display: Display,
opts: Chip8Opts,

memory: [memory_size]u8,

PC: u16,
I: u16,
stack: Stack,
V: [register_size]u8,

delay_timer: u8,
sound_timer: u8,

pub const Stack = struct {
    stack: [stack_size]u16,

    pub fn init() Stack {
        return .{ .stack = [_]u16{0} ** stack_size };
    }

    pub fn push(self: *Stack, item: u16) void {
        self.stack[self.stack.len - 1] = item;
    }

    pub fn pop(self: *Stack) u16 {
        return self.stack[self.stack.len - 1];
    }
};

pub fn init(allocator: std.mem.Allocator, opts: Chip8Opts) Chip8Error!Self {
    var chip8 = Self{
        .memory = [_]u8{0} ** memory_size,

        .PC = program_start,
        .I = 0,

        .stack = Stack.init(),
        .V = [_]u8{0} ** register_size,

        .display = try Display.init(allocator, opts.scale),

        .delay_timer = 0,
        .sound_timer = 0,

        .allocator = allocator,

        .opts = opts,
    };

    errdefer chip8.deinit();

    try chip8.loadProgram();

    chip8.loadFonts();

    return chip8;
}

pub fn deinit(self: *Self) void {
    self.display.deinit();
}

pub fn run(self: *Self) Chip8Error!void {
    try self.display.open();
    defer self.display.close();

    while (!self.display.loop()) {
        const fstart = self.display.time();

        for (0..self.opts.ips / Display.fps) |_| {
            if (self.PC + 1 < self.memory.len) {
                self.fde();
            }
        }

        self.display.render(self.opts.scale);

        const elapsed = self.display.time() - fstart;

        if (elapsed < Display.fduration) {
            self.display.sleep(Display.fduration - elapsed);
        }

        if (self.delay_timer > 0) self.delay_timer -= 1;
        if (self.sound_timer > 0) self.sound_timer -= 1;
    }
}

fn fde(self: *Self) void {
    const instruction = @as(u16, self.memory[self.PC]) << 8 | @as(u16, self.memory[self.PC + 1]);
    self.PC += 2;

    const decoded = decode(instruction);

    switch (decoded.opcode) {
        0x0 => {
            switch (instruction) {
                0x00E0 => {
                    self.display.clear();
                },
                0x00EE => {
                    // return from subroutine
                    self.PC = self.stack.pop();
                },
                else => {},
            }
        },
        0x2 => {
            self.stack.push(self.PC);
            self.PC = combineLast3Parts(decoded);
        },
        0x1 => {
            self.PC = combineLast3Parts(decoded);
        },
        0x6 => {
            const value = combineLast2Parts(decoded);
            self.V[@intCast(decoded.second)] = value;
        },
        0x7 => {
            const value = combineLast2Parts(decoded);
            self.V[decoded.second] +%= value;
        },
        0xA => {
            self.I = combineLast3Parts(decoded);
        },
        0xD => {
            const x = self.V[decoded.second] % Display.display_width;
            const y = self.V[decoded.third] % Display.display_height;
            const n = decoded.fourth;

            // VF
            self.V[0xF] = 0;

            for (0..n) |row| {
                const sprite_byte = self.memory[self.I + row];

                for (0..8) |bit| {
                    const actual_pixel_on = self.display.isPixelOn(x, y);
                    const current_pixel_on = (sprite_byte & (@as(u8, 0x80) >> @as(u3, @intCast(bit)))) != 0;

                    const pixel_x = (x + @as(u8, @intCast(bit)));
                    const pixel_y = y + @as(u8, @intCast(row));

                    if (current_pixel_on) {
                        self.display.togglePixel(pixel_x, pixel_y);

                        if (actual_pixel_on) {
                            // VF
                            self.V[0xF] = 1;
                        }
                    }
                }
            }
        },
        0xF => {
            switch (combineLast2Parts(decoded)) {
                0x0029 => {
                    const digit = self.V[@as(u8, decoded.second)];

                    self.I = font_start + (digit * font_height);
                },
                else => {},
            }
        },
        else => {
            std.debug.print("opcode not implemented\n", .{});
        },
    }
}

const Decoded = struct {
    opcode: u4,
    second: u4,
    third: u4,
    fourth: u4,
};

// instruction (u16) = 0b[opcode][second][third][fourth]
// each 4 bytes
inline fn decode(instruction: u16) Decoded {
    return .{ .opcode = @intCast((instruction & 0xF000) >> 12), .second = @intCast((instruction & 0x0F00) >> 8), .third = @intCast((instruction & 0x00F0) >> 4), .fourth = @intCast(instruction & 0x000F) };
}

inline fn combineLast2Parts(decoded: Decoded) u8 {
    return @as(u8, decoded.third) << 4 | @as(u8, decoded.fourth);
}

inline fn combineLast3Parts(decoded: Decoded) u12 {
    return @as(u12, decoded.second) << 8 | @as(u12, decoded.third) << 4 | @as(u12, decoded.fourth);
}

fn loadProgram(self: *Self) Chip8Error!void {
    const file = std.fs.cwd().openFile(self.opts.program, .{}) catch return error.ProgramOpenFailed;
    defer file.close();

    const stat = file.stat() catch return error.ProgramOpenFailed;

    if (stat.size > memory_size - program_start) {
        return error.ProgramTooLarge;
    }

    var buffer: [4096]u8 = undefined;
    var reader = file.reader(&buffer);
    const contents = reader.interface.allocRemaining(self.allocator, std.Io.Limit.limited(memory_size - program_start)) catch return error.ProgramReadFailed;
    defer self.allocator.free(contents);

    // program from 512 to ...
    for (contents, 0..) |byte, i| {
        self.memory[program_start + i] = byte;
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

    // fonts are from 80 to 159
    for (font_set, 0..) |pixel, i| {
        self.memory[font_start + i] = pixel;
    }
}
