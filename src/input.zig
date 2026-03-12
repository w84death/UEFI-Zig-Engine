// Input handling: mouse and keyboard

const std = @import("std");
const uefi = std.os.uefi;
const constants = @import("constants.zig");

/// Mouse state structure
pub const MouseState = struct {
    x: i32,
    y: i32,
    last_dx: i32,
    last_dy: i32,
    left_button: bool,
    right_button: bool,
    available: bool,
    scroll_delta: i32, // Accumulated scroll wheel movement

    pub fn init(screen_w: u32, screen_h: u32, available: bool) MouseState {
        return .{
            .x = @intCast(screen_w >> 1),
            .y = @intCast(screen_h >> 1),
            .last_dx = 0,
            .last_dy = 0,
            .left_button = false,
            .right_button = false,
            .available = available,
            .scroll_delta = 0,
        };
    }
};

/// Initialize mouse input
pub fn initMouse(boot_services: *uefi.tables.BootServices) ?*uefi.protocol.SimplePointer {
    if (boot_services.locateProtocol(uefi.protocol.SimplePointer, null)) |mouse_result| {
        if (mouse_result) |m| {
            _ = m.reset(true) catch {};
            return m;
        }
    } else |_| {}
    return null;
}

/// Get mouse event for waiting
pub fn getMouseEvent(mouse: ?*uefi.protocol.SimplePointer) ?uefi.Event {
    if (mouse) |m| {
        // wait_for_input is always valid if protocol opened successfully
        return m.wait_for_input;
    }
    return null;
}

/// Update mouse state from UEFI input
pub fn updateMouse(state: *MouseState, mouse: ?*uefi.protocol.SimplePointer, screen_w: u32, screen_h: u32) void {
    if (mouse) |m| {
        if (m.getState()) |ms| {
            const raw_dx = ms.relative_movement_x;
            const raw_dy = ms.relative_movement_y;
            const dx = @divTrunc(raw_dx, 5000);
            const dy = @divTrunc(raw_dy, 5000);

            var new_x = state.x + @as(i32, @intCast(dx));
            var new_y = state.y + @as(i32, @intCast(dy));

            // Clamp to screen bounds
            if (new_x < 0) new_x = 0;
            if (new_y < 0) new_y = 0;
            if (new_x >= @as(i32, @intCast(screen_w))) new_x = @intCast(screen_w - 1);
            if (new_y >= @as(i32, @intCast(screen_h))) new_y = @intCast(screen_h - 1);

            state.x = new_x;
            state.y = new_y;
            state.last_dx = @as(i32, @intCast(dx));
            state.last_dy = @as(i32, @intCast(dy));
            state.left_button = ms.left_button;
            state.right_button = ms.right_button;

            // Accumulate scroll wheel movement (Z axis)
            // Most mice report 1 "click" as around 120 units
            state.scroll_delta += @divTrunc(ms.relative_movement_z, 120);
        } else |_| {}
    }
}

/// Get accumulated scroll amount and reset counter
/// Returns positive for scroll up (faster), negative for scroll down (slower)
pub fn getScrollAndReset(state: *MouseState) i32 {
    const delta = state.scroll_delta;
    state.scroll_delta = 0;
    return delta;
}

/// Check if point is within palette area
pub fn inPalette(x: i32, y: i32) bool {
    return x >= constants.PALETTE_X and x < constants.PALETTE_X + @as(i32, @intCast(constants.PALETTE_COLS * constants.PALETTE_CELL_SIZE)) and
        y >= constants.PALETTE_Y and y < constants.PALETTE_Y + @as(i32, @intCast(constants.PALETTE_ROWS * constants.PALETTE_CELL_SIZE));
}

/// Get palette color index from screen coordinates
pub fn getPaletteColorIndex(x: i32, y: i32) usize {
    const col = @as(u32, @intCast(x - constants.PALETTE_X)) / constants.PALETTE_CELL_SIZE;
    const row = @as(u32, @intCast(y - constants.PALETTE_Y)) / constants.PALETTE_CELL_SIZE;
    return @as(usize, @intCast(row * constants.PALETTE_COLS + col));
}
