// Runtime configuration - values that can change during execution

// Game of Life update configuration
pub var gol_update_interval: u32 = 1;
pub const GOL_INTERVAL_MIN: u32 = 1;
pub const GOL_INTERVAL_MAX: u32 = 120;
pub const GOL_INTERVAL_STEP: u32 = 1;

// Game of Life cell configuration
pub const YOUNG_THRESHOLD: u8 = 5;
pub const STABILITY_THRESHOLD: u8 = 10;
pub const MIN_SOIL_TILE: u8 = 0;
pub const MAX_SOIL_TILE: u8 = 6;
pub const INITIAL_SPAWN_CHANCE: u8 = 15;

// Terrain generation configuration
pub const MAX_TILE_VALUE: u8 = 9;

// UI configuration
pub var show_tileset: bool = false;
pub var show_debug: bool = true;

// Audio configuration
pub const DURATION_SHORT: u32 = 2;
pub const DURATION_MEDIUM: u32 = 4;
pub const DURATION_LONG: u32 = 6;

/// Reset all runtime configuration to defaults
pub fn resetAll() void {
    gol_update_interval = 1;
    show_tileset = false;
    show_debug = true;
}
