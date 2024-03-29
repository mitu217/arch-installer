#!/bin/bash

# see http://redsymbol.net/articles/unofficial-bash-strict-mode/
# To silent an error || true
set -euo pipefail
IFS=$'\n\t'

if [ "${1:-}" = "--verbose" ] || [ "${1:-}" = "-v" ]; then
	set -x
fi

# defaults
NEW_HOSTNAME=${NEW_HOSTNAME:-arch}
NEW_USERNAME=${NEW_USERNAME:-guest}

#----------------------
# Setup Mirrors
#----------------------
mv /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak 
cat <<EOF > /etc/pacman.d/mirrorlist
##
## Arch Linux repository mirrorlist
##
## Japan
Server = https://ftp.jaist.ac.jp/pub/Linux/ArchLinux/\$repo/os/\$arch
Server = https://jpn.mirror.pkgbuild.com/\$repo/os/\$arch
Server = https://mirrors.cat.net/archlinux/\$repo/os/\$arch
EOF

#----------------------
# Install BaseSystem
#----------------------
pacstrap -i /mnt base base-devel net-tools wireless_tools wpa_supplicant grub efibootmgr sudo openssh git
genfstab -U -p /mnt >> /mnt/etc/fstab

#----------------------
# Workaround
#----------------------
# Workaround
# https://bugs.archlinux.org/task/61040
# https://bbs.archlinux.org/viewtopic.php?pid=1820949
mkdir /mnt/hostlvm
mount --bind /run/lvm /mnt/hostlvm

# Base configuration tasks
cat <<EOF > /mnt/root/base_configuration_tasks.sh
set -eux

passwd

export LANG=en_US.UTF-8
echo \$LANG UTF-8 >> /etc/locale.gen
echo LANG=\$LANG > /etc/locale.conf
locale-gen

rm -rf /etc/localtime
ln -s /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
hwclock --systohc --utc

echo $NEW_HOSTNAME > /etc/hostname
systemctl enable dhcpcd.service

sed -i 's/^HOOKS=.*/HOOKS="base udev autodetect modconf block keyboard encrypt lvm2 resume filesystems fsck"/' /etc/mkinitcpio.conf
mkinitcpio -p linux

dd bs=512 count=8 if=/dev/urandom of=/crypto_keyfile.bin
cryptsetup luksAddKey /dev/sda2 /crypto_keyfile.bin
chmod 000 /crypto_keyfile.bin
echo "cryptboot /dev/sda2 /crypto_keyfile.bin luks" >> /etc/crypttab

# Workaround
# https://bugs.archlinux.org/task/61040
# https://bbs.archlinux.org/viewtopic.php?pid=1820949
ln -s /hostlvm /run/lvm

echo GRUB_ENABLE_CRYPTODISK=y >> /etc/default/grub
ROOTUUID=\$(blkid /dev/sda3 | awk '{print \$2}' | cut -d '"' -f2)
sed -i "s/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX=\"cryptdevice=UUID="\$ROOTUUID":lvm:allow-discards root=\/dev\/mapper\/arch-root resume=\/dev\/mapper\/arch-swap\"/" /etc/default/grub
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=grub --recheck
grub-mkconfig -o /boot/grub/grub.cfg
chmod -R g-rwx,o-rwx /boot

# for VirtualBox
mkdir -p /boot/efi/EFI/boot
cp /boot/efi/EFI/grub/grubx64.efi /boot/efi/EFI/boot/bootx64.efi

groupadd admin
useradd -U -m \
        -G admin \
        -s /bin/bash \
        $NEW_USERNAME
passwd $NEW_USERNAME
echo '%admin ALL=(ALL) ALL' > /etc/sudoers.d/admin
EOF
chmod +x /mnt/root/base_configuration_tasks.sh
arch-chroot /mnt /root/base_configuration_tasks.sh
rm -rf /mnt/tmp/base_configuration_tasks.sh

umount /mnt/hostlvm
rm -r /mnt/hostlvm

umount -R /mnt
