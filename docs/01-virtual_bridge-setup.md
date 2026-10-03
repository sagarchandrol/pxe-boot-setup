# Network Topology: Virtual Bridge Setup
-To allow broadcast-based DHCP and TFTP communication, a level-2 virtual bridge is used to connect both the server and client virtual machines within the same broadcast domain
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
