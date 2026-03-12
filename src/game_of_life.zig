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

// Stability tracking: counts how many generations a cell has been in the same state
// Used to detect stalled patterns like 2x2 blocks
pub var stability_counter: [MAX_CELLS]u8 = undefined;
const STABILITY_THRESHOLD: u8 = 10; // Sacrifice after 10 generations of stability

// Soil tile range (tiles 0-6 are valid for life, 7-10 are rocky/deadly)
const MIN_SOIL_TILE: u8 = 0;
const MAX_SOIL_TILE: u8 = 6;

/// Living cell sprites
/// Young cells (newly born or unstable) use sprite 19
/// Mature cells (stable) use sprite 20
pub const YOUNG_CELL_TILE: u32 = 19;
pub const MATURE_CELL_TILE: u32 = 20;
/// Threshold for cell maturity - cells with stability < this are "young"
pub const YOUNG_THRESHOLD: u8 = 5;

/// Chaos mode: terrain-dependent probabilities for cell survival
pub var chaos_mode: bool = true; // Enabled by default

/// Generation counter
pub var generation: u32 = 0;

/// Check if civilization is dead (no living cells)
pub fn isDead() bool {
    return countLiving() == 0;
}

/// Check if a terrain tile is soil (can support life)
fn isSoil(tile: u8) bool {
    return tile >= MIN_SOIL_TILE and tile <= MAX_SOIL_TILE;
}

/// Kill all cells on rocky terrain (>=7)
pub fn killRockyCells(map_cols: u32, map_rows: u32) void {
    var row: u32 = 0;
    while (row < map_rows) : (row += 1) {
        var col: u32 = 0;
        while (col < map_cols) : (col += 1) {
            const map_idx = row * map_cols + col;
            if (cell_buffer[map_idx] != 0) {
                const terrain_tile = terrain.getTile(map_idx);
                // Kill cell if terrain is rocky (>=7, i.e., not 0-6)
                if (terrain_tile > MAX_SOIL_TILE) {
                    cell_buffer[map_idx] = 0;
                }
            }
        }
    }
}

