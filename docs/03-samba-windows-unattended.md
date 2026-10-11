## UEFI Network Boot (PXE) Architecture & Setup for Windows 10

### Overview & Architecture
- When client machine is turned on, it's UEFI NIC ROM executes PXE over IPv4 to broadcast for a DHCP domain server
- It obtains IP address from the DHCP server and address of the TFTP server with the filename of bootloader/s
- After checking the vendor-class (PXEClient) and architecture-type (UEFI), The appropriate bootloader is downloaded over TFTP
- Bootloader `ipxe-x86_64.efi` is executed in memory and broadcasts a DHCP Request to the server
- IPXE downloads the `boot.ipxe` menu file over HTTP  which contains the **kernel** and **initial Ram Disk** addresses
- Kernel `wimboot`, initial Ram Disk `BCD`, `boot.sdi`, `boot.wim` are loaded over HTTP
- `BCD` contains the boot menu entries, `boot.sdi` contains the binary to mount `boot.wim` which contains the filesystem in RAM
- **WinPE** i.e. kernel or minimal environment is booted in Ram Disk and the filesystem (boot.wim) it mounted as **X:** drive
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

