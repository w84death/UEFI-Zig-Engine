#!/bin/bash
# Update existing USB drive with new EFI files
# Usage: sudo ./update-usb.sh /dev/sdX
# Example: sudo ./update-usb.sh /dev/sdb
#
# This mounts the USB's first partition and just copies/overwrites
# the EFI files without reformatting. Much faster than full format.

set -e

if [ $# -ne 1 ]; then
    echo "Usage: sudo $0 /dev/sdX"
    echo "Example: sudo $0 /dev/sdb"
    echo ""
    echo "Updates EFI files on an already-formatted USB drive"
    echo "The USB must have been formatted first with: zig build usb -- /dev/sdX"
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

# Get the partition device (handles /dev/sdb -> /dev/sdb1)
PARTITION="${USB_DEVICE}1"
if [[ "$USB_DEVICE" == *"mmc"* ]]; then
    PARTITION="${USB_DEVICE}p1"
fi

if [ ! -b "$PARTITION" ]; then
    echo "ERROR: Partition $PARTITION does not exist"
    echo "The USB must be formatted first with: zig build usb -- $USB_DEVICE"
    exit 1
fi

echo "Mounting $PARTITION..."
MOUNT_POINT="/tmp/uefi-usb-update-$$"
mkdir -p "$MOUNT_POINT"
mount "$PARTITION" "$MOUNT_POINT"

# Ensure EFI/BOOT directory exists
mkdir -p "$MOUNT_POINT/EFI/BOOT"

echo "Copying EFI files..."
cp -v "$(dirname "$0")/../zig-out/bin/EFI/BOOT/BOOTIA32.EFI" "$MOUNT_POINT/EFI/BOOT/"
cp -v "$(dirname "$0")/../zig-out/bin/EFI/BOOT/BOOTX64.EFI" "$MOUNT_POINT/EFI/BOOT/"

echo "Verifying..."
ls -la "$MOUNT_POINT/EFI/BOOT/"

echo "Unmounting..."
umount "$MOUNT_POINT"
rmdir "$MOUNT_POINT"

echo ""
echo "=========================================="
echo "SUCCESS! USB drive updated"
echo "=========================================="
echo ""
echo "Device: $USB_DEVICE"
echo "Partition: $PARTITION"
echo ""
echo "Files updated:"
echo " /EFI/BOOT/BOOTIA32.EFI"
echo " /EFI/BOOT/BOOTX64.EFI"
echo ""
echo "Boot from USB to test the new build"
