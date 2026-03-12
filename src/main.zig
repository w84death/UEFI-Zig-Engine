const std = @import("std");
const uefi = std.os.uefi;

// MSVC runtime symbols for 32-bit UEFI (must be exported from root)
export fn _aullrem(a: u64, b: u64) u64 {
    return @rem(a, b);
}
export fn _aulldiv(a: u64, b: u64) u64 {
    return @divTrunc(a, b);
}
export fn _allrem(a: i64, b: i64) i64 {
    return @rem(a, b);
}
export fn _alldiv(a: i64, b: i64) i64 {
    return @divTrunc(a, b);
}
export fn __fltused() void {}

// Import modules
const constants = @import("constants.zig");
const rng = @import("rng.zig");
const font = @import("font.zig");
const graphics = @import("graphics.zig");
const terrain = @import("terrain.zig");
const input = @import("input.zig");
const game_of_life = @import("game_of_life.zig");
const audio = @import("audio.zig");

// Re-export audio functions for convenience
const sfxClick = audio.sfxClick;
const sfxPlaceTile = audio.sfxPlaceTile;
const sfxRegenerate = audio.sfxRegenerate;
const sfxError = audio.sfxError;

// UEFI Entry Point
export fn _EfiMain(handle: uefi.Handle, st: *uefi.tables.SystemTable) usize {
    uefi.handle = handle;
    uefi.system_table = st;
    return @intFromEnum(main());
}