/// Initialize the Game of Life with random cells on soil
pub fn init(map_cols: u32, map_rows: u32) void {
    @memset(&cell_buffer, 0);
    @memset(&stability_counter, 0); // Reset stability tracking
    generation = 0; // Reset generation counter

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
    @memset(&stability_counter, 0); // Reset stability tracking
    generation = 0; // Reset generation counter
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
///
/// Chaos mode: 50/50 chance that any state change is applied
pub fn update(map_cols: u32, map_rows: u32) void {
    // First, kill any cells on rocky terrain
    killRockyCells(map_cols, map_rows);

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
                    // Only spawn on soil tiles (0-6)
                    const terrain_tile = terrain.getTile(map_idx);
                    if (isSoil(terrain_tile)) {
                        next_gen[map_idx] = 1;
                    }
                }
            }
        }
    }

    // Apply chaos mode: terrain-dependent probabilities
    // Classical GoL rules calculated first, then we check if the change should actually happen
    // 0-1 (harsh): 25% birth chance, 75% death chance
    // 2-5 (normal): 50% birth chance, 50% death chance
    // 6-7 (fertile): 75% birth chance, 25% death chance
    if (chaos_mode) {
        var r: u32 = 0;
        while (r < map_rows) : (r += 1) {
            var c: u32 = 0;
            while (c < map_cols) : (c += 1) {
                const map_idx = r * map_cols + c;
                const terrain_tile = terrain.getTile(map_idx);

                // Skip if not on soil
                if (!isSoil(terrain_tile)) continue;

                const was_alive = cell_buffer[map_idx] != 0;
                const will_be_alive = next_gen[map_idx] != 0;

                // Determine birth/death probabilities based on terrain
                var birth_chance: u8 = 50; // default 50%
                var death_chance: u8 = 50; // default 50%
                if (terrain_tile <= 1) {
                    // Harsh terrain (0-1): hard to be born, easy to die
                    birth_chance = 25;
                    death_chance = 75;
                } else if (terrain_tile >= 6) {
                    // Fertile terrain (6-7): easy to be born, hard to die
                    birth_chance = 75;
                    death_chance = 25;
                }

                // Check if GoL wants to change the cell state
                if (!was_alive and will_be_alive) {
                    // GoL says BIRTH (0 -> 1)
                    // Apply birth probability
                    if (rng.randomU8(100) >= birth_chance) {
                        next_gen[map_idx] = 0; // Birth failed, stay dead
                    }
                } else if (was_alive and !will_be_alive) {
                    // GoL says DEATH (1 -> 0)
                    // Apply death probability
                    if (rng.randomU8(100) >= death_chance) {
                        next_gen[map_idx] = 1; // Death failed, stay alive
                    }
                }
                // If state doesn't change, do nothing
            }
        }
    }

    // Apply stability-based sacrifice to break stalled patterns (2x2 blocks, etc.)
    // If a cell hasn't changed for STABILITY_THRESHOLD generations, it may sacrifice
    var sacrifice_r: u32 = 0;
    while (sacrifice_r < map_rows) : (sacrifice_r += 1) {
        var sacrifice_c: u32 = 0;
        while (sacrifice_c < map_cols) : (sacrifice_c += 1) {
            const map_idx = sacrifice_r * map_cols + sacrifice_c;
            const was_alive = cell_buffer[map_idx] != 0;
            const is_alive_now = next_gen[map_idx] != 0;

            if (was_alive == is_alive_now) {
                // State hasn't changed - increment stability counter
                if (stability_counter[map_idx] < 255) {
                    stability_counter[map_idx] += 1;
                }
            } else {
                // State changed - reset stability counter
                stability_counter[map_idx] = 0;
            }

            // Check for sacrifice condition: alive and stable for threshold
            if (is_alive_now and stability_counter[map_idx] >= STABILITY_THRESHOLD) {
                // 10% chance to sacrifice and spawn nearby
                if (rng.randomU8(100) < 10) {
                    // Sacrifice this cell (it dies)
                    next_gen[map_idx] = 0;

                    // Try to spawn in one of the 8 neighboring cells
                    const dr = [_]i32{ -1, -1, -1, 0, 0, 1, 1, 1 };
                    const dc = [_]i32{ -1, 0, 1, -1, 1, -1, 0, 1 };

                    // Try up to 3 times to find a valid neighbor
                    var attempts: u8 = 0;
                    while (attempts < 3) : (attempts += 1) {
                        const dir = rng.randomU8(8);
                        const nr = @as(i32, @intCast(sacrifice_r)) + dr[dir];
                        const nc = @as(i32, @intCast(sacrifice_c)) + dc[dir];

                        // Check bounds
                        if (nr < 0 or nr >= @as(i32, @intCast(map_rows))) continue;
                        if (nc < 0 or nc >= @as(i32, @intCast(map_cols))) continue;

                        const neighbor_idx = @as(usize, @intCast(nr)) * map_cols + @as(usize, @intCast(nc));
                        const neighbor_tile = terrain.getTile(neighbor_idx);

                        // Only spawn on soil and only if cell is dead
                        if (isSoil(neighbor_tile) and next_gen[neighbor_idx] == 0) {
                            next_gen[neighbor_idx] = 1;
                            stability_counter[neighbor_idx] = 0; // Reset stability for new cell
                            break;
                        }
                    }
                }
            }
        }
    }

    // Copy next generation to current
    @memcpy(&cell_buffer, &next_gen);

    // Increment generation counter
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
/// Young cells (stability < YOUNG_THRESHOLD) use sprite 19
/// Mature cells (stability >= YOUNG_THRESHOLD) use sprite 20
pub fn draw(fb: [*]u32, fb_stride: u32, map_cols: u32, map_rows: u32) void {
    var row: u32 = 0;
    while (row < map_rows) : (row += 1) {
        var col: u32 = 0;
        while (col < map_cols) : (col += 1) {
            const map_idx = row * map_cols + col;
            if (cell_buffer[map_idx] != 0) {
                const screen_x = @as(i32, @intCast(col * constants.TILE_SIZE));
                const screen_y = @as(i32, @intCast(row * constants.TILE_SIZE));
                // Choose sprite based on stability
                const is_young = stability_counter[map_idx] < YOUNG_THRESHOLD;
                const sprite = if (is_young) YOUNG_CELL_TILE else MATURE_CELL_TILE;
                graphics.drawSprite(fb, fb_stride, sprite, screen_x, screen_y);
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
