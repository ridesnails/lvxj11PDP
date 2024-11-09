#!/bin/sh
# 初始化Alpine系统，适配版本3.20
echo "初始化 Alpine 系统..."
apk update
apk upgrade

echo "安装常用工具..."
apk add curl nftables openssh net-tools

echo "启动nftables, sshd和local服务..."
rc-service nftables start
rc-update add nftables default
rc-service sshd start
rc-update add sshd default
# 开机执行脚本服务
rc-update add local default

echo "设置开启转发支持..."
echo -e "#!/bin/sh\nsysctl -w net.ipv4.ip_forward=1\nsysctl -w net.ipv6.conf.all.forwarding=1" > /etc/local.d/enable_forwarding.start
chmod +x /etc/local.d/enable_forwarding.start

# 非必须，用于tproxy模式透明代理
# echo "添加路由表和路由规则..."
# echo -e "#!/bin/sh\nip route add local default dev lo table 100\nip rule add fwmark 1 table 100" > /etc/local.d/add_routing_table.start
# chmod +x /etc/local.d/add_routing_table.start