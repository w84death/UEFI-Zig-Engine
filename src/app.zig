// Application lifecycle management

const std = @import("std");
const uefi = std.os.uefi;
const input = @import("input.zig");

/// Graphics context holding GOP and screen information
pub const GraphicsContext = struct {
    gop: *uefi.protocol.GraphicsOutput,
    screen_w: u32,
    screen_h: u32,
    stride: u32,
    framebuffer: [*]u32,
    fb_size: usize,
};

/// Application buffers
pub const AppBuffers = struct {
    background: [*]u32,
    foreground: [*]u32,
};

/// Event configuration
pub const EventConfig = struct {
    events: [3]uefi.Event,
    num_events: usize,
    timer_event: uefi.Event,
};

/// Initialize graphics output protocol and select best mode
pub fn initGraphics(boot_services: *uefi.tables.BootServices) error{ OutOfResources, Aborted, InvalidParameter }!GraphicsContext {
    var gop: *uefi.protocol.GraphicsOutput = undefined;
    const result = boot_services.locateProtocol(uefi.protocol.GraphicsOutput, null) catch |err| switch (err) {
        error.InvalidParameter => return error.InvalidParameter,
        error.Unexpected => return error.Aborted,
    };
    gop = result orelse return error.Aborted;

    // Select graphics mode (prefer 1920x1200, then 1920x1080, then any 1920 width)
    var chosen_mode: u32 = gop.mode.mode;
    var mode_idx: u32 = 0;
    var found_1080: ?u32 = null;
    var found_1920: ?u32 = null;

    while (mode_idx < gop.mode.max_mode) : (mode_idx += 1) {
        const info = gop.queryMode(mode_idx) catch continue;
        // Prefer 1920x1200 (WUXGA)
        if (info.horizontal_resolution == 1920 and info.vertical_resolution == 1200) {
            chosen_mode = mode_idx;
            break;
        }
        // Remember 1920x1080 as fallback
        if (found_1080 == null and info.horizontal_resolution == 1920 and info.vertical_resolution == 1080) {
            found_1080 = mode_idx;
        }
        // Remember any 1920 width mode as last resort
        if (found_1920 == null and info.horizontal_resolution == 1920) {
            found_1920 = mode_idx;
        }
    }

    // If we didn't find 1920x1200, use 1920x1080, or any 1920 width
    if (chosen_mode == gop.mode.mode) {
        if (found_1080) |mode| {
            chosen_mode = mode;
        } else if (found_1920) |mode| {
            chosen_mode = mode;
        }
    }

    if (chosen_mode != gop.mode.mode) {
        gop.setMode(chosen_mode) catch {};
    }

    const screen_w = gop.mode.info.horizontal_resolution;
    const screen_h = gop.mode.info.vertical_resolution;
    const stride = gop.mode.info.pixels_per_scan_line;
    const fb_size = stride * screen_h;
    const framebuffer: [*]u32 = @ptrFromInt(@as(usize, @truncate(gop.mode.frame_buffer_base)));

    return GraphicsContext{
        .gop = gop,
        .screen_w = screen_w,
        .screen_h = screen_h,
        .stride = stride,
        .framebuffer = framebuffer,
        .fb_size = fb_size,
    };
}

/// Allocate background and foreground buffers
pub fn allocateBuffers(boot_services: *uefi.tables.BootServices, fb_size: usize) error{OutOfResources}!AppBuffers {
    const background_alloc = boot_services.allocatePool(uefi.tables.MemoryType.loader_data, fb_size * @sizeOf(u32)) catch {
        return error.OutOfResources;
    };
    const background_buffer: [*]u32 = @ptrCast(@alignCast(background_alloc));

    const foreground_alloc = boot_services.allocatePool(uefi.tables.MemoryType.loader_data, fb_size * @sizeOf(u32)) catch {
        return error.OutOfResources;
    };
    const foreground_buffer: [*]u32 = @ptrCast(@alignCast(foreground_alloc));

    return AppBuffers{
        .background = background_buffer,
        .foreground = foreground_buffer,
    };
}

/// Free allocated buffers
pub fn freeBuffers(boot_services: *uefi.tables.BootServices, buffers: AppBuffers) void {
    _ = boot_services.freePool(@ptrCast(@alignCast(buffers.background))) catch {};
    _ = boot_services.freePool(@ptrCast(@alignCast(buffers.foreground))) catch {};
}

/// Setup event loop with timer and keyboard (mouse is polled, not event-driven)
pub fn setupEvents(
    boot_services: *uefi.tables.BootServices,
    con_in: *uefi.protocol.SimpleTextInput,
    mouse: ?*uefi.protocol.SimplePointer,
    mouse_available: bool,
) error{Aborted}!EventConfig {
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

    // Setup event loop: keyboard(0), mouse(1), timer(2)
    // Mouse event MUST be at index 1 (like working reference)
    var events: [3]uefi.Event = undefined;
    var num_events: usize = 2;
    events[0] = con_in.wait_for_key;

    if (mouse_available) {
        if (input.getMouseEvent(mouse)) |evt| {
            events[1] = evt;
            events[2] = timer_event;
            num_events = 3;
        } else {
            events[1] = timer_event;
        }
    } else {
        events[1] = timer_event;
    }

    return EventConfig{
        .events = events,
        .num_events = num_events,
        .timer_event = timer_event,
    };
}
