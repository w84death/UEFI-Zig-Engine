// Shared utilities and helpers

const std = @import("std");

// =============================================================================
// Random Number Generation (LCG)
// =============================================================================

var rng_seed: u32 = 12345;

/// Initialize RNG with a seed value
pub fn rngInit(new_seed: u32) void {
    rng_seed = new_seed;
}

/// Generate a random 15-bit value (0-32767)
pub fn rngRandom() u32 {
    rng_seed = rng_seed *% 1103515245 +% 12345;
    return (rng_seed >> 16) & 0x7FFF;
}

/// Generate random u8 in range [0, limit)
pub fn rngRandomU8(limit: u8) u8 {
    return @intCast(rngRandom() % @as(u32, limit));
}

/// Get current seed value
pub fn rngGetSeed() u32 {
    return rng_seed;
}

/// Set seed from position (for terrain regeneration)
pub fn rngSetSeed(new_seed: u32) void {
    rng_seed = new_seed;
}

/// Generate seed from screen coordinates
pub fn generateSeedFromPos(x: i32, y: i32) u32 {
    return @as(u32, @intCast(x)) *% 12345 +% @as(u32, @intCast(y)) *% 67890 +% rng_seed;
}

// =============================================================================
// Math Utilities
// =============================================================================

/// Clamp i32 value to range [lo, hi]
pub fn clamp(val: i32, lo: i32, hi: i32) i32 {
    if (val < lo) return lo;
    if (val > hi) return hi;
    return val;
}

/// Clamp u32 value to range [lo, hi]
pub fn clampU32(val: u32, lo: u32, hi: u32) u32 {
    if (val < lo) return lo;
    if (val > hi) return hi;
    return val;
}

/// Minimum of two u32 values
pub fn min(a: u32, b: u32) u32 {
    return if (a < b) a else b;
}

/// Maximum of two u32 values
pub fn max(a: u32, b: u32) u32 {
    return if (a > b) a else b;
}

// =============================================================================
// Coordinate Utilities
// =============================================================================

/// Grid position from screen coordinates
pub fn screenToGrid(screen_x: i32, screen_y: i32, tile_size: u32) struct { col: u32, row: u32 } {
    return .{
        .col = @as(u32, @intCast(screen_x)) / tile_size,
        .row = @as(u32, @intCast(screen_y)) / tile_size,
    };
}

/// Screen position from grid coordinates
pub fn gridToScreen(col: u32, row: u32, tile_size: u32) struct { x: u32, y: u32 } {
    return .{
        .x = col * tile_size,
        .y = row * tile_size,
    };
}

/// Calculate map index from grid position
pub fn getMapIndex(col: u32, row: u32, cols: u32) usize {
    return @as(usize, row * cols + col);
}
