# DOCUMENT ME
BITCOINCORE_FINGERPRINT="01EA5486DE18A882D4C2684590C8019E36C2E964"
GLACIER_FINGERPRINT="E1AAEBB7AC90C1FE80F010349D1B7F534B43EAB0"

BITCOINCORE_SHASUMS_URL="https://bitcoincore.org/bin/bitcoin-core-0.17.0.1/SHA256SUMS.asc"
BITCOINCORE_DOWNLOAD_URL="https://bitcoincore.org/bin/bitcoin-core-0.17.0.1/bitcoin-0.17.0.1-x86_64-linux-gnu.tar.gz"

GLACIER_SHASUMS_URL="https://keybase.io/glacierprotocol/pgp_keys.asc?fingerprint=e1aaebb7ac90c1fe80f010349d1b7f534b43eab0"
GLACIER_DOWNLOAD_URL="https://github.com/GlacierProtocol/GlacierProtocol/archive/v0.93-beta.tar.gz"

DISK=$1

function init_environment() {
# Required for running in the bootable ubuntu usb  

    add-apt-repository universe

    apt-get --assume-yes install debootstrap squashfs-tools xorriso grub-pc-bin grub-efi-amd64-bin mtools
    
    mkdir $HOME/LIVE_BOOT

}

function create_base_system() {
    debootstrap --arch=amd64 --variant=minbase stretch $HOME/LIVE_BOOT/chroot http://ftp.us.debian.org/debian/

    # this section needs to be executed within chroot
    # this is a place to tweak to add/remove packages from the base system
    # NOTE. We will need to add python to make glacier work
    chroot "$HOME/LIVE_BOOT/chroot" bash <<-'EOF'
        
        export DEBIAN_FRONTEND=noninteractive
        apt-get update &&
        apt-get install --no-install-recommends -y \
            linux-image-amd64 live-boot systemd-sysv blackbox xserver-xorg-core \
            xserver-xorg xinit xterm # vim qrencode zbar-tools &&

        apt-get clean
        # TODO. Put this in a function that configures the system
        echo "root:icecube" | chpasswd
        printf 'icecube\n' > /etc/hostname
EOF

}

# Routine that safely downloads bitcoin core. 
# FIXME. It is crucial to audit this thorougly.
function install_bitcoincore() {
   
    wget $BITCOINCORE_DOWNLOAD_URL $BITCOINCORE_SHASUMS_URL 

    if ! sha256sum --ignore-missing --check SHA256SUMS.asc ; then
        print 'Something is awfully wrong with bitcoin core binaries. Aborting.\n'   
        exit
    fi   

    gpg --recv-keys $BITCOINCORE_FINGERPRINT 
    
    out=$(gpg --status-fd 1 --verify SHA256SUMS.asc 2>/dev/null)
    
    if ! (echo "$out" | grep "GOODSIG" && echo "$out" | grep "VALIDSIG $BITCOINCORE_FINGERPRINT") ; then
        echo "Checking integrity of Bitcoin core failed. Abort protocol"
        exit
    fi        
    # FIXME. Make sure its good to assume we can split in this way
    tar -xf  `basename $BITCOINCORE_DOWNLOAD_URL` -C $HOME/LIVE_BOOT/chroot
}

function install_glacier() {
   
    wget --output-document=glacier.tar.gz $GLACIER_DOWNLOAD_URL 
    wget --output-document=glacier.asc $GLACIER_SHASUMS_URL 
    gpg --import glacier.asc
    mkdir glacier &&  tar -xf "glacier.tar.gz" -C glacier --strip-components 1 && cd glacier
    out=$(gpg --status-fd 1 --verify SHA256SUMS.sig SHA256SUMS 2>/dev/null)
    
    if ! (echo "$out" | grep "GOODSIG" && echo "$out" | grep "VALIDSIG $GLACIER_FINGERPRINT") ; then
        echo "Checking integrity of Glacier failed. Abort protocol"
        exit
    fi

    cd .. 
    mv glacier $HOME/LIVE_BOOT/chroot/root
}

# TODO This function should remove all that is unneded on the live USB
function trim_installation() {
    :    
}

# TODO This function should configure the underlying OS. Speficially it should
#   1. Put bitcoind in the init script to be executed at runtime
#   2. Make X start automatically
#   3. Set the configurations so that a notepad, the glacier PDF and a terminal window are opened at boot
function configure_installation() {
    :
}

# This function is based on the excelent article from Will Haley, see https://willhaley.com/blog/custom-debian-live-environment/
function setup_bootable_USB() {

    mkdir -p $HOME/LIVE_BOOT/{scratch,image/live}

    mksquashfs $HOME/LIVE_BOOT/chroot $HOME/LIVE_BOOT/image/live/filesystem.squashfs -e boot

    cp $HOME/LIVE_BOOT/chroot/boot/vmlinuz-* $HOME/LIVE_BOOT/image/vmlinuz  
    cp $HOME/LIVE_BOOT/chroot/boot/initrd.img-* $HOME/LIVE_BOOT/image/initrd

    cat <<-'EOF' >$HOME/LIVE_BOOT/scratch/grub.cfg

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

#    dd if=/dev/zero of=$DISK bs=1k count=2048

    mkdir -p /mnt/{usb,efi}

    parted --script $DISK \
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

    gdisk $DISK <<-'EOF'
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

    mkfs.vfat -F32 ${DISK}2 && mkfs.vfat -F32 ${DISK}3

    mount ${DISK}2 /mnt/efi && mount ${DISK}3 /mnt/usb

    grub-install --force --target=x86_64-efi --efi-directory=/mnt/efi --boot-directory=/mnt/usb/boot --removable --recheck

    grub-install --force --target=i386-pc --boot-directory=/mnt/usb/boot --recheck $DISK

    mkdir -p /mnt/usb/{boot/grub,live}

    cp -r $HOME/LIVE_BOOT/image/* /mnt/usb/

    cp $HOME/LIVE_BOOT/scratch/grub.cfg /mnt/usb/boot/grub/grub.cfg

    umount /mnt/{usb,efi}
}

if [ "$#" -ne 1 ]; then
    echo "Usage: icecube.sh <PATH TO USB DEVICE>"
    exit
fi

if [ "$EUID" -ne 0 ]; then 
  echo "Please run the script as root."
  exit
fi

init_environment
create_base_system
install_glacier
install_bitcoincore
trim_installation 
configure_installation
setup_bootable_USB
