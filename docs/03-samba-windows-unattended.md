---
## UEFI Network Boot (PXE) Architecture & Setup for Windows 10



---
### Overview & Architecture
---
- When client machine is turned on, it's UEFI NIC ROM executes PXE over IPv4 to broadcast for a DHCP domain server
- It obtains IP address from the DHCP server and address of the TFTP server with the filename of bootloader/s
- After checking the vendor-class (PXEClient) and architecture-type (UEFI), The appropriate bootloader is downloaded over TFTP
- Bootloader `ipxe-x86_64.efi` is executed in memory and broadcasts a DHCP Request to the server
- IPXE downloads the `boot.ipxe` menu file over HTTP  which contains the **kernel** and **initiall RAM Disk** addresses
- Kernel `wimboot`, initial RAM Disk `BCD`, `boot.sdi`, `boot.wim` are loaded over HTTP
- `BCD` contains the boot menu entries, `boot.sdi` contains the binary to mount `boot.wim` which contains the filesystem in RAM
- **WinPE** i.e. kernel or minimal environment is booted in Ram Disk and the filesystem (boot.wim) is mounted as **X:** drive
- **X:** drive contains **winpeshl.ini** config file, This config file invokes `startnet.cmd` which initializes network card
- `startnet.cmd` contains instructions to connect to samba server and maps the samba root directory as **Z:** drive
- samba root directory i.e. `Z:` drive contains the extracted Windows ISO files (installer, binaries, sources and install.wim)
- `Z:\setup.exe` installer is executed with the `autounattend.xml` file for a automated windows installation



```
+----------------------------------------------------------------------------------+
|                             Network Boot Stages                                  |
+----------------------------------------------------------------------------------+
|                                                                                  |
|  [Client NIC]                                                                    |
|       |                                                                          |
|       |  1. DHCP Discover (UDP 67/68)                                            |
|       +---------------------------------> [DHCP Service]                         |
|       <---------------------------------+  Offers IP + TFTP server address       |
|       |                                                                          |
|       |  2. TFTP (UDP 69)                                                        |
|       +---------------------------------> [TFTP Service]                         |
|       <---------------------------------+  Transfers ipxe-x86_64.efi             |
|       |                                                                          |
|       |  3. DHCP Request (iPXE User-Class)                                       |
|       +---------------------------------> [DHCP Service]                         |
|       <---------------------------------+  Offers HTTP boot.ipxe URI             |
|       |                                                                          |
|       |  4. HTTP (TCP 80)                                                        |
|       +---------------------------------> [HTTP Server]                          |
|       <---------------------------------+  Transfers wimboot, BCD,               |
|       |                                              boot.sdi, boot.wim          |
|       |                                                                          |
|       |  5. WinPE Boots in RAM (X:\)                                             |
|       |     - winpeshl.ini invokes startnet.cmd                                  |
|       |     - wpeinit initializes network card                                   |
|       |                                                                          |
|       |  6. SMB Mount & Setup                                                    |
|       +---------------------------------> [Samba (SMB) Server]                   |
|       <---------------------------------+  Mounts \\192.168.10.1\win10 as Z:\    |
|       |                                                                          |
|       |  7. Executes Z:\setup.exe (Full Windows Installation)                    |
|                                                                                  |
+----------------------------------------------------------------------------------+
```


---
## Prerequisites and Environment  

Before configuring the services, please ensure the following packages and resources are available on the server host/VM  
- **Network & Installation Services**
  - `dhcp-server` (`dhcpd`): To lease IP addresses and deliver PXE conditional boot options based on client Architecture (TFTP for raw UEFI, HTTP URI for IPXE)
  - `tftp-server`: To host initial UEFI bootloader (ipxe-x86_64.efi)
  - `httpd` (Apache): To serve `wimboot`, the WindowsPE ramdisk files (`BCD`, `boot.sdi`, `boot.wim`) and the `boot.ipxe` script
  - `samba` or `samba-client` (`smb`): To host the full windows installation tree (`setup.exe`, `install.wim` and repositories sources) over SMB (Server Message Block)
  - `wimblib-utils`: To inspect, modify and inject custom scripts into `boot.wim` on Linux without Windows tools
