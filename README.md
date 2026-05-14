# iros2018tablet-a33-linux

Bypass the factory bootloader to run Linux on an Allwinner A33 "Q8" tablet.

## Phase 1: SD Card Partitioning & RootFS

The SD card requires a specific partition table to leave room for the bootloader at the very beginning of the drive (the first 1MB of the drive completely empty, unallocated space; Partition 1, 100MB FAT32, label BOOT; Partition 2, remaining space ext4, label ROOTFS).

```bash
./scripts/flash_sd_allwinner.sh
```
