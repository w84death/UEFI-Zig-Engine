// Terrain generation and map management

const constants = @import("constants.zig");
const rng = @import("rng.zig");
const graphics = @import("graphics.zig");

// Terrain map storage
pub var terrain_map: [constants.MAX_MAP_COLS * constants.MAX_MAP_ROWS]u8 = undefined;

/// Generate procedural terrain map
pub fn generateTerrain(fb: [*]u32, fb_stride: u32, screen_w: u32, screen_h: u32) void {
    const map_cols = screen_w / constants.TILE_SIZE;
    const map_rows = screen_h / constants.TILE_SIZE;

    // Generate map data
    var row: u32 = 0;
    while (row < map_rows) : (row += 1) {
        var col: u32 = 0;
        while (col < map_cols) : (col += 1) {
            const map_idx = row * map_cols + col;
            var tile: u8 = 0;

            if (col == 0 and row == 0) {
                // First tile (0,0): random from first 10 tiles
                tile = rng.randomU8(10);
            } else if (col == 0) {
                // First column (not first row): check top neighbor only
                const top_tile = terrain_map[map_idx - map_cols];
                const rule_idx = rng.randomU8(8);
                tile = constants.terrain_rules[top_tile][rule_idx];
            } else if (row == 0) {
                // First row (not first column): check left neighbor only
                const left_tile = terrain_map[map_idx - 1];
                const rule_idx = rng.randomU8(8);
                tile = constants.terrain_rules[left_tile][rule_idx];
            } else {
                // Other tiles: randomly choose between left and top neighbor rules
                const left_tile = terrain_map[map_idx - 1];
                const top_tile = terrain_map[map_idx - map_cols];
                const rule_idx = rng.randomU8(8);

                // 50/50 chance to use left or top tile rules
                if (rng.randomU8(2) == 0) {
                    tile = constants.terrain_rules[left_tile][rule_idx];
                } else {
                    tile = constants.terrain_rules[top_tile][rule_idx];
                }
            }

            // Clamp to valid range 0-9
            if (tile > 9) tile = 9;

            terrain_map[map_idx] = tile;
        }
    }

    // Draw the map
    drawTerrain(fb, fb_stride, screen_w, screen_h);
}

/// Draw the terrain map to the framebuffer
pub fn drawTerrain(fb: [*]u32, fb_stride: u32, screen_w: u32, screen_h: u32) void {
    const map_cols = screen_w / constants.TILE_SIZE;
    const map_rows = screen_h / constants.TILE_SIZE;

    var row: u32 = 0;
    while (row < map_rows) : (row += 1) {
        var col: u32 = 0;
        while (col < map_cols) : (col += 1) {
            const tile = terrain_map[row * map_cols + col];
            const tile_sheet_x = tile % constants.TILES_PER_ROW;
            const tile_sheet_y = tile / constants.TILES_PER_ROW;
            const screen_x = col * constants.TILE_SIZE;
            const screen_y = row * constants.TILE_SIZE;
            graphics.drawTile(fb, fb_stride, tile_sheet_x, tile_sheet_y, screen_x, screen_y);
        }
    }
}

/// Get map index from grid position
pub fn getMapIndex(grid_col: u32, grid_row: u32, map_cols: u32) usize {
    return grid_row * map_cols + grid_col;
}

/// Get tile at map position
pub fn getTile(map_idx: usize) u8 {
    if (map_idx < terrain_map.len) {
        return terrain_map[map_idx];
    }
    return 0;
}

/// Set tile at map position
pub fn setTile(map_idx: usize, tile: u8) void {
    if (map_idx < terrain_map.len) {
        terrain_map[map_idx] = tile;
    }
}
