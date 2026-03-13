// UI rendering and display components

const constants = @import("constants.zig");
const font = @import("font.zig");
const config = @import("config.zig");
const input = @import("input.zig");
const game_of_life = @import("game_of_life.zig");
const window = @import("window.zig");
const graphics = @import("graphics.zig");

// Window styling
const WINDOW_PADDING_X: u32 = 8;
const WINDOW_PADDING_Y: u32 = 8;
const LINE_HEIGHT: u32 = 12;
const COL_WIDTH: u32 = 9;

/// Draw debug information panel in a window
pub fn drawDebugInfo(
    fb: [*]u32,
    fb_stride: u32,
    screen_w: u32,
    screen_h: u32,
    mouse_state: *const input.MouseState,
    gol_running: bool,
    living_cells: u32,
    gol_interval: u32,
    generation: u32,
) void {
    const win_w: u32 = 300;
    const win_h: u32 = 180;
    const win_x = screen_w - win_w - 10;
    const win_y: u32 = 10;
    const text_color = 0xFFFFFFFF;

    // Draw window frame
    window.drawWindow(fb, fb_stride, .{
        .x = win_x,
        .y = win_y,
        .w = win_w,
        .h = win_h,
        .title = "DEBUG INFO",
    });

    // Content area starts below title bar
    const content_x = win_x + WINDOW_PADDING_X;
    const content_y = win_y + WINDOW_PADDING_Y + 16; // Below title

    // Line 1: Resolution
    var y = content_y;
    font.drawString(fb, fb_stride, content_x, y, "RES:", text_color);
    font.drawNumber(fb, fb_stride, content_x + 35, y, screen_w, text_color);
    font.drawString(fb, fb_stride, content_x + 85, y, "x", text_color);
    font.drawNumber(fb, fb_stride, content_x + 100, y, screen_h, text_color);

    // Line 2: Mouse X/Y
    y += LINE_HEIGHT;
    font.drawString(fb, fb_stride, content_x, y, "X:", text_color);
    font.drawNumber3(fb, fb_stride, content_x + 20, y, mouse_state.x, text_color);
    font.drawString(fb, fb_stride, content_x + 70, y, "Y:", text_color);
    font.drawNumber3(fb, fb_stride, content_x + 90, y, mouse_state.y, text_color);

    // Line 3: Mouse DX/DY
    y += LINE_HEIGHT;
    font.drawString(fb, fb_stride, content_x, y, "DX:", text_color);
    font.drawNumber3(fb, fb_stride, content_x + 25, y, mouse_state.last_dx, text_color);
    font.drawString(fb, fb_stride, content_x + 75, y, "DY:", text_color);
    font.drawNumber3(fb, fb_stride, content_x + 100, y, mouse_state.last_dy, text_color);

    // Line 4: GOL status and living count
    y += LINE_HEIGHT;
    const status_str = if (gol_running) "GOL:ON " else "GOL:OFF";
    font.drawString(fb, fb_stride, content_x, y, status_str, text_color);
    font.drawString(fb, fb_stride, content_x + 70, y, "LIVE:", text_color);
    font.drawNumber3(fb, fb_stride, content_x + 115, y, @intCast(living_cells), text_color);

    // Line 5: Chaos mode
    y += LINE_HEIGHT;
    const chaos_str = if (game_of_life.isChaosMode()) "CHAOS:ON " else "CHAOS:OFF";
    font.drawString(fb, fb_stride, content_x, y, chaos_str, text_color);

    // Line 6: Speed and Generation
    y += LINE_HEIGHT;
    font.drawString(fb, fb_stride, content_x, y, "SPD:", text_color);
    font.drawNumber3(fb, fb_stride, content_x + 35, y, @intCast(gol_interval), text_color);
    font.drawString(fb, fb_stride, content_x + 65, y, "GEN:", text_color);
    font.drawNumber(fb, fb_stride, content_x + 105, y, generation, text_color);

    // Controls help at bottom
    y += LINE_HEIGHT + 6;
    font.drawString(fb, fb_stride, content_x, y, "SPACE:Pause | G:Terrain", text_color);
    y += LINE_HEIGHT;
    font.drawString(fb, fb_stride, content_x, y, "C:Clear | R:Reset | T:Tileset", text_color);
    y += LINE_HEIGHT;
    font.drawString(fb, fb_stride, content_x, y, "+/-:Speed | H:Chaos", text_color);
}

/// Draw "Civilisation collapsed" message in a centered window
pub fn drawCivilizationCollapsed(
    fb: [*]u32,
    fb_stride: u32,
    screen_w: u32,
    screen_h: u32,
    generation: u32,
) void {
    const title_color = 0xFFFF0000; // Red title
    const text_color = 0xFFFFFFFF;

    // Calculate window size based on generation number length
    // "Lasted " (7 chars) + number + " generations" (11 chars) = ~18-22 chars minimum
    const gen_digits = if (generation == 0) 1 else blk: {
        var n = generation;
        var count: u32 = 0;
        while (n > 0) : (n /= 10) count += 1;
        break :blk count;
    };
    const num_display_width = gen_digits * 9; // 9 pixels per character
    const min_content_width = 7 * 9 + num_display_width + 11 * 9; // "Lasted " + number + " generations"
    const win_w = @min(480, @max(320, min_content_width + 32)); // Min 320, max 480, with padding
    const win_h: u32 = 80;
    const win_x = (screen_w - win_w) / 2;
    const win_y = (screen_h - win_h) / 2;

    // Draw window frame with red title
    window.drawWindow(fb, fb_stride, .{
        .x = win_x,
        .y = win_y,
        .w = win_w,
        .h = win_h,
        .title = "GAME OVER",
    });

    // Content area
    const content_x = win_x + WINDOW_PADDING_X + 8;
    const content_y = win_y + WINDOW_PADDING_Y + 20;

    // Main message
    font.drawString(fb, fb_stride, content_x, content_y, "Civilisation collapsed!", title_color);

    // Duration info on next line
    const y2 = content_y + LINE_HEIGHT + 4;
    font.drawString(fb, fb_stride, content_x, y2, "Lasted ", text_color);
    // drawNumber right-aligns, so position at right edge of number
    const num_x = content_x + 55 + num_display_width - 9;
    font.drawNumber(fb, fb_stride, num_x, y2, generation, text_color);
    font.drawString(fb, fb_stride, content_x + 60 + num_display_width, y2, "generations", text_color);

    // Press key hint
    const y3 = y2 + LINE_HEIGHT + 4;
    font.drawString(fb, fb_stride, content_x + 40, y3, "Press R to restart", text_color);
}
