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

export fn _EfiMain(handle: uefi.Handle, st: *uefi.tables.SystemTable) usize {
    uefi.handle = handle;
    uefi.system_table = st;
    return @intFromEnum(main());
}

const LOGO_W: u32 = 128;
const LOGO_H: u32 = 128;
const logo_raw: []const u8 = @embedFile("logo.raw");

// DawnBringer 16 color palette (ARGB format)
const palette: [16]u32 = .{
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

const PALETTE_COLS: u32 = 4;
const PALETTE_ROWS: u32 = 4;
const PALETTE_CELL_SIZE: u32 = 32;
const PALETTE_X: u32 = 10;
const PALETTE_Y: u32 = 10;

fn simdCopy(dst: [*]u32, src: [*]const u32, len: usize) void {
    const Vec4 = @Vector(4, u32);
    const vec_pixels = len / 4;
    const remainder = len % 4;

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

fn inPalette(x: i32, y: i32) bool {
    return x >= PALETTE_X and x < PALETTE_X + @as(i32, @intCast(PALETTE_COLS * PALETTE_CELL_SIZE)) and
        y >= PALETTE_Y and y < PALETTE_Y + @as(i32, @intCast(PALETTE_ROWS * PALETTE_CELL_SIZE));
}

fn getPaletteColorIndex(x: i32, y: i32) usize {
    const col = @as(u32, @intCast(x - PALETTE_X)) / PALETTE_CELL_SIZE;
    const row = @as(u32, @intCast(y - PALETTE_Y)) / PALETTE_CELL_SIZE;
    return @as(usize, @intCast(row * PALETTE_COLS + col));
}

pub fn main() uefi.Status {
    const st = uefi.system_table;
    const boot_services = st.boot_services orelse return .aborted;
    const con_in = st.con_in orelse return .success;

    var gop: *uefi.protocol.GraphicsOutput = undefined;
    const result = boot_services.locateProtocol(uefi.protocol.GraphicsOutput, null) catch |err| switch (err) {
        error.InvalidParameter => return .invalid_parameter,
        error.Unexpected => return .aborted,
    };
    gop = result orelse return .aborted;

    // Try 1920x1080
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

    // Allocate canvas
    const canvas_alloc = boot_services.allocatePool(uefi.tables.MemoryType.loader_data, fb_size * @sizeOf(u32)) catch {
        return .out_of_resources;
    };
    const canvas: [*]u32 = @ptrCast(@alignCast(canvas_alloc));

    // Clear to black (background)
    const bg_color: u32 = 0xFF000000;
    var py: u32 = 0;
    while (py < screen_h) : (py += 1) {
        var px: u32 = 0;
        while (px < screen_w) : (px += 1) {
            fb[py * stride + px] = bg_color;
        }
    }

    // Save black background to canvas
    simdCopy(canvas, fb, fb_size);

    // Draw logo
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
    var pr: u32 = 0;
    while (pr < PALETTE_ROWS) : (pr += 1) {
        var pc: u32 = 0;
        while (pc < PALETTE_COLS) : (pc += 1) {
            const color_idx = pr * PALETTE_COLS + pc;
            const cell_x = PALETTE_X + pc * PALETTE_CELL_SIZE;
            const cell_y = PALETTE_Y + pr * PALETTE_CELL_SIZE;
            var cy: u32 = cell_y;
            while (cy < cell_y + PALETTE_CELL_SIZE) : (cy += 1) {
                var cx: u32 = cell_x;
                while (cx < cell_x + PALETTE_CELL_SIZE) : (cx += 1) {
                    fb[cy * stride + cx] = palette[color_idx];
                }
            }
        }
    }

    // Save scene to canvas
    simdCopy(canvas, fb, fb_size);

    // Setup mouse
    var mouse: ?*uefi.protocol.SimplePointer = null;
    var mouse_available = false;

    if (boot_services.locateProtocol(uefi.protocol.SimplePointer, null)) |mouse_result| {
        if (mouse_result) |m| {
            mouse = m;
            mouse_available = true;
            _ = mouse.?.reset(true) catch {};
        }
    } else |_| {}

    // Initialize cursor
    var cursor_x: i32 = @intCast(screen_w >> 1);
    var cursor_y: i32 = @intCast(screen_h >> 1);
    var current_color: u32 = palette[15];

    // Draw initial cursor
    var i: u32 = 0;
    while (i < screen_w) : (i += 1) fb[@as(u32, @intCast(cursor_y)) * stride + i] = 0xFFFFFFFF;
    i = 0;
    while (i < screen_h) : (i += 1) fb[i * stride + @as(u32, @intCast(cursor_x))] = 0xFFFFFFFF;

    // Event loop
    var running = true;
    var events: [2]uefi.Event = undefined;
    var num_events: usize = 1;
    events[0] = con_in.wait_for_key;

    if (mouse_available) {
        const mouse_evt = mouse.?.wait_for_input;
        if (@intFromPtr(mouse_evt) != 0) {
            events[1] = mouse_evt;
            num_events = 2;
        }
    }

    while (running) {
        const wait_result = boot_services.waitForEvent(events[0..num_events]) catch continue;
        const index = wait_result[1];

        if (index == 0) {
            if (con_in.readKeyStroke()) |_| running = false else |_| {}
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

                // Right button: pick color
                if (state.right_button) {
                    if (inPalette(new_x, new_y)) {
                        const color_idx = getPaletteColorIndex(new_x, new_y);
                        current_color = palette[color_idx];
                    } else {
                        const pixel_idx = @as(u32, @intCast(new_y)) * stride + @as(u32, @intCast(new_x));
                        current_color = canvas[pixel_idx];
                    }
                }

                // Left button: draw
                var needs_update = (new_x != cursor_x or new_y != cursor_y);
                if (state.left_button and !inPalette(new_x, new_y)) {
                    var by: i32 = -2;
                    while (by <= 2) : (by += 1) {
                        var bx: i32 = -2;
                        while (bx <= 2) : (bx += 1) {
                            const px = new_x + bx;
                            const pyy = new_y + by;
                            if (px >= 0 and pyy >= 0 and px < @as(i32, @intCast(screen_w)) and pyy < @as(i32, @intCast(screen_h))) {
                                const pixel_idx = @as(u32, @intCast(pyy)) * stride + @as(u32, @intCast(px));
                                canvas[pixel_idx] = current_color;
                                needs_update = true;
                            }
                        }
                    }
                }

                if (needs_update) {
                    simdCopy(fb, canvas, fb_size);
                    cursor_x = new_x;
                    cursor_y = new_y;
                    var h: u32 = 0;
                    while (h < screen_w) : (h += 1) fb[@as(u32, @intCast(cursor_y)) * stride + h] = 0xFFFFFFFF;
                    var v: u32 = 0;
                    while (v < screen_h) : (v += 1) fb[v * stride + @as(u32, @intCast(cursor_x))] = 0xFFFFFFFF;
                }
            } else |_| {}
        }
    }

    _ = boot_services.freePool(@ptrCast(@alignCast(canvas))) catch {};
    return .success;
}

pub fn panic(_: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    while (true) asm volatile ("hlt");
}
