---

## Multi-Platform Automated PXE Boot Lab

A multi-platform network boot (PXE) and unattended operating system installation environment built on Linux (KVM/libvirt). This lab automatically detects client firmware architecture (Legacy BIOS vs. UEFI) using DHCP options and routes to either an automated Kickstart installation for RHEL 8 or a custom WinPE/Samba deployment for Windows 10.

---

## Features

* [x] Layer-2 virtual bridge creation using virsh CLI
* [x] Legacy BIOS network boot (`pxelinux.0` + Syslinux modules)
* [x] DHCP Option 93 & Option 60 autodection (Legacy BIOS vs. UEFI)
* [x] Automated RHEL 8 deployment via Kickstart (`ks.cfg`)
* [x] Two-stage UEFI iPXE chaining over HTTP (`wimboot`)
* [x] Samba (SMB) share integration for Windows ISO installation media

---

### Architecture Overview

```text
                      +-----------------------------+                      
                      |   Layer-2 Virtual Bridge    |                      
                      |          (PXEbr0)           |                      
                      +--------------+--------------+                      
                                     |                                     
           +-------------------------+-------------------------+           
           |                                                   |           
+----------v-----------+                             +---------v----------+
|      Server VM       |                             |     Client VM      |
|     192.168.10.1     |                             |     DHCP Client    |
+----------------------+                             +--------------------+
| * DHCP (Option 93/60)| <=== 1. DHCP Discover ===== | PXE ROM / UEFI NIC |
| * TFTP (UDP 69)      | <=== 2. Bootloader Request  |                    |
| * HTTP (TCP 80)      | <=== 3. Kernel / Initrd === |                    |
| * Samba (TCP 445)    | <=== 4. OS Tree / Unattend  |                    |
+----------------------+                             +--------------------+

```


### Key Highlights

* **Client Architecture Detection:** Uses DHCP Option 93 (`architecture-type`) and Option 60 (`vendor-class-identifier`) to branch between Legacy BIOS (`pxelinux.0`) and UEFI (`ipxe-x86_64.efi`).
* **Two-Stage UEFI Handoff:** UEFI firmware retrieves iPXE over TFTP; iPXE then re-queries DHCP with Option 77 (`user-class = "iPXE"`) to fetch configuration menus and Windows PE ramdisk binaries over HTTP
* **Automated RHEL 8 Deployment:** Fully automated partition layout, package selection, and post-installation setup using Anaconda Kickstart (`ks.cfg`) over HTTP.
* **Unattended Windows 10 via SMB:** Bypasses WinPE ISO media constraints by injecting custom `winpeshl.ini` and `startnet.cmd` routines into `boot.wim`, mapping a Samba share to drive `Z:`, running scripted partitioning using `diskpart.txt`, and launching `setup.exe` unattended.

---


### Implementation Guides

Detailed step-by-step documentation for each stage of the lab:

1. **[01. Layer-2 Virtual Bridge Setup](https://github.com/sagarchandrol/pxe-boot-setup/blob/main/docs/01-virtual_bridge-setup.md)**
Creation of isolated virtual bridge in libvirt, using bridging helpers for unprivileged user sessions (`qemu:///session`), and client VM creation via `virt-install`.
2. **[02. Legacy BIOS RHEL 8 Kickstart](https://github.com/sagarchandrol/pxe-boot-setup/blob/main/docs/02-legacy-bios-rhel-kickstart.md)**
Configuring `dhcpd`, Syslinux COM32 modules, TFTP boot staging, and Anaconda Kickstart installation over HTTP.
3. **[03. Windows 10 Unattended Setup via Samba](https://github.com/sagarchandrol/pxe-boot-setup/blob/main/docs/03-samba-windows-unattended.md)**
Staging two step boot iPXE + `wimboot` over HTTP, injecting startup scripts into `boot.wim` using `wimlib-utils`, configuring Samba shares, and automated disk partitioning.

---


### Configuration Files  Map

When deploying this lab on a Linux server, copy the repository configuration files to the following real-world system paths:

|           Repository File           |            Target System Path            |                             Purpose                                |
| ----------------------------------- | ---------------------------------------- | ------------------------------------------------------------------ |
| `configs/dhcp/dhcpd.conf`           | `/etc/dhcp/dhcpd.conf`                   | ISC DHCP daemon configuration with Option 93 & Option 60 branching |
| `configs/tftp/pxelinux.cfg/default` | `/var/lib/tftpboot/pxelinux.cfg/default` | Syslinux boot menu for Legacy BIOS RHEL installation               |
| `configs/http/rhel/ks.cfg`          | `/var/www/html/ks.cfg`                   | RHEL 8 automated Kickstart answer file                             |
| `configs/http/win10/boot.ipxe`      | `/var/www/html/win10/boot.ipxe`          | iPXE boot script chaining `wimboot`, BCD, and `boot.wim`           |
| `configs/samba/smb.conf`            | `/etc/samba/smb.conf`                    | Samba daemon configuration exporting the Windows ISO root          |
| `configs/samba/diskpart.txt`        | `/srv/samba/win10/diskpart.txt`          | Scripted GPT/EFI/MSR disk partitioning routine for WinPE           |
| `configs/samba/autounattend.xml`    | `/srv/samba/win10/autounattend.xml`      | Windows unattended setup answer file                               |

---
