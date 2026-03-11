const std = @import("std");
const uefi = std.os.uefi;

// MSVC runtime symbols for 32-bit UEFI
export fn _aullrem(a: u64, b: u64) u64 {
    return @rem(a, b);
}
export fn _aulldiv(a: u64, b: u64) u64 {
    return @divTrunc(a, b);
}
export fn _allrem(a: i64, b: i64) i64 {
    return @rem(a, b);
}
export fn _alldiv(a: i64, b: i64) i64 {
    return @divTrunc(a, b);
}
export fn __fltused() void {}

export fn _EfiMain(handle: uefi.Handle, st: *uefi.tables.SystemTable) usize {
    uefi.handle = handle;
    uefi.system_table = st;
    return @intFromEnum(main());
}

const LOGO_W: u32 = 128;
const LOGO_H: u32 = 128;
const logo_raw: []const u8 = @embedFile("logo.raw");

// Tileset configuration - can be changed for different tilesets
const TILE_SIZE: u32 = 16; // 16x16 pixels per tile
const TILESHEET_W: u32 = 256; // Total width of tileset image
const TILESHEET_H: u32 = 128; // Total height of tileset image
const TILES_PER_ROW: u32 = 16; // Number of tiles horizontally (256/16)
const TILES_PER_COL: u32 = 8; // Number of tiles vertically (128/16)
const TOTAL_TILES: u32 = 128; // Total tile count (16*8)
const tileset_ppm: []const u8 = @embedFile("tileset.ppm");

// PPM header size: "P6\n256 128\n255\n" = 12 bytes
const PPM_HEADER_SIZE: usize = 12;

// DawnBringer 16 color palette (ARGB format)
const palette: [16]u32 = .{
    0xFF140C1C, // 0: Very dark blue-black
    0xFF442434, // 1: Dark purple
    0xFF30346D, // 2: Dark blue
    0xFF4E4A4F, // 3: Dark gray
    0xFF854C30, // 4: Brown
    0xFF346524, // 5: Dark green
    0xFFD04648, // 6: Red
    0xFF757161, // 7: Gray
    0xFF597DCE, // 8: Blue
    0xFFD27D2C, // 9: Orange
    0xFF8595A1, // 10: Light gray
    0xFF6DAA2C, // 11: Green
    0xFFD2AA99, // 12: Peach
    0xFF6DC2CA, // 13: Cyan
    0xFFDAD45E, // 14: Yellow
    0xFFDEEED6, // 15: W4te
};

// Terrain generation rules - 10 tiles, each with 8 possible next tiles
// Selected rules that generate best results
const terrain_rules: [11][8]u8 = .{
    .{ 0, 0, 1, 1, 0, 0, 1, 1 }, // Tile 0
    .{ 1, 0, 1, 0, 1, 2, 1, 2 }, // Tile 1
    .{ 2, 0, 1, 2, 1, 2, 3, 3 }, // Tile 2
    .{ 3, 2, 1, 3, 2, 1, 4, 4 }, // Tile 3
    .{ 4, 3, 2, 4, 3, 4, 5, 5 }, // Tile 4
    .{ 5, 5, 3, 4, 4, 6, 6, 7 }, // Tile 5
    .{ 6, 5, 5, 6, 6, 7, 6, 7 }, // Tile 6
    .{ 7, 6, 7, 7, 7, 8, 8, 8 }, // Tile 7
    .{ 8, 7, 7, 8, 8, 9, 9, 9 }, // Tile 8
    .{ 9, 7, 8, 8, 9, 9, 10, 10 }, // Tile 9
    .{ 10, 10, 10, 10, 9, 10, 9, 10 }, // Tile 9
};

// Simple LCG random number generator
var rng_seed: u32 = 12345;
fn random() u32 {
    rng_seed = rng_seed *% 1103515245 +% 12345;
    return (rng_seed >> 16) & 0x7FFF;
}

