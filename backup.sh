#!/bin/bash

set -e #当命令以非零状态退出时，则退出shell

Color_End="\033[0m"
Color_Red="\033[31m"
Color_Green="\033[32m"

if [ `id -u` != 0 ];then
    echo -e "$Color_Red权限不足，退出脚本！ $Color_End"
    exit 1
fi

# 设置文件存放目录
BACKUP_DIR=`pwd`
BACK_UP_DIR=$BACKUP_DIR/raspi-backup
FILE=$BACK_UP_DIR/raspi-backup.img  #备份后的img文件名
mkdir $BACK_UP_DIR

#安装必要的软件安装包 
echo -e "$Color_Green安装必要的软件...$Color_End"
apt-get install -qq -y dosfstools dump parted kpartx rsync
apt-get clean

#创建镜像img文件
echo -e "$Color_Green创建img文件...$Color_End"
ROOT=`df -P | grep /dev/root | awk '{print $3}'`   #获取 ROOT的文件大小
MMCBLK0P1=`df -P | grep /dev/mmcblk0p1 | awk '{print $2}'`  #获取主目录的文件大小
ALL=`echo $ROOT $MMCBLK0P1 | awk '{print int(($1+$2)*1.1)}'`  #生成一个比原文件大200M的IMG文件
echo "预计生成文件大小：$(($ALL/1024))MB"
echo "root 大小是 $(($ROOT/1024))MB"
echo "boot 大小是 $(($MMCBLK0P1/1024))MB"
echo "文件路径是 $FILE"
dd if=/dev/zero of=$FILE bs=1K count=$ALL status=progress

#格式化分区
echo -e "$Color_Green格式化root和boot...$Color_End"
P1_START=`fdisk -l /dev/mmcblk0 | grep /dev/mmcblk0p1 | awk '{print $2}'`
P1_END=`fdisk -l /dev/mmcblk0 | grep /dev/mmcblk0p1 | awk '{print $3}'`
P2_START=`fdisk -l /dev/mmcblk0 | grep /dev/mmcblk0p2 | awk '{print $2}'`
echo "boot_start is :$P1_START .boot_end is : $P1_END  .rootfs_start is :$P2_START"
parted $FILE --script -- mklabel msdos
parted $FILE --script -- mkpart primary fat32 ${P1_START}s ${P1_END}s
parted $FILE --script -- mkpart primary ext4 ${P2_START}s -1
parted $FILE --script -- quit

# mount
echo -e "$Color_Green挂载分区...$Color_End"
loopdevice_dst=`losetup -f --show $FILE` 
echo "loop分区在 $loopdevice_dst"
PART_BOOT="/dev/dm-0"
PART_ROOT="/dev/dm-1"
sleep 1
device_dst=`kpartx -va $loopdevice_dst | sed -E 's/.*(loop[0-9])p.*/\1/g' | head -1`
sleep 1
device_dst="/dev/mapper/${device_dst}"
sleep 1
mkfs.vfat ${device_dst}p1 -n boot 
sleep 1
mkfs.ext4 ${device_dst}p2 -L rootfs
sleep 1

# 复制文件到img
echo -e "$Color_Green复制文件到img...$Color_End"
echo "备份分区 /dev/boot"
dst_boot_path=$BACK_UP_DIR/dst_boot
mkdir  $dst_boot_path
mount -t vfat ${device_dst}p1 $dst_boot_path 
cp -rfp /boot/* $dst_boot_path
echo "备份boot完成"
echo "备份分区 /dev/root"
dst_root_path=$BACK_UP_DIR/dst_root
mkdir  $dst_root_path
sleep 1
mount -t ext4 ${device_dst}p2 $dst_root_path
cd $dst_root_path
chmod 777 $dst_root_path/
#通过rsync复制根目录文件到IMG镜像中，排除了一些不需要同步的文件
rsync -ax --info=progress2 --no-inc-recursive \
    --exclude="$FILE" \
    --exclude=$BACK_UP_DIR  \
    --exclude=$BACKUP_DIR/$0  \
    --exclude=/sys/* \
    --exclude=/proc/*  \
    --exclude=/tmp/* /  $dst_root_path/
echo "备份root完成"

# 设置自动扩展空间
echo -e "$Color_Green设置自动扩展空间 ...$Color_End"
sed -i 's/exit 0/sudo bash \/expand-rootfs.sh \&/' $dst_root_path/etc/rc.local 
echo "exit 0" >> $dst_root_path/etc/rc.local 
cat > $dst_root_path/expand-rootfs.sh << EOF
#!/bin/bash

sed -i '/sudo bash \/expand-rootfs.sh &/d' /etc/rc.local 
rm "\`pwd\`/\$0"
echo -e "\033[33m两秒后扩展分区空间！\033[0m"
sleep 2
raspi-config --expand-rootfs
echo -e "\033[33my一秒后重启系统！\033[0m"
sleep 1
reboot
EOF


#返回目录 $BACKUP_DIR
cd $BACKUP_DIR
sync

#替换PARTUUID 这步非常重要，liunx启动时会对PARTUUID有特定的指定，备份的时候是把旧的也同步过来，需要根据新的IMG文件来更新PARTUUID
echo -e "$Color_Green替换PARTUUID ...$Color_End"
opartuuidb=`blkid -o export /dev/mmcblk0p1 | grep PARTUUID`
opartuuidr=`blkid -o export /dev/mmcblk0p2| grep PARTUUID`
npartuuidb=`blkid -o export ${device_dst}p1 | grep PARTUUID`
npartuuidr=`blkid -o export ${device_dst}p2 | grep PARTUUID`
echo "BOOT uuid $opartuuidb 替换为 $npartuuidb"
echo "ROOT uuid $opartuuidr 替换为 $npartuuidr"
sed -i "s/$opartuuidr/$npartuuidr/g" $dst_boot_path/cmdline.txt
sed -i "s/$opartuuidb/$npartuuidb/g" $dst_root_path/etc/fstab
sed -i "s/$opartuuidr/$npartuuidr/g" $dst_root_path/etc/fstab

#清理释放装载的文件夹
echo -e "$Color_Green清理释放装载的文件夹...$Color_End"
umount $dst_boot_path
umount $dst_root_path
kpartx -d ${device_dst}p1
kpartx -d ${device_dst}p2
kpartx -d $loopdevice_dst 
losetup -d $loopdevice_dst   
rm -rf  $dst_boot_path
rm -rf  $dst_root_path
chmod 766 $FILE
mv $FILE $BACKUP_DIR
rm -rf $BACK_UP_DIR

echo -e "$Color_Green备份完成。$Color_End"
exit 0