```
# Install them using
sudo dnf install epel-release
sudo dnf install httpd tftp dhcp-server samba wimlib-utils
```

- **Bootloader Files (`wimboot`, `iPXE`)**
  - Core Bootloader: `ipxe-x86_64.efi`
  - Windows PE Boot Helper: `wimboot`

```
# Download iPXE binary and wimboot executable
sudo mkdir -p /var/lib/tftpboot/win10 /var/www/html/win10
wget -O /var/lib/tftpboot/win10/ipxe-x86_64.efi https://www.boot.ipxe.org/x84_64-efi/ipxe.efi
wget -O /var/www/html/win10/wimboot https://www.github.com/ipxe/wimboot/releases/latest/download/wimboot
```

- **Operating System Media**
  - Windows 10 64-bit ISO mounted to extract full OS media and assets
  - Automated Answer File: `autounattend.xml` staged in samba share directory



---
### Step 1: Server base configuration (IP & Firewall)
---
**Objective:**
- **Static IP**: *Network services (DHCP, TFTP, HTTP, Samba) require a permanent, unchanging target IP across host reboots*
- **Firewall Rules**: *Open **DHCP**(67 UDP), **TFTP**(69 UDP), **HTTP**(TCP 80) and **Samba**(TCP 445, UDP 137-138) so that client machines and VMs can communicate with every staging phase


NOTE: The network device name for the server is `enp1s0`  
Provide static IP to the server
```
sudo nmcli connection modify enp1s0 ipv4.method manual ipv4.addresses 192.168.10.1/24
sudo nmcli connection up enp1s0
```


Open firewall ports for DHCP service, TFTP service and HTTP service
```
sudo firewall-cmd --add-service=http --add-service=tftp --add-service=dhcp --add-service=samba --permanent
sudo firewall-cmd --reload
```


---
### Step 2: DHCP service configuration  
---
**Objective:**
- **Two Stage DHCP handoff**: *A UEFI PXE client sends an initial discover request without user-class. DHCP sends Option 67 pointing to filename `ipxe-x86_64.efi` over TFTP. when iPXE runs, it queries DHCP again with user-class `iPXE`, allowing DHCP to redirect it to `boot.ipxe` over HTTP*


Edit the dhcp configuration file at `/etc/dhcp/dhcpd.conf`
```
sudo $EDITOR /etc/dhcp/dhcpd.conf
```


Add the following configuration
```
# creating a custom DHCP option definition of 16 bits (2 bytes) whole integer
# we can use this later to identify the architecture type of client (BIOS/UEFI)
option architecture-type code 93 = unsigned integer 16;
class "PXEClient" {
# match option 60 class ID signify the platform of the client (pxeclient/android...)
# length of PXEClient is 9 characters, hence (0, 9)
      match if substring (option vendor-class-identifier, 0, 9) = "PXEClient";
# second handoff, triggers after ipxe-x86_64.efi has been passed
# ipxe queries for configuration file with option 77
# DHCP provides the address for boot.ipxe
      if exists user-class and option user-class = "iPXE" {
      filename "http://192.168.10.1/win10/boot.ipxe";
      }
# option 93 architecture-type usage
# 00:07 and 00:09 for x86_64 efi
      else if option architecture-type = 00:07 or option architecture-type = 00:09 {
      filename "win10/ipxe-x86_64.efi";
      }
      else {
# rest of the architecture-type in 93 is assumed to be BIOS
      filename "pxelinux.0";
      }
}
subnet 192.168.10.0 netmask 255.255.255.0 {
       range 192.168.10.2 192.168.10.50;
       option routers 192.168.10.1;
       option domain-name-servers 192.168.10.1;
# next-server (TFTP server) IP address
       next-server 192.168.10.1;
}
```


---
### Step 3: HTTP & WinPE image staging
---
**Objective:**
- **Extract Boot Files**: *Windows boot binaries (`BCD`, `boot.sdi`, `boot.wim`) are extracted from Windows ISO and hosted on HTTP*  
- **Inject Network Mount Script (`startnet.cmd`)**: *Windows PE booted over RAM does not know where installation media lives. Injecting a `winpeshl.ini` config file and `startnet.cmd` command script into index 2 of `boot.wim` forces WinPE to bring up NIC (`wpeinit`), mount the samba share `Z:` and start `setup.exe` unattended*  


