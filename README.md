# iros2018tablet-a33-linux

Objective: Bypass the factory bootloader to run Linux on an Allwinner A33 "Q8" tablet. The Allwinner BootROM (BROM) is hardcoded. When you power on an A33 device, the silicon permanently executes a specific sequence before it even looks at the internal NAND memory where your Android 4.4 KitKat sits. It checks MMC0 (the Micro-SD slot) first. If it finds a valid boot signature at a specific offset (8KB), it will execute it. If it doesn't, it falls back to the internal NAND, and if that is corrupted, it drops to the USB FEL mode (1f3a:efe8). This means your tablets are practically unbrickable. We can completely bypass the internal storage by putting a bootloader (U-Boot) on the SD card.

## Step 1: Generate `u-boot-sunxi-with-spl.bin`

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

This generates our desired `u-boot-sunxi-with-spl.bin` file.

Exit the container.

## Step 2: MicroSD Card Partitioning + Install `u-boot-sunxi-with-spl.bin` at 8KB + `boot.scr` to BOOT via u-boot-tools 

MicroSD characteristics:

- Capacity: 16GB or 32GB. 32GB is the maximum size for the SDHC standard. Staying at or below 32GB ensures maximum compatibility with the A33's BootROM without having to worry about SDXC formatting quirks. It gives you plenty of room for logs, swap space, and experimenting. Note: I've tried with 64 GB and `u-boot-sunxi-with-spl.bin` was **not** detected, you have been warned. :smiley:
- Speed / Class: Look for UHS-I (U1 or U3) with an A1 Application Performance Class rating.

The MicroSD card requires a specific partition table to leave room for the bootloader at the very beginning of the drive (the first 1MB of the drive completely empty, unallocated space; Partition 1, 100MB FAT32, label BOOT; Partition 2, remaining space ext4, label ROOTFS). You must write the resulting `u-boot-sunxi-with-spl.bin` directly to the SD card's raw block device, skipping the first 8KB. All of this (including essentially `sudo dd if=u-boot-sunxi-with-spl.bin of=/dev/sdX bs=1024 seek=8`) is better via script (now contains `mkimage -C none -A arm -T script -d ./scripts/boot.cmd /mnt/BOOT/boot.scr`):

```bash
sudo apt install u-boot-tools
./scripts/flash_sd_allwinner.sh ./u-boot-sunxi-with-spl.bin /dev/sdX # adapt to your file path and device name
```

With this, you should be able to turn the tablet on with this microSD inside, resulting in a boot sequence that displays the Das U-Boot logo and some errors (rather than the vendor-installed Android sequence), ending at a `=>`.

## Step 3: `zImage` and `dtbs`

BOOT partition needs 3 files: `boot.scr` (done in previous step), `zImage` and `dtbs`. Clone the stable Linux kernel (using depth=1 saves downloading GBs of history):

```bash
git clone --depth=1 --branch v6.6 https://github.com/torvalds/linux.git
cd linux
```

Over-write the device tree source (adapt paths depending on your setup):

```bash
cp ./dts/sun8i-a33-q8-tablet-peripheral.dts arch/arm/boot/dts/allwinner/sun8i-a33-q8-tablet.dts
```

Enter the container:

```bash
docker run -it --rm -v $(pwd):/home/builder/workspace a33-builder bash
```

(Inside the container) Configure the kernel for Allwinner (sunxi) processors:

```bash
# Nuke the old config and load the default factory baseline
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- sunxi_defconfig

# Resurrect DRM and Lima (GPU)
./scripts/config --enable CONFIG_DRM
./scripts/config --enable CONFIG_DRM_SUN4I
./scripts/config --enable CONFIG_DRM_SUN8I_MIXER
./scripts/config --module CONFIG_DRM_LIMA

# Enable the DPI Panel Drivers
./scripts/config --enable CONFIG_DRM_PANEL
./scripts/config --enable CONFIG_DRM_PANEL_SIMPLE

# Turn on the DRM Text Console (So you still get your boot text!)
./scripts/config --enable CONFIG_DRM_FBDEV_EMULATION
./scripts/config --enable CONFIG_FRAMEBUFFER_CONSOLE

#./scripts/config --enable CONFIG_LOGO  # Optional: Shows the Tux penguins on boot!

# The Touchscreen (Silead GSL2681)
./scripts/config --enable CONFIG_INPUT_TOUCHSCREEN
./scripts/config --enable CONFIG_I2C_SUN6I_P2WI      # Allwinner specific I2C
./scripts/config --module CONFIG_TOUCHSCREEN_SILEAD

# The USB Subsystem (Host Mode for Android Auto)
./scripts/config --enable CONFIG_USB
./scripts/config --enable CONFIG_USB_SUPPORT
./scripts/config --enable CONFIG_USB_MUSB_SUNXI      # Allwinner USB PHY
./scripts/config --enable CONFIG_USB_MUSB_HDRC
./scripts/config --enable CONFIG_USB_MUSB_HOST       # Force it to be the "Boss"

# The Wi-Fi (Realtek SDIO)
./scripts/config --enable CONFIG_WLAN
./scripts/config --module CONFIG_CFG80211
./scripts/config --module CONFIG_MAC80211
./scripts/config --enable CONFIG_STAGING             # Required for Realtek driver
./scripts/config --enable CONFIG_R8723BS             # The RTL8723BS SDIO driver

# Apply config
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- olddefconfig
```

