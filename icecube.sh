#### INIT 
sudo apt-get install debootstrap squashfs-tools xorriso grub-pc-bin grub-efi-amd64-bin mtools
mkdir $HOME/LIVE_BOOT
#### INIT

#### CREATE THE BASE SYSTEM 
sudo debootstrap --arch=amd64 --variant=minbase stretch $HOME/LIVE_BOOT/chroot http://ftp.us.debian.org/debian/

# this section needs to be executed within chroot
# this is the place to tweak to add/remove packages from the base system
sudo chroot "$HOME/LIVE_BOOT/chroot" bash << 'EOF'
printf 'icecube\n' > /etc/hostname

export DEBIAN_FRONTEND=noninteractive
apt-get update &&
apt-get install --no-install-recommends -y \
    linux-image-amd64 live-boot systemd-sysv blackbox xserver-xorg-core \
    xserver-xorg xinit xterm # vim qrencode zbar-tools &&

apt-get clean
# FIXME Make Xorg start automatically and remove this bit 
echo "root:icecube" | chpasswd
EOF



mkdir -p $HOME/LIVE_BOOT/{scratch,image/live}

sudo mksquashfs $HOME/LIVE_BOOT/chroot $HOME/LIVE_BOOT/image/live/filesystem.squashfs -e boot

### SETUP THE BOOTLOADER
cp $HOME/LIVE_BOOT/chroot/boot/vmlinuz-* $HOME/LIVE_BOOT/image/vmlinuz  
cp $HOME/LIVE_BOOT/chroot/boot/initrd.img-* $HOME/LIVE_BOOT/image/initrd

cat <<'EOF' >$HOME/LIVE_BOOT/scratch/grub.cfg

search --set=root --file /DEBIAN_CUSTOM

insmod all_video

set default="0"
set timeout=0

menuentry "icecube" {
    linux /vmlinuz boot=live quiet nomodeset
    initrd /initrd
}
EOF
touch $HOME/LIVE_BOOT/image/DEBIAN_CUSTOM

#### MAKE BOOTABLE USB

# FIXME Make this a command line argument
export disk=/dev/sda

sudo mkdir -p /mnt/{usb,efi}
sudo parted --script $disk \
    mklabel gpt \
    mkpart primary fat32 2048s 4095s \
        name 1 BIOS \
        set 1 bios_grub on \
    mkpart ESP fat32 4096s 413695s \
        name 2 EFI \
        set 2 esp on \
    mkpart primary fat32 413696s 100% \
        name 3 LINUX \
        set 3 msftdata on

sudo gdisk $disk << EOF
r     # recovery and transformation options
h     # make hybrid MBR
1 2 3 # partition numbers for hybrid MBR
N     # do not place EFI GPT (0xEE) partition first in MBR
EF    # MBR hex code
N     # do not set bootable flag
EF    # MBR hex code
N     # do not set bootable flag
83    # MBR hex code
Y     # set the bootable flag
x     # extra functionality menu
h     # recompute CHS values in protective/hybrid MBR
w     # write table to disk and exit
Y     # confirm changes
EOF

sudo mkfs.vfat -F32 ${disk}2 && \
sudo mkfs.vfat -F32 ${disk}3

sudo mount ${disk}2 /mnt/efi && \
sudo mount ${disk}3 /mnt/usb

sudo grub-install --force \
    --target=x86_64-efi \
    --efi-directory=/mnt/efi \
    --boot-directory=/mnt/usb/boot \
    --removable \
    --recheck

sudo grub-install --force \
    --target=i386-pc \
    --boot-directory=/mnt/usb/boot \
    --recheck \
    $disk

sudo mkdir -p /mnt/usb/{boot/grub,live}

sudo cp -r $HOME/LIVE_BOOT/image/* /mnt/usb/

sudo cp \
    $HOME/LIVE_BOOT/scratch/grub.cfg \
    /mnt/usb/boot/grub/grub.cfg

sudo umount /mnt/{usb,efi}

