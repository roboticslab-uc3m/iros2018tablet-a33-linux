echo "Loading Kernel (Read-Write Mode)..."
setenv bootargs console=tty1 root=/dev/mmcblk0p2 rw rootwait panic=10 maxcpus=1 ignore_loglevel
load mmc 0:1 0x42000000 zImage
load mmc 0:1 0x43000000 sun8i-a33-q8-tablet.dtb
bootz 0x42000000 - 0x43000000
