// Constants and configuration for the UEFI application

pub const LOGO_W: u32 = 128;
pub const LOGO_H: u32 = 128;
pub const logo_raw: []const u8 = @embedFile("logo.raw");

// Tileset configuration
pub const TILE_SIZE: u32 = 16;
pub const TILESHEET_W: u32 = 256;
pub const TILESHEET_H: u32 = 128;
pub const TILES_PER_ROW: u32 = 16;
pub const TILES_PER_COL: u32 = 8;
pub const TOTAL_TILES: u32 = 128;
pub const tileset_ppm: []const u8 = @embedFile("tileset.ppm");

// PPM header size: "P6\n256 128\n255\n" = 12 bytes
pub const PPM_HEADER_SIZE: usize = 12;

// DawnBringer 16 color palette (ARGB format)
pub const palette: [16]u32 = .{
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
    0xFFDEEED6, // 15: White
};

// Terrain generation rules - 11 tiles, each with 8 possible next tiles
pub const terrain_rules: [11][8]u8 = .{
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
    .{ 10, 10, 10, 10, 9, 10, 9, 10 }, // Tile 10
};

// Maximum map size
pub const MAX_MAP_COLS: u32 = 120;
pub const MAX_MAP_ROWS: u32 = 68;

// UI constants
pub const PALETTE_COLS: u32 = 4;
pub const PALETTE_ROWS: u32 = 4;
pub const PALETTE_CELL_SIZE: u32 = 16;
pub const PALETTE_X: u32 = 10;
pub const PALETTE_Y: u32 = 10;
pub const TILESET_DISPLAY_X: u32 = 100;
pub const PALETTE_DISPLAY_Y: u32 = 10;

// Cursor tile
pub const CURSOR_TILE: u32 = 67;

// Font constants
pub const FONT_FIRST_CHAR: u8 = 32;
pub const FONT_CHAR_COUNT: u8 = 59;
