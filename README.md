# Raspberry-backup
树莓派备份脚本

优点：备份后的镜像在恢复时会自动扩容空间

运行`sudo bash backup.sh`将在当前路径生成备份文件

生成的镜像名为`raspi-backup.img`

一键备份：
```
curl -sSL https://raw.githubusercontent.com/mghcool/Raspberry-backup/master/backup.sh | sudo bash
```
