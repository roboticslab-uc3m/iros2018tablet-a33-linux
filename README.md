# iros2018tablet-a33-linux

Objective: Bypass the factory bootloader to run Linux on an Allwinner A33 "Q8" tablet. The Allwinner BootROM (BROM) is hardcoded. When you power on an A33 device, the silicon permanently executes a specific sequence before it even looks at the internal NAND memory where your Android 4.4 KitKat sits. It checks MMC0 (the Micro-SD slot) first. If it finds a valid boot signature at a specific offset (8KB), it will execute it. If it doesn't, it falls back to the internal NAND, and if that is corrupted, it drops to the USB FEL mode (1f3a:efe8). This means your tablets are practically unbrickable. We can completely bypass the internal storage by putting a bootloader (U-Boot) on the SD card.

## Phase 1: Generate `u-boot-sunxi-with-spl.bin`

We want `u-boot-sunxi-with-spl.bin` because it is important for Allwinner (such as A33) chips. It contains two parts: SPL (Secondary Program Loader, a tiny piece of code that fits into the tablet's tiny 32KB internal SRAM, with the only job of turning the DDR RAM on) and U-Boot (Once the RAM is on, the SPL loads the main U-Boot program into the massive 1 GB RAM space and executes it).

Clone the mainline U-Boot repository (using the GitHub mirror for speed; checkout a recent, stable release to avoid bleeding-edge bugs):

```bash
git clone --branch v2024.01 --depth 1 https://github.com/u-boot/u-boot.git
cd u-boot
```

Build the Docker image:

```bash
docker build --build-arg USER_ID=$(id -u) --build-arg GROUP_ID=$(id -g) -t a33-builder ./docker/
```

Enter the container:

```bash
docker run -it --rm -v $(pwd):/home/builder/workspace a33-builder bash
```

(Inside the container) Configure the build environment for the A33 tablet reference design:

```bash
make CROSS_COMPILE=arm-linux-gnueabihf- q8_a33_tablet_1024x600_defconfig
```

(Inside the container) Compile U-Boot:

```bash
make CROSS_COMPILE=arm-linux-gnueabihf- -j$(nproc)
```

## Phase 2: MicroSD Card Partitioning & RootFS

MicroSD characteristics:

- Capacity: 16GB or 32GB. 32GB is the maximum size for the SDHC standard. Staying at or below 32GB ensures maximum compatibility with the A33's BootROM without having to worry about SDXC formatting quirks. It gives you plenty of room for logs, swap space, and experimenting. Note: I've tried with 64 GB and `u-boot-sunxi-with-spl.bin` was **not** detected, you have been warned. :smiley:
- Speed / Class: Look for UHS-I (U1 or U3) with an A1 Application Performance Class rating.

The MicroSD card requires a specific partition table to leave room for the bootloader at the very beginning of the drive (the first 1MB of the drive completely empty, unallocated space; Partition 1, 100MB FAT32, label BOOT; Partition 2, remaining space ext4, label ROOTFS). Write the resulting `u-boot-sunxi-with-spl.bin` directly to the SD card's raw block device, skipping the first 8KB (better via script, essentially `sudo dd if=u-boot-sunxi-with-spl.bin of=/dev/sdX bs=1024 seek=8`):

```bash
./scripts/flash_sd_allwinner.sh ./u-boot-sunxi-with-spl.bin /dev/sdX # adapt to your file path and device name
```
