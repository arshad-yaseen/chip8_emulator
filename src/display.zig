const c = @cImport({
    @cInclude("fenster.h");
});

const fenster = c.fenster;

const display_width = 64;
const display_height = 32;
const scale = 10;

const display_size = display_width * display_height;
const display_size_scaled = (display_width * scale) * (display_height * scale);
const packed_pixels_size = display_size / 8;

pub const Self = @This();

// packed
pixels: [packed_pixels_size]u8,

pub fn init() Self {
    return .{
        .pixels = [_]u8{0} ** packed_pixels_size,
    };
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
