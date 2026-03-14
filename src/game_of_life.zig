// Game of Life visualization on terrain
// Sparse optimization: only tracks alive cells and their neighbors ("hot cells")
// instead of scanning the entire grid every generation.
// Maintains alive count for O(1) isDead()/countLiving().
// Threaded update not possible in UEFI (no OS scheduler), but algorithm is optimized.

const constants = @import("constants.zig");
const terrain = @import("terrain.zig");
const graphics = @import("graphics.zig");
const utils = @import("utils.zig");
const config = @import("config.zig");

// Maximum grid size: 120 * 80 = 9600 cells
pub const MAX_CELLS = constants.MAX_MAP_COLS * constants.MAX_MAP_ROWS;

// Cell state buffer (0 = dead, 1 = alive)
pub var cell_buffer: [MAX_CELLS]u8 = undefined;

// Stability tracking: counts generations a cell stays in same state
pub var stability_counter: [MAX_CELLS]u8 = undefined;

// Sparse alive cell tracking
// Instead of scanning all 9600 cells, we maintain a list of alive indices
// and a boolean lookup for O(1) neighbor checks.
var alive_cells: [MAX_CELLS]u32 = undefined;
var alive_count: u32 = 0;
var is_alive: [MAX_CELLS]bool = undefined; // O(1) lookup

// Hot cells: alive cells + their neighbors (the only cells that can change)
var hot_cells: [MAX_CELLS * 9 / 8 + 64]u32 = undefined; // generous buffer
var hot_count: u32 = 0;
var hot_generation: [MAX_CELLS]u32 = undefined; // generation counter avoids full memset
var hot_gen_counter: u32 = 0;

// Living cell sprite tiles
pub const YOUNG_CELL_TILE: u32 = 11;
pub const MATURE_CELL_TILE: u32 = 12;
pub const YOUNG_THRESHOLD: u8 = 7;

pub var chaos_mode: bool = true;
pub var generation: u32 = 0;

// Dirty flag - set when cells change, cleared after draw
// Skips draw work when no cells exist or nothing changed
var dirty: bool = true;

// Neighbor direction offsets (8-connected)
const DR = [_]i32{ -1, -1, -1, 0, 0, 1, 1, 1 };
const DC = [_]i32{ -1, 0, 1, -1, 1, -1, 0, 1 };

/// Rebuild the hot cells list from current alive cells.
/// Hot cells = alive cells + all their 8 neighbors.
/// These are the only cells that can change state in the next generation.
fn rebuildHotCells(map_cols: u32, map_rows: u32) void {
    hot_gen_counter += 1;
    hot_count = 0;

    // Use alive_count snapshot to avoid processing cells added during iteration
    const count = alive_count;
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const idx = alive_cells[i];
        const row = idx / map_cols;
        const col = idx % map_cols;

        // Add alive cell itself
        if (hot_generation[idx] != hot_gen_counter) {
            hot_generation[idx] = hot_gen_counter;
            hot_cells[hot_count] = idx;
            hot_count += 1;
        }

        // Add all 8 neighbors
        var d: u32 = 0;
        while (d < 8) : (d += 1) {
            const nr = @as(i32, @intCast(row)) + DR[d];
            const nc = @as(i32, @intCast(col)) + DC[d];
            if (nr < 0 or nr >= @as(i32, @intCast(map_rows))) continue;
            if (nc < 0 or nc >= @as(i32, @intCast(map_cols))) continue;
            const n_idx = @as(u32, @intCast(nr)) * map_cols + @as(u32, @intCast(nc));
            if (hot_generation[n_idx] != hot_gen_counter) {
                hot_generation[n_idx] = hot_gen_counter;
                hot_cells[hot_count] = n_idx;
                hot_count += 1;
            }
        }
    }
}

/// Check if a terrain tile is soil (supports life)
fn isSoil(tile: u8) bool {
    return tile <= 6;
}

/// Count living neighbors from prev_buffer (snapshot)
fn countNeighborsFromBuf(map_cols: u32, map_rows: u32, idx: u32) u8 {
    const row = idx / map_cols;
    const col = idx % map_cols;
    var count: u8 = 0;
    var d: u32 = 0;
    while (d < 8) : (d += 1) {
        const nr = @as(i32, @intCast(row)) + DR[d];
        const nc = @as(i32, @intCast(col)) + DC[d];
        if (nr < 0 or nr >= @as(i32, @intCast(map_rows))) continue;
        if (nc < 0 or nc >= @as(i32, @intCast(map_cols))) continue;
        const n_idx = @as(u32, @intCast(nr)) * map_cols + @as(u32, @intCast(nc));
        if (prev_buffer[n_idx] != 0) count += 1;
    }
    return count;
}