mount the Windows 10 ISO to any path and copy `bcd`, `boot.sdi` & `boot.wim`  
Note: The mount point for Windows 10 ISO on my system is `/mnt/winiso/`  
```
sudo mkdir -p /mnt/winiso
sudo mount -o loop /path/of/Windows-10.iso /mnt/winiso
sudo mkdir /var/www/html/win10
sudo cp /mnt/winiso/efi/microsoft/boot/bcd /var/www/html/win10/
sudo cp /mnt/winiso/boot/boot.sdi /var/www/html/win10/
sudo cp /mnt/winiso/sources/boot.wim /var/www/html/win10/
```
Create and edit `boot.ipxe` config file for iPXE bootloader  
Make sure the DHCP user-class points to `boot.ipxe`  
Make sure the addresses inside `boot.ipxe` point to `wimboot`, `bcd`, `boot.sdi` and `boot.wim`  
```
sudo touch /var/www/html/win10/boot.ipxe
sudo chmod -R 755 /var/www/html/win10/
sudo $EDITOR /var/www/html/win10/boot.ipxe
```

Add the following configuration inside the `boot.ipxe`  
Remove comments from the text except line 1 (`#!ipxe`)  
```
#!ipxe
# above line is shebang calls the ipxe program

# menu entries for boot from disk or install windows
# local entry is set as default on timeout avoids installation loop
menu Windows UEFI Boot Menu
item --gap --         ---------OPTIONS------------
item --key d local    Boot from Local Disk [D]
item --key w windows  Install Windows 10 LTSC [W]
choose --default local --timeout 5000 target && goto ${target}

# windows installation label entry
# download kernel, initrd images from the HTTP server
# Boot with kernel and initrd after downloading
:windows
kernel http://192.168.10.1/UEFI/wimboot
initrd http://192.168.10.1/UEFI/win/bcd
initrd http://192.168.10.1/UEFI/win/boot.sdi
initrd http://192.168.10.1/UEFI/win/boot.wim
boot

# local menu entry exit 1 (exit with error)
# This skips PXE over IPv4 and goes to next boot order
:local
exit 1
```

**Injecting `startnet.cmd` & `winpeshl.ini` into `boot.wim`**:  
By default when `boot.wim` filesystem is loaded, it executes `setup.exe` from the `X:` drive rather than `Z:` drive, which we will be using as samba mount point.  
To resolve this, we first need to initialize the NIC of WinPE environment and mount samba share directory at `Z:`. This can be achieved by injecting a `startnet.cmd` script into `boot.wim` (index 2). To ensure our script runs at boot/mount, we need to create a config file named `winpeshl.ini` which launches any programs mentioned in it at boot or mount.  
We will instruct `winpeshl.ini` to run `startnet.cmd` which will in turn mount samba share point (`Z:` drive) and bring up NIC  


NOTE: *The mount point for `boot.wim` is /mnt/iso in my system, change path accordingly*


```
sudo mkdir /mnt/iso
sudo wimmountrw /var/www/html/win10/boot.wim 2 /mnt/iso
sudo touch /mnt/iso/Windows/System32/{winpeshl.ini,startnet.cmd}
sudo cat > /mnt/iso/Windows/System32/winpeshl.ini << 'EOF'
[LaunchApps]
"%SYSTEMROOT%\System32\startnet.cmd"
EOF
sudo cat > /mnt/iso/Windows/System32/startnet.cmd << 'EOF'
wpeinit
net use Z: \\192.168.10.1\win10 /user:guest ""
diskpart /s Z:\diskpart.txt
Z:\sources\setup.exe /unattend:Z:\unattended.xml
EOF
sudo wimunmount /mnt/iso --commit
```
Inside the `startnet.cmd` script is a custom text file for `diskpart` which will clean and partition the disk. The syntax for it is explained below


