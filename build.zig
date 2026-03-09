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
    const optimize = b.standardOptimizeOption(.{});

    // -----------------------------------------------------------------------
    // Build BOTH 32-bit and 64-bit UEFI binaries
    //
    // 32-bit (ia32): For older systems like Intel Compute Stick STCK1A32WFC
    // 64-bit (x64):  For modern PCs (most common)
    //
    // UEFI firmware loads the appropriate file based on its architecture:
    // - 32-bit UEFI → BOOTIA32.EFI
    // - 64-bit UEFI → BOOTX64.EFI
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
        "-usb", "-device", "usb-mouse", // Enable USB mouse support
    });
    qemu.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run in QEMU with 32-bit UEFI (requires qemu-system-i386 + OVMF32)");
    run_step.dependOn(&qemu.step);

    // Alias 'qemu' step for easier typing
    const qemu_step = b.step("qemu", "Run in QEMU with 32-bit UEFI (requires qemu-system-i386 + OVMF32)");
    qemu_step.dependOn(&qemu.step);

    // -----------------------------------------------------------------------
    // `zig build image` — Create GPT-partitioned bootable USB image
    //
    // Creates: zig-out/uefi-boot.img (64MB GPT with ESP containing bootloader)
    //
    // Flash to USB:
    //   sudo dd if=zig-out/uefi-boot.img of=/dev/sdX bs=4M status=progress
    //   (Replace /dev/sdX with your USB device! Use lsblk to find it.)
    //
    // Or manually format USB:
    // sudo parted /dev/sdX --script -- mklabel gpt
    // sudo parted /dev/sdX --script -- mkpart primary fat32 1MiB 100%
    // sudo parted /dev/sdX --script -- set 1 esp on
    // sudo mkfs.fat -F 32 /dev/sdX1
    // sudo mkdir -p /mnt/efi && sudo mount /dev/sdX1 /mnt/efi
    // sudo mkdir -p /mnt/efi/EFI/BOOT
    // sudo cp zig-out/bin/EFI/BOOT/BOOTIA32.EFI /mnt/efi/EFI/BOOT/
    // sudo cp zig-out/bin/EFI/BOOT/BOOTX64.EFI /mnt/efi/EFI/BOOT/
    // sudo umount /mnt/efi
    //
    // Requirements: parted, dosfstools (mkfs.fat)
    // -----------------------------------------------------------------------
    const image_script = b.addSystemCommand(&.{
        "sh", "-c",
        // Step 1: Create 64MB disk image
        "cd zig-out && rm -f uefi-boot.img && " ++
            "dd if=/dev/zero of=uefi-boot.img bs=1M count=64 status=none && " ++
            // Step 2: Create GPT with ESP partition (type EF00)
            "parted -s uefi-boot.img mklabel gpt && " ++
            "parted -s uefi-boot.img mkpart primary fat32 1MiB 63MiB && " ++
            "parted -s uefi-boot.img set 1 esp on && " ++
            // Step 3: Setup loop device for the partition
            "LOOP_DEV=$(sudo losetup -f --show -P uefi-boot.img) && " ++
            "PART_DEV=\"${LOOP_DEV}p1\" && " ++
            // Step 4: Format ESP as FAT32
            "sudo mkfs.fat -F 32 -n \"UEFI\" \"$PART_DEV\" && " ++
            // Step 5: Mount and copy BOTH EFI files (32-bit and 64-bit)
            "sudo mkdir -p /tmp/uefi-esp && " ++
            "sudo mount \"$PART_DEV\" /tmp/uefi-esp && " ++
            "sudo mkdir -p /tmp/uefi-esp/EFI/BOOT && " ++
            "sudo cp bin/EFI/BOOT/BOOTIA32.EFI /tmp/uefi-esp/EFI/BOOT/ && " ++
            "sudo cp bin/EFI/BOOT/BOOTX64.EFI /tmp/uefi-esp/EFI/BOOT/ && " ++
            "echo 'Files copied:' && " ++
            "ls -la /tmp/uefi-esp/EFI/BOOT/ && " ++
            "sudo umount /tmp/uefi-esp && " ++
            "sudo rm -rf /tmp/uefi-esp && " ++
            "sudo losetup -d \"$LOOP_DEV\" && " ++
            // Step 6: Show result
            "echo '' && " ++
            "echo '========================================' && " ++
            "echo 'UEFI boot image created successfully!' && " ++
            "echo '========================================' && " ++
            "echo 'File: zig-out/uefi-boot.img' && " ++
            "echo 'Size: 64MB (GPT partitioned with ESP)' && " ++
            "echo 'Contents:' && " ++
            "echo '  /EFI/BOOT/BOOTIA32.EFI (32-bit)' && " ++
            "echo '  /EFI/BOOT/BOOTX64.EFI (64-bit)' && " ++
            "echo '' && " ++
            "echo 'To flash to USB:' && " ++
            "echo ' sudo dd if=zig-out/uefi-boot.img of=/dev/sdX bs=4M status=progress' && " ++
            "echo '' && " ++
            "echo 'Replace /dev/sdX with your USB device (check with: lsblk)'",
    });
    image_script.step.dependOn(b.getInstallStep());

    const image_step = b.step("image", "Create GPT-partitioned USB image with 32+64 bit (requires sudo)");
    image_step.dependOn(&image_script.step);

    // -----------------------------------------------------------------------
    // `zig build simple-image` — Create simple FAT image (no partition table)
    //
    // This creates just a FAT32 filesystem without GPT. Some systems can boot
    // this, but most real hardware requires GPT partition table.
    // Use `zig build image` for proper hardware compatibility.
    //
    // No sudo required for this version.
    // -----------------------------------------------------------------------
    const simple_image_script = b.addSystemCommand(&.{
        "sh", "-c",
        "cd zig-out && rm -f uefi-simple.img && " ++
            "dd if=/dev/zero of=uefi-simple.img bs=1M count=32 status=none && " ++
            "mkfs.fat -F 32 -n \"UEFI\" uefi-simple.img && " ++
            "mmd -i uefi-simple.img ::/EFI && " ++
            "mmd -i uefi-simple.img ::/EFI/BOOT && " ++
            "mcopy -i uefi-simple.img bin/EFI/BOOT/BOOTIA32.EFI ::/EFI/BOOT/BOOTIA32.EFI && " ++
            "mcopy -i uefi-simple.img bin/EFI/BOOT/BOOTX64.EFI ::/EFI/BOOT/BOOTX64.EFI && " ++
            "echo 'Simple FAT image created: zig-out/uefi-simple.img' && " ++
            "echo 'Contains: BOOTIA32.EFI + BOOTX64.EFI' && " ++
            "echo '(No partition table - mainly for QEMU testing)'",
    });
    simple_image_script.step.dependOn(b.getInstallStep());

    const simple_image_step = b.step("simple-image", "Create simple FAT image with 32+64 bit (no GPT)");
    simple_image_step.dependOn(&simple_image_script.step);

    // -----------------------------------------------------------------------
    // `zig build usb /dev/sdX` — Format USB drive directly (most reliable)
    //
    // This formats a USB drive with GPT + FAT32 and copies the EFI file.
    // The drive will show up as a normal FAT32 USB drive in your OS.
    //
    // Usage:
    //   zig build usb -- /dev/sdX
    //   Example: zig build usb -- /dev/sdb
    //
    // Find your device with: lsblk
    // WARNING: This ERASES all data on the USB drive!
    //
    // After formatting, you can:
    //   1. Eject and re-insert the USB to see it as a regular drive
    //   2. Boot from it (disable Secure Boot, select USB in boot menu)
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