/// Initialize with random cells on soil tiles
pub fn init(map_cols: u32, map_rows: u32) void {
    @memset(&cell_buffer, 0);
    @memset(&is_alive, false);
    @memset(&stability_counter, 0);
    @memset(&hot_generation, 0);
    alive_count = 0;
    hot_gen_counter = 0;
    generation = 0;
    dirty = true;

    var row: u32 = 0;
    while (row < map_rows) : (row += 1) {
        var col: u32 = 0;
        while (col < map_cols) : (col += 1) {
            const map_idx = row * map_cols + col;
            const terrain_tile = terrain.getTile(map_idx);
            if (isSoil(terrain_tile) and utils.rngRandomU8(100) < config.INITIAL_SPAWN_CHANCE) {
                cell_buffer[map_idx] = 1;
                is_alive[map_idx] = true;
                alive_cells[alive_count] = map_idx;
                alive_count += 1;
            }
        }
    }
    rebuildHotCells(map_cols, map_rows);
}

/// Clear all living cells
pub fn clear() void {
    @memset(&cell_buffer, 0);
    @memset(&is_alive, false);
    @memset(&stability_counter, 0);
    alive_count = 0;
    hot_gen_counter = 0;
    generation = 0;
    dirty = true;
}

/// Kill a specific cell and update tracking
fn killCellAt(idx: u32) void {
    cell_buffer[idx] = 0;
    is_alive[idx] = false;
    // Swap-and-pop removal from alive_cells
    var i: u32 = 0;
    while (i < alive_count) : (i += 1) {
        if (alive_cells[i] == idx) {
            alive_count -= 1;
            alive_cells[i] = alive_cells[alive_count];
            return;
        }
    }
}

/// Previous generation buffer (snapshot of cell_buffer before update)
var prev_buffer: [MAX_CELLS]u8 = undefined;

/// Update one generation
pub fn update(map_cols: u32, map_rows: u32) void {
    // Kill cells on rocky terrain
    {
        var i: u32 = 0;
        while (i < alive_count) {
            const idx = alive_cells[i];
            if (terrain.getTile(idx) > 6) {
                alive_count -= 1;
                alive_cells[i] = alive_cells[alive_count];
                cell_buffer[idx] = 0;
                is_alive[idx] = false;
            } else {
                i += 1;
            }
        }
    }

    // Snapshot cell_buffer BEFORE GoL rules
    @memcpy(&prev_buffer, &cell_buffer);

    // Phase 1: GoL rules - FULL GRID SCAN (debugging version)
    {
        var row: u32 = 0;
        while (row < map_rows) : (row += 1) {
            var col: u32 = 0;
            while (col < map_cols) : (col += 1) {
                const idx = row * map_cols + col;
                const was_alive = prev_buffer[idx] != 0;
                const neighbors = countNeighborsFromBuf(map_cols, map_rows, idx);

                if (was_alive) {
                    cell_buffer[idx] = if (neighbors == 2 or neighbors == 3) 1 else 0;
                } else {
                    if (neighbors == 3 and isSoil(terrain.getTile(idx))) {
                        cell_buffer[idx] = 1;
                    } else {
                        cell_buffer[idx] = 0;
                    }
                }
            }
        }
    }

    // Phase 2: Chaos mode - FULL GRID SCAN
    if (chaos_mode) {
        var row: u32 = 0;
        while (row < map_rows) : (row += 1) {
            var col: u32 = 0;
            while (col < map_cols) : (col += 1) {
                const idx = row * map_cols + col;
                const terrain_tile = terrain.getTile(idx);
                if (!isSoil(terrain_tile)) continue;

                const was_alive = prev_buffer[idx] != 0;
                const will_be_alive = cell_buffer[idx] != 0;
                const is_birth = !was_alive and will_be_alive;
                const is_death = was_alive and !will_be_alive;

                var birth_chance: u8 = 50;
                var death_chance: u8 = 50;
                if (terrain_tile <= 1) {
                    birth_chance = 25;
                    death_chance = 75;
                } else if (terrain_tile >= 6) {
                    birth_chance = 75;
                    death_chance = 25;
                }

                if (is_birth and utils.rngRandomU8(100) >= birth_chance) {
                    cell_buffer[idx] = 0;
                } else if (is_death and utils.rngRandomU8(100) >= death_chance) {
                    cell_buffer[idx] = 1;
                }
            }
        }
    }

    // Phase 3: Stability sacrifice - FULL GRID SCAN
    {
        var row: u32 = 0;
        while (row < map_rows) : (row += 1) {
            var col: u32 = 0;
            while (col < map_cols) : (col += 1) {
                const idx = row * map_cols + col;
                const was_alive = prev_buffer[idx] != 0;
                const is_alive_now = cell_buffer[idx] != 0;

                if (was_alive == is_alive_now) {
                    if (stability_counter[idx] < 255) stability_counter[idx] += 1;
                } else {
                    stability_counter[idx] = 0;
                }

                if (is_alive_now and stability_counter[idx] >= config.STABILITY_THRESHOLD) {
                    if (utils.rngRandomU8(100) < 10) {
                        cell_buffer[idx] = 0;
                        const r = row;
                        const c = col;
                        var attempts: u8 = 0;
                        while (attempts < 3) : (attempts += 1) {
                            const dir = utils.rngRandomU8(8);
                            const nr = @as(i32, @intCast(r)) + DR[dir];
                            const nc = @as(i32, @intCast(c)) + DC[dir];
                            if (nr < 0 or nr >= @as(i32, @intCast(map_rows))) continue;
                            if (nc < 0 or nc >= @as(i32, @intCast(map_cols))) continue;
                            const n_idx = @as(u32, @intCast(nr)) * map_cols + @as(u32, @intCast(nc));
                            if (isSoil(terrain.getTile(n_idx)) and prev_buffer[n_idx] == 0 and cell_buffer[n_idx] == 0) {
                                cell_buffer[n_idx] = 1;
                                stability_counter[n_idx] = 0;
                                break;
                            }
                        }
                    }
                }
            }
        }
    }

    // Phase 4: Rebuild alive tracking from cell_buffer (full scan)
    alive_count = 0;
    {
        var row: u32 = 0;
        while (row < map_rows) : (row += 1) {
            var col: u32 = 0;
            while (col < map_cols) : (col += 1) {
                const idx = row * map_cols + col;
                is_alive[idx] = cell_buffer[idx] != 0;
                if (cell_buffer[idx] != 0) {
                    alive_cells[alive_count] = idx;
                    alive_count += 1;
                }
            }
        }
    }

    if (alive_count > 0) dirty = true;
    generation += 1;
}

