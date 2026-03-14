const std = @import("std");
const uefi = std.os.uefi;

// MSVC runtime symbols for 32-bit UEFI
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
const utils = @import("utils.zig");
const config = @import("config.zig");
const app = @import("app.zig");
const graphics = @import("graphics.zig");
const terrain = @import("terrain.zig");
const input = @import("input.zig");
const game_of_life = @import("game_of_life.zig");
// const audio = @import("audio.zig");
const ui = @import("ui.zig");
const font = @import("font.zig");

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
    const gfx = app.initGraphics(boot_services) catch |err| switch (err) {
        error.OutOfResources => return .out_of_resources,
        error.Aborted => return .aborted,
        error.InvalidParameter => return .invalid_parameter,
    };

    // Allocate buffers
    const buffers = app.allocateBuffers(boot_services, gfx.fb_size) catch {
        return .out_of_resources;
    };

    // Initialize input
    const mouse = input.initMouse(boot_services);
    var mouse_state = input.MouseState.init(gfx.screen_w, gfx.screen_h, mouse != null, mouse);

    // Setup events
    const events = app.setupEvents(boot_services, con_in, mouse, mouse_state.available) catch {
        return .aborted;
    };

    // Update mouse availability based on actual event registration
    mouse_state.available = events.num_events == 3;

    // Initial render
    graphics.clearScreen(buffers.background, gfx.stride, gfx.screen_w, gfx.screen_h, 0xFF000000);
    terrain.generateTerrain(buffers.background, gfx.stride, gfx.screen_w, gfx.screen_h);

    // Initialize Game of Life
    const map_cols = gfx.screen_w / constants.TILE_SIZE;
    const map_rows = gfx.screen_h / constants.TILE_SIZE;
    game_of_life.init(map_cols, map_rows);

    // Initial display update (don't wait for first event)
    graphics.simdCopy(buffers.foreground, buffers.background, gfx.fb_size);
    game_of_life.draw(buffers.foreground, gfx.stride, map_cols, map_rows);
    if (mouse != null) {
        graphics.drawSprite(buffers.foreground, gfx.stride, constants.CURSOR_TILE, mouse_state.x - 8, mouse_state.y - 8);
    }
    graphics.simdCopy(gfx.framebuffer, buffers.foreground, gfx.fb_size);

    // Main loop
    var running = true;
    var gol_frame_counter: u32 = 0;
    var gol_running = true;

    while (running) {
        const wait_result = boot_services.waitForEvent(events.events[0..events.num_events]) catch continue;
        const index = wait_result[1];

        // Handle keyboard input
        if (index == 0) {
            if (con_in.readKeyStroke()) |key| {
                const c = key.unicode_char;
                switch (c) {
                    ' ' => {
                        gol_running = !gol_running;
                        // audio.sfxClick();
                    },
                    'c', 'C' => {
                        game_of_life.clear();
                        // audio.sfxRegenerate();
                    },
                    'r', 'R' => {
                        game_of_life.init(map_cols, map_rows);
                        // audio.sfxRegenerate();
                    },
                    't', 'T' => {
                        config.show_tileset = !config.show_tileset;
                        // audio.sfxClick();
                    },
                    'h', 'H' => {
                        game_of_life.toggleChaosMode();
                        // audio.sfxClick();
                    },
                    'g', 'G' => {
                        utils.rngSetSeed(utils.generateSeedFromPos(mouse_state.x, mouse_state.y));
                        terrain.generateTerrain(buffers.background, gfx.stride, gfx.screen_w, gfx.screen_h);
                        game_of_life.init(map_cols, map_rows);
                    },
                    '+', '=' => adjustSpeed(-1),
                    '-' => adjustSpeed(1),
                    'q', 'Q' => running = false,
                    else => {},
                }
            } else |_| {}
        }

        // Handle mouse input - event-driven only (when SimplePointer signals)
        if (mouse != null and events.num_events == 3 and index == 2) {
            mouse_state.event_triggered = true;
            input.updateMouse(&mouse_state, mouse, gfx.screen_w, gfx.screen_h);

            // Right button: regenerate terrain
            if (mouse_state.right_button) {
                // audio.sfxRegenerate();
                utils.rngSetSeed(utils.generateSeedFromPos(mouse_state.x, mouse_state.y));
                terrain.generateTerrain(buffers.background, gfx.stride, gfx.screen_w, gfx.screen_h);
                game_of_life.init(map_cols, map_rows);
            }

            // Left button: spawn cell
            if (mouse_state.left_button and !input.inPalette(mouse_state.x, mouse_state.y)) {
                const grid = utils.screenToGrid(mouse_state.x, mouse_state.y, constants.TILE_SIZE);
                if (!game_of_life.isAlive(grid.col, grid.row, map_cols)) {
                    if (game_of_life.spawnCell(grid.col, grid.row, map_cols)) {
                        // audio.sfxClick();
                    } else {
                        // audio.sfxError();
                    }
                }
            }

            // Scroll wheel: adjust speed
            const scroll = input.getScrollAndReset(&mouse_state);
            if (scroll != 0) adjustSpeed(if (scroll > 0) -1 else 1);
        }

        // Update Game of Life
        if (gol_running and !game_of_life.isDead()) {
            gol_frame_counter += 1;
            if (gol_frame_counter >= config.gol_update_interval) {
                gol_frame_counter = 0;
                game_of_life.update(map_cols, map_rows);
            }
        }

        // Render
        graphics.simdCopy(buffers.foreground, buffers.background, gfx.fb_size);
        // audio.audio_player.update();

        if (config.show_tileset) {
            graphics.drawTilesetPreview(buffers.foreground, gfx.stride, constants.TILESET_DISPLAY_X, constants.PALETTE_DISPLAY_Y, constants.TILES_PER_ROW, constants.TILES_PER_COL);
        }

        game_of_life.draw(buffers.foreground, gfx.stride, map_cols, map_rows);

        // Draw civilization collapsed message
        if (game_of_life.isDead() and game_of_life.generation > 0) {
            ui.drawCivilizationCollapsed(buffers.foreground, gfx.stride, gfx.screen_w, gfx.screen_h, game_of_life.generation);
        }

        // Draw mouse debug info (always show)
        ui.drawMouseDebugInfo(buffers.foreground, gfx.stride, &mouse_state, events.num_events);

        // Draw debug info
        if (config.show_debug) {
            ui.drawDebugInfo(buffers.foreground, gfx.stride, gfx.screen_w, gfx.screen_h, &mouse_state, gol_running, game_of_life.countLiving(), config.gol_update_interval, game_of_life.generation);
        }

        if (mouse != null) {
            graphics.drawSprite(buffers.foreground, gfx.stride, constants.CURSOR_TILE, mouse_state.x - 8, mouse_state.y - 8);
        }
        graphics.simdCopy(gfx.framebuffer, buffers.foreground, gfx.fb_size);
    }

    // Cleanup
    app.freeBuffers(boot_services, buffers);
    return .success;
}

/// Adjust Game of Life speed
fn adjustSpeed(direction: i32) void {
    const new_interval = if (direction < 0) config.gol_update_interval -| config.GOL_INTERVAL_STEP else config.gol_update_interval + config.GOL_INTERVAL_STEP;
    config.gol_update_interval = utils.clampU32(new_interval, config.GOL_INTERVAL_MIN, config.GOL_INTERVAL_MAX);
    // audio.sfxClick();
}

pub fn panic(_: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    while (true) asm volatile ("hlt");
}
