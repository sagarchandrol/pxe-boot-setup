# Configuring PXE boot server for legacy BIOS (syslinux/RHEL8)
- When client virtual machine is powered on, it's NIC executes the PXE ROM to broadcast for a DHCP server.  
- It obtains IP address and instructions to pull the core bootloader `pxelinux.0` over TFTP.  
- After loading the core bootloader and menu config, it queries for **kernel** `vmlinuz` and **initial RAM Disk** `initrd.img` over TFTP.  
- The hardware switches from NIC ROM to linux kernel and the kernel mounts `initrd.img` as a temporary in-memory file system.  
- The system downloads  SquashFS runtime `install.img` over HTTP and mounts it as temporary root filesystem (/)  
- The installer runtime contains **Anaconda** which parses the kickstarter file `ks.cfg` and installs OS packages onto the targeted disk.



## Prerequisites and Environment  
Before configuring the services, please ensure the following packages and resources are available on the server host/VM  
- **Network & Installation Services**
  - `dhcp server` (`dhcpd`): To lease IP address and deliver PXE boot options (Next Server & Filename)
  - `tftp-server`: To host initial bootloader, modules and kernel binaries
  - `httpd` (Apache): To server the kickstart configuration and OS repositories  
```
# Install them using
sudo dnf install httpd tftp dhcp-server
```

- **Bootloader Files (syslinux packages)**
  - Core Bootloader: `pxelinux.0`
  - syslinux modules: `menu.c32`, `ldlinux.c32`, `libcom32.c32`, `libutil.c32`  

```
# Install `syslinux` package to get bootloader and modules
sudo dnf install syslinux syslinux-tftpboot
```

- **Operating System Media**
  - RHEL 8 DVD ISO mounted to provide (`vmlinuz`, `initrd.img` and package repositories)



### Step 1: Server base configuration (IP & Firewall)


NOTE: The network device name for the server is `enp1s0`  
Provide static IP to the server
```
sudo nmcli connection modify enp1s0 ipv4.method manual ipv4.addresses 192.168.10.1/24
```


Open firewall ports for DHCP service, TFTP service and HTTP service
```
sudo firewall-cmd --add-service=http --add-service=tftp --add-service=dhcp --permanent
sudo firewall-cmd --reload
```


### Step 2: DHCP service configuration  
copy or move `menu.c32`, `ldlinux.c32`, `libcom32.c32`, `libutil.c32`, `pxelinux.0` from `/tftpboot/` to the tftp server's root directory `/var/lib/tftpboot/`   
```
sudo cp /tftpboot/{menu.c32,ldlinux.c32,libcom32.c32,libutil.c32,pxelinux.0} /var/lib/tftpboot/
```

Edit the dhcp configuration file at `/etc/dhcp/dhcpd.conf`
```
sudo $EDITOR /etc/dhcp/dhcpd.conf
```
Add the following lines for a minimal PXE boot setup
```
subnet 192.168.10.0 netmask 255.255.255.0 {
       range 192.168.10.2 192.168.10.10;
       option routers 192.168.10.1;
       option domain-name-servers 192.168.10.1;

# address of the tftp server
       next-server 192.168.10.1;
# add the filepath of pxelinux.0 relative to the tftp root directory
       filename "pxelinux.0"
}
```


### Step 3: TFTP Service & Bootloader Setup
Mount the RHEL 8 DVD ISO to any path and copy `vmlinuz` & `initrd.img`  
Note: The mount point for RHEL 8 DVD ISO on my system is `/mnt/iso/`
```
sudo mkdir /var/lib/tftpboot/rhel8
sudo cp /mnt/iso/images/pxeboot/{vmlinuz,initrd.img} /var/lib/tftpboot/rhel8
```
Create and edit the pxelinux config file named `default` inside the `pxelinux.cfg` directory
Make sure the `pxelinux.cfg` directory is in the same path as the pxelinux.0 and modules
```
sudo mkdir /var/lib/tftpboot/pxelinux.cfg
sudo touch /var/lib/tftpboot/pxelinux.cfg/default
sudo chmod -R 755 /var/lib/tftpboot
sudo $EDITOR /var/lib/tftpboot/pxelinux.cfg/default
```


```
DEFAULT menu.c32
TIMEOUT 100
ONTIMEOUT local
LABEL rhel8-auto
      MENU LABEL Install RHEL8 (kickstart)
      KERNEL rhel8/vmlinuz
      INITRD rhel8/initrd.img
      APPEND inst.ks=http://192.168.10.1/ks.cfg inst.repo=http://192.168.10.1/rhel8/
LABEL local
      MENU LABEL Boot from Local Disk
      MENU DEFAULT
      LOCALBOOT 0
```


### Step 4: HTTP service & Repositories (Anaconda/kickstart)
Copy the `AppStream`, `BaseOS`, `images`, `.discinfo`, `RPM-GPG-KEY-redhat-beta`, `RPM-GPG-KEY-redhat-release`, `.treeinfo` from the mount point to the http root directory
```
sudo mkdir /var/www/html/rhel8/
sudo cp -r /mnt/iso/{AppStream,BaseOS,images,\.discinfo,RPM-GPG-KEY-redhat-beta,RPM-GPG-KEY-redhat-release,\.treeinfo} /var/www/html/rhel8/
```
Now the Repositories are in place, generate encrypted password for root user and normal users  
Else use --plaintext in kickstart file
```
sudo touch /var/www/html/ks.cfg
sudo chmod -R 755 /var/www/html/
openssl passwd -6 "rootpasswd/userpasswd"
sudo $EDITOR /var/www/html/ks.cfg
```  
Add **keyboard layout**, **Timezone**,**system language**, **packages**, **username** & **password** to suit your environment. The values provided here are for reference and can be customized as needed  
```
# Kickstart File
text
keyboard --xlayouts='us'
lang en_US.UTF-8
timezone Asia/Kolkata --utc
network --bootproto=DHCP --device=link --activate
zerombr
clearpart --initlabel --all
autopart
%packages --ignoremissing
@^graphical-server-environment
@core
@standard
%end
rootpw --iscrypted $6$P2drDZlO4slqBm3g$HlLll23iMK4dawwQPPqbXzA/mo4fuyFtlcqc0IFbmfQFPfER07tKQyg2bIuJM.KuvWIU.Kk3/wrepl1VCJTy6.
user --name='username' --group='wheel' --iscrypted --password=$6$6zTXC2TxLaUwGshK$T2OJZYLJ3kFjYx2Hscc5I7/bSJIRfYFg0SaHv2f.6h7Z40/D5XonCm57sOdvPjbqbNogHq8nunsdh3wJ/O95o0
%post
systemctl set-default graphical.target
%end
poweroff
```


### Test the PXE boot
**Start and enable DHCP, TFTP and HTTP services**  
```
sudo systemctl enable --now httpd tftp dhcpd
systemctl status httpd tftp dhcpd
```  
With DHCP, TFTP and HTTP services configured and running, start the client virtual machine. Ensure its boot order is set to network boot (PXE) and it will automatically acquire IP address, load boot menu and begin unattended installation