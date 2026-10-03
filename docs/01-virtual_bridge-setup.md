# Network Topology: Virtual Bridge Setup
- To allow broadcast-based DHCP and TFTP communication, a level-2 virtual bridge is used to connect both the server and client virtual machines within the same broadcast domain


```
_________________________________________________________________
|                                                               |
|         _____________________________________________         |
|        |           (Virtual Switch Layer-2)          |        |
|        |_____________________________________________|        |
|                |                              |               |
|                |                              |               |
|         _______|_______                _______|_______        |
|        |   Server VM   |              |   Client VM   |       |
|        |  (Adapter 1)  |              |  (Adapter 2)  |       |
|        |_______________|              |_______________|       |
|_______________________________________________________________|
```


## Prerequisites and Environment
This setup using **libvert** to manage linux bridge and virtual machine networking. Ensure the following are available:
- **Hyprevisor**: QEMU/KVM
- **Management Tools**: `libvirt` daemon (libvertd) running with `virsh` CLI
- **Privelges**: `sudo`/ROOT privelges for (qemu:///system) system networks



