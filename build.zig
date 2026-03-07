// =============================================================================
// build.zig — Zig 0.15.x build script for UEFI Logo Display
// Target: Intel Compute Stick STCK1A32WFC (32-bit UEFI / ia32)
//
// Project layout:
//   src/
//     main.zig          ← application source
//   assets/
//     logo.raw          ← 128x128 raw BGRA image, exactly 65536 bytes
//                         embedded into the EFI binary via @embedFile
//   build.zig           ← this file
//
// Build:
//   zig build                        → zig-out/BOOTIA32.EFI
//   zig build -Doptimize=ReleaseSmall → smaller binary, no debug info
//   zig build run                    → QEMU test (see requirements below)
//
// Deploy to USB (GPT + FAT32):
//   mkdir -p /mnt/usb/EFI/BOOT
//   cp zig-out/BOOTIA32.EFI /mnt/usb/EFI/BOOT/BOOTIA32.EFI
//   # No other files needed — logo.raw is baked into the EFI binary.
//
// Generating logo.raw with ImageMagick:
//   convert logo.png -resize 128x128! bgr0:assets/logo.raw
//   # The `bgr0:` output format writes raw 32-bit pixels in B,G,R,0 order
//   # which matches the Bay Trail framebuffer (PixelBgrReserved8BitPerColor).
//
// Generating logo.raw with Python / Pillow:
//   from PIL import Image
//   img = Image.open("logo.png").resize((128, 128)).convert("RGBA")
//   r, g, b, a = img.split()
//   bgra = Image.merge("RGBA", (b, g, r, a))  # swap R<->B for BGR0
//   with open("assets/logo.raw", "wb") as f:
//       f.write(bgra.tobytes())
// =============================================================================

const std = @import("std");

pub fn build(b: *std.Build) void {
    // -----------------------------------------------------------------------
    // Target: x86 (32-bit) UEFI
    //
    // .cpu_arch = .x86   → 32-bit IA-32 PE32 image (not PE32+)
    // .os_tag   = .uefi  → Zig emits a UEFI application with entry shim,
    //                      and populates system_table + handle globals
    //
    // MUST be .x86 — the STCK1A32WFC has a 32-bit UEFI firmware and will
    // refuse to load a 64-bit PE32+ image (bootx64.efi / x86_64 target).
    // -----------------------------------------------------------------------
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .x86,
        .os_tag = .uefi,
    });

    // Allow -Doptimize= override. ReleaseSmall recommended for EFI binaries.
    const optimize = b.standardOptimizeOption(.{});

    // -----------------------------------------------------------------------
    // 0.15.x API: source file + target + optimize all go into createModule().
    // -----------------------------------------------------------------------
    const exe = b.addExecutable(.{
        .name = "BOOTIA32",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // -----------------------------------------------------------------------
    // @embedFile in main.zig resolves paths relative to src/main.zig itself,
    // so "../assets/logo.raw" is correct. No build.zig wiring needed for
    // embedded files — the Zig compiler handles them automatically.
    //
    // The comptime size check in main.zig will catch a missing or wrong-sized
    // logo.raw at compile time with a clear error message.
    // -----------------------------------------------------------------------

    // -----------------------------------------------------------------------
    // Install to zig-out/EFI/BOOT/BOOTIA32.EFI for UEFI auto-boot
    // -----------------------------------------------------------------------
    const install = b.addInstallArtifact(exe, .{
        .dest_sub_path = "EFI/BOOT/BOOTIA32.EFI",
    });
    b.getInstallStep().dependOn(&install.step);

    // -----------------------------------------------------------------------
    // `zig build run` — test in QEMU with 32-bit OVMF firmware.
    //
    // Requirements:
    //   qemu-system-i386
    //   32-bit OVMF firmware — one of:
    //     /usr/share/ovmf/OVMF32.fd          (Debian/Ubuntu: apt install ovmf)
    //     /usr/share/edk2/ia32/OVMF_CODE.fd  (Fedora: dnf install edk2-ovmf)
    //     /usr/share/edk2-ovmf/ia32/OVMF_CODE.fd (Arch: pacman -S edk2-ovmf)
    //
    // QEMU serves zig-out/ as a FAT drive. The firmware finds BOOTIA32.EFI
    // at the root, loads it, and you see your logo on the QEMU window.
    // The -vga std flag ensures GOP is available (QEMU default).
    // -----------------------------------------------------------------------
    const qemu = b.addSystemCommand(&.{
        "qemu-system-i386",
        "-bios",  "/usr/share/edk2/ia32/OVMF.4m.fd", // adjust path for your distro
        "-drive", "format=raw,file=fat:rw:zig-out/bin",
        "-vga",   "std",
        "-net",   "none",
    });
    qemu.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run in QEMU with 32-bit UEFI (requires qemu-system-i386 + OVMF32)");
    run_step.dependOn(&qemu.step);

    // Alias 'qemu' step for easier typing
    const qemu_step = b.step("qemu", "Run in QEMU with 32-bit UEFI (requires qemu-system-i386 + OVMF32)");
    qemu_step.dependOn(&qemu.step);
}
