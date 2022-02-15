A Utility to Split Filesystems out of a Raspbian img

As most curious people know, the Raspbian img files from
https://www.raspberrypi.com/software/operating-systems/ are sector by sector 
copies of Pi bootable drives.  An image is comprised of a DOS MBR (sector 0),
some padding (as partition 1 does not start at sector 1), a VFAT partition 1,
possibly some padding, and finally a minimal ext4 partition 2.
The image files come “from the factory” as zipped files that can be used
directly by the Balena Etcher utility, Raspberry Pi Imager, or (after unzipping) 
by ‘dd’, to produce a bootable disk.  This bootable disk, usually an SD card 
(or USB thumb drive, SSD, or HDD on a Pi3), can be placed in a Pi and booted 
by the Pi firmware. The unfortunate thing about this packaging method is that 
the first partition, the VFAT ‘/boot’ one, is not easily resizable and may be 
too small.  (Or too big. Depends on who you ask!)

Some things to keep in mind.

it’s a dos MBR disk, not GPT (and therefore limited in size to 2 TiB.)
RANT:  TiB?  Really. Not TB?  That’s because some idiot (yes, I know all about
the IEEE), probably in collusion with the drive manufacturers, decided that
1K=1,000 (like in Europe), not 1024 (2**10) like it had always been for decades!
Granted, one kilogram is 1000 grams, one kilometer is 1000 meters, no argument
there; but 1K in a computer IS 1024, one page in Linux IS 4k, 4096 bytes,
not 4000 bytes.  1MB IS 1024*1024 bytes, 1048576, not 1000000 bytes.  Etcetera.
I’ll stop pontificating now.

the program that follows has only been tested on disks that are
“Sector size (logical/physical): 512 bytes / 512 bytes”.  Sorry.  It’s cheap.
I’m lazy.  And I don’t have a 4096 logical sector size disk.

There is no stage 1 bootloader code in the MBR, as the Pi has no bios and
loading is handled by Pi firmware.  And that firmware appears to be limited
and is closed source.  Even the new Pi4 firmware!   

The first partition, later mounted at ‘/boot’, is VFAT; as mentioned, it is
relatively small; and (from Linux) is not really resizable.  It contains the
kernel, a ‘cmdline.txt’ file containing kernel parms, a ‘config.txt’ file
containing keyword values used by the firmware (remember, there is no BIOS,
so these are roughly equivalent to BIOS settings), and various files required
for boot.

The “Disk identifier” in the MBR is usually referenced in the ‘cmdline.txt’
file (root=PARTUUID=xxxxxxxx-02) and in ‘/etc/fstab’ entries.  (On disk, it is
at 0x1b0 and is little-endian. It displays big-endian in ‘fdisk’, and that is
what should be coded in ‘cmdline.txt’ and ‘/etc/fstab’.) E.g.
in /boot/cmdline.txt:
root=PARTUUID=xxxxxxxx-02
in /etc/fstab:
PARTUUID=xxxxxxxx-01  /boot           vfat    defaults          0       2
PARTUUID=xxxxxxxx-02  /               ext4    defaults,noatime  0       1

The second partition, later mounted at ‘/’ (ie. the root partition), is ext4,
a minimal size (so it will fit on any 8GB SD card), and will be resized when
the card is first booted in a Pi (assuming that it is on ‘/dev/mmcblk0’).
(In ‘/boot/cmdline.txt’ there is 'init=/usr/lib/raspi-config/init_resize.sh '.
And in ‘/etc/init.d’ there is an “rc file” called ‘resize2fs_once’ that
accomplishes this, as will the raspi-config script.)

The Raspbian images mentioned above only have VFAT and ext4 support compiled
into the kernel. There is no btrfs, f2fs, or lvm2 (dm-mod) support. To support
these you need an initramfs.

An initramfs is supported (so you can add other filesystem support, LVM,
and any drivers needed early on), but it is a tight squeeze into the first
partition.  There are a few good articles on this topic.  I like the first
answer in this one: https://raspberrypi.stackexchange.com/questions/92557/how-can-i-use-an-init-ramdisk-initramfs-on-boot-up-raspberry-pi?noredirect=1&lq=1

So, why do you need a utility to split out the /boot and /root filesystems?
Generally, you don’t.  (And with the proper calculation of skip= and count=,
you could use ‘dd’ instead.)

But what if you want to have a larger ‘/boot’ partition (partition 1)?  Or if
you want to have the second partition be LVM2 with ‘/root’ on a logical volume?
This would necessitate an initramfs and a larger ‘/boot’ partition to contain it.
The C program in this repository compiles on both Ubuntu 18.04, and on Raspbian
GNU/Linux 9 (stretch).  Assuming it is named ‘raspberry-split.c’, it can be
compiled with ‘gcc -o raspberry-split raspberry-split.c’ and optionally copied
to ‘/usr/local/bin’.

The program produces a .boot and a .root file that can subsequently be mounted
on a loopback device and used to rsync to a properly formatted SD card,
USB stick, USB SSD, or USB HDD.
After compilation, as an example, you could do this to set up your target drive:
cd Downloads/raspian
sudo unzip 2019-04-08-raspbian-stretch-full.zip
./raspberry-split
sudo fdisk /dev/sdb
   p
   d/2
   d/1
   n/p/1/8192/516095
   t/1/c
   n/p/2/516096/10969087
   t/2/83
   x/i/0x43c1e3bb
   r
   w

(that is, print the size, partition information, disk identification, etc of
the target drive;
delete the 2nd and 1st partitions if needed;
create a new partition 1 starting at 8192 (or 2048), ending at 516095, and make it VFAT;
create a new partition 2 starting at 516096, going to the end of the disk,
and make it ext4;
and set the ‘Disk identifier’ to 0x43c1e3bb.)

Then you could do this to format the filesystems, mount everything, and copy
the OS to your target drive:

sudo mkfs.vfat /dev/sdb1
sudo mkfs.ext4 /dev/sdb2
mkdir -p /mnt/boot.SD
mkdir -p /mnt/root.SD
mkdir -p /mnt/boot.img
mkdir -p /mnt/root.img
sudo mount /dev/sdb1 /mnt/boot.SD
sudo mount /dev/sdb2 /mnt/root.SD
sudo mount 2019-04-08-raspbian-stretch-full.img.boot /mnt/boot.img
sudo mount 2019-04-08-raspbian-stretch-full.img.root /mnt/root.img
sudo rsync -avx --sparse /mnt/boot.img/ /mnt/boot.SD
sudo rsync -ax   --sparse /mnt/root.img/ /mnt/root.SD
sudo umount /mnt/boot.SD /mnt/root.SD /mnt/boot.img /mnt/root.img
cd -

(This assumes your target device is on /dev/sdb,
the “2019-04-08-raspbian-stretch-full.zip” img has been downloaded to
~/Downloads/raspian, and the above C program has been compiled with
“gcc -o ~/Downloads/raspian/raspberry-split raspberry-split.c”
You could also add the --static flag if you want to copy the executable around...)

Hope this is useful, but, as always, YMMV.
