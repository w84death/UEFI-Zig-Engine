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
    // Debug info
    protocol_ptr: u64, // Raw pointer to mouse protocol for debugging
    event_ptr: u64, // Raw pointer to wait event
    last_raw_dx: i64, // Last raw movement values
    last_raw_dy: i64,
    last_raw_dz: i64,
    getstate_ok: bool, // Did last getState succeed?
    update_count: u32, // How many times updateMouse was called
    not_ready_count: u32, // NotReady responses (normal - no new movement)
    device_error_count: u32, // DeviceError responses (real problem)
    other_error_count: u32, // Other unexpected errors
    mouse_was_null: bool, // Was mouse pointer null during last update?
    init_protocol_ptr: u64, // Protocol pointer captured at init time
    event_triggered: bool, // Was mouse event (index 2) ever triggered?
    consecutive_errors: u32, // Consecutive errors (for auto-disable)
    disabled: bool, // Mouse polling disabled due to errors

    pub fn init(screen_w: u32, screen_h: u32, available: bool, mouse_protocol: ?*uefi.protocol.SimplePointer) MouseState {
        return .{
            .x = @intCast(screen_w >> 1),
            .y = @intCast(screen_h >> 1),
            .last_dx = 0,
            .last_dy = 0,
            .left_button = false,
            .right_button = false,
            .available = available,
            .scroll_delta = 0,
            .protocol_ptr = if (mouse_protocol) |m| @intFromPtr(m) else 0,
            .event_ptr = 0,
            .last_raw_dx = 0,
            .last_raw_dy = 0,
            .last_raw_dz = 0,
            .getstate_ok = false,
            .update_count = 0,
            .not_ready_count = 0,
            .device_error_count = 0,
            .other_error_count = 0,
            .mouse_was_null = false,
            .init_protocol_ptr = if (mouse_protocol) |m| @intFromPtr(m) else 0,
            .event_triggered = false,
            .consecutive_errors = 0,
            .disabled = false,
        };
    }
};

/// Initialize mouse input
pub fn initMouse(boot_services: *uefi.tables.BootServices) ?*uefi.protocol.SimplePointer {
    if (boot_services.locateProtocol(uefi.protocol.SimplePointer, null)) |mouse_result| {
        if (mouse_result) |m| {
            // NO reset at all - some USB mice freeze when reset is called
            // We'll try getState directly and handle NotReady/DeviceError
            return m;
        }
    } else |_| {}
    return null;
}

/// Get mouse event for waiting
pub fn getMouseEvent(mouse: ?*uefi.protocol.SimplePointer) ?uefi.Event {
    if (mouse) |m| {
        return m.wait_for_input;
    }
    return null;
}

/// Poll mouse state using direct _get_state call (like C reference)
pub fn pollMouse(state: *MouseState, mouse: ?*uefi.protocol.SimplePointer, screen_w: u32, screen_h: u32) bool {
    if (state.disabled) return false;

    if (mouse) |m| {
        state.mouse_was_null = false;
        state.protocol_ptr = @intFromPtr(m);
        state.event_ptr = @intFromPtr(m.wait_for_input);

        // Call _get_state directly like the C reference does
        var ms: uefi.protocol.SimplePointer.State = undefined;
        const status = m._get_state(m, &ms);

        if (status == .success) {
            state.getstate_ok = true;
            state.consecutive_errors = 0;

            const raw_dx = ms.relative_movement_x;
            const raw_dy = ms.relative_movement_y;
            const raw_dz = ms.relative_movement_z;

            state.last_raw_dx = raw_dx;
            state.last_raw_dy = raw_dy;
            state.last_raw_dz = raw_dz;

            // Use resolution-based scaling like the C reference
            const res_x = if (m.mode.resolution_x > 0) m.mode.resolution_x else 1;
            const res_y = if (m.mode.resolution_y > 0) m.mode.resolution_y else 1;

            const dx: i32 = @intCast(@divTrunc(@as(i64, raw_dx), @as(i64, @intCast(res_x))));
            const dy: i32 = @intCast(@divTrunc(@as(i64, raw_dy), @as(i64, @intCast(res_y))));

            var new_x = state.x + dx;
            var new_y = state.y + dy;

            if (new_x < 0) new_x = 0;
            if (new_y < 0) new_y = 0;
            if (new_x >= @as(i32, @intCast(screen_w))) new_x = @intCast(screen_w - 1);
            if (new_y >= @as(i32, @intCast(screen_h))) new_y = @intCast(screen_h - 1);

            state.x = new_x;
            state.y = new_y;
            state.last_dx = dx;
            state.last_dy = dy;
            state.left_button = ms.left_button;
            state.right_button = ms.right_button;
            state.scroll_delta += @divTrunc(raw_dz, 120);
            return true;
        } else {
            state.consecutive_errors += 1;
            if (state.consecutive_errors >= 50) {
                state.disabled = true;
            }

            if (status == .not_ready) {
                state.not_ready_count += 1;
                state.getstate_ok = true; // NotReady is OK
            } else if (status == .device_error) {
                state.device_error_count += 1;
                state.getstate_ok = false;
            } else {
                state.other_error_count += 1;
                state.getstate_ok = false;
            }
        }
    } else {
        state.mouse_was_null = true;
    }
    return false;
}

/// Update mouse state from UEFI input (event-driven only)
pub fn updateMouse(state: *MouseState, mouse: ?*uefi.protocol.SimplePointer, screen_w: u32, screen_h: u32) void {
    state.update_count += 1;
    _ = pollMouse(state, mouse, screen_w, screen_h);
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
