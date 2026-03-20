#!/bin/sh

DOMAIN="tj.lvxj11.top"
IPSET_NAME="ipv6-for-webserver"

# 获取当前解析的 IPv6 地址
domain_ipv6_addr=$(nslookup "${DOMAIN}" "223.5.5.5" | awk '/^Address: / { ip=$2 } END { print ip }')

# 添加到数据集
/etc/custom-scripts/update-ipset.sh "${IPSET_NAME}" "${domain_ipv6_addr}"
if [ $? -eq 0 ]; then
  echo "IPv6 address ${domain_ipv6_addr} 已添加到 ${IPSET_NAME}"
else
  echo "IPv6 address ${domain_ipv6_addr} 向IP集 ${IPSET_NAME} 添加失败"
fi

exit 0