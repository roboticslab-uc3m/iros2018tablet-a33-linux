#!/bin/bash
# __version__: 1.2.0
# Description: Fully automates formatting, partitioning, flashing U-Boot, and generating a dynamic boot.scr.
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
sudo sfdisk "$TARGET_DEV" <<EOF
label: dos
start=2048, size=500M, type=c, bootable
type=83
EOF

echo "--- Informing kernel of new partitions ---"
sudo partprobe "$TARGET_DEV"
sleep 2 

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
sudo dd if="$UBOOT_IMG" of="$TARGET_DEV" bs=1024 seek=8 status=progress
sync

# =================================================================
# AUTOMATED BOOT.SCR GENERATION (Dynamic PARTUUID)
# =================================================================

echo "--- Forcing kernel to recognize new partitions for blkid ---"
sudo partprobe "$TARGET_DEV"
udevadm settle

echo "--- Extracting RootFS PARTUUID ---"
if [ -z "$PART2" ]; then
    echo "CRITICAL ERROR: The PART2 variable is empty! Check script variable definitions."
    exit 1
fi

ROOT_PARTUUID=$(sudo blkid -s PARTUUID -o value "$PART2")

if [ -z "$ROOT_PARTUUID" ]; then
    echo "ERROR: blkid could not read the PARTUUID from $PART2. You will need to generate boot.scr manually."
else
    echo "Success! Found Root PARTUUID: $ROOT_PARTUUID"

    echo "--- Generating Auto-Configured boot.cmd ---"
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
    RESIDUAL_CMD="$SCRIPT_DIR/boot.cmd"

    cat <<EOF > "$RESIDUAL_CMD"
echo "Loading Kernel (Dynamic PARTUUID)..."
setenv bootargs console=tty1 root=PARTUUID=$ROOT_PARTUUID rw rootwait panic=10 loglevel=3
load mmc 0:1 0x42000000 zImage
load mmc 0:1 0x43000000 sun8i-a33-q8-tablet.dtb
bootz 0x42000000 - 0x43000000
EOF
    
    chmod 644 "$RESIDUAL_CMD"
    echo "Saved residual text file to: $RESIDUAL_CMD"

    echo "--- Compiling and Copying boot.scr ---"
    sudo mkdir -p /mnt/tablet_boot_temp
    sudo mount "$PART1" /mnt/tablet_boot_temp
    
    sudo mkimage -C none -A arm -T script -d "$RESIDUAL_CMD" /mnt/tablet_boot_temp/boot.scr
    
    sudo umount /mnt/tablet_boot_temp
    echo "Automated boot.scr successfully generated and installed to the BOOT partition!"
fi

echo "=========================================================="
echo "SUCCESS! The SD Card is fully prepped."
echo "Partition 1 (Boot): $PART1 (FAT32, 500MB)"
echo "Partition 2 (Root): $PART2 (EXT4, Remaining)"
echo "You can now mount $PART1 and copy your zImage and .dtb files."
echo "=========================================================="