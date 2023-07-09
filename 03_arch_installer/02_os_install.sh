#!/bin/bash
set -e
source config.sh
source print.sh

print_banner "OS Installation (3/4)"
print_text "This section will guide you through the OS installation."

# load configs
check_conf_file
source ./config.gen.sh
check_vars



#######################################################################
######## BOOT FROM INSTALLATION MEDIUM ################################
#######################################################################
print_header_section "Preliminary operations"

### check we have booted in UEFI mode
print_checklist_item "checking correct UEFI boot"
if [ -z "$(ls -A /sys/firmware/efi/efivars)" ]; then
    echo "Empty '/sys/firmware/efi/efivars'"
    exit 1
fi

### set keyboard layout
print_checklist_item "setting IT keyboard layout"
print_text "Setting /usr/share/kbd/keymaps/i386/qwerty/it layout"
set -x
find /usr/share/kbd/keymaps -type f -name "*.map.gz" | grep it
loadkeys /usr/share/kbd/keymaps/i386/qwerty/it
set +x

### connect to internet using non-interactive CLI
print_checklist_item "connecting via wifi device"
set -x
iwctl device list
iwctl station "$WIFI_DEVICE" scan
iwctl station "$WIFI_DEVICE" get-networks
iwctl --passphrase "$WIFI_PASSPHRASE" station "$WIFI_DEVICE" connect "$WIFI_SSID"
set +x

print_text "Waiting for connection.. (5 secs)"
set -x
sleep 5
ping -c 5 -w 10 8.8.8.8
set +x

### sync the machine clock using the NTP time protocol
print_checklist_item "sync time (NTP)"
set -x
timedatectl set-ntp true
set +x

### remount partitions
print_checklist_item "remounting partitions (if needed)"
set -x
if ! mountpoint -d /mnt; then mount --mkdir "$DISK_PART_ROOT_DEV_FILE" /mnt; fi
if ! mountpoint -d /mnt/boot; then mount --mkdir "$DISK_PART_EFI_DEV_FILE" /mnt/boot; fi
if ! swapon -s | grep "$DISK_PART_SWAP_DEV_FILE"; then swapon "$DISK_PART_SWAP_DEV_FILE" || true; fi
set +x

prompt_continue "Continue?"

#######################################################################
######## OS INSTALLATION ##############################################
#######################################################################
print_header_section "OS Installation"

### optimize downloads
print_checklist_item "setting mirrors"
set -x
reflector \
  --download-timeout 60 \
  --country 'Italy' \
  --age 48 \
  --latest 20 \
  --protocol https \
  --sort rate \
  --save /etc/pacman.d/mirrorlist
set +x

### install linux + basic packages
print_checklist_item "installing basic packages"
set -x
sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
pacman --noconfirm -Sy
pacstrap /mnt \
    linux \
    linux-firmware \
    base \
    sudo \
    networkmanager \
    gcc \
    git \
    make \
    docker \
    vim \
    curl
sed -i 's/^#ParallelDownloads/ParallelDownloads/' /mnt/etc/pacman.conf
set +x

### persist mounts
print_checklist_item "persist mounts with genfstab"
set -x
genfstab -U /mnt >> /mnt/etc/fstab
set +x

prompt_continue "Continue?"

### chroot into ROOT partition (where OS will be installed)
print_checklist_item "copying scripts into ROOT partition"
set -x
cp -R "$(pwd)/../.." /mnt/root/arch-installer
set +x

print_text "Copied to '/mnt/root/arch-installer'"
print_text "Folder contents ('/mnt/root/arch-installer'):
\n$(ls -alh /mnt/root/arch-installer)"

prompt_continue "Continue?"

arch-chroot /mnt/ /bin/bash -c "
  cd /mnt/root/arch-installer/03_arch_installer
  ./02_os_install_chroot.sh
"

print_text "Cleaning"
set -x
rm -rf /mnt/root/arch-installer
set +x