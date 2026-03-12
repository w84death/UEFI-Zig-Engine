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
    mouse_state: *const input.MouseState,
    gol_running: bool,
    living_cells: u32,
    gol_interval: u32,
    generation: u32,
) void {
    const win_w: u32 = 280;
    const win_h: u32 = 140;
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

    // Line 1: Mouse X/Y
    var y = content_y;
    font.drawString(fb, fb_stride, content_x, y, "X:", text_color);
    font.drawNumber3(fb, fb_stride, content_x + 20, y, mouse_state.x, text_color);
    font.drawString(fb, fb_stride, content_x + 70, y, "Y:", text_color);
    font.drawNumber3(fb, fb_stride, content_x + 90, y, mouse_state.y, text_color);

    // Line 2: Mouse DX/DY
    y += LINE_HEIGHT;
    font.drawString(fb, fb_stride, content_x, y, "DX:", text_color);
    font.drawNumber3(fb, fb_stride, content_x + 25, y, mouse_state.last_dx, text_color);
    font.drawString(fb, fb_stride, content_x + 75, y, "DY:", text_color);
    font.drawNumber3(fb, fb_stride, content_x + 100, y, mouse_state.last_dy, text_color);

    // Line 3: GOL status and living count
    y += LINE_HEIGHT;
    const status_str = if (gol_running) "GOL: ON " else "GOL: OFF";
    font.drawString(fb, fb_stride, content_x, y, status_str, text_color);
    font.drawString(fb, fb_stride, content_x + 80, y, "LIVE:", text_color);
    font.drawNumber3(fb, fb_stride, content_x + 125, y, @intCast(living_cells), text_color);

    // Line 4: Chaos mode
    y += LINE_HEIGHT;
    const chaos_str = if (game_of_life.isChaosMode()) "CHAOS: ON " else "CHAOS: OFF";
    font.drawString(fb, fb_stride, content_x, y, chaos_str, text_color);

    // Line 5: Speed and Generation
    y += LINE_HEIGHT;
    font.drawString(fb, fb_stride, content_x, y, "SPD:", text_color);
    font.drawNumber3(fb, fb_stride, content_x + 35, y, @intCast(gol_interval), text_color);

    y += LINE_HEIGHT;
    font.drawString(fb, fb_stride, content_x, y, "GEN:", text_color);
    font.drawNumber3(fb, fb_stride, content_x + 40, y, @intCast(generation), text_color);

    // Controls help at bottom
    y += LINE_HEIGHT + 4;
    font.drawString(fb, fb_stride, content_x, y, "SPACE:Pause C:Clear", text_color);
    y += LINE_HEIGHT;
    font.drawString(fb, fb_stride, content_x, y, "R:Reset T:Tileset +/-:Speed", text_color);
}

/// Draw "Civilisation collapsed" message in a centered window
pub fn drawCivilizationCollapsed(
    fb: [*]u32,
    fb_stride: u32,
    screen_w: u32,
    screen_h: u32,
    generation: u32,
) void {
    const win_w: u32 = 320;
    const win_h: u32 = 80;
    const win_x = (screen_w - win_w) / 2;
    const win_y = (screen_h - win_h) / 2;
    const title_color = 0xFFFF0000; // Red title
    const text_color = 0xFFFFFFFF;

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
    font.drawNumber3(fb, fb_stride, content_x + 55, y2, @intCast(generation), text_color);
    font.drawString(fb, fb_stride, content_x + 95, y2, "generations", text_color);

    // Press key hint
    const y3 = y2 + LINE_HEIGHT + 4;
    font.drawString(fb, fb_stride, content_x + 40, y3, "Press R to restart", text_color);
}
