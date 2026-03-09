// =============================================================================
// build.zig — Zig 0.15.x build script for UEFI Paint Application
// Target: Intel Compute Stick STCK1A32WFC (32-bit UEFI / ia32)
//
// Build commands:
//   zig build              → Build EFI files (zig-out/bin/EFI/BOOT/*.EFI)
//   zig build usb -- /dev/sdX  → Flash to USB drive
//   zig build run          → Test in QEMU
//
// Project layout:
//   src/main.zig           ← application source
//   assets/logo.raw        ← 128x128 raw BGRA image (embedded into binary)
//   build.zig              ← this file
//   scripts/format-usb.sh  ← USB formatting script
// =============================================================================

const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    // -----------------------------------------------------------------------
    // Build BOTH 32-bit and 64-bit UEFI binaries
    // -----------------------------------------------------------------------

    // 32-bit x86 target
    const target_32 = b.resolveTargetQuery(.{
        .cpu_arch = .x86,
        .os_tag = .uefi,
    });

    const exe_32 = b.addExecutable(.{
        .name = "BOOTIA32",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target_32,
            .optimize = optimize,
        }),
    });

    // 64-bit x86_64 target
    const target_64 = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .uefi,
    });

    const exe_64 = b.addExecutable(.{
        .name = "BOOTX64",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target_64,
            .optimize = optimize,
        }),
    });

    // Install both binaries
    const install_32 = b.addInstallArtifact(exe_32, .{
        .dest_sub_path = "EFI/BOOT/BOOTIA32.EFI",
    });

    const install_64 = b.addInstallArtifact(exe_64, .{
        .dest_sub_path = "EFI/BOOT/BOOTX64.EFI",
    });

    b.getInstallStep().dependOn(&install_32.step);
    b.getInstallStep().dependOn(&install_64.step);

    // -----------------------------------------------------------------------
    // `zig build run` — test in QEMU with 32-bit OVMF firmware
    // -----------------------------------------------------------------------
    const qemu = b.addSystemCommand(&.{
        "qemu-system-i386",
        "-bios",
        "/usr/share/edk2/ia32/OVMF.4m.fd",
        "-drive",
        "format=raw,file=fat:rw:zig-out/bin",
        "-vga",
        "std",
        "-net",
        "none",
        "-usb",
        "-device",
        "usb-mouse",
    });
    qemu.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run in QEMU (requires qemu-system-i386 + OVMF32)");
    run_step.dependOn(&qemu.step);

    // -----------------------------------------------------------------------
    // `zig build usb -- /dev/sdX` — Format USB drive directly
    //
    // Usage: zig build usb -- /dev/sdX
    // Example: zig build usb -- /dev/sdb
    //
    // Find your device with: lsblk
    // WARNING: This ERASES all data on the USB drive!
    // -----------------------------------------------------------------------
    const usb_script = b.addSystemCommand(&.{
        "sudo", "./scripts/format-usb.sh",
    });
    usb_script.step.dependOn(b.getInstallStep());

    // Allow extra arguments (the device path)
    if (b.args) |args| {
        usb_script.addArgs(args);
    }

    const usb_step = b.step("usb", "Format USB drive for booting (usage: zig build usb -- /dev/sdX)");
    usb_step.dependOn(&usb_script.step);
}
