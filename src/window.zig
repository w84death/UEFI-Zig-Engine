// 9-patch (scale-9) window rendering using tiles 21-29
// 3x3 Grid layout:
// Row 1 (Header):  21:Top-left   22:Top-edge   23:Top-right
// Row 2 (Content): 24:Left-edge  25:Fill       26:Right-edge
// Row 3 (Footer):  27:Bot-left   28:Bot-edge   29:Bot-right

const constants = @import("constants.zig");
const graphics = @import("graphics.zig");
const font = @import("font.zig");

// Tile IDs in the tilesheet (tile_index -> tile_x, tile_y where tile_x = index % 16, tile_y = index / 16)
// Window frame tiles: 20-28
const TILE_TL: u32 = 20; // Top-left corner (tile index 20)
const TILE_TC: u32 = 21; // Top edge/header center
const TILE_TR: u32 = 22; // Top-right corner
const TILE_ML: u32 = 23; // Middle-left edge
const TILE_MC: u32 = 24; // Middle-center fill
const TILE_MR: u32 = 25; // Middle-right edge
const TILE_BL: u32 = 26; // Bottom-left corner
const TILE_BC: u32 = 27; // Bottom edge center
const TILE_BR: u32 = 28; // Bottom-right corner

/// Window descriptor
pub const Window = struct {
    x: u32,
    y: u32,
    w: u32,
    h: u32,
    title: ?[]const u8,
};

/// Get tile coordinates in the tilesheet from tile index
fn tileX(tile_index: u32) u32 {
    return tile_index % 16;
}

fn tileY(tile_index: u32) u32 {
    return tile_index / 16;
}

/// Draw a 9-patch window
pub fn drawWindow(fb: [*]u32, fb_stride: u32, win: Window) void {
    const tile_size = constants.TILE_SIZE;

    // Calculate how many tiles fit in each dimension
    const cols = win.w / tile_size;
    const rows = win.h / tile_size;

    // Ensure minimum size (3x3 tiles minimum)
    if (cols < 3 or rows < 3) return;

    // Draw row by row
    var row: u32 = 0;
    while (row < rows) : (row += 1) {
        const screen_y = win.y + row * tile_size;

        // Determine which tile row to use based on window row
        const is_top_row = (row == 0);
        const is_bottom_row = (row == rows - 1);

        var col: u32 = 0;
        while (col < cols) : (col += 1) {
            const screen_x = win.x + col * tile_size;

            // Determine which tile column to use based on window column
            const is_left_col = (col == 0);
            const is_right_col = (col == cols - 1);

            // Select appropriate tile based on position
            var tile_idx: u32 = undefined;

            if (is_top_row) {
                if (is_left_col) tile_idx = TILE_TL else if (is_right_col) tile_idx = TILE_TR else tile_idx = TILE_TC;
            } else if (is_bottom_row) {
                if (is_left_col) tile_idx = TILE_BL else if (is_right_col) tile_idx = TILE_BR else tile_idx = TILE_BC;
            } else {
                // Middle rows
                if (is_left_col) tile_idx = TILE_ML else if (is_right_col) tile_idx = TILE_MR else tile_idx = TILE_MC;
            }

            // Draw the tile
            graphics.drawTile(fb, fb_stride, tileX(tile_idx), tileY(tile_idx), screen_x, screen_y);
        }
    }

    // Draw title in the header row (centered)
    if (win.title) |title| {
        const title_width = @as(u32, @intCast(title.len)) * 9;
        const title_x = win.x + (win.w - title_width) / 2;
        const title_y = win.y + 4;
        font.drawString(fb, fb_stride, title_x, title_y, title, 0xFFFFFFFF);
    }
}

/// Calculate window height needed for N lines of text
pub fn calculateHeight(lines: u32) u32 {
    // Top edge + bottom edge + line height per line + padding
    return (2 + lines) * 16 + 8;
}

/// Calculate window width needed for text (approximate)
pub fn calculateWidth(chars: u32) u32 {
    const text_width = chars * 9;
    const min_width = 3 * 16;
    if (text_width + 32 < min_width) return min_width;
    return text_width + 32;
}
