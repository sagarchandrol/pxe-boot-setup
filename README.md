## Roadmap & Features
- [x] Legacy BIOS network boot (pxelinux)
- [] Automated RHEL installation via kickstart (ks.cfg)
- [] DHCP option 93/60 autodetection (legacy BIOS vs UEFI)
- [] UEFI boot over network (bootx64.efi / GRUB2)
- [] Samba integration for windows automated installation

setting/creating a virtual bridge(switch) in QEMU using virsh
**create a custom file pxe-net.xml with minimal settings**
add lines
'''xml
<network>
  <name>PXE-net</name>
  <bridge name='PXEbr0' stp='on' delay='0'/>
</network>
'''
**go to virsh interactive mode or enter lines with virsh in terminal**
virsh -c qemu:///system net-list --all
virsh
net-define /path/to/pxe-net.xml
net-start PXE-net
net-autostart PXE-net
**check whether the network has been added or not**
ip link show pxebr0
# add the bridge to the domains or vm
virsh edit <domain name>
*find the <interactive type='user'> section*
edit <interactive type='user'> to  <interactive type='bridge'>
add source as bridge <source bridge='PXEbr0'/>
add these lines so that the vms can connect to internet using NAT
<interface type='user'>
  <model type='virtio'/>
</interface>
no there are two interfaces connected to server vm one virtual switch named PXEbr0 and default network (NAT)
# allow virtual bridge by adding a bridge.conf file
echo "allow PXEbr0" | sudo tee /etc/qemu/bridge.conf
# add SUID to owner /usr/lib/qemu/qemu-bridge-helper
sudo chmod u+s /usr/lib/qemu/qemu-bridge-helper

# setup pxe-server
*launch pxe server vm*
setup static ip to server ep1s0 the interface connected to virtual bridge
nmcli connection modify ep1s0 ipv4.method manual ipv4.address 192.168.50.1/24
install tftp-server, dhcp-server, httpd
install syslinux, syslinux-tftpboot
copy files from /usr/share/syslinux to /var/lib/
pxelinux.0, libutil.c32, ldlinux.c32, libcom32.c32, menu.c32
**files info**
pxelinux.0 - The Bootloader Binary. This is the core PXE program. When the client computer boots over the network card, TFTP sends pxelinux.0 into the client's RAM. It acts like GRUB for network booting.
menu.c32 - The Menu UI Module. This creates the text/graphical boot menu on the client's screen (allowing you to select OS options or hit Enter to boot).
ldlinux.c32  - Syslinux Core Library. Required background code for Syslinux modules to run.
libcom32.c32 - COM32 Library. Provides 32-bit helper routines used by menu.c32.
libutil.c32  - Utility Library. Provides string handling, memory functions, and menu rendering code for menu.c32.
vmlinuz - the compressed files of linux kernel(vmlinux)
initramfs - The temporary filesystem containing network drivers (nfs, network interface drivers) so the kernel can connect to your server before mounting /.