### Additional Step: Changing interface model of Virtual Bridge
In Hypervisor like QEMU/KVM, virtIO acts as an abstraction standard for virtualized I/O devices. By default, windows does not have drivers for virtIO. We need to either use a workaround i.e. `e1000e` which is an emulation for Intel 82574L Gigabit NIC or load the drivers for `virtIO` into the `boot.wim` file.  
I am using the former method i.e. switching NIC model to `e1000e`. Use `qemu///:session` if Virtual machine is located in your home directory; otherwise, use `qemu:///system` with root privilege  
```
virsh -c qemu:///session edit [vm name]
# go to interface section and change model type form 'virtio' to 'e1000e'
<interface type='bridge'>
    <source bridge='PXEbr0'/>
    <model type='e1000e'/>
</interface>
# save and exit
```


---
### Step 4: Samba (SMB) share & Media Staging
---
**Objective:**
- **Samba package staging**: *The multi-gigabyte `install.wim` and ISO root files are shared over SMB so `setup.exe` can pull installation layer directly during phase 2*  
- **Automated Answer File (`autounattend.xml`)**: *Automated configuration file handling locale, generic windows version keys, language setting and initial local accounts*  


Create the samba share directly and copy all Windows ISO contents
Mount point for Windows ISO is `/mnt/winiso/`
```
sudo mkdir -p /srv/samba/win10/
sudo cp /mnt/iso/* /srv/samba/win10/
sudo chmod -R 755 /srv/samba/win10/
```

Generate a `autounattend.xml` answer file from Windows 10 generator online at https://www.schneegans.de/windows/unattend-generator or any other source as per your need.  
Use the generic key windows version key in the generator. `M7XTQ-FN8P6-TTKYV-9D4CC-J462D` is the key for windows 10 enterprise ltsc 2021 or use any other key suitable for your windows version  
Note: Disable the (**Generate a .cmd script to handle WinPE stage**) option as the generated script expects `setup.exe` in `X:` instead of our mounted samba share. Instead we use our own WinPE routine to execute a custom `diskpart.txt` for partitioning and run `setup.exe`  
Copy or move the generated `autounattend.xml` to samba share directory `/srv/samba/win10/`  
```
sudo cp /path/of/autounattend.xml /srv/samba/win10/
```


Create a custom `diskpart.txt` for partitioning and place it inside samba share
```
sudo cat > /srv/samba/win10/diskpart.txt << 'EOF'
SELECT DISK=0
CLEAN
CONVERT GPT
CREATE PARTITION EFI SIZE=300
FORMAT QUICK FS=FAT32 LABEL="SYSTEM"
ASSIGN LETTER=S
CREATE PARTITION MSR SIZE=16
CREATE PARTITION PRIMARY
FORMAT QUICK FS=NTFS LABEL="WINDOWS"
ASSIGN LETTER=C
EXIT
EOF
```


Edit Samba configuration file at `/etc/samba/smb.conf`
```
sudo $EDITOR /etc/samba/smb.conf

# add the map to guest line in [global] section
[global]
	map to guest = bad user

# add the [win10] section at the end
[win10]
	path = /srv/samba/win10
	browseable = yes
	read only = yes
	guest ok = yes
	guest only = yes
```

Lastly, we should add a custom element in the `autounattend.xml` in `<settings pass="windowsPE">` `<component name="Microsoft-Windows-Setup"...>` section to make installation completely hands-free or else the installer asks to select **windows version** and **partition**
```
sudo $EDITOR /srv/samba/win10/autounattend.xml
# go to <component name="Microsoft-Windows-Setup"...> of <settings pass="windowsPE">
# add the following element
<ImageInstall>
  <OSImage>
    <InstallFrom>
      <MetaData wcm:action="add">
	<Key>/IMAGE/INDEX</Key>
	<Value>1</Value>
      </MetaData>
    </InstallFrom>
    <InstallTo>
      <DiskID>0</DiskID>
      <PartitionID>3</PartitionID>
    </InstallTo>
    <WillShowUI>OnError</WillShowUI>
  </OSImage>
</ImageInstall>
```
save and exit  

Now the installation environment is ready, ensure all the services are up and running and test the boot  
---



### Test the PXE boot
**Start and enable DHCP, TFTP, HTTP and Samba services**  
```
sudo systemctl enable --now httpd tftp dhcpd smb
systemctl status httpd tftp dhcpd smb
```  
With DHCP, TFTP, HTTP and Samba services configured and running, start the client virtual machine. Ensure its boot order is set to network boot (PXE) and it will automatically acquire an IP address, load the boot menu and begin unattended installation
