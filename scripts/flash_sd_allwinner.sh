#!/bin/bash
# __version__: 1.1.0
# Description: Fully automates formatting, partitioning, and flashing an Allwinner SD Card.
# Warning: This will DESTROY ALL DATA on the target drive without prompting.

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <path_to_u-boot-sunxi-with-spl.bin> <sd_card_device>"
    echo "Example: $0 ./u-boot-sunxi-with-spl.bin /dev/sdX"
    exit 1
fi

UBOOT_IMG=$1
TARGET_DEV=$2

# Safety check: Prevent flashing the host OS drive
if [[ "$TARGET_DEV" == "/dev/sda" || "$TARGET_DEV" == "/dev/nvme0n1" ]]; then
    echo "ERROR: Refusing to flash $TARGET_DEV. Please verify your SD card block device."
    exit 1
fi

if [ ! -f "$UBOOT_IMG" ]; then
    echo "ERROR: U-Boot image not found at $UBOOT_IMG"
    exit 1
fi

echo "--- Unmounting any active partitions on $TARGET_DEV ---"
sudo umount ${TARGET_DEV}* 2>/dev/null || true

echo "--- Wiping the first 10MB to destroy old partition tables and bootloaders ---"
sudo dd if=/dev/zero of="$TARGET_DEV" bs=1M count=10 status=none
sync

echo "--- Creating new partition layout ---"
# We pipe the layout directly into sfdisk
# Part 1: Start at 1MB (sector 2048), size 500MB, type 'c' (W95 FAT32 LBA), bootable flag '*'
# Part 2: Start immediately after, take remaining space, type '83' (Linux EXT4)
sudo sfdisk "$TARGET_DEV" <<EOF
label: dos
start=2048, size=500M, type=c, bootable
type=83
EOF

echo "--- Informing kernel of new partitions ---"
sudo partprobe "$TARGET_DEV"
sleep 2 # Brief pause to ensure device nodes populate in /dev/

# Determine the correct partition paths (/dev/sdb1 vs /dev/mmcblk0p1)
if [[ "$TARGET_DEV" == *[0-9] ]]; then
    PART1="${TARGET_DEV}p1"
    PART2="${TARGET_DEV}p2"
else
    PART1="${TARGET_DEV}1"
    PART2="${TARGET_DEV}2"
fi

echo "--- Formatting Partitions ---"
echo "Formatting Boot Partition ($PART1) as FAT32..."
sudo mkfs.vfat -F 32 -n "BOOT" "$PART1"

echo "Formatting RootFS Partition ($PART2) as EXT4..."
sudo mkfs.ext4 -F -L "ROOTFS" "$PART2"

echo "--- Writing U-Boot SPL to the 8KB offset ---"
# We do this LAST to ensure formatting the MBR didn't overwrite the BROM space
sudo dd if="$UBOOT_IMG" of="$TARGET_DEV" bs=1024 seek=8 status=progress
sync

echo "=========================================================="
echo "SUCCESS! The SD Card is partitioned, formatted, and flashed."
echo "Partition 1 (Boot): $PART1 (FAT32, 500MB)"
echo "Partition 2 (Root): $PART2 (EXT4, Remaining)"
echo "You can now mount $PART1 and copy your zImage/dtb/boot.scr."
echo "=========================================================="