/// Toggle chaos mode
pub fn toggleChaosMode() void {
    chaos_mode = !chaos_mode;
}

/// Get chaos mode status
pub fn isChaosMode() bool {
    return chaos_mode;
}

/// Spawn a living cell at grid coordinates (if on soil)
pub fn spawnCell(grid_col: u32, grid_row: u32, map_cols: u32) bool {
    const map_idx = grid_row * map_cols + grid_col;
    if (map_idx >= MAX_CELLS) return false;
    if (is_alive[map_idx]) return false; // Already alive

    const terrain_tile = terrain.getTile(map_idx);
    if (!isSoil(terrain_tile)) return false;

    cell_buffer[map_idx] = 1;
    is_alive[map_idx] = true;
    alive_cells[alive_count] = map_idx;
    alive_count += 1;
    dirty = true;
    return true;
}

/// Kill a cell at grid coordinates
pub fn killCell(grid_col: u32, grid_row: u32, map_cols: u32) void {
    const map_idx = grid_row * map_cols + grid_col;
    if (map_idx < MAX_CELLS and is_alive[map_idx]) {
        killCellAt(map_idx);
        dirty = true;
    }
}

/// Check if cell is alive at position - O(1)
pub fn isAlive(grid_col: u32, grid_row: u32, map_cols: u32) bool {
    const map_idx = grid_row * map_cols + grid_col;
    if (map_idx >= MAX_CELLS) return false;
    return is_alive[map_idx];
}

/// Toggle cell state at position
pub fn toggleCell(grid_col: u32, grid_row: u32, map_cols: u32) bool {
    const map_idx = grid_row * map_cols + grid_col;
    if (map_idx >= MAX_CELLS) return false;

    const terrain_tile = terrain.getTile(map_idx);
    if (!isSoil(terrain_tile)) return false;

    if (is_alive[map_idx]) {
        killCellAt(map_idx);
    } else {
        cell_buffer[map_idx] = 1;
        is_alive[map_idx] = true;
        alive_cells[alive_count] = map_idx;
        alive_count += 1;
    }
    dirty = true;
    return true;
}

/// Draw living cells - only iterates alive cells instead of full grid
pub fn draw(fb: [*]u32, fb_stride: u32, map_cols: u32, _: u32) void {
    var i: u32 = 0;
    while (i < alive_count) : (i += 1) {
        const idx = alive_cells[i];
        const col = idx % map_cols;
        const row = idx / map_cols;
        const screen_x = @as(i32, @intCast(col * constants.TILE_SIZE));
        const screen_y = @as(i32, @intCast(row * constants.TILE_SIZE));
        const is_young = stability_counter[idx] < YOUNG_THRESHOLD;
        const sprite = if (is_young) YOUNG_CELL_TILE else MATURE_CELL_TILE;
        graphics.drawSprite(fb, fb_stride, sprite, screen_x, screen_y);
    }
}

/// Check if civilization is dead - O(1) instead of scanning all cells
pub fn isDead() bool {
    return alive_count == 0;
}

/// Count total living cells - O(1)
pub fn countLiving() u32 {
    return alive_count;
}