(Inside the container) Compile the Kernel and Device Trees (this will take a few minutes)

```bash
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- -j$(nproc) zImage dtbs
```

Exit the container and copy the generated core files to your microSD (adapt paths depending on your setup, e.g. `/media/$USER/BOOT` may be `/mnt/BOOT`)

```bash
cp arch/arm/boot/zImage /media/$USER/BOOT/
cp arch/arm/boot/dts/allwinner/sun8i-a33-q8-tablet.dtb /media/$USER/BOOT/
```

If you boot from this microSD card, you should reach Das U-Boot message ""Starting kernel ..."!

## Step 4: Install Debian (armhf)

Run debootstrap to construct Debian 12 (Bookworm) for the 32-bit ARM architecture. This will take a few minutes as it downloads and extracts the core packages ((adapt paths depending on your setup, e.g. `/media/$USER/ROOTFS` may be `/mnt/ROOTFS`; additionally, permissions e.g. `sudo mount -o remount,exec,dev,suid /media/$USER/ROOTFS`):

```bash
sudo apt install debootstrap qemu-user-static
sudo debootstrap --arch=armhf bookworm /mnt/ROOTFS http://deb.debian.org/debian/
```

Set the password:

```bash
sudo chroot /media/$USER/ROOTFS /bin/bash
passwd
```

And update the hostname (when you run `debootstrap`, it often directly copies your host Ubuntu PC's `/etc/hosts` file onto the SD card, we want to override that):

```bash
export NEW_HOSTNAME=iros2018tablet
sudo bash -c "echo '$NEW_HOSTNAME' > /media/$USER/ROOTFS/etc/hostname"
sudo bash -c "echo -e '127.0.0.1\tlocalhost\n127.0.1.1\t$NEW_HOSTNAME' > /media/$USER/ROOTFS/etc/hosts"
```

Note: `sudo screen /dev/ttyACM0 115200`

## Step 5: 

The tablet's motherboard uses an RTL8703B chip (reporting on the SDIO bus as `0xb703`/8723CS). Mainline 6.6 does not include this driver. We must cross-compile the community rtw88 framework.

Compile the Driver: Clone the community repository inside the Docker container (outside the linux tree):

```bash
git clone https://github.com/lwfinger/rtw88.git
cd rtw88
```

(Inside the container, note the expected `../linux` from before) Cross-compile it against your newly built 6.6 kernel:

```bash
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- -C ../linux M=$(pwd) modules
```

Install the Modules: Mount the ROOTFS partition on the host.

Create the kernel modules directory (e.g., /lib/modules/6.6.0-dirty/) and copy all .ko files from the rtw88 folder into it.

Wi-Fi Firmware Injection & Activation

The driver requires proprietary binary blobs from Realtek to initialize the radio.

Download Firmware: Download the main firmware and the Wake-on-WLAN firmware directly from the Linux firmware repository:

`rtw8703b_fw.bin`
`rtw8703b_wow_fw.bin`

Inject Firmware:

Create the target directory on the SD card: `/mnt/ROOTFS/lib/firmware/rtw88/`

Copy both .bin files into that directory.

Activate (On the Tablet via USB Shell):

Rebuild the module map: `depmod -a`

Load the SDIO core and specific chip driver:

```bash
modprobe rtw_sdio
modprobe rtw_8723cs
```

Verify the interface exists using ip a (look for wlan0).

Connect to Network: Enable radio and connect via NetworkManager:

```bash
nmcli radio wifi on
nmcli dev wifi connect "YOUR_SSID" password "YOUR_PASSWORD"
```