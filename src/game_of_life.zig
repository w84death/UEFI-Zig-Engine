// Game of Life visualization on terrain
// Uses sprite 21 (tile index 20) for living cells
// Classical rules with terrain constraint: new cells only spawn on soil tiles (1-8)

const constants = @import("constants.zig");
const terrain = @import("terrain.zig");
const graphics = @import("graphics.zig");
const rng = @import("rng.zig");

// Living cell storage - bit packed for efficiency
// Each cell needs 1 bit: 0 = dead, 1 = alive
// Maximum map size: 120 * 68 = 8160 cells = 1020 bytes
pub const MAX_CELLS = constants.MAX_MAP_COLS * constants.MAX_MAP_ROWS;
pub var cell_buffer: [MAX_CELLS]u8 = undefined;

// Soil tile range (tiles 1-8 are valid for spawning)
const MIN_SOIL_TILE: u8 = 1;
const MAX_SOIL_TILE: u8 = 8;

/// Living cell sprite (tile index 20, which is the 21st tile)
pub const LIVING_CELL_TILE: u32 = 20;

/// Check if a terrain tile is soil (can support life)
fn isSoil(tile: u8) bool {
    return tile >= MIN_SOIL_TILE and tile <= MAX_SOIL_TILE;
}

/// Initialize the Game of Life with random cells on soil
pub fn init(map_cols: u32, map_rows: u32) void {
    @memset(&cell_buffer, 0);

    var row: u32 = 0;
    while (row < map_rows) : (row += 1) {
        var col: u32 = 0;
        while (col < map_cols) : (col += 1) {
            const map_idx = row * map_cols + col;
            const terrain_tile = terrain.getTile(map_idx);

            // Only spawn on soil with 15% probability
            if (isSoil(terrain_tile) and rng.randomU8(100) < 15) {
                cell_buffer[map_idx] = 1;
            }
        }
    }
}

/// Clear all living cells
pub fn clear() void {
    @memset(&cell_buffer, 0);
}

/// Count living neighbors for a cell
fn countNeighbors(map_cols: u32, map_rows: u32, row: u32, col: u32) u8 {
    var count: u8 = 0;

    // Check all 8 neighbors
    const dr = [_]i32{ -1, -1, -1, 0, 0, 1, 1, 1 };
    const dc = [_]i32{ -1, 0, 1, -1, 1, -1, 0, 1 };

    var i: usize = 0;
    while (i < 8) : (i += 1) {
        const nr = @as(i32, @intCast(row)) + dr[i];
        const nc = @as(i32, @intCast(col)) + dc[i];

        // Bounds check
        if (nr < 0 or nr >= @as(i32, @intCast(map_rows))) continue;
        if (nc < 0 or nc >= @as(i32, @intCast(map_cols))) continue;

        const neighbor_idx = @as(usize, @intCast(nr)) * map_cols + @as(usize, @intCast(nc));
        if (cell_buffer[neighbor_idx] != 0) {
            count += 1;
        }
    }

    return count;
}

/// Update one generation of Game of Life
/// Classical rules:
/// - Underpopulation: < 2 neighbors = die
/// - Survival: 2-3 neighbors = live
/// - Overpopulation: > 3 neighbors = die
/// - Reproduction: exactly 3 neighbors = birth (only on soil)
pub fn update(map_cols: u32, map_rows: u32) void {
    // Temporary buffer for next generation
    var next_gen: [MAX_CELLS]u8 = undefined;
    @memset(&next_gen, 0);

    var row: u32 = 0;
    while (row < map_rows) : (row += 1) {
        var col: u32 = 0;
        while (col < map_cols) : (col += 1) {
            const map_idx = row * map_cols + col;
            const is_alive = cell_buffer[map_idx] != 0;
            const neighbors = countNeighbors(map_cols, map_rows, row, col);

            if (is_alive) {
                // Classical survival rules
                if (neighbors == 2 or neighbors == 3) {
                    next_gen[map_idx] = 1;
                }
                // else: dies (underpopulation or overpopulation)
            } else {
                // Classical birth rule: exactly 3 neighbors
                if (neighbors == 3) {
                    // NEW RULE: Only spawn on soil tiles (1-8)
                    const terrain_tile = terrain.getTile(map_idx);
                    if (isSoil(terrain_tile)) {
                        next_gen[map_idx] = 1;
                    }
                }
            }
        }
    }

    // Copy next generation to current
    @memcpy(&cell_buffer, &next_gen);
}

/// Spawn a living cell at specific grid coordinates (if on soil)
pub fn spawnCell(grid_col: u32, grid_row: u32, map_cols: u32) bool {
    const map_idx = grid_row * map_cols + grid_col;
    if (map_idx >= MAX_CELLS) return false;

    const terrain_tile = terrain.getTile(map_idx);
    if (!isSoil(terrain_tile)) return false;

    cell_buffer[map_idx] = 1;
    return true;
}

/// Kill a cell at specific grid coordinates
pub fn killCell(grid_col: u32, grid_row: u32, map_cols: u32) void {
    const map_idx = grid_row * map_cols + grid_col;
    if (map_idx < MAX_CELLS) {
        cell_buffer[map_idx] = 0;
    }
}

/// Check if cell is alive at position
pub fn isAlive(grid_col: u32, grid_row: u32, map_cols: u32) bool {
    const map_idx = grid_row * map_cols + grid_col;
    if (map_idx >= MAX_CELLS) return false;
    return cell_buffer[map_idx] != 0;
}

/// Toggle cell state at position
pub fn toggleCell(grid_col: u32, grid_row: u32, map_cols: u32) bool {
    const map_idx = grid_row * map_cols + grid_col;
    if (map_idx >= MAX_CELLS) return false;

    const terrain_tile = terrain.getTile(map_idx);
    if (!isSoil(terrain_tile)) return false;

    cell_buffer[map_idx] = if (cell_buffer[map_idx] == 0) 1 else 0;
    return true;
}

/// Draw all living cells to the framebuffer
pub fn draw(fb: [*]u32, fb_stride: u32, map_cols: u32, map_rows: u32) void {
    var row: u32 = 0;
    while (row < map_rows) : (row += 1) {
        var col: u32 = 0;
        while (col < map_cols) : (col += 1) {
            const map_idx = row * map_cols + col;
            if (cell_buffer[map_idx] != 0) {
                const screen_x = @as(i32, @intCast(col * constants.TILE_SIZE));
                const screen_y = @as(i32, @intCast(row * constants.TILE_SIZE));
                graphics.drawSprite(fb, fb_stride, LIVING_CELL_TILE, screen_x, screen_y);
            }
        }
    }
}

/// Count total living cells
pub fn countLiving() u32 {
    var count: u32 = 0;
    var i: usize = 0;
    while (i < MAX_CELLS) : (i += 1) {
        if (cell_buffer[i] != 0) count += 1;
    }
    return count;
}
