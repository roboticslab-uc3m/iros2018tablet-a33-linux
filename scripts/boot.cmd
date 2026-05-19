echo "Loading Kernel (Dynamic PARTUUID)..."
setenv bootargs console=tty1 root=PARTUUID=95d7ac2c-02 rw rootwait panic=10 loglevel=3
load mmc 0:1 0x42000000 zImage
load mmc 0:1 0x43000000 sun8i-a33-q8-tablet.dtb
bootz 0x42000000 - 0x43000000
