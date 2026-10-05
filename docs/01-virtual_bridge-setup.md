# Network Topology: Virtual Bridge Setup
To allow broadcast-based DHCP and TFTP communication, a level-2 virtual bridge is used to connect both the server and client virtual machines within the same broadcast domain


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
This setup uses **libvirt** to manage linux bridge and virtual machine networking. Ensure the following are available:
- **Hypervisor**: QEMU/KVM
- **Management Tools**: `libvirt` daemon (libvirtd) running with `virsh` CLI
- **Privileges**: `sudo`/ROOT privilege for (qemu:///system) system networks



### Step 1: Create a custom file `pxe-net.xml` with minimal settings
Start with a `<network>` element with the name of the network device  
Create a `<bridge>` element with the name of the bridge, set STP as enabled and delay to zero
```
<network>
  <name>PXE-Net</name>
  <bridge name='PXEbr0' stp='on' delay='0'/>
</network>
```


### Step 2: Define and Start the network device in `virsh` CLI interactive mode
To run virsh in `qemu:///system` mode, user must either be a member of `wheel` group and/or `libvirt` group
``` bash
sudo virsh -c qemu:///system
net-define /path/to/pxe-net.xml
net-start PXE-Net
net-autostart PXE-Net
```
**Check the network**
```
ip link show PXEbr0
```


### Step 3: Connect the network interface to the server virtual machine and client virtual machine
check whether the virtual machines run in `qemu:///session` mode or `qemu:///system` mode  
`sudo virsh -c qemu:///system list --all` or `virsh -c qemu:///session list --all` to list virtual machines  
virtual machines in my case run in `qemu:///session` mode
``` bash
virsh -c qemu:///session edit <server vm name>
```
In the editor, either replace the existing `<interface>` element or create a new `<interface>` element
```
<interface type='bridge'>
  <source bridge='PXEbr0'/>
  <model type='virtio'/>
</interface>
```
Virtual machines run under normal user or (libvirt-qemu) user, but creating a network TAP requires root privilege. So we use a binary called `qemu-bridge-helper` to temporarily run as privileged user for the duration of the network operations
```
sudo chmod u+s /usr/lib/qemu/qemu-bridge-helper
```

**Whitelist the virtual bridge**
```
echo "allow PXEbr0" | sudo tee /etc/qemu/bridge.conf
```


### Step 4: Install Client virtual machine
To create client virtual machine, `virt-install` tool is being used. Install it if already not on your system  
Note: Package Manager on my system is **apt**, change package manager in command line depending upon the system
```
sudo apt install virt-install
```
Client virtual machine can be installed in either `qemu:///session` mode or `qemu:///system` mode  
If using `qemu:///system` then use prefix `sudo` before `virt-install` to grant **ROOT** privilege  
Adjust **VM name**, **memory**, **vcpu** and **disk size** as per your hardware and make sure to attach `--network` to your virtual bridge
```
virt-install --connect qemu:///session --name rhel8-client --memory 2048 --vcpu 2 --disk size=20,format=qcow2 --boot network,hd --os-variant rhl8.0 --network bridge=PXEbr0,model=virtio --noautoconsole --noreboot
```
Check the virtual machine status  
Run the command with `sudo` privilege if VM was installed with `qemu:///system`
```
virsh list --all
```

TIP: If using graphical virtual managers like GNOME Boxes or virt-manager, ensure the virtual machine's prefrences are set "Run in Background" so the network installation is not suspended when switching windows  
*Now the **server** virtual machine and **client** virtual machine is connected to the virtual bridge*