#!/bin/sh
# 全局配置
uci set network.globals.ula_prefix='fd00:129::/64'
# 配置wan6口ipv6
# 1. 删除可能存在的 wan6 和 wan_6 防止干扰
uci -q delete network.wan6
uci -q delete network.wan_6
# 配置wan口ipv6
uci set network.wan.ipv6='auto'
uci set network.wan.ip6ifaceid='random'
# 配置lan口ipv6
uci set network.lan.ip6assign='64'
uci set dhcp.lan.ra='server'
uci set dhcp.lan.max_preferred_lifetime='1800'
uci set dhcp.lan.max_valid_lifetime='3600'
uci add_list dhcp.lan.ra_flags='none'
uci set dhcp.lan.ra_dns='0'
uci set dhcp.lan.dns_service='0'
uci set dhcp.lan.ra_mininterval='60'
uci set dhcp.lan.ra_maxinterval='180'
# 提交修改
uci commit network
uci commit dhcp
