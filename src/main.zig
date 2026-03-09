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
    const fb: [*]volatile u32 = @ptrFromInt(@as(usize, @truncate(gop.mode.frame_buffer_base)));

    // Clear screen to white
    const bg_color: u32 = 0xFFFFFFFF;
    var py: u32 = 0;
    while (py < screen_h) : (py += 1) {
        var px: u32 = 0;
        while (px < screen_w) : (px += 1) {
            fb[py * stride + px] = bg_color;
        }
    }

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

    // Try to get Simple Pointer Protocol for mouse
    var mouse: ?*uefi.protocol.SimplePointer = null;
    var mouse_available = false;

    if (boot_services.locateProtocol(uefi.protocol.SimplePointer, null)) |mouse_result| {
        if (mouse_result) |m| {
            mouse = m;
            mouse_available = true;
        }
    } else |_| {}

    // Initialize cursor position (center of screen)
    var cursor_x: i32 = @intCast(screen_w >> 1);
    var cursor_y: i32 = @intCast(screen_h >> 1);

    // Draw status indicator (green=mouse available, red=not available)
    const status_color: u32 = if (mouse_available) 0xFF00FF00 else 0xFF0000FF;
    var sy: u32 = 10;
    while (sy < 20) : (sy += 1) {
        var sx: u32 = 10;
        while (sx < 20) : (sx += 1) {
            fb[sy * stride + sx] = status_color;
        }
    }

    // Draw initial cursor
    fb[@as(u32, @intCast(cursor_y)) * stride + @as(u32, @intCast(cursor_x))] = 0xFF0000FF;

    // Setup event-based input handling
    var index: usize = undefined;
    var running = true;

    // Get wait_for_key event from con_in
    const wait_for_key_event = con_in.wait_for_key;

    // Prepare events array
    var events: [2]uefi.Event = undefined;
    var num_events: usize = 1;
    events[0] = wait_for_key_event;

    // Add mouse event only if handle is non-null
    if (mouse_available) {
        // Try to reset mouse to enable reporting
        _ = mouse.?.reset(true) catch {};

        const mouse_evt = mouse.?.wait_for_input;
        if (@intFromPtr(mouse_evt) != 0) {
            events[1] = mouse_evt;
            num_events = 2;
        }
    }

    while (running) {
        // Wait for event (blocking, efficient)
        const wait_result = boot_services.waitForEvent(events[0..num_events]) catch {
            continue;
        };
        index = wait_result[1];

        // Handle key event (index 0)
        if (index == 0) {
            if (con_in.readKeyStroke()) |_| {
                running = false;
            } else |_| {}
        }

        // Handle mouse event (index 1) - only if mouse is available
        if (mouse_available and index == 1) {
            if (mouse.?.getState()) |state| {
                // Erase old cursor
                fb[@as(u32, @intCast(cursor_y)) * stride + @as(u32, @intCast(cursor_x))] = bg_color;

                // Scale raw values to pixels (values are large, divide by 1000)
                const dx = @divTrunc(state.relative_movement_x, 1000);
                const dy = @divTrunc(state.relative_movement_y, 1000);

                cursor_x += @intCast(dx);
                cursor_y += @intCast(dy);

                // Clamp to screen bounds
                if (cursor_x < 0) cursor_x = 0;
                if (cursor_y < 0) cursor_y = 0;
                if (cursor_x >= @as(i32, @intCast(screen_w))) cursor_x = @intCast(screen_w - 1);
                if (cursor_y >= @as(i32, @intCast(screen_h))) cursor_y = @intCast(screen_h - 1);

                // Draw new cursor (blue pixel)
                fb[@as(u32, @intCast(cursor_y)) * stride + @as(u32, @intCast(cursor_x))] = 0xFF0000FF;

                // Draw on left click (red dot around cursor)
                if (state.left_button) {
                    const mx: u32 = @intCast(cursor_x);
                    const my: u32 = @intCast(cursor_y);
                    var ddy: i32 = -2;
                    while (ddy <= 2) : (ddy += 1) {
                        var ddx: i32 = -2;
                        while (ddx <= 2) : (ddx += 1) {
                            const pxx = @as(i32, @intCast(mx)) + ddx;
                            const pyy = @as(i32, @intCast(my)) + ddy;
                            if (pxx >= 0 and pyy >= 0 and pxx < @as(i32, @intCast(screen_w)) and pyy < @as(i32, @intCast(screen_h))) {
                                fb[@as(u32, @intCast(pyy)) * stride + @as(u32, @intCast(pxx))] = 0xFF0000FF;
                            }
                        }
                    }
                }
            } else |_| {}
        }
    }

    return .success;
}

pub fn panic(_: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    while (true) {
        asm volatile ("hlt");
    }
}
