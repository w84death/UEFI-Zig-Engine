// UI rendering and display components

const constants = @import("constants.zig");
const font = @import("font.zig");
const config = @import("config.zig");
const input = @import("input.zig");
const game_of_life = @import("game_of_life.zig");

/// Draw debug information panel
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
    const start_x = screen_w - 300;
    const y = 5;
    const color = 0xFFFFFFFF;

    // Mouse position
    font.drawString(fb, fb_stride, start_x, y, "X:", color);
    font.drawNumber3(fb, fb_stride, start_x + 15, y, mouse_state.x, color);

    font.drawString(fb, fb_stride, start_x + 50, y, "Y:", color);
    font.drawNumber3(fb, fb_stride, start_x + 65, y, mouse_state.y, color);

    font.drawString(fb, fb_stride, start_x + 100, y, "DX:", color);
    font.drawNumber3(fb, fb_stride, start_x + 120, y, mouse_state.last_dx, color);

    font.drawString(fb, fb_stride, start_x + 160, y, "DY:", color);
    font.drawNumber3(fb, fb_stride, start_x + 180, y, mouse_state.last_dy, color);

    // Game of Life status
    const gol_y = y + 15;
    if (gol_running) {
        font.drawString(fb, fb_stride, start_x, gol_y, "GOL:ON", color);
    } else {
        font.drawString(fb, fb_stride, start_x, gol_y, "GOL:OFF", color);
    }
    font.drawString(fb, fb_stride, start_x + 60, gol_y, "LIVE:", color);
    font.drawNumber3(fb, fb_stride, start_x + 105, gol_y, @intCast(living_cells), color);

    // Chaos mode indicator
    const chaos_y = gol_y + 15;
    if (game_of_life.isChaosMode()) {
        font.drawString(fb, fb_stride, start_x, chaos_y, "CHAOS:ON", color);
    } else {
        font.drawString(fb, fb_stride, start_x, chaos_y, "CHAOS:OFF", color);
    }

    // Speed indicator
    const speed_y = chaos_y + 15;
    font.drawString(fb, fb_stride, start_x, speed_y, "SPD:", color);
    font.drawNumber3(fb, fb_stride, start_x + 35, speed_y, @intCast(gol_interval), color);

    // Generation counter
    const gen_y = speed_y + 15;
    font.drawString(fb, fb_stride, start_x, gen_y, "GEN:", color);
    font.drawNumber3(fb, fb_stride, start_x + 35, gen_y, @intCast(generation), color);
}

/// Draw "Civilisation collapsed" message
pub fn drawCivilizationCollapsed(
    fb: [*]u32,
    fb_stride: u32,
    screen_w: u32,
    screen_h: u32,
    generation: u32,
) void {
    const center_x = screen_w / 2 - 150;
    const center_y = screen_h / 2 - 20;
    const warning_color = 0xFFFF0000; // Red

    // Main message
    font.drawString(fb, fb_stride, center_x, center_y, "Civilisation collapsed!", warning_color);

    // Duration info
    const gen_str = "Lasted ";
    font.drawString(fb, fb_stride, center_x, center_y + 15, gen_str, warning_color);
    font.drawNumber3(fb, fb_stride, center_x + @as(u32, @intCast(gen_str.len)) * 9, center_y + 15, @intCast(generation), warning_color);
    font.drawString(fb, fb_stride, center_x + @as(u32, @intCast(gen_str.len)) * 9 + 35, center_y + 15, "generations", warning_color);
}
