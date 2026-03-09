#!/bin/bash
# Create UEFI bootable USB image
# Usage: sudo ./create-boot-image.sh

set -e

cd "$(dirname "$0")/.."

# Build first
echo "Building..."
zig build

# Create image
echo "Creating bootable image..."
cd zig-out
rm -f uefi-boot.img

# Create 64MB image
dd if=/dev/zero of=uefi-boot.img bs=1M count=64 status=progress

# Create GPT partition table with ESP
parted -s uefi-boot.img mklabel gpt
parted -s uefi-boot.img mkpart primary fat32 1MiB 63MiB
parted -s uefi-boot.img set 1 esp on

# Setup loop device
LOOP_DEV=$(losetup -f --show -P uefi-boot.img)
PART_DEV="${LOOP_DEV}p1"

# Format ESP as FAT32
mkfs.fat -F 32 -n "UEFI" "$PART_DEV"

# Mount and copy files
mkdir -p /tmp/uefi-esp
mount "$PART_DEV" /tmp/uefi-esp
mkdir -p /tmp/uefi-esp/EFI/BOOT
cp bin/EFI/BOOT/BOOTIA32.EFI /tmp/uefi-esp/EFI/BOOT/

# Verify
ls -la /tmp/uefi-esp/EFI/BOOT/

# Cleanup
umount /tmp/uefi-esp
rm -rf /tmp/uefi-esp
losetup -d "$LOOP_DEV"

echo ""
echo "Success! Created: zig-out/uefi-boot.img"
echo ""
echo "To flash to USB:"
echo "  sudo dd if=zig-out/uefi-boot.img of=/dev/sdX bs=4M status=progress"
echo "  (Replace /dev/sdX with your USB device!)"
