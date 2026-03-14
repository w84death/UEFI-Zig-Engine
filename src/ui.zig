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

/// Draw detailed mouse debug information in a window
pub fn drawMouseDebugInfo(
    fb: [*]u32,
    fb_stride: u32,
    mouse_state: *const input.MouseState,
    num_events: usize,
) void {
    const win_w: u32 = 300;
    const win_h: u32 = 200;
    const win_x: u32 = 10;
    const win_y: u32 = 10;
    const text_color = 0xFFFFFFFF;
    const warn_color = 0xFFFFD700; // Yellow for warnings
    const error_color = 0xFFFF0000; // Red for errors
    const ok_color = 0xFF00FF00; // Green for OK

    // Draw window frame
    window.drawWindow(fb, fb_stride, .{
        .x = win_x,
        .y = win_y,
        .w = win_w,
        .h = win_h,
        .title = "MOUSE DEBUG",
    });

    // Content area starts below title bar
    const content_x = win_x + WINDOW_PADDING_X;
    const content_y = win_y + WINDOW_PADDING_Y + 16;

    // Line 1: Available status and event count
    var y = content_y;
    const avail_str = if (mouse_state.available) "AVAILABLE:YES" else "AVAILABLE:NO";
    const avail_color: u32 = if (mouse_state.available) ok_color else error_color;
    font.drawString(fb, fb_stride, content_x, y, avail_str, avail_color);
    font.drawString(fb, fb_stride, content_x + 160, y, "EVT:", text_color);
    font.drawNumber(fb, fb_stride, content_x + 195, y, @intCast(num_events), text_color);

    // Line 2: Event triggered status and update count
    y += LINE_HEIGHT;
    const trig_str = if (mouse_state.event_triggered) "EVT_FIRE:YES" else "EVT_FIRE:NO";
    const trig_color: u32 = if (mouse_state.event_triggered) ok_color else error_color;
    font.drawString(fb, fb_stride, content_x, y, trig_str, trig_color);
    font.drawString(fb, fb_stride, content_x + 140, y, "UPD:", text_color);
    font.drawNumber(fb, fb_stride, content_x + 175, y, mouse_state.update_count, text_color);

    // Line 3: Protocol pointer at init vs runtime
    y += LINE_HEIGHT;
    font.drawString(fb, fb_stride, content_x, y, "INIT:", text_color);
    if (mouse_state.init_protocol_ptr == 0) {
        font.drawString(fb, fb_stride, content_x + 35, y, "NULL", error_color);
    } else {
        const init_lo: u32 = @intCast(mouse_state.init_protocol_ptr & 0xFFFFFFFF);
        font.drawNumber(fb, fb_stride, content_x + 35, y, init_lo, ok_color);
    }
    font.drawString(fb, fb_stride, content_x + 100, y, "NOW:", text_color);
    if (mouse_state.protocol_ptr == 0) {
        font.drawString(fb, fb_stride, content_x + 135, y, "NULL", error_color);
    } else {
        const prot_lo: u32 = @intCast(mouse_state.protocol_ptr & 0xFFFFFFFF);
        font.drawNumber(fb, fb_stride, content_x + 135, y, prot_lo, ok_color);
    }

    // Line 4: Event pointer (low 32 bits)
    y += LINE_HEIGHT;
    font.drawString(fb, fb_stride, content_x, y, "EVENT:", text_color);
    if (mouse_state.event_ptr == 0) {
        font.drawString(fb, fb_stride, content_x + 50, y, "NOT SET", error_color);
    } else {
        const evt_lo: u32 = @intCast(mouse_state.event_ptr & 0xFFFFFFFF);
        font.drawNumber(fb, fb_stride, content_x + 50, y, evt_lo, text_color);
    }

    // Line 5: GetState status - distinguish between OK, NotReady, DeviceError
    y += LINE_HEIGHT;
    font.drawString(fb, fb_stride, content_x, y, "STATE:", text_color);
    if (mouse_state.getstate_ok) {
        if (mouse_state.not_ready_count > 0 and mouse_state.device_error_count == 0) {
            font.drawString(fb, fb_stride, content_x + 50, y, "NOT_READY", warn_color);
        } else {
            font.drawString(fb, fb_stride, content_x + 50, y, "OK", ok_color);
        }
    } else {
        font.drawString(fb, fb_stride, content_x + 50, y, "FAIL", error_color);
    }

    // Line 6: Error counters
    y += LINE_HEIGHT;
    font.drawString(fb, fb_stride, content_x, y, "NRDY:", text_color);
    font.drawNumber(fb, fb_stride, content_x + 40, y, mouse_state.not_ready_count, text_color);
    font.drawString(fb, fb_stride, content_x + 100, y, "DERR:", text_color);
    font.drawNumber(fb, fb_stride, content_x + 140, y, mouse_state.device_error_count, error_color);
    font.drawString(fb, fb_stride, content_x + 180, y, "OERR:", text_color);
    font.drawNumber(fb, fb_stride, content_x + 220, y, mouse_state.other_error_count, error_color);

    // Line 7: Raw DX/DY values
    y += LINE_HEIGHT;
    font.drawString(fb, fb_stride, content_x, y, "RAW:", text_color);
    if (mouse_state.last_raw_dx != 0 or mouse_state.last_raw_dy != 0) {
        font.drawString(fb, fb_stride, content_x + 35, y, "DX:", warn_color);
        font.drawNumber(fb, fb_stride, content_x + 60, y, @intCast(mouse_state.last_raw_dx), warn_color);
        font.drawString(fb, fb_stride, content_x + 130, y, "DY:", warn_color);
        font.drawNumber(fb, fb_stride, content_x + 155, y, @intCast(mouse_state.last_raw_dy), warn_color);
    } else {
        font.drawString(fb, fb_stride, content_x + 35, y, "NO MOVEMENT", warn_color);
    }

    // Line 8: Scaled DX/DY
    y += LINE_HEIGHT;
    font.drawString(fb, fb_stride, content_x, y, "SCL:", text_color);
    font.drawString(fb, fb_stride, content_x + 35, y, "DX:", text_color);
    font.drawNumber3(fb, fb_stride, content_x + 60, y, mouse_state.last_dx, text_color);
    font.drawString(fb, fb_stride, content_x + 100, y, "DY:", text_color);
    font.drawNumber3(fb, fb_stride, content_x + 125, y, mouse_state.last_dy, text_color);

    // Line 9: Buttons and disabled status
    y += LINE_HEIGHT;
    font.drawString(fb, fb_stride, content_x, y, "BTN:", text_color);
    const l_str = if (mouse_state.left_button) "LEFT:1" else "LEFT:0";
    const r_str = if (mouse_state.right_button) "RIGHT:1" else "RIGHT:0";
    font.drawString(fb, fb_stride, content_x + 35, y, l_str, text_color);
    font.drawString(fb, fb_stride, content_x + 90, y, r_str, text_color);
    const dis_str = if (mouse_state.disabled) "DIS:1" else "DIS:0";
    const dis_color: u32 = if (mouse_state.disabled) error_color else text_color;
    font.drawString(fb, fb_stride, content_x + 145, y, dis_str, dis_color);

    // Line 10: Consecutive errors
    y += LINE_HEIGHT;
    font.drawString(fb, fb_stride, content_x, y, "CERR:", text_color);
    font.drawNumber(fb, fb_stride, content_x + 40, y, mouse_state.consecutive_errors, text_color);
}
