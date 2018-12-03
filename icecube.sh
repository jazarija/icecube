# DOCUMENT ME
BITCOINCORE_FINGERPRINT="01EA5486DE18A882D4C2684590C8019E36C2E964"
GLACIER_FINGERPRINT="E1AAEBB7AC90C1FE80F010349D1B7F534B43EAB0"


function init_environment() {

    sudo apt-get install debootstrap squashfs-tools xorriso grub-pc-bin grub-efi-amd64-bin mtools
    mkdir $HOME/LIVE_BOOT

}

function create_base_system() {
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
# FIXME try to indent that
EOF




}



# Routine that safely downloads bitcoin core. 
# FIXME. It is crucial to audit this thorougly.
function install_bitcoincore() {
   
    wget https://bitcoincore.org/bin/bitcoin-core-0.17.0.1/SHA256SUMS.asc
    wget https://bitcoincore.org/bin/bitcoin-core-0.17.0.1/bitcoin-0.17.0.1-x86_64-linux-gnu.tar.gz

    if ! sha256sum --ignore-missing --check SHA256SUMS.asc ; then
        print 'Something is awfully wrong. Aborting.\n'   
        exit
    fi   

    gpg --recv-keys $BITCOINCORE_FINGERPRINT 
    
    out=$(gpg --status-fd 1 --verify SHA256SUMS.asc 2>/dev/null)
    
    if ! (echo "$out" | grep "GOODSIG" && echo "$out" | grep "VALIDSIG $BITCOINCORE_FINGERPRINT") ; then
        echo "Checking integrity of Bitcoin core failed. Abort protocol"
        exit
    fi        
    tar -xf bitcoin-0.17.0.1-x86_64-linux-gnu.tar.gz -C $HOME/LIVE_BOOT/chroot
}

function install_glacier() {
   
    wget https://github.com/GlacierProtocol/GlacierProtocol/archive/v0.93-beta.tar.gz
    wget --output-document=glacier.asc  https://keybase.io/glacierprotocol/pgp_keys.asc?fingerprint=e1aaebb7ac90c1fe80f010349d1b7f534b43eab0 
    gpg --import glacier.asc
    mkdir glacier && tar -xf "v0.93-beta.tar.gz" -C glacier --strip-components 1 && cd glacier
    out=$(gpg --status-fd 1 --verify SHA256SUMS.sig SHA256SUMS 2>/dev/null)
    
    if ! (echo "$out" | grep "GOODSIG" && echo "$out" | grep "VALIDSIG $GLACIER_FINGERPRINT") ; then
        echo "Checking integrity of Glacier failed. Abort protocol"
        exit
    fi

    cd .. 
    mv glacier $HOME/LIVE_BOOT/chroot/root
}


### SETUP THE BOOTLOADER

#### MAKE BOOTABLE USB

function setup_bootable_USB() {
    mkdir -p $HOME/LIVE_BOOT/{scratch,image/live}

    sudo mksquashfs $HOME/LIVE_BOOT/chroot $HOME/LIVE_BOOT/image/live/filesystem.squashfs -e boot

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

    # FIXME Make this a command line argument
export disk=/dev/sda

#FIXME

# Maybe add sudo dd if=/dev/zero of=$disk bs=1k count=2048

#or, rather sudo mkfs.vfat /dev/sdZ


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

}


#init_environment
#create_base_system

install_glacier
install_bitcoincore
setup_bootable_USB
