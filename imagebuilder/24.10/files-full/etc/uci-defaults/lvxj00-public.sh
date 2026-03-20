#!/bin/sh

# 允许 WAN 输入连接（首次使用 Web UI）
# wan_zone_idx=$(uci show firewall | grep "=zone" | grep "'wan'" | cut -d'[' -f2 | cut -d']' -f1)
# uci set firewall.@zone[$wan_zone_idx].input='ACCEPT'
# uci commit firewall

# 设置 LAN 默认 IP
uci set network.lan.ipaddr='192.168.56.1'

# 检测物理网卡数量（排除 lo，匹配常见前缀）
count=0
for iface in $(ls /sys/class/net | grep -v '^lo$'); do
  if [ -d /sys/class/net/$iface ] && echo "$iface" | grep -E -q '^(eth|en|lan|wan)[0-9]*$'; then
    count=$((count + 1))
  fi
done

# 如果只有一个网卡，改为 DHCP 模式（适用于虚拟机等自动获取地址场景）
if [ "$count" -eq 1 ]; then
    uci set network.lan.proto='dhcp'
    uci set dhcp.lan.ignore='1'
    uci set dhcp.@dnsmasq[0].min_cache_ttl='60'
fi

# 提交更改
uci commit network
uci commit dhcp

# 如果存在/etc/custom-scripts/目录，给目录下所有文件添加执行权限
if [ -d /etc/custom-scripts/ ]; then
    chmod +x /etc/custom-scripts/*
fi
