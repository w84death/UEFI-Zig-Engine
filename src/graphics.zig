// Graphics utilities: SIMD operations, color conversion, tile rendering

const constants = @import("constants.zig");

/// Fast SIMD copy of pixel data
pub fn simdCopy(dst: [*]u32, src: [*]const u32, len: usize) void {
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

/// Convert RGB (PPM) to BGRA (framebuffer)
pub fn rgbToBgra(r: u8, g: u8, b: u8) u32 {
    return 0xFF000000 | (@as(u32, r) << 16) | (@as(u32, g) << 8) | @as(u32, b);
}

/// Get tileset pixel data pointer
pub fn getTilesetData() [*]const u8 {
    return @ptrCast(constants.tileset_ppm.ptr + constants.PPM_HEADER_SIZE);
}

/// Calculate tilesheet stride in bytes
pub fn getTilesheetStride() u32 {
    return constants.TILESHEET_W * 3;
}

/// Draw a tile from the tileset to the framebuffer
/// tile_x, tile_y: position in tilesheet (0-15, 0-7)
/// screen_x, screen_y: position on screen
pub fn drawTile(fb: [*]u32, fb_stride: u32, tile_x: u32, tile_y: u32, screen_x: u32, screen_y: u32) void {
    const ppm_data = getTilesetData();
    const tilesheet_stride = getTilesheetStride();

    var ty: u32 = 0;
    while (ty < constants.TILE_SIZE) : (ty += 1) {
        // Calculate row offset in tilesheet
        const tile_row_y = tile_y * constants.TILE_SIZE + ty;
        const row_offset = tile_row_y * tilesheet_stride;
        const tile_col_x = tile_x * constants.TILE_SIZE * 3; // 16 pixels * 3 bytes

        var tx: u32 = 0;
        while (tx < constants.TILE_SIZE) : (tx += 1) {
            const pixel_offset = row_offset + tile_col_x + (tx * 3);
            const r = ppm_data[pixel_offset];
            const g = ppm_data[pixel_offset + 1];
            const b = ppm_data[pixel_offset + 2];
            fb[(screen_y + ty) * fb_stride + (screen_x + tx)] = rgbToBgra(r, g, b);
        }
    }
}

/// Draw a sprite tile with transparency (black is transparent)
/// tile_index: 0-127 for the tile to use as sprite
/// screen_x, screen_y: position on screen (can be negative for partial off-screen)
pub fn drawSprite(fb: [*]u32, fb_stride: u32, tile_index: u32, screen_x: i32, screen_y: i32) void {
    const tile_x = tile_index % 16;
    const tile_y = tile_index / 16;
    const ppm_data = getTilesetData();
    const tilesheet_stride = getTilesheetStride();

    var ty: u32 = 0;
    while (ty < constants.TILE_SIZE) : (ty += 1) {
        const pixel_y = screen_y + @as(i32, @intCast(ty));
        if (pixel_y < 0) continue;

        // Calculate row offset in tilesheet
        const tile_row_y = tile_y * constants.TILE_SIZE + ty;
        const row_offset = tile_row_y * tilesheet_stride;
        const tile_col_x = tile_x * constants.TILE_SIZE * 3;

        var tx: u32 = 0;
        while (tx < constants.TILE_SIZE) : (tx += 1) {
            const pixel_x = screen_x + @as(i32, @intCast(tx));
            if (pixel_x < 0) continue;

            const pixel_offset = row_offset + tile_col_x + (tx * 3);
            const r = ppm_data[pixel_offset];
            const g = ppm_data[pixel_offset + 1];
            const b = ppm_data[pixel_offset + 2];

            // Skip palette color 0 (black) pixels - treat as transparent
            // Palette color 0 is 0xFF140C1C = RGB(20, 12, 28)
            // Use tolerance to account for slight variations in the sprite
            if (r <= 30 and g <= 25 and b <= 40) continue;

            fb[@as(u32, @intCast(pixel_y)) * fb_stride + @as(u32, @intCast(pixel_x))] = rgbToBgra(r, g, b);
        }
    }
}

/// Clear framebuffer to a solid color
pub fn clearScreen(fb: [*]u32, fb_stride: u32, screen_w: u32, screen_h: u32, color: u32) void {
    var y: u32 = 0;
    while (y < screen_h) : (y += 1) {
        var x: u32 = 0;
        while (x < screen_w) : (x += 1) {
            fb[y * fb_stride + x] = color;
        }
    }
}

/// Draw a section of the tileset directly to the framebuffer
pub fn drawTilesetPreview(fb: [*]u32, fb_stride: u32, screen_x: u32, screen_y: u32, tiles_per_row: u32, tiles_per_col: u32) void {
    const ppm_data = getTilesetData();
    const tilesheet_stride = getTilesheetStride();

    var tile_y: u32 = 0;
    while (tile_y < tiles_per_col) : (tile_y += 1) {
        var tile_x: u32 = 0;
        while (tile_x < tiles_per_row) : (tile_x += 1) {
            const preview_x = screen_x + tile_x * constants.TILE_SIZE;
            const preview_y = screen_y + tile_y * constants.TILE_SIZE;
            const tile_row_y = tile_y * constants.TILE_SIZE;
            const tile_col_x = tile_x * constants.TILE_SIZE * 3;

            // Draw full tile
            var ppy: u32 = 0;
            while (ppy < constants.TILE_SIZE) : (ppy += 1) {
                var ppx: u32 = 0;
                while (ppx < constants.TILE_SIZE) : (ppx += 1) {
                    const src_y = tile_row_y + ppy;
                    const src_x = tile_col_x + ppx * 3;
                    const pixel_offset = src_y * tilesheet_stride + src_x;
                    const r = ppm_data[pixel_offset];
                    const g = ppm_data[pixel_offset + 1];
                    const b = ppm_data[pixel_offset + 2];
                    fb[(preview_y + ppy) * fb_stride + (preview_x + ppx)] = rgbToBgra(r, g, b);
                }
            }
        }
    }
}
