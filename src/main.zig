const std = @import("std");
const uefi = std.os.uefi;

// Provide MSVC runtime symbols for 32-bit UEFI
// Unsigned 64-bit helpers
export fn _aullrem(a: u64, b: u64) u64 {
    return @rem(a, b);
}

export fn _aulldiv(a: u64, b: u64) u64 {
    return @divTrunc(a, b);
}

// Signed 64-bit helpers (also required by the 32-bit PE linker)
export fn _allrem(a: i64, b: i64) i64 {
    return @rem(a, b);
}

export fn _alldiv(a: i64, b: i64) i64 {
    return @divTrunc(a, b);
}

export fn __fltused() void {}

// Export EfiMain with underscore prefix for PE32
export fn _EfiMain(handle: uefi.Handle, st: *uefi.tables.SystemTable) usize {
    uefi.handle = handle;
    uefi.system_table = st;
    return @intFromEnum(main());
}

const LOGO_W: u32 = 128;
const LOGO_H: u32 = 128;

const logo_raw: []const u8 = @embedFile("logo.raw");

// Palette configuration
const PALETTE_COLS: u32 = 4;
const PALETTE_ROWS: u32 = 4;
const PALETTE_CELL_SIZE: u32 = 32;
const PALETTE_X: u32 = 10;
const PALETTE_Y: u32 = 10;
const PALETTE_WIDTH: u32 = PALETTE_COLS * PALETTE_CELL_SIZE;
const PALETTE_HEIGHT: u32 = PALETTE_ROWS * PALETTE_CELL_SIZE;

// 16 nice pastel colors (ARGB format)
const palette_colors: [16]u32 = .{
    0xFFFFB3BA, // Light Pink
    0xFFFFDFBA, // Peach
    0xFFFFFFBA, // Cream
    0xFFBAFFC9, // Mint
    0xFFBAE1FF, // Light Blue
    0xFFE6B9FF, // Lavender
    0xFFFFB9E6, // Light Magenta
    0xFFFFD9B3, // Apricot
    0xFFC9FFBA, // Light Green
    0xFFBAFFD9, // Aqua
    0xFFD9BAFF, // Light Purple
    0xFFFFBAC9, // Rose
    0xFFFFFFD9, // Light Yellow
    0xFFD9FFFF, // Cyan
    0xFFFFD9FF, // Light Fuchsia
    0xFFD9D9FF, // Periwinkle
};

// SIMD-optimized memory copy using Zig's built-in SIMD types
fn simdCopy(dst: [*]u32, src: [*]const u32, len: usize) void {
    const Vec4 = @Vector(4, u32);
    const total_pixels = len;
    const vec_pixels = total_pixels / 4;
    const remainder = total_pixels % 4;

    var i: usize = 0;
    while (i < vec_pixels) : (i += 1) {
        const src_vec: *align(1) const Vec4 = @ptrCast(src + i * 4);
        const dst_vec: *align(1) Vec4 = @ptrCast(dst + i * 4);
        dst_vec.* = src_vec.*;
    }

    const rem_start = vec_pixels * 4;
    var j: usize = 0;
    while (j < remainder) : (j += 1) {
        dst[rem_start + j] = src[rem_start + j];
    }
}

// Check if point is inside palette
fn inPalette(x: i32, y: i32) bool {
    return x >= PALETTE_X and x < PALETTE_X + @as(i32, @intCast(PALETTE_WIDTH)) and
        y >= PALETTE_Y and y < PALETTE_Y + @as(i32, @intCast(PALETTE_HEIGHT));
}

// Get color index from palette coordinates
fn getPaletteColorIndex(x: i32, y: i32) usize {
    const col = @as(u32, @intCast(x - PALETTE_X)) / PALETTE_CELL_SIZE;
    const row = @as(u32, @intCast(y - PALETTE_Y)) / PALETTE_CELL_SIZE;
    return @as(usize, @intCast(row * PALETTE_COLS + col));
}