pub fn main() uefi.Status {
    const st = uefi.system_table;
    const boot_services = st.boot_services orelse return .aborted;
    const con_in = st.con_in orelse return .success;

    // Initialize graphics
    var gop: *uefi.protocol.GraphicsOutput = undefined;
    const result = boot_services.locateProtocol(uefi.protocol.GraphicsOutput, null) catch |err| switch (err) {
        error.InvalidParameter => return .invalid_parameter,
        error.Unexpected => return .aborted,
    };
    gop = result orelse return .aborted;

    // Select graphics mode (prefer 1920x1080)
    var chosen_mode: u32 = gop.mode.mode;
    var mode_idx: u32 = 0;
    while (mode_idx < gop.mode.max_mode) : (mode_idx += 1) {
        const info = gop.queryMode(mode_idx) catch continue;
        if (info.horizontal_resolution == 1920 and info.vertical_resolution == 1080) {
            chosen_mode = mode_idx;
            break;
        }
    }

    if (chosen_mode != gop.mode.mode) {
        gop.setMode(chosen_mode) catch {};
    }

    const screen_w = gop.mode.info.horizontal_resolution;
    const screen_h = gop.mode.info.vertical_resolution;
    const stride = gop.mode.info.pixels_per_scan_line;
    const fb_size = stride * screen_h;
    const fb: [*]u32 = @ptrFromInt(@as(usize, @truncate(gop.mode.frame_buffer_base)));

    // Allocate buffers
    const background_alloc = boot_services.allocatePool(uefi.tables.MemoryType.loader_data, fb_size * @sizeOf(u32)) catch {
        return .out_of_resources;
    };
    const background_buffer: [*]u32 = @ptrCast(@alignCast(background_alloc));

    const foreground_alloc = boot_services.allocatePool(uefi.tables.MemoryType.loader_data, fb_size * @sizeOf(u32)) catch {
        return .out_of_resources;
    };
    const foreground_buffer: [*]u32 = @ptrCast(@alignCast(foreground_alloc));

    // Initialize input
    const mouse = input.initMouse(boot_services);
    var mouse_state = input.MouseState.init(screen_w, screen_h, mouse != null);

    // Create timer event for ~30fps updates (33ms = 330000 * 100ns units)
    var timer_event: uefi.Event = undefined;
    const timer_type = uefi.EventType{ .timer = true };
    const notify_opts = uefi.tables.BootServices.NotifyOpts{
        .tpl = .application,
        .function = null,
    };
    const timer_result = boot_services.createEvent(timer_type, notify_opts);
    if (timer_result) |evt| {
        timer_event = evt;
        // Set timer to trigger every 33ms (approx 30fps) - in 100ns units
        _ = boot_services.setTimer(timer_event, .periodic, 330000) catch {};
    } else |_| {
        // Fallback: use keyboard event (updates only on input)
        timer_event = con_in.wait_for_key;
    }

    // Setup event loop (max 3 events: key, timer, mouse)
    var events: [3]uefi.Event = undefined;
    var num_events: usize = 2;
    events[0] = con_in.wait_for_key;
    events[1] = timer_event;

    if (mouse_state.available) {
        if (input.getMouseEvent(mouse)) |evt| {
            events[2] = evt;
            num_events = 3;
        }
    }

    // Initial render setup
    graphics.clearScreen(background_buffer, stride, screen_w, screen_h, 0xFF000000);
    terrain.generateTerrain(background_buffer, stride, screen_w, screen_h);
    graphics.drawTilesetPreview(background_buffer, stride, constants.TILESET_DISPLAY_X, constants.PALETTE_DISPLAY_Y, constants.TILES_PER_ROW, constants.TILES_PER_COL);

    // Initialize Game of Life
    const map_cols = screen_w / constants.TILE_SIZE;
    const map_rows = screen_h / constants.TILE_SIZE;
    game_of_life.init(map_cols, map_rows);

    // Main loop
    var running = true;
    var gol_frame_counter: u32 = 0;
    const gol_update_interval: u32 = 30; // Update Game of Life every 30 frames (0.5 seconds at 60fps)
    var gol_running = true; // Toggle Game of Life simulation
    while (running) {
        const wait_result = boot_services.waitForEvent(events[0..num_events]) catch continue;
        const index = wait_result[1];

        // Handle timer event (index 1) - always render on timer tick
        if (index == 1) {
            // Timer fired - this is our signal to render a new frame
        }

        // Handle keyboard (index 0)
        if (index == 0) {
            if (con_in.readKeyStroke()) |key| {
                const c = key.unicode_char;
                if (c == ' ') {
                    // Spacebar toggles Game of Life simulation
                    gol_running = !gol_running;
                    sfxClick();
                } else if (c == 'c' or c == 'C') {
                    // 'C' key clears all living cells
                    game_of_life.clear();
                    sfxRegenerate();
                } else if (c == 'r' or c == 'R') {
                    // 'R' key reinitializes with random cells
                    game_of_life.init(map_cols, map_rows);
                    sfxRegenerate();
                } else if (c == 'q' or c == 'Q') {
                    // 'Q' key quits
                    running = false;
                }
            } else |_| {}
        }

        // Handle mouse (index 2 if available)
        if (mouse_state.available and index == 2) {
            input.updateMouse(&mouse_state, mouse, screen_w, screen_h);

            // Right button: regenerate terrain
            if (mouse_state.right_button) {
                sfxRegenerate();
                rng.setSeed(rng.generateSeedFromPos(mouse_state.x, mouse_state.y));
                terrain.generateTerrain(background_buffer, stride, screen_w, screen_h);
                graphics.drawTilesetPreview(background_buffer, stride, constants.TILESET_DISPLAY_X, constants.PALETTE_DISPLAY_Y, constants.TILES_PER_ROW, constants.TILES_PER_COL);
            }

            // Left button: spawn new life (only on soil tiles 1-8)
            if (mouse_state.left_button and !input.inPalette(mouse_state.x, mouse_state.y)) {
                const grid = input.screenToGrid(mouse_state.x, mouse_state.y);
                // Only spawn if cell is not already alive
                if (!game_of_life.isAlive(grid.col, grid.row, map_cols)) {
                    if (game_of_life.spawnCell(grid.col, grid.row, map_cols)) {
                        sfxClick(); // Successfully spawned on soil
                    } else {
                        sfxError(); // Cannot spawn (not on soil)
                    }
                }
            }
        }

        // Update Game of Life simulation
        if (gol_running) {
            gol_frame_counter += 1;
            if (gol_frame_counter >= gol_update_interval) {
                gol_frame_counter = 0;
                game_of_life.update(map_cols, map_rows);
            }
        }

        // Render pipeline:
        // 1. Copy background to foreground
        // 2. Process audio
        // 3. Draw UI to foreground
        // 4. Blit to GPU framebuffer

        graphics.simdCopy(foreground_buffer, background_buffer, fb_size);
        audio.audio_player.update();

        // Draw Game of Life cells
        game_of_life.draw(foreground_buffer, stride, map_cols, map_rows);

        // Draw UI
        drawDebugInfo(foreground_buffer, stride, screen_w, &mouse_state, gol_running, game_of_life.countLiving());
        graphics.drawSprite(foreground_buffer, stride, constants.CURSOR_TILE, mouse_state.x - 8, mouse_state.y - 8);

        graphics.simdCopy(fb, foreground_buffer, fb_size);
    }

    // Cleanup
    _ = boot_services.freePool(@ptrCast(@alignCast(background_buffer))) catch {};
    _ = boot_services.freePool(@ptrCast(@alignCast(foreground_buffer))) catch {};
    return .success;
}

fn drawDebugInfo(fb: [*]u32, fb_stride: u32, screen_w: u32, mouse_state: *const input.MouseState, gol_running: bool, living_cells: u32) void {
    const start_x = screen_w - 300;
    const y = 5;
    const color = 0xFFFFFFFF;

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
}

pub fn panic(_: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    while (true) asm volatile ("hlt");
}
