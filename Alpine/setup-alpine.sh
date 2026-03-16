#!/bin/sh

# 生成answers.txt文件
cat > /tmp/answers.txt << 'ANSWERS'
KEYMAPOPTS="us us"
HOSTNAMEOPTS="-n alpine-pve"
INTERFACESOPTS="auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp"
TIMEZONEOPTS="-z Asia/Shanghai"
PROXYOPTS="none"
NTPOPTS="-c chrony"
APKREPOSOPTS="https://mirror.nju.edu.cn/alpine/v3.23/main https://mirror.nju.edu.cn/alpine/v3.23/community"
SSHDOPTS="-c openssh"
ERASE_DISKS="sda"
DISKOPTS="-m sys /dev/sda"
ROOTSSHKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL2r+nbC89lI6ie+lySem1yL5PbW2xXvM+iUVodklEqo lvxj11@lvxj11-PC"
ANSWERS

# 执行安装
ERASE_DISKS=sda setup-alpine -f /tmp/answers.txt

# 安装完成后配置SSH（允许root公钥登录）
if [ -d "/mnt/etc/ssh" ]; then
    sed -i 's/#PermitRootLogin.*/PermitRootLogin prohibit-password/' /mnt/etc/ssh/sshd_config
fi

echo "安装完成！"
