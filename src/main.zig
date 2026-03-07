const std = @import("std");
const uefi = std.os.uefi;

// Provide MSVC runtime symbols for 32-bit UEFI
export fn _aullrem(a: u64, b: u64) u64 {
    return @rem(a, b);
}

export fn _aulldiv(a: u64, b: u64) u64 {
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

    // Clear screen to dark grey
    const bg_color: u32 = 0x00202020;
    var py: u32 = 0;
    while (py < screen_h) : (py += 1) {
        var px: u32 = 0;
        while (px < screen_w) : (px += 1) {
            fb[py * stride + px] = bg_color;
        }
    }

    if (screen_w < LOGO_W or screen_h < LOGO_H) return .aborted;

    // Center the logo using shift instead of divide to avoid 64-bit ops
    const blit_x: u32 = (screen_w - LOGO_W) >> 1;
    const blit_y: u32 = (screen_h - LOGO_H) >> 1;

    // Blit logo
    const logo_pixels: [*]const u32 = @ptrCast(@alignCast(logo_raw.ptr));
    var row: u32 = 0;
    while (row < LOGO_H) : (row += 1) {
        const dst_offset = (blit_y + row) * stride + blit_x;
        const src_offset = row * LOGO_W;
        const dst_ptr: [*]u32 = @constCast(@volatileCast(fb + dst_offset));
        @memcpy(dst_ptr[0..LOGO_W], logo_pixels[src_offset..][0..LOGO_W]);
    }

    // Wait for keypress
    const con_in = st.con_in orelse return .success;
    while (con_in.readKeyStroke() == error.NotReady) {}

    return .success;
}

pub fn panic(_: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    while (true) {
        asm volatile ("hlt");
    }
}
