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

# The USB Subsystem (Shared for both modes)
./scripts/config --enable CONFIG_USB
./scripts/config --enable CONFIG_USB_SUPPORT
./scripts/config --enable CONFIG_USB_MUSB_SUNXI      # Allwinner USB PHY
./scripts/config --enable CONFIG_USB_MUSB_HDRC
./scripts/config --disable CONFIG_USB_MUSB_DUAL_ROLE # 1. Aggressively kill the conflicting USB modes

# The USB Subsystem (Host Mode for Android Auto)
#./scripts/config --enable CONFIG_USB_MUSB_HOST       # Force it to be the "Boss"

# The USB Subsystem (Gadget Mode for Serial Console)
./scripts/config --disable CONFIG_USB_MUSB_HOST # 1. Aggressively kill the conflicting USB modes
./scripts/config --enable CONFIG_USB_MUSB_GADGET
./scripts/config --enable CONFIG_USB_GADGET
./scripts/config --enable CONFIG_USB_G_SERIAL   # Building CONFIG_USB_G_SERIAL as a module (--module) rather than baking it in (--enable) is generally safer for systemd, as it allows the root filesystem to fully mount before the USB serial port initializes.) -> # 3. Bake the Serial Gadget directly into the kernel (No module loading needed!)

# The Wi-Fi (Realtek SDIO)
./scripts/config --enable CONFIG_WLAN
./scripts/config --module CONFIG_CFG80211
./scripts/config --module CONFIG_MAC80211
./scripts/config --enable CONFIG_WLAN_VENDOR_REALTEK
./scripts/config --module CONFIG_RTW88
./scripts/config --module CONFIG_RTW88_CORE
./scripts/config --module CONFIG_RTW88_SDIO
./scripts/config --module CONFIG_RTW88_8723CS

# Apply config
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- olddefconfig
```

(Inside the container) Compile the Kernel and Device Trees (this will take a few minutes)

```bash
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- -j$(nproc) zImage modules dtbs
```

Exit the container and copy the generated core files to your microSD (adapt paths depending on your setup, e.g. `/media/$USER/BOOT` may be `/mnt/BOOT`)

```bash
cp arch/arm/boot/zImage /media/$USER/BOOT/
cp arch/arm/boot/dts/allwinner/sun8i-a33-q8-tablet.dtb /media/$USER/BOOT/
```

If you boot from this microSD card, you should reach Das U-Boot message ""Starting kernel ..."!

To force USB gadget, Create the symlink to force systemd to spawn a login prompt on the USB gadget port (looks strange, but equivalent to `sudo chroot /media/$USER/ROOTFS; systemctl enable serial-getty@ttyGS0.service; exit`):

```bash
sudo ln -s /lib/systemd/system/serial-getty@.service /media/$USER/ROOTFS/etc/systemd/system/getty.target.wants/serial-getty@ttyGS0.service
```

Check via `echo "ttyGS0" | sudo tee -a /media/$USER/ROOTFS/etc/securetty`.

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

## Step 5: Wifi

The tablet's motherboard uses an RTL8703B chip (reporting on the SDIO bus as `0xb703`/8723CS). Mainline 6.6 does not include this driver. We must cross-compile the community rtw88 framework.

```bash
git clone https://github.com/lwfinger/rtw88.git
```

(in container)

```bash
cd linux
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- -j$(nproc) zImage modules dtbs
cd ../rtw88
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- -C ../linux M=$(pwd) modules
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- -C ../linux M=$(pwd) INSTALL_MOD_PATH=./_export modules_install
```

Install the Modules and Firmware

After a successful build, use the kernel's built-in installation script to route the modules and generate the dependency lists directly on the SD card. The 8723CS chip shares RF silicon with the 8703B, so it explicitly requires the rtw8703b_fw.bin firmware blob to operate.

```bash
sudo cp -r ./linux/_export/lib/modules/6.6.0-dirty/updates /media/$USER/ROOTFS/lib/modules/6.6.0-dirty/
sudo depmod -a -b /media/$USER/ROOTFS 6.6.0-dirty
sync
```

Verify rtw8703b_fw.bin is physically present in `/media/$USER/ROOTFS/lib/firmware/rtw88/`.

Activate (On the Tablet via USB Shell):

Rebuild the module map: `depmod -a`

Load the SDIO core and specific chip driver:

```bash
modprobe rtw_sdio
modprobe rtw_8723cs
```

Verify the interface exists using `ip a` (look for `wlan0`).

Before these work, we need to install stuff:

Connect to Network: Enable radio and connect via NetworkManager:

```bash
nmcli radio wifi on
nmcli dev wifi connect "YOUR_SSID" password "YOUR_PASSWORD"
```

## Step 6: Install stuff

Ensure the NetworkManager config directory exists on the SD card

```bash
sudo mkdir -p /media/$USER/ROOTFS/etc/NetworkManager/system-connections/
```

Write the connection profile directly to the SD card

```bash
sudo tee /media/$USER/ROOTFS/etc/NetworkManager/system-connections/HomeWiFi.nmconnection > /dev/null <<EOF
[connection]
id=HomeWiFi
type=wifi
interface-name=wlan0

[wifi]
ssid=YOUR_WIFI_NAME
mode=infrastructure

[wifi-security]
key-mgmt=wpa-psk
psk=YOUR_WIFI_PASSWORD

[ipv4]
method=auto

[ipv6]
method=ignore
EOF
```

CRITICAL: NetworkManager will completely ignore this file if the permissions aren't locked down!

```bash
sudo chmod 600 /media/$USER/ROOTFS/etc/NetworkManager/system-connections/HomeWiFi.nmconnection
```

Because your host PC is x86 (Intel/AMD) and the tablet's Debian filesystem is ARM, a standard chroot will immediately crash with an "Exec format error." You have to inject an emulator into the SD card first (`qemu-user-static` we installed before).

```bash
# 1. Prep the Emulator and Mounts (Host PC)
sudo cp /usr/bin/qemu-arm-static /media/$USER/ROOTFS/usr/bin/
sudo mount --bind /dev /media/$USER/ROOTFS/dev
sudo mount --bind /sys /media/$USER/ROOTFS/sys
sudo mount --bind /proc /media/$USER/ROOTFS/proc
sudo mount --bind /etc/resolv.conf /media/$USER/ROOTFS/etc/resolv.conf

# 2. Enter the Matrix
sudo chroot /media/$USER/ROOTFS

# --- INSIDE CHROOT ---
apt update

# Fix Locales
apt install locales
sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# Install Networking
apt install network-manager wpasupplicant iptables

# Install and Enable SSH
apt install openssh-server
systemctl enable ssh
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

# Leave the Matrix
exit
# ---------------------

# 3. Clean up Mounts (Host PC)
sudo umount /media/$USER/ROOTFS/dev
sudo umount /media/$USER/ROOTFS/sys
sudo umount /media/$USER/ROOTFS/proc
sudo umount /media/$USER/ROOTFS/etc/resolv.conf
```

Note `nmtui` as ASCII-art Wi-Fi menu.
