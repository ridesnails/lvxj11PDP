#!/bin/sh

IPSET_NAME="ipv6-for-webserver"
RULE_NAME="Allow-ipv6-for-webserver"
DEST_PORT="8888 8889"
UPDATE_SCRIPT="/etc/custom-scripts/update-ipv6-for-webserver-ipset.sh"
CRON_TASK="*/5 * * * * ${UPDATE_SCRIPT}"

# 1. 创建 ipset（如果不存在）
if ! uci show firewall | grep -q "firewall.@ipset.*name='${IPSET_NAME}'"; then
  uci add firewall ipset
  uci set firewall.@ipset[-1].name="${IPSET_NAME}"
  uci set firewall.@ipset[-1].family='ipv6'
  uci set firewall.@ipset[-1].timeout='86400'
  uci add_list firewall.@ipset[-1].match='dest_ip'
fi

# 2. 创建防火墙规则（如果不存在）
if ! uci show firewall | grep -q "firewall.@rule.*name='${RULE_NAME}'"; then
  uci add firewall rule
  uci set firewall.@rule[-1].name="${RULE_NAME}"
  uci set firewall.@rule[-1].src='wan'
  uci set firewall.@rule[-1].dest='lan'
  uci set firewall.@rule[-1].dest_port="${DEST_PORT}"
  uci set firewall.@rule[-1].proto='tcp'
  uci set firewall.@rule[-1].family='ipv6'
  uci set firewall.@rule[-1].target='ACCEPT'
  uci set firewall.@rule[-1].ipset="${IPSET_NAME}"
fi

# 3. 应用防火墙配置
uci commit firewall
# /etc/init.d/firewall restart

# 4. 更新脚本赋权
[ -f "${UPDATE_SCRIPT}" ] && chmod +x "${UPDATE_SCRIPT}"

# 5. 添加 cron 定时任务（如未添加过）
if ! crontab -l 2>/dev/null | grep -Fq "${CRON_TASK}"; then
  ( crontab -l 2>/dev/null; echo "${CRON_TASK}" ) | crontab -
fi

# 6. 标记脚本执行成功（uci-defaults 专用）
exit 0