fn randomU8(max: u8) u8 {
    return @intCast(random() % @as(u32, max));
}

// Import audio module for non-blocking PC speaker playback
const audio = @import("audio.zig");

// Re-export sound effect functions for convenience
const sfxClick = audio.sfxClick;
const sfxPlaceTile = audio.sfxPlaceTile;
const sfxRegenerate = audio.sfxRegenerate;
const sfxError = audio.sfxError;

// Font data from font.asm - 59 characters (ASCII 32-90), 8x8 pixels
// Each character is 8 bytes, one byte per row
// Bit 7 = leftmost pixel, Bit 0 = rightmost pixel
const font_data = [_][8]u8{
    .{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, // Space (32)
    .{ 0x60, 0xF0, 0xF0, 0xF0, 0x60, 0x60, 0x00, 0x60 }, // !
    .{ 0xD8, 0xD8, 0xD8, 0x00, 0x00, 0x00, 0x00, 0x00 }, // "
    .{ 0x6C, 0xFE, 0xFE, 0x6C, 0xFE, 0x6C, 0x00, 0x00 }, // #
    .{ 0x1E, 0x3E, 0x68, 0x78, 0x3C, 0x0E, 0x7C, 0x08 }, // $
    .{ 0xE2, 0xE6, 0xEC, 0x18, 0x3E, 0x6E, 0x4E, 0x00 }, // %
    .{ 0x00, 0x00, 0x38, 0x38, 0x38, 0x00, 0x00, 0x00 }, // &
    .{ 0x60, 0x30, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00 }, // '
    .{ 0x78, 0xF8, 0xE0, 0xC0, 0xC0, 0xE0, 0x78, 0x00 }, // (
    .{ 0xF0, 0xF8, 0x38, 0x18, 0x18, 0x38, 0xF0, 0x00 }, // )
    .{ 0xCC, 0xCC, 0x30, 0xFC, 0xFC, 0x30, 0xCC, 0x00 }, // *
    .{ 0x00, 0x30, 0x30, 0xFC, 0xFC, 0x30, 0x30, 0x00 }, // +
    .{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x60, 0x60, 0x20 }, // ,
    .{ 0x00, 0x00, 0x00, 0xF8, 0xF8, 0x00, 0x00, 0x00 }, // -
    .{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x60, 0x60, 0x00 }, // .
    .{ 0x18, 0x18, 0x30, 0x30, 0x30, 0x60, 0x60, 0x00 }, // /
    .{ 0x7C, 0xFE, 0xCE, 0xD6, 0xE6, 0xC6, 0x7C, 0x00 }, // 0 (48)
    .{ 0x18, 0x38, 0x78, 0x18, 0x18, 0x18, 0x18, 0x00 }, // 1
    .{ 0x7C, 0xFE, 0xC6, 0x1E, 0x7C, 0xC0, 0xFE, 0x00 }, // 2
    .{ 0x7C, 0xFE, 0xC6, 0x0C, 0xCE, 0xC6, 0x7C, 0x00 }, // 3
    .{ 0x66, 0xE6, 0xC6, 0xFE, 0x7E, 0x06, 0x06, 0x00 }, // 4
    .{ 0xFE, 0xFE, 0xC0, 0xF8, 0xFE, 0x06, 0xFE, 0x00 }, // 5
    .{ 0x7E, 0xFE, 0xC0, 0xC0, 0xFE, 0xC6, 0xFE, 0x00 }, // 6
    .{ 0xFE, 0xFE, 0x06, 0x06, 0x0C, 0x0C, 0x0C, 0x00 }, // 7
    .{ 0x7C, 0xFE, 0xC6, 0xC6, 0x7C, 0xC6, 0x7C, 0x00 }, // 8
    .{ 0x7C, 0xFE, 0xC6, 0xC6, 0xFE, 0x06, 0x06, 0x00 }, // 9
    .{ 0x00, 0x38, 0x38, 0x00, 0x38, 0x38, 0x00, 0x00 }, // :
    .{ 0x00, 0x38, 0x38, 0x00, 0x38, 0x38, 0x70, 0x00 }, // ;
    .{ 0x10, 0x30, 0x7F, 0xFF, 0x7F, 0x30, 0x10, 0x00 }, // <
    .{ 0x00, 0xFC, 0xFC, 0x00, 0xFC, 0xFC, 0x00, 0x00 }, // =
    .{ 0x08, 0x0C, 0xFE, 0xFF, 0xFE, 0x0C, 0x08, 0x00 }, // >
    .{ 0x78, 0xFC, 0xCC, 0xDC, 0x18, 0x30, 0x00, 0x30 }, // ?
    .{ 0xFE, 0xBD, 0xBD, 0x81, 0xBD, 0xA5, 0xFF, 0x00 }, // @
    .{ 0x78, 0xFC, 0xCC, 0xCC, 0xFC, 0xFC, 0xCC, 0x00 }, // A (65)
    .{ 0xF8, 0xFC, 0xCC, 0xF8, 0xFC, 0xCC, 0xF8, 0x00 }, // B
    .{ 0x7C, 0xFC, 0xC0, 0xC0, 0xC0, 0xC0, 0x7C, 0x00 }, // C
    .{ 0xF8, 0xFC, 0xCC, 0xCC, 0xCC, 0xCC, 0xF8, 0x00 }, // D
    .{ 0xFC, 0xFC, 0xC0, 0xF8, 0xF8, 0xC0, 0xFC, 0x00 }, // E
    .{ 0xFC, 0xFC, 0xC0, 0xF8, 0xF8, 0xC0, 0xC0, 0x00 }, // F
    .{ 0x7C, 0xFC, 0xC0, 0xDC, 0xDC, 0xC4, 0xF8, 0x00 }, // G
    .{ 0xCC, 0xCC, 0xCC, 0xFC, 0xFC, 0xCC, 0xCC, 0x00 }, // H
    .{ 0x38, 0x38, 0x38, 0x38, 0x38, 0x38, 0x38, 0x00 }, // I
    .{ 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0xF8, 0x00 }, // J
    .{ 0xCC, 0xDC, 0xF8, 0xF0, 0xF8, 0xDC, 0xCC, 0x00 }, // K
    .{ 0xC0, 0xC0, 0xC0, 0xC0, 0xC0, 0xC0, 0xFC, 0x00 }, // L
    .{ 0xC6, 0xEE, 0xFE, 0xD6, 0xC6, 0xC6, 0xC6, 0x00 }, // M
    .{ 0xC6, 0xE6, 0xF6, 0xDE, 0xCE, 0xC6, 0xC6, 0x00 }, // N
    .{ 0x7C, 0xFE, 0xC6, 0xC6, 0xC6, 0xC6, 0x7C, 0x00 }, // O
    .{ 0xF8, 0xCC, 0xCC, 0xCC, 0xFC, 0xC0, 0xC0, 0x00 }, // P
    .{ 0x7C, 0xFE, 0xC6, 0xC6, 0xD6, 0xCA, 0x74, 0x00 }, // Q
    .{ 0xF8, 0xCC, 0xCC, 0xCC, 0xFC, 0xD8, 0xCC, 0x00 }, // R
    .{ 0x7C, 0xFC, 0xC0, 0xF0, 0x78, 0x1C, 0xF8, 0x00 }, // S
    .{ 0xFC, 0xFC, 0x30, 0x30, 0x30, 0x30, 0x30, 0x00 }, // T
    .{ 0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0x78, 0x00 }, // U
    .{ 0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0x48, 0x30, 0x00 }, // V
    .{ 0xC6, 0xC6, 0xC6, 0xD6, 0xD6, 0x7C, 0x28, 0x00 }, // W
    .{ 0xC6, 0xC6, 0x6C, 0x7C, 0x38, 0x6C, 0xC6, 0x00 }, // X
    .{ 0xC6, 0xC6, 0x6C, 0x6C, 0x10, 0x10, 0x10, 0x00 }, // Y
    .{ 0xFC, 0xFC, 0x0C, 0x3C, 0xF0, 0xC0, 0xFC, 0x00 }, // Z
};

// Font starts at ASCII 32 (space)
const FONT_FIRST_CHAR: u8 = 32;
const FONT_CHAR_COUNT: u8 = 59;

// Draw a single character at (x,y) with shadow effect
fn drawChar(fb: [*]u32, fb_stride: u32, x: u32, y: u32, c: u8, color: u32) void {
    const idx = c - FONT_FIRST_CHAR;
    if (idx >= FONT_CHAR_COUNT) return;

    const char_data = font_data[idx];
    var row: u32 = 0;
    while (row < 8) : (row += 1) {
        var col: u32 = 0;
        const row_data = char_data[row];
        while (col < 8) : (col += 1) {
            // Check bit 7-col (leftmost is bit 7)
            const bit_set = (row_data >> @as(u3, @intCast(7 - col))) & 1;
            if (bit_set != 0) {
                // Draw shadow first (black, offset by 1 pixel)
                fb[(y + 1 + row) * fb_stride + (x + 1 + col)] = 0xFF000000;
                // Then draw the actual character
                fb[(y + row) * fb_stride + (x + col)] = color;
            }
        }
    }
}

// Draw a string at (x,y)
fn drawString(fb: [*]u32, fb_stride: u32, x: u32, y: u32, str: []const u8, color: u32) void {
    var dx: u32 = 0;
    for (str) |c| {
        drawChar(fb, fb_stride, x + dx, y, c, color);
        dx += 9; // 8 pixel width + 1 spacing
    }
}

// Draw a number with 3 digits (padded with zeros)
fn drawNumber3(fb: [*]u32, fb_stride: u32, x: u32, y: u32, num: i32, color: u32) void {
    var n: i32 = if (num < 0) -num else num;
    if (n > 999) n = 999;

    const hundreds = @divTrunc(n, 100);
    const tens = @divTrunc(@rem(n, 100), 10);
    const ones = @rem(n, 10);

    drawChar(fb, fb_stride, x, y, @as(u8, @intCast('0' + hundreds)), color);
    drawChar(fb, fb_stride, x + 9, y, @as(u8, @intCast('0' + tens)), color);
    drawChar(fb, fb_stride, x + 18, y, @as(u8, @intCast('0' + ones)), color);
}

// Maximum map size (1920x1080 / 16 = 120x68 tiles)
const MAX_MAP_COLS: u32 = 120;
const MAX_MAP_ROWS: u32 = 68;
var terrain_map: [MAX_MAP_COLS * MAX_MAP_ROWS]u8 = undefined;

// Generate procedural terrain map
fn generateTerrain(fb: [*]u32, fb_stride: u32, screen_w: u32, screen_h: u32) void {
    const map_cols = screen_w / TILE_SIZE;
    const map_rows = screen_h / TILE_SIZE;

    // Generate map data
    var row: u32 = 0;
    while (row < map_rows) : (row += 1) {
        var col: u32 = 0;
        while (col < map_cols) : (col += 1) {
            const map_idx = row * map_cols + col;
            var tile: u8 = 0;

            if (col == 0 and row == 0) {
                // First tile (0,0): random from first 10 tiles
                tile = randomU8(10);
            } else if (col == 0) {
                // First column (not first row): check top neighbor only
                const top_tile = terrain_map[map_idx - map_cols];
                const rule_idx = randomU8(8);
                tile = terrain_rules[top_tile][rule_idx];
            } else if (row == 0) {
                // First row (not first column): check left neighbor only
                const left_tile = terrain_map[map_idx - 1];
                const rule_idx = randomU8(8);
                tile = terrain_rules[left_tile][rule_idx];
            } else {
                // Other tiles: randomly choose between left and top neighbor rules
                const left_tile = terrain_map[map_idx - 1];
                const top_tile = terrain_map[map_idx - map_cols];
                const rule_idx = randomU8(8);

                // 50/50 chance to use left or top tile rules
                if (randomU8(2) == 0) {
                    tile = terrain_rules[left_tile][rule_idx];
                } else {
                    tile = terrain_rules[top_tile][rule_idx];
                }
            }

            // Clamp to valid range 0-9
            if (tile > 9) tile = 9;

            terrain_map[map_idx] = tile;
        }
    }

    // Draw the map
    row = 0;
    while (row < map_rows) : (row += 1) {
        var col: u32 = 0;
        while (col < map_cols) : (col += 1) {
            const tile = terrain_map[row * map_cols + col];
            const tile_sheet_x = tile % TILES_PER_ROW;
            const tile_sheet_y = tile / TILES_PER_ROW;
            const screen_x = col * TILE_SIZE;
            const screen_y = row * TILE_SIZE;
            drawTile(fb, fb_stride, tile_sheet_x, tile_sheet_y, screen_x, screen_y);
        }
    }
}

const PALETTE_COLS: u32 = 4;
const PALETTE_ROWS: u32 = 4;
const PALETTE_CELL_SIZE: u32 = 16; // Half size for smaller palette
const PALETTE_X: u32 = 10;
const PALETTE_Y: u32 = 10;
const TILESET_DISPLAY_X: u32 = 100; // Where to display full tileset
const TILESET_DISPLAY_Y: u32 = 10;

fn simdCopy(dst: [*]u32, src: [*]const u32, len: usize) void {
    const Vec4 = @Vector(4, u32);
    const vec_pixels = len / 4;
    const remainder = len % 4;

    var i: usize = 0;
    while (i < vec_pixels) : (i += 1) {
        const src_vec: *align(1) const Vec4 = @ptrCast(src + i * 4);
        const dst_vec: *align(1) Vec4 = @ptrCast(dst + i * 4);
        dst_vec.* = src_vec.*;
    }

    const rem_start = vec_pixels * 4;
    var j: usize = 0;
    while (j < remainder) : (j += 1) {
        dst[rem_start + j] = src[rem_start + j];
    }
}

// Convert RGB (PPM) to BGRA (framebuffer)
fn rgbToBgra(r: u8, g: u8, b: u8) u32 {
    return 0xFF000000 | (@as(u32, r) << 16) | (@as(u32, g) << 8) | @as(u32, b);
}

// Draw a tile from the tileset to the framebuffer
// tile_x, tile_y: position in tilesheet (0-15, 0-7)
// screen_x, screen_y: position on screen
fn drawTile(fb: [*]u32, fb_stride: u32, tile_x: u32, tile_y: u32, screen_x: u32, screen_y: u32) void {
    const ppm_data: [*]const u8 = @ptrCast(tileset_ppm.ptr + PPM_HEADER_SIZE);
    const tilesheet_stride = TILESHEET_W * 3; // 256 pixels * 3 bytes RGB

    var ty: u32 = 0;
    while (ty < TILE_SIZE) : (ty += 1) {
        // Calculate row offset in tilesheet
        const tile_row_y = tile_y * TILE_SIZE + ty;
        const row_offset = tile_row_y * tilesheet_stride;
        const tile_col_x = tile_x * TILE_SIZE * 3; // 16 pixels * 3 bytes

        var tx: u32 = 0;
        while (tx < TILE_SIZE) : (tx += 1) {
            const pixel_offset = row_offset + tile_col_x + (tx * 3);
            const r = ppm_data[pixel_offset];
            const g = ppm_data[pixel_offset + 1];
            const b = ppm_data[pixel_offset + 2];
            fb[(screen_y + ty) * fb_stride + (screen_x + tx)] = rgbToBgra(r, g, b);
        }
    }
}

// Draw a sprite tile with transparency (black is transparent)
// tile_index: 0-127 for the tile to use as sprite
// screen_x, screen_y: position on screen (can be negative for partial off-screen)
fn drawSprite(fb: [*]u32, fb_stride: u32, tile_index: u32, screen_x: i32, screen_y: i32) void {
    const tile_x = tile_index % 16;
    const tile_y = tile_index / 16;
    const ppm_data: [*]const u8 = @ptrCast(tileset_ppm.ptr + PPM_HEADER_SIZE);
    const tilesheet_stride = TILESHEET_W * 3;

    var ty: u32 = 0;
    while (ty < TILE_SIZE) : (ty += 1) {
        const pixel_y = screen_y + @as(i32, @intCast(ty));
        if (pixel_y < 0) continue;

        // Calculate row offset in tilesheet
        const tile_row_y = tile_y * TILE_SIZE + ty;
        const row_offset = tile_row_y * tilesheet_stride;
        const tile_col_x = tile_x * TILE_SIZE * 3;

        var tx: u32 = 0;
        while (tx < TILE_SIZE) : (tx += 1) {
            const pixel_x = screen_x + @as(i32, @intCast(tx));
            if (pixel_x < 0) continue;

            const pixel_offset = row_offset + tile_col_x + (tx * 3);
            const r = ppm_data[pixel_offset];
            const g = ppm_data[pixel_offset + 1];
            const b = ppm_data[pixel_offset + 2];

            // Skip black pixels (transparent)
            if (r == 0 and g == 0 and b == 0) continue;

            fb[@as(u32, @intCast(pixel_y)) * fb_stride + @as(u32, @intCast(pixel_x))] = rgbToBgra(r, g, b);
        }
    }
}

fn inPalette(x: i32, y: i32) bool {
    return x >= PALETTE_X and x < PALETTE_X + @as(i32, @intCast(PALETTE_COLS * PALETTE_CELL_SIZE)) and
        y >= PALETTE_Y and y < PALETTE_Y + @as(i32, @intCast(PALETTE_ROWS * PALETTE_CELL_SIZE));
}

fn getPaletteColorIndex(x: i32, y: i32) usize {
    const col = @as(u32, @intCast(x - PALETTE_X)) / PALETTE_CELL_SIZE;
    const row = @as(u32, @intCast(y - PALETTE_Y)) / PALETTE_CELL_SIZE;
    return @as(usize, @intCast(row * PALETTE_COLS + col));
}

pub fn main() uefi.Status {
    const st = uefi.system_table;
    const boot_services = st.boot_services orelse return .aborted;
    const con_in = st.con_in orelse return .success;

    var gop: *uefi.protocol.GraphicsOutput = undefined;
    const result = boot_services.locateProtocol(uefi.protocol.GraphicsOutput, null) catch |err| switch (err) {
        error.InvalidParameter => return .invalid_parameter,
        error.Unexpected => return .aborted,
    };
    gop = result orelse return .aborted;

    // Use current mode (native resolution)
    // Optionally try 1920x1080 if available
    var chosen_mode: u32 = gop.mode.mode;
    var mode_idx: u32 = 0;
    while (mode_idx < gop.mode.max_mode) : (mode_idx += 1) {
        const info = gop.queryMode(mode_idx) catch continue;
        if (info.horizontal_resolution == 1920 and info.vertical_resolution == 1080) {
            chosen_mode = mode_idx;
            break;
        }
    }

    if (chosen_mode != gop.mode.mode) {
        gop.setMode(chosen_mode) catch {};
    }

    const screen_w = gop.mode.info.horizontal_resolution;
    const screen_h = gop.mode.info.vertical_resolution;
    const stride = gop.mode.info.pixels_per_scan_line;
    const fb_size = stride * screen_h;
    const fb: [*]u32 = @ptrFromInt(@as(usize, @truncate(gop.mode.frame_buffer_base)));

    // Allocate backbuffer (render everything here first, then copy to fb once)
    const backbuffer_alloc = boot_services.allocatePool(uefi.tables.MemoryType.loader_data, fb_size * @sizeOf(u32)) catch {
        return .out_of_resources;
    };
    const backbuffer: [*]u32 = @ptrCast(@alignCast(backbuffer_alloc));

    // Clear backbuffer to black
    const bg_color: u32 = 0xFF000000;
    var py: u32 = 0;
    while (py < screen_h) : (py += 1) {
        var px: u32 = 0;
        while (px < screen_w) : (px += 1) {
            backbuffer[py * stride + px] = bg_color;
        }
    }

    // Generate terrain to backbuffer
    generateTerrain(backbuffer, stride, screen_w, screen_h);

    // Draw tileset preview (1:1 scale, 32x32 pixels per tile)
    // 8x4 tiles = 256x128 pixels total
    const ppm_data: [*]const u8 = @ptrCast(tileset_ppm.ptr + PPM_HEADER_SIZE);
    const tilesheet_stride = TILESHEET_W * 3;
    var tile_y: u32 = 0;
    while (tile_y < TILES_PER_COL) : (tile_y += 1) {
        var tile_x: u32 = 0;
        while (tile_x < TILES_PER_ROW) : (tile_x += 1) {
            const preview_x = TILESET_DISPLAY_X + tile_x * TILE_SIZE;
            const preview_y = TILESET_DISPLAY_Y + tile_y * TILE_SIZE;
            const tile_row_y = tile_y * TILE_SIZE;
            const tile_col_x = tile_x * TILE_SIZE * 3;

            // Draw full 32x32 tile
            var ppy: u32 = 0;
            while (ppy < TILE_SIZE) : (ppy += 1) {
                var ppx: u32 = 0;
                while (ppx < TILE_SIZE) : (ppx += 1) {
                    const src_y = tile_row_y + ppy;
                    const src_x = tile_col_x + ppx * 3;
                    const pixel_offset = src_y * tilesheet_stride + src_x;
                    const r = ppm_data[pixel_offset];
                    const g = ppm_data[pixel_offset + 1];
                    const b = ppm_data[pixel_offset + 2];
                    backbuffer[(preview_y + ppy) * stride + (preview_x + ppx)] = rgbToBgra(r, g, b);
                }
            }
        }
    }

    // Copy static scene to framebuffer once
    simdCopy(fb, backbuffer, fb_size);

    // Setup mouse
    var mouse: ?*uefi.protocol.SimplePointer = null;
    var mouse_available = false;

    if (boot_services.locateProtocol(uefi.protocol.SimplePointer, null)) |mouse_result| {
        if (mouse_result) |m| {
            mouse = m;
            mouse_available = true;
            _ = mouse.?.reset(true) catch {};
        }
    } else |_| {}

    // Initialize cursor
    var cursor_x: i32 = @intCast(screen_w >> 1);
    var cursor_y: i32 = @intCast(screen_h >> 1);
    var last_dx: i32 = 0;
    var last_dy: i32 = 0;

    // Event loop
    var running = true;
    var events: [2]uefi.Event = undefined;
    var num_events: usize = 1;
    events[0] = con_in.wait_for_key;

    if (mouse_available) {
        const mouse_evt = mouse.?.wait_for_input;
        if (@intFromPtr(mouse_evt) != 0) {
            events[1] = mouse_evt;
            num_events = 2;
        }
    }

    while (running) {
        const wait_result = boot_services.waitForEvent(events[0..num_events]) catch continue;
        const index = wait_result[1];

        if (index == 0) {
            if (con_in.readKeyStroke()) |_| running = false else |_| {}
        }

        if (mouse_available and index == 1) {
            if (mouse.?.getState()) |state| {
                const raw_dx = state.relative_movement_x;
                const raw_dy = state.relative_movement_y;
                const dx = @divTrunc(raw_dx, 5000);
                const dy = @divTrunc(raw_dy, 5000);

                var new_x = cursor_x + @as(i32, @intCast(dx));
                var new_y = cursor_y + @as(i32, @intCast(dy));

                if (new_x < 0) new_x = 0;
                if (new_y < 0) new_y = 0;
                if (new_x >= @as(i32, @intCast(screen_w))) new_x = @intCast(screen_w - 1);
                if (new_y >= @as(i32, @intCast(screen_h))) new_y = @intCast(screen_h - 1);

                // Update cursor position
                cursor_x = new_x;
                cursor_y = new_y;
                last_dx = @as(i32, @intCast(dx));
                last_dy = @as(i32, @intCast(dy));

                // Right button: regenerate terrain with new seed
                if (state.right_button) {
                    const new_seed = @as(u32, @intCast(cursor_x)) *% 12345 +% @as(u32, @intCast(cursor_y)) *% 67890 +% rng_seed;
                    rng_seed = new_seed;
                    // Generate to fb, then copy to backbuffer
                    generateTerrain(fb, stride, screen_w, screen_h);
                    simdCopy(backbuffer, fb, fb_size);
                    // Play regeneration sound
                    sfxRegenerate();
                }

                // Left button: spawn random tile at grid position
                // Also update the backbuffer so the change persists
                if (state.left_button and !inPalette(cursor_x, cursor_y)) {
                    const grid_col = @as(u32, @intCast(cursor_x)) / TILE_SIZE;
                    const grid_row = @as(u32, @intCast(cursor_y)) / TILE_SIZE;
                    const map_cols = screen_w / TILE_SIZE;
                    const map_idx = grid_row * map_cols + grid_col;
                    const random_tile = randomU8(@intCast(TOTAL_TILES));

                    if (map_idx < terrain_map.len) {
                        terrain_map[map_idx] = random_tile;
                    }

                    const tile_sheet_x = random_tile % TILES_PER_ROW;
                    const tile_sheet_y = random_tile / TILES_PER_ROW;
                    const screen_x = grid_col * TILE_SIZE;
                    const screen_y = grid_row * TILE_SIZE;
                    // Draw to backbuffer (permanent)
                    drawTile(backbuffer, stride, tile_sheet_x, tile_sheet_y, screen_x, screen_y);
                    // Play tile placement sound
                    sfxPlaceTile();
                }
            } else |_| {}
        }

        // Restore backbuffer (static scene with terrain and placed tiles)
        simdCopy(fb, backbuffer, fb_size);

        // Update audio (process sound queue)
        audio.audio_player.update();

        // Draw debug info with labels (dynamic overlay)
        // Format: X: 000 Y: 000 DX: 000 DY: 000
        drawString(fb, stride, screen_w - 300, 5, "X:", 0xFFFFFFFF);
        drawNumber3(fb, stride, screen_w - 285, 5, cursor_x, 0xFFFFFFFF);

        drawString(fb, stride, screen_w - 250, 5, "Y:", 0xFFFFFFFF);
        drawNumber3(fb, stride, screen_w - 235, 5, cursor_y, 0xFFFFFFFF);

        drawString(fb, stride, screen_w - 200, 5, "DX:", 0xFFFFFFFF);
        drawNumber3(fb, stride, screen_w - 180, 5, last_dx, 0xFFFFFFFF);

        drawString(fb, stride, screen_w - 140, 5, "DY:", 0xFFFFFFFF);
        drawNumber3(fb, stride, screen_w - 120, 5, last_dy, 0xFFFFFFFF);

        // Draw cursor as sprite (use tile 67 = 0x43 as cursor, centered on position)
        // This is the only dynamic sprite drawn each frame
        const CURSOR_TILE: u32 = 67;
        drawSprite(fb, stride, CURSOR_TILE, cursor_x - 8, cursor_y - 8);
    }

    _ = boot_services.freePool(@ptrCast(@alignCast(backbuffer))) catch {};
    return .success;
}

pub fn panic(_: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    while (true) asm volatile ("hlt");
}
