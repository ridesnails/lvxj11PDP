#!/bin/sh

# 设置 LAN 默认 IP 和子网掩码
uci set network.lan.ipaddr='10.0.1.1'
uci set network.lan.netmask='255.255.255.0'

# 检测物理网卡（排除 lo，匹配常见前缀）
iface_list=""
for iface in $(ls /sys/class/net | grep -v '^lo$'); do
  if [ -d /sys/class/net/$iface ] && echo "$iface" | grep -E -q '^(eth|en|lan|wan)[0-9]*$'; then
    iface_list="$iface_list $iface"
  fi
done

# 转换为数组并计数
iface_array=$(echo $iface_list | tr ' ' '\n')
count=$(echo "$iface_array" | grep -c .)

if [ "$count" -eq 1 ]; then
    # 只有一个网卡，改为 DHCP 模式（适用于虚拟机等自动获取地址场景）
    uci set network.lan.proto='dhcp'
    uci set dhcp.lan.ignore='1'
    uci set dhcp.@dnsmasq[0].authoritative='0'
    uci set dhcp.@dnsmasq[0].min_cache_ttl='60'
elif [ "$count" -gt 1 ]; then
    # 多个网卡：最后一个为 WAN 口，其余为 LAN 口
    wan_if=$(echo "$iface_array" | tail -n 1)
    lan_ifs=$(echo "$iface_array" | head -n -1 | tr '\n' ' ' | sed 's/ $//')
    
    # 配置 LAN 桥接接口
    uci set network.lan.device='br-lan'
    uci set network.lan.type='bridge'
    uci add_list network.lan.ports="$lan_ifs"
    
    # 配置 WAN 接口
    uci set network.wan=interface
    uci set network.wan.device="$wan_if"
    uci set network.wan.proto='dhcp'
    uci set network.wan.metric='10'
    
    # 配置 WAN 防火墙区域
    wan_zone_idx=$(uci show firewall | grep "firewall.@zone" | grep "name='wan'" | cut -d'[' -f2 | cut -d']' -f1)
    if [ -n "$wan_zone_idx" ]; then
        is_added=$(uci get firewall.@zone[$wan_zone_idx].network 2>/dev/null | grep -w "wan")
        if [ -z "$is_added" ]; then
            uci add_list firewall.@zone[$wan_zone_idx].network='wan'
        fi
    fi
fi
# 禁用ipv6服务
uci del dhcp.lan.ra
uci del dhcp.lan.dhcpv6
# 取消委托ipv6前缀
uci set network.lan.delegate='0'
# 本地ipv6使用随机地址
uci set network.lan.ip6ifaceid='random'
# 取消 DNS 重定向
uci set dhcp.@dnsmasq[0].dns_redirect='0'

# 新建ipv6接口
uci set network.lan6=interface
uci set network.lan6.proto='dhcpv6'
uci set network.lan6.device='br-lan'
uci set network.lan6.reqaddress='try'
uci set network.lan6.reqprefix='auto'
uci set network.lan6.norelease='1'
uci set network.lan6.sourcefilter='0'
uci set network.lan6.delegate='0'
uci set network.lan6.ip6ifaceid='random'
# 处理新接口的防火墙策略
zone_idx=$(uci show firewall | grep "firewall.@zone" |  grep "name='lan'" | cut -d'[' -f2 | cut -d']' -f1)
if [ -n "$zone_idx" ]; then
    is_added=$(uci get firewall.@zone[$zone_idx].network | grep -w "lan6")
    if [ -z "$is_added" ]; then
        uci add_list firewall.@zone[$zone_idx].network='lan6'
    fi
fi

# 提交更改
uci commit network
uci commit dhcp
uci commit firewall

# 如果存在/etc/custom-scripts/目录，给目录下所有文件添加执行权限
if [ -d /etc/custom-scripts/ ]; then
    chmod +x /etc/custom-scripts/*
fi
