#!/bin/bash
# Format USB drive with proper UEFI boot partition
# Usage: sudo ./format-usb.sh /dev/sdX
# Example: sudo ./format-usb.sh /dev/sdb

set -e

if [ $# -ne 1 ]; then
    echo "Usage: sudo $0 /dev/sdX"
    echo "Example: sudo $0 /dev/sdb"
    echo ""
    echo "WARNING: This will DESTROY all data on the device!"
    echo "Use 'lsblk' to find your USB device"
    exit 1
fi

USB_DEVICE="$1"

# Safety check - don't allow operating on system disks
if [[ "$USB_DEVICE" == *"nvme"* ]]; then
    echo "ERROR: This looks like a system disk. Use a USB device like /dev/sdb"
    exit 1
fi

if [ ! -b "$USB_DEVICE" ]; then
    echo "ERROR: $USB_DEVICE is not a block device"
    exit 1
fi

echo "WARNING: This will ERASE all data on $USB_DEVICE"
echo "Press Ctrl+C to cancel, or wait 3 seconds..."
sleep 3

echo ""
echo "Step 1: Creating GPT partition table..."
parted -s "$USB_DEVICE" mklabel gpt

echo "Step 2: Creating FAT32 partition..."
parted -s "$USB_DEVICE" mkpart primary fat32 1MiB 100%

echo "Step 3: Setting ESP flag..."
parted -s "$USB_DEVICE" set 1 esp on

# Get the partition device (handles /dev/sdb -> /dev/sdb1)
PARTITION="${USB_DEVICE}1"
if [[ "$USB_DEVICE" == *"mmc"* ]]; then
    PARTITION="${USB_DEVICE}p1"
fi

echo "Step 4: Formatting as FAT32..."
mkfs.fat -F 32 -n "P1X" "$PARTITION"

echo "Step 5: Mounting and copying files..."
MOUNT_POINT="/tmp/uefi-usb-$$"
mkdir -p "$MOUNT_POINT"
mount "$PARTITION" "$MOUNT_POINT"

# Create EFI directory structure
mkdir -p "$MOUNT_POINT/EFI/BOOT"

# Copy BOTH EFI files (32-bit and 64-bit)
echo "  Copying BOOTIA32.EFI (32-bit)..."
cp "$(dirname "$0")/../zig-out/bin/EFI/BOOT/BOOTIA32.EFI" "$MOUNT_POINT/EFI/BOOT/"
echo "  Copying BOOTX64.EFI (64-bit)..."
cp "$(dirname "$0")/../zig-out/bin/EFI/BOOT/BOOTX64.EFI" "$MOUNT_POINT/EFI/BOOT/"

# Verify
echo "Step 6: Verifying..."
ls -la "$MOUNT_POINT/EFI/BOOT/"

echo "Step 7: Unmounting..."
umount "$MOUNT_POINT"
rmdir "$MOUNT_POINT"

echo ""
echo "=========================================="
echo "SUCCESS! USB drive formatted and ready"
echo "=========================================="
echo ""
echo "Device: $USB_DEVICE"
echo "Partition: $PARTITION (FAT32 with GPT)"
echo ""
echo "Files installed:"
echo "  /EFI/BOOT/BOOTIA32.EFI (for 32-bit UEFI)"
echo "  /EFI/BOOT/BOOTX64.EFI (for 64-bit UEFI)"
echo ""
echo "You can now boot from this USB drive"
echo ""
echo "Troubleshooting:"
echo "1. Disable Secure Boot in BIOS"
echo "2. Select USB from boot menu (F12/F10/Esc)"
echo "3. Make sure BIOS is in UEFI mode (not Legacy/CSM)"
echo "4. Most modern PCs use 64-bit UEFI (BOOTX64.EFI)"
