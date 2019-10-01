#!/bin/bash

set -e

#设置文件存放目录

BACKUP_DIR=`pwd`

BACK_UP_DIR=$BACKUP_DIR/raspi-backup

FILE=$BACK_UP_DIR/raspi-backup.img  #备份后的img文件名

sudo mkdir $BACK_UP_DIR

echo

#安装需要的软件安装包 

echo "安装需要的软件  ..."

apt-get install dosfstools dump parted kpartx rsync -y

echo

#生成镜像img文件

echo "生成img文件 ..."

ROOT=`df -P | grep /dev/root | awk '{print $3}'`   #获取 ROOT的文件大小

MMCBLK0P1=`df -P | grep /dev/mmcblk0p1 | awk '{print $2}'`  #获取主目录的文件大小

ALL=`echo $ROOT $MMCBLK0P1 |awk '{print int(($1+$2)*1.2)}'`  #生成一个比ROOT目录和主目录大一点的IMG文件

dd if=/dev/zero of=$FILE bs=1K count=$ALL

echo "Root 大小是 $ROOT"

echo "root 大小是 $MMCBLK0P1"

echo "文件路径是 $FILE"

echo


#格式化分区
echo "格式化root和boot..."

P1_START=`fdisk -l /dev/mmcblk0 | grep /dev/mmcblk0p1 | awk '{print $2}'`

P1_END=`fdisk -l /dev/mmcblk0 | grep /dev/mmcblk0p1 | awk '{print $3}'`

P2_START=`fdisk -l /dev/mmcblk0 | grep /dev/mmcblk0p2 | awk '{print $2}'`

echo "boot_start is :$P1_START .boot_end is : $P1_END  .rootfs_start is :$P2_START"

parted $FILE --script -- mklabel msdos

parted $FILE --script -- mkpart primary fat32 ${P1_START}s ${P1_END}s

parted $FILE --script -- mkpart primary ext4 ${P2_START}s -1

parted $FILE --script -- quit

echo


# mount
echo "挂载分区 ..."

loopdevice_dst=`sudo losetup -f --show $FILE` 

echo "loopdevice_dst is $loopdevice_dst"

PART_BOOT="/dev/dm-0"

PART_ROOT="/dev/dm-1"

sleep 1

device_dst=`kpartx -va $loopdevice_dst | sed -E 's/.*(loop[0-9])p.*/\1/g' | head -1`

sleep 1

device_dst="/dev/mapper/${device_dst}"

sleep 1

sudo mkfs.vfat ${device_dst}p1 -n boot 

sleep 1

sudo mkfs.ext4 ${device_dst}p2 -L rootfs

sleep 1

echo


# 开始拷贝文件
echo "复制文件到img..."

echo "备份磁盘 /dev/boot ..."

dst_boot_path=$BACK_UP_DIR/dst_boot

sudo mkdir  $dst_boot_path

mount -t vfat ${device_dst}p1 $dst_boot_path 

cp -rfp /boot/* $dst_boot_path

echo

echo "备份磁盘 /dev/root ..."

dst_root_path=$BACK_UP_DIR/dst_root

sudo mkdir  $dst_root_path

sleep 1

sudo mount -t ext4 ${device_dst}p2 $dst_root_path

cd $dst_root_path

sudo chmod 777  $dst_root_path/

#通过rsync 来同步根目录到IMG镜像中，排除了一些不需要同步的文件
sudo rsync -ax  -q --exclude="$FILE" --exclude=$BACK_UP_DIR/*  --exclude=/sys/* --exclude=/proc/*  --exclude=/tmp/* /  $dst_root_path/

#返回目录 $BACKUP_DIR
cd $BACKUP_DIR

sync

echo

#替换PARTUUID 这步非常重要，liunx启动时会对PARTUUID有特定的指定，备份的时候是把旧的也同步过来，需要根据新的IMG文件来更新PARTUUID
echo "替换PARTUUID ..."

opartuuidb=`blkid -o export /dev/mmcblk0p1 | grep PARTUUID`

opartuuidr=`blkid -o export /dev/mmcblk0p2| grep PARTUUID`

npartuuidb=`blkid -o export ${device_dst}p1 | grep PARTUUID`

npartuuidr=`blkid -o export ${device_dst}p2 | grep PARTUUID`

echo "BOOT uuid $opartuuidb 替换为 $npartuuidb"

echo "ROOT uuid $opartuuidr 替换为 $npartuuidr"

sudo sed -i "s/$opartuuidr/$npartuuidr/g" $dst_boot_path/cmdline.txt

sudo sed -i "s/$opartuuidb/$npartuuidb/g" $dst_root_path/etc/fstab

sudo sed -i "s/$opartuuidr/$npartuuidr/g" $dst_root_path/etc/fstab


#清理释放装载的文件夹
echo "清理释放装载的文件夹 ..."
sleep 1

sudo umount $dst_boot_path

sudo umount $dst_root_path

sudo  kpartx  -d ${device_dst}p1

sudo  kpartx -d ${device_dst}p2

sudo  losetup -d $loopdevice_dst   

sudo rm -rf  $dst_boot_path

sudo rm -rf  $dst_root_path

sudo chmod 766 $FILE

sudo mv $FILE $BACKUP_DIR

sudo rm -rf $BACK_UP_DIR

echo "================完成================="

exit 0
