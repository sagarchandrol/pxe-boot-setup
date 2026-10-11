## Configuring PXE boot server for legacy BIOS (syslinux/RHEL8)
- When client virtual machine is powered on, its NICs executes the PXE ROM to broadcast for a DHCP server.  
- It obtains an IP address and instructions to pull the core bootloader `pxelinux.0` over TFTP.  
- After loading the core bootloader and menu config, it queries for **kernel** `vmlinuz` and **initial RAM Disk** `initrd.img` over TFTP.  
- The hardware switches from the NIC ROM to the Linux Kernel and the kernel mounts `initrd.img` as a temporary in-memory file system.  
- The system downloads the  SquashFS runtime `install.img` over HTTP and mounts it as temporary root filesystem (/)  
- The installer runtime contains **Anaconda** which parses the kickstart file `ks.cfg` and installs OS packages onto the targeted disk.


```
[ Client NIC ]
      │
      │ 1. DHCP DORA (UDP 67/68)
  DHCP Server (dhcpd)
  ── Assigns IP + "TFTP-Server IP address" & "Bootfile info"
      │
      │ 2. TFTP Fetch (UDP 69)
  TFTP Server (tftp-server)
  ── Sends raw bootloader (`pxelinux.0`), menu config (`default`)
     Linux Kernel (`vmlinuz`), and Initial RAM Disk (`initrd.img`)
      │
      │ 3. Memory Boot & Stage handoff
  Client RAM / Kernel space
  ── Hardware switches from NIC ROM to Linux Kernel (`vmlinuz`)
  ── Kernel mounts `initrd.img` as a temporary in-memory root filesystem
      │
      │ 4. HTTP Fetch (TCP 80)
  HTTP Server (Apache httpd)
  ── `initrd.img` scripts fetch `ks.cfg`, `install.img` (SquashFS runtime)
      Downloads `.rpm` packages onto disk.
```


## Prerequisites and Environment  
Before configuring the services, please ensure the following packages and resources are available on the server host/VM  
- **Network & Installation Services**
  - `dhcp-server` (`dhcpd`): To lease IP addresses and deliver PXE boot options (Next Server & Filename)
  - `tftp-server`: To host initial bootloader, modules and kernel binaries
  - `httpd` (Apache): To serve the kickstart configuration and OS repositories  
```
# Install them using
sudo dnf install httpd tftp dhcp-server
```

- **Bootloader Files (syslinux packages)**
  - Core Bootloader: `pxelinux.0`
  - syslinux modules: `menu.c32`, `ldlinux.c32`, `libcom32.c32`, `libutil.c32`  

```
# Install `syslinux` package to obtain bootloader and modules
sudo dnf install syslinux syslinux-tftpboot
```

- **Operating System Media**
  - RHEL 8 DVD ISO mounted to provide (`vmlinuz`, `initrd.img`...)



### Step 1: Server base configuration (IP & Firewall)
**Objective:**
- **Static IP**: *Network services (DHCP, TFTP, HTTP) cannot run on dynamic host IPs. PXE clients expect a permanent, unchanging target IP across host reboots*
- **Firewall Rules**: *By default `firewalld` drops unsolicited inbound traffic. We must open **DHCP**, **TFTP** and **HTTP** so that client machines and VMs can reach the server.*


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
**Objective:**
- **TFTP modules**: *We stage the syslinux network bootstrap program `pxelinux.0` along with its helper COM32 modules (`menu.c32`, `ldlinux.c32`, `libcom32.c32` and `libutil.c32`) in `/var/lib/tftpboot/` so that the client can display an interactive boot menu over TFTP*
- **DHCP Daemon**: *Allocate IP addresses to unconfigured clients and provide **Option 66** (`next-server` i.e. TFTP server) and **Option 67** (filename pointing to `pxelinux.0`)*


Copy or move `menu.c32`, `ldlinux.c32`, `libcom32.c32`, `libutil.c32`, `pxelinux.0` from `/tftpboot/` to the tftp server's root directory `/var/lib/tftpboot/`   
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
       filename "pxelinux.0";
}
```


### Step 3: TFTP Service & Bootloader Setup
**Objective:**
- **Bootloader Instructions (`default` menu)**: *Once `pxelinux.0` executes in client memory, it searches for configuration file inside `pxelinux.cfg` directory. The `default` menu defines the Kernel and initial RAM parameters (`APPEND`) and points the installer to the `inst.repo` package repositories and `inst.ks` kickstart file*
- **Safe FallBack (`LOCALBOOT 0`)**: *Sets the bootloader timeout to fallback to the internal Disk incase no manual choice is made preventing re-installation loops on existing machines*
- **Staging Kernel and Initramfs**: *Raw network boot ROMs cannot access ISO files or packages directly. We extract `vmlinuz` (Linux Kernel) and `initrd.img` (initial RAM disk) into TFTP directory `/var/lib/tftpboot/rhel8/` so that the client can pull and extract and execute minimal installer runtime into RAM*


mount the RHEL 8 DVD ISO to any path and copy `vmlinuz` & `initrd.img`  
Note: The mount point for RHEL 8 DVD ISO on my system is `/mnt/iso/`
```
sudo mkdir -p /mnt/iso
sudo mount -o loop /path/of/RHEL-8_DVD.iso /mnt/iso
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
**Objective:**
- **HTTP package staging**: *TFTP uses UDP which is impractical for large multi-gigabyte package trees. Copying the repositories files (`AppStream`, `BaseOS`, `.treeinfo`) to `/var/www/html/rhel8` allows anaconda to stream repositories packages over reliable, high-speed HTTP (TCP) connection*
- **Automated Answer File (`ks.cfg`)**: *Automated installation require predetermined answers for partitioning, timezone, language, package group, credentials etc. Staging `ks.cfg` in web root directory allows complete automated, hands-free installation*
- **Credential Security**: *Generating encrypted SHA-512 password hash via `openssl passwd -6` ensure the root password and user password are never stored or shared in plaintext*


Copy the `AppStream`, `BaseOS`, `images`, `.discinfo`, `RPM-GPG-KEY-redhat-beta`, `RPM-GPG-KEY-redhat-release`, `.treeinfo` from the mount point to the HTTP root directory
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
With DHCP, TFTP and HTTP services configured and running, start the client virtual machine. Ensure its boot order is set to network boot (PXE) and it will automatically acquire an IP address, load the boot menu and begin unattended installation