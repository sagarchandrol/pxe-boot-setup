#!/usr/bin/env bash

dest="$HOME/pxe-boot-setup"
dhcpsr="/etc/dhcp/dhcpd.conf"
httpRoot="/var/www/html"
httpks="$httpRoot/BIOS/ks.cfg"
httpwim="$httpRoot/UEFI/boot.ipxe"
sambaconfig="/etc/samba/smb.conf"
tftpRoot="/var/lib/tftpboot/BIOS/pxelinux.cfg/default"

if [[ -f "$dhcpsr" && -f "$httpks" && -f "$httpwim" && -f "$sambaconfig" && -f "$tftpRoot" ]]; then
   cp "$dhcpsr" "$dest"/configs/dhcp
   cp "$httpks" "$dest"/configs/http/RHEL/ks-post-login_script.cfg
   cp "$httpwim" "$dest"/configs/http/Windows/boot.ipxe
   cp "$sambaconfig" "$dest"/configs/samba/smb.conf
   cp "$tftpRoot" "$dest"/configs/tftp/RHEL/pxelinux.cfg
fi
