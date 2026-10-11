rem The path for this file is inside the boot.wim file
rem The boot.wim file is located at /var/www/html/UEFI/win/boot.wim
rem mount the boot.wim at any location using wimmountrw
rem copy or move start.net to Windows/System32 folder inside boot.wim

@echo off
wpeinit

echo "Connecting to Samba server..."
net use Z: \\192.168.10.1\win10 /user:guest ""

if exist Z:\sources\setup.exe (
   echo "Running Setup.."
   echo "Clean and partition disk 0"
   diskpart /s Z:\diskpart.txt
   Z:\sources\setup.exe /unattend:Z:\autounattend.xml
   ) else (
   echo "Setup not found.. exiting.."
   pause
   cmd.exe)
