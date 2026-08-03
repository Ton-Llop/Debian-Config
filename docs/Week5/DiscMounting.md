# Week 5 - Add and Mount a New Virtual Disk

## Overview
This procedure creates a new virtual disk in VirtualBox, detects it inside Debian, partitions it, formats it with `ext4`, mounts it at `/srv/week5-data`, and makes the mount persistent through `/etc/fstab`.

---

## 1) Power off the virtual machine

Make sure the VM is completely powered off before changing storage settings.

---

## 2) Create and attach a new disk in VirtualBox

Open **VirtualBox** and follow these steps:

1. Select the VM: `debian-gsx`
2. Click **Settings**
3. Go to **Storage**
4. Select **Controller: SATA**
5. Click the **Add Hard Disk** icon
6. Choose **Create**
7. Select:
   - **VDI**
   - **Dynamically allocated**
8. Set the size, for example: `10 GB`
9. Save it with a different name from the system disk, for example: `debian-gsx_2.vdi`
10. Confirm the SATA controller now contains:
   - `debian-gsx.vdi` → main system disk
   - `debian-gsx_2.vdi` → new data disk

---

## 3) Boot Debian and verify the new disk

Start the VM and run:

```bash
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT
```
Expected result:

sda = main disk

sdb = new disk

sdb should appear as a new disk, initially without useful partitions

Example:

sda   20G

├─sda1 18.9G ext4 /

├─sda5 1.1G  swap [SWAP]

sdb   10G

## 4) Partition the new disk

Create one primary partition on /dev/sdb:
```bash
sudo fdisk /dev/sdb
````

Inside fdisk, type:
n
p
1
enter
enter
w

Explanation

n → new partition

p → primary

1 → partition number 1

press Enter twice to accept the default first and last sector

w → write changes and exit

## 5) Format the partition with ext4
```bash
sudo mkfs.ext4 /dev/sdb1
```
## 6) Create the mount point
```bash
sudo mkdir -p /srv/week5-data
```
## 7) Get the UUID of the new partition
```bash
sudo blkid /dev/sdb1
```

Example output:

/dev/sdb1: UUID="5ec95878-7491-46ff-b4b5-38939a7f88a7" BLOCK_SIZE="4096" TYPE="ext4" PARTUUID="5f174075-01"
## 8) Back up /etc/fstab
```bash
sudo cp /etc/fstab /etc/fstab.bak
````
## 9) Add the persistent mount entry
Edit /etc/fstab:
```bash
sudo nano /etc/fstab
```
Add this line at the end:

UUID=5ec95878-7491-46ff-b4b5-38939a7f88a7 /srv/week5-data ext4 defaults 0 2

Explanation:

- UUID=... → identifies the partition reliably
- /srv/week5-data → mount point
- ext4 → filesystem type
- defaults → standard mount options
- 0 → disable dump
- 2 → filesystem check after the root filesystem

## 10) Test the configuration without rebooting
```bash
sudo mount -a
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT
df -h
```
Expected result:

/dev/sdb1 mounted on /srv/week5-data

Example:

sdb      10G

└─sdb1   10G ext4  /srv/week5-data

and in df -h:

/dev/sdb1   9.8G   ...   /srv/week5-data
## 11) Reboot and verify persistence
```bash
sudo reboot
```
After reboot:
```bash
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT
df -h
```

If /srv/week5-data still appears, the mount is persistent and correctly configured.

## 12) Summary
A second virtual disk was added in VirtualBox, detected in Debian as /dev/sdb, partitioned as /dev/sdb1, formatted with ext4, mounted at /srv/week5-data, and configured in /etc/fstab using its UUID so the mount remains persistent after reboot.
