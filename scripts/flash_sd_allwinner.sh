#!/bin/bash
# flash_sd_allwinner.sh
# Version: 1.0.0
# Description: Flashes an Allwinner U-Boot with SPL to a Micro-SD card.
# WARNING: Double-check your target device path using 'lsblk' before running.

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <path_to_u-boot-sunxi-with-spl.bin> <sd_card_device>"
    echo "Example: $0 ./u-boot-sunxi-with-spl.bin /dev/sdX"
    exit 1
fi

UBOOT_IMG=$1
TARGET_DEV=$2

# Safety check to ensure we aren't flashing the primary system drive
if [[ "$TARGET_DEV" == "/dev/sda" ]]; then
    echo "ERROR: Refusing to flash /dev/sda. Please verify your SD card block device."
    exit 1
fi

if [ ! -f "$UBOOT_IMG" ]; then
    echo "ERROR: U-Boot image not found at $UBOOT_IMG"
    exit 1
fi

echo "Zeroing out the first 1MB of the SD card (clearing partition table and old bootloaders)..."
# We skip the very first sector (MBR/GPT partition table area) to avoid breaking the filesystem layout if partitions already exist.
sudo dd if=/dev/zero of="$TARGET_DEV" bs=1024 seek=8 count=1015 status=progress

echo "Writing U-Boot with SPL to the Allwinner BROM 8KB offset..."
# The A33 BROM looks specifically for the eGON signature at the 8KB offset (block size 1024 * 8).
sudo dd if="$UBOOT_IMG" of="$TARGET_DEV" bs=1024 seek=8 status=progress

# Flush I/O buffers to ensure everything is written
sync

echo "Flash complete. You can now insert the SD card into the tablet and power it on."
