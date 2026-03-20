#!/bin/sh
IPSET_NAME="$1"
IP_ADDR="$2"
LOG="/etc/custom-scripts/log.sh"

if ! echo "${IP_ADDR}" | grep -qE '^(([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,6}(:[0-9a-fA-F]{1,4}){1,6})$' ; then
  echo "IPv6 格式不正确: ${ipv6_addr}"
  ${LOG} "IPv6 格式不正确: ${ipv6_addr}"
  exit 1
fi

# 查找 ipset 的索引
ipset_index=$(uci show firewall | grep "firewall.@ipset\[[0-9]*\].name='${IPSET_NAME}'" | sed -n 's/.*@ipset\[\([0-9]*\)\].*/\1/p')
# 获取当前 uci 配置中的 IPv6 地址（entry）
if [ -n "${ipset_index}" ]; then
  # 获取当前ipset的ipv6地址
  ipv6_entries=$(uci -q get firewall.@ipset["${ipset_index}"].entry)
  # 如果与新的IPv6地址相同则跳过更新
  if [ "${ipv6_entries}" != "${IP_ADDR}" ]; then
    # 更新配置
    uci -q delete firewall.@ipset["${ipset_index}"].entry
    uci add_list firewall.@ipset["${ipset_index}"].entry="${IP_ADDR}"
    uci commit firewall
    /etc/init.d/firewall reload
    ${LOG} "ipset '${IPSET_NAME}' 地址已更新为：${IP_ADDR}"
    echo "ipset '${IPSET_NAME}' 地址已更新为：${IP_ADDR}"
  else
    # ${LOG} "ipset '${IPSET_NAME}' 地址未改变，跳过更新"
    echo "${IP_ADDR} 与IP集 '${IPSET_NAME}' 地址一致，跳过更新"
  fi
else
  ${LOG} "ipset '${IPSET_NAME}' 没有在UCI配置中找到。"
  exit 1
fi
exit 0