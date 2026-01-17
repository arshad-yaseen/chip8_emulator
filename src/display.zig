const std = @import("std");

const fenster_def = extern struct {
    title: [*:0]const u8,
    width: c_int,
    height: c_int,
    buf: [*]u32,
    keys: [256]c_int,
    mod: c_int,
    x: c_int,
    y: c_int,
    mouse: c_int,
    _opaque: [256]u8,
};

extern fn fenster_open(f: *fenster_def) c_int;
extern fn fenster_loop(f: *fenster_def) c_int;
extern fn fenster_close(f: *fenster_def) void;
extern fn fenster_sleep(ms: i64) void;
extern fn fenster_time() i64;

pub const display_width = 64;
pub const display_height = 32;
pub const fps = 60;
pub const fduration: i64 = 1000 / fps;

pub const default_ips: u32 = 660; // 11 instuctions per frame

// actural chip8 width and height are too small, we need to scale when rendering
pub const default_scale: u32 = 10;

const display_size = display_width * display_height;
const packed_pixels_size = display_size / 8;

pub const Self = @This();

pub const DisplayError = error{ OutOfMemory, FensterOpenFailed };

const Key = enum(u8) { escape = 27 };

fenster: fenster_def,
scale: u32,
// packed
pixels: [packed_pixels_size]u8,
buffer: []u32,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator, scale: u32) DisplayError!Self {
    const width = display_width * scale;
    const height = display_height * scale;

    const buffer = try allocator.alloc(u32, width * height);
    errdefer allocator.free(buffer);

    var fenster = std.mem.zeroes(fenster_def);

    fenster.title = "CHIP-8";
    fenster.width = @intCast(width);
    fenster.height = @intCast(height);
    fenster.buf = buffer.ptr;

    return .{
        .pixels = [_]u8{0} ** packed_pixels_size,
        .fenster = fenster,
        .scale = scale,
        .buffer = buffer,
        .allocator = allocator,
    };
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.buffer);
}

pub fn open(self: *Self) DisplayError!void {
    if (fenster_open(&self.fenster) != 0) {
        return error.FensterOpenFailed;
    }
}

pub fn close(self: *Self) void {
    fenster_close(&self.fenster);
}

pub fn time(_: *Self) i64 {
    return fenster_time();
}

pub fn sleep(_: *Self, ms: i64) void {
    return fenster_sleep(ms);
}

pub fn loop(self: *Self) bool {
    const res = fenster_loop(&self.fenster) != 0;

    if (self.isKeyPressed(.escape)) {
        return true;
    }

    return res;
}

/// render pixels with scale handling
pub fn render(self: *Self, scale: u32) void {
    const scaled_width = display_width * scale;

    for (0..display_height) |y| {
        for (0..display_width) |x| {
            const is_pixel_on = self.isPixelOn(@intCast(x), @intCast(y));
            const color = self.pixelColor(is_pixel_on);

            for (0..scale) |sy| {
                for (0..scale) |sx| {
                    const buf_x = x * scale + sx;
                    const buf_y = y * scale + sy;

                    self.buffer[buf_y * scaled_width + buf_x] = color;
                }
            }
        }
    }
}

fn pixelColor(_: *Self, on: bool) u32 {
    return if (on) 0xFFFFFFFF else 0x00000000;
}

pub inline fn isKeyPressed(self: *Self, key: Key) bool {
    return self.fenster.keys[@intFromEnum(key)] != 0;
}

pub inline fn getPixel(self: *Self, x: u8, y: u8) u1 {
    const index = pixelIndex(x, y);
    const byte = self.pixels[byteIndex(index)];
    const offset = bitOffset(index);
    return @intCast((byte >> offset) & 1);
}

pub inline fn isPixelOn(self: *Self, x: u8, y: u8) bool {
    return self.getPixel(x, y) != 0;
}

// toggle pixel
pub inline fn togglePixel(self: *Self, x: u8, y: u8) void {
    const index = pixelIndex(x, y);
    const byte_idx = byteIndex(index);
    const offset = bitOffset(index);

    self.pixels[byte_idx] ^= @as(u8, 1) << offset;
}

inline fn pixelIndex(x: u8, y: u8) u12 {
    return @as(u12, y) * display_width + x;
}

// get byte index in packed array
inline fn byteIndex(index: u12) usize {
    return index / 8;
}

// get bit position within byte
inline fn bitOffset(index: u12) u3 {
    return @intCast(7 - index % 8);
}