pub fn main() uefi.Status {
    const st = uefi.system_table;
    const boot_services = st.boot_services orelse return .aborted;
    const con_in = st.con_in orelse return .success;

    // Setup graphics
    var gop: *uefi.protocol.GraphicsOutput = undefined;
    const result = boot_services.locateProtocol(uefi.protocol.GraphicsOutput, null) catch |err| switch (err) {
        error.InvalidParameter => return .invalid_parameter,
        error.Unexpected => return .aborted,
    };
    gop = result orelse return .aborted;

    // Set 1920x1080 if available
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

    // Allocate canvas buffer using UEFI boot services
    const canvas_size = fb_size * @sizeOf(u32);
    const canvas_alloc = boot_services.allocatePool(uefi.tables.MemoryType.loader_data, canvas_size) catch {
        return .out_of_resources;
    };
    const canvas: [*]u32 = @ptrCast(@alignCast(canvas_alloc));

    // Clear screen to black (dark mode) and copy to canvas
    const bg_color: u32 = 0xFF000000;
    var py: u32 = 0;
    while (py < screen_h) : (py += 1) {
        var px: u32 = 0;
        while (px < screen_w) : (px += 1) {
            fb[py * stride + px] = bg_color;
        }
    }

    // Copy black background to canvas
    simdCopy(canvas, fb, fb_size);

    if (screen_w < LOGO_W or screen_h < LOGO_H) return .aborted;

    // Center and blit logo
    const blit_x: u32 = (screen_w - LOGO_W) >> 1;
    const blit_y: u32 = (screen_h - LOGO_H) >> 1;
    const logo_pixels: [*]const u32 = @ptrCast(@alignCast(logo_raw.ptr));
    var row: u32 = 0;
    while (row < LOGO_H) : (row += 1) {
        const dst_offset = (blit_y + row) * stride + blit_x;
        const src_offset = row * LOGO_W;
        const dst_ptr: [*]u32 = @constCast(@volatileCast(fb + dst_offset));
        @memcpy(dst_ptr[0..LOGO_W], logo_pixels[src_offset..][0..LOGO_W]);
    }

    // Draw palette
    var palette_row: u32 = 0;
    while (palette_row < PALETTE_ROWS) : (palette_row += 1) {
        var palette_col: u32 = 0;
        while (palette_col < PALETTE_COLS) : (palette_col += 1) {
            const color_idx = palette_row * PALETTE_COLS + palette_col;
            const cell_x = PALETTE_X + palette_col * PALETTE_CELL_SIZE;
            const cell_y = PALETTE_Y + palette_row * PALETTE_CELL_SIZE;

            var cy: u32 = cell_y;
            while (cy < cell_y + PALETTE_CELL_SIZE) : (cy += 1) {
                var cx: u32 = cell_x;
                while (cx < cell_x + PALETTE_CELL_SIZE) : (cx += 1) {
                    fb[cy * stride + cx] = palette_colors[color_idx];
                }
            }
        }
    }

    // Draw status indicator (green=mouse available, red=not available)
    var mouse: ?*uefi.protocol.SimplePointer = null;
    var mouse_available = false;

    if (boot_services.locateProtocol(uefi.protocol.SimplePointer, null)) |mouse_result| {
        if (mouse_result) |m| {
            mouse = m;
            mouse_available = true;
        }
    } else |_| {}

    const status_color: u32 = if (mouse_available) 0xFF00FF00 else 0xFF0000FF;
    var sy: u32 = 10;
    while (sy < 20) : (sy += 1) {
        var sx: u32 = 10;
        while (sx < 20) : (sx += 1) {
            fb[sy * stride + sx] = status_color;
        }
    }

    // Save the scene to canvas
    simdCopy(canvas, fb, fb_size);

    // Initialize cursor position (center of screen)
    var cursor_x: i32 = @intCast(screen_w >> 1);
    var cursor_y: i32 = @intCast(screen_h >> 1);

    // Initialize drawing color (first palette color)
    var current_color: u32 = palette_colors[0];
    var is_drawing: bool = false;

    // Draw initial cursor (white lines)
    var i: u32 = 0;
    while (i < screen_w) : (i += 1) {
        fb[@as(u32, @intCast(cursor_y)) * stride + i] = 0xFFFFFFFF;
    }
    i = 0;
    while (i < screen_h) : (i += 1) {
        fb[i * stride + @as(u32, @intCast(cursor_x))] = 0xFFFFFFFF;
    }

    // Setup event-based input handling
    var index: usize = undefined;
    var running = true;

    const wait_for_key_event = con_in.wait_for_key;
    var events: [2]uefi.Event = undefined;
    var num_events: usize = 1;
    events[0] = wait_for_key_event;

    if (mouse_available) {
        _ = mouse.?.reset(true) catch {};
        const mouse_evt = mouse.?.wait_for_input;
        if (@intFromPtr(mouse_evt) != 0) {
            events[1] = mouse_evt;
            num_events = 2;
        }
    }

    while (running) {
        const wait_result = boot_services.waitForEvent(events[0..num_events]) catch {
            continue;
        };
        index = wait_result[1];

        if (index == 0) {
            if (con_in.readKeyStroke()) |_| {
                running = false;
            } else |_| {}
        }

        if (mouse_available and index == 1) {
            if (mouse.?.getState()) |state| {
                const dx = @divTrunc(state.relative_movement_x, 5000);
                const dy = @divTrunc(state.relative_movement_y, 5000);

                var new_x = cursor_x + @as(i32, @intCast(dx));
                var new_y = cursor_y + @as(i32, @intCast(dy));

                if (new_x < 0) new_x = 0;
                if (new_y < 0) new_y = 0;
                if (new_x >= @as(i32, @intCast(screen_w))) new_x = @intCast(screen_w - 1);
                if (new_y >= @as(i32, @intCast(screen_h))) new_y = @intCast(screen_h - 1);

                // Handle right button (pick color)
                if (state.right_button) {
                    if (inPalette(new_x, new_y)) {
                        const color_idx = getPaletteColorIndex(new_x, new_y);
                        current_color = palette_colors[color_idx];
                    } else {
                        // Pick color from canvas at cursor position
                        const pixel_idx = @as(u32, @intCast(new_y)) * stride + @as(u32, @intCast(new_x));
                        current_color = canvas[pixel_idx];
                    }
                }

                // Handle left button (draw)
                if (state.left_button and !inPalette(new_x, new_y)) {
                    // Draw to canvas and framebuffer
                    const brush_size: i32 = 2;
                    var by: i32 = -brush_size;
                    while (by <= brush_size) : (by += 1) {
                        var bx: i32 = -brush_size;
                        while (bx <= brush_size) : (bx += 1) {
                            const px = new_x + bx;
                            const pyy = new_y + by;
                            if (px >= 0 and pyy >= 0 and px < @as(i32, @intCast(screen_w)) and pyy < @as(i32, @intCast(screen_h))) {
                                const pixel_idx = @as(u32, @intCast(pyy)) * stride + @as(u32, @intCast(px));
                                canvas[pixel_idx] = current_color;
                            }
                        }
                    }
                    is_drawing = true;
                } else {
                    is_drawing = false;
                }

                // Only redraw cursor if position changed or was drawing
                if (new_x != cursor_x or new_y != cursor_y or is_drawing) {
                    // Copy canvas to framebuffer
                    simdCopy(fb, canvas, fb_size);

                    // Update cursor position
                    cursor_x = new_x;
                    cursor_y = new_y;

                    // Draw white cursor lines
                    var h: u32 = 0;
                    while (h < screen_w) : (h += 1) {
                        fb[@as(u32, @intCast(cursor_y)) * stride + h] = 0xFFFFFFFF;
                    }
                    var v: u32 = 0;
                    while (v < screen_h) : (v += 1) {
                        fb[v * stride + @as(u32, @intCast(cursor_x))] = 0xFFFFFFFF;
                    }
                }
            } else |_| {}
        }
    }

    _ = boot_services.freePool(@ptrCast(@alignCast(canvas))) catch {};
    return .success;
}

pub fn panic(_: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    while (true) {
        asm volatile ("hlt");
    }
}
