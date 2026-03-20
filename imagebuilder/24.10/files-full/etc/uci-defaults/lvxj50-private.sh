#!/bin/sh
# 自用镜像私有配置，注意：不要提交此文件到git公开仓库
# 配置wan口
# 配置为pppoe
uci set network.wan.proto='pppoe'
uci set network.wan.keepalive='5 5'
# 提交修改
uci commit network
# 如果已安装 upnp 模块并存在配置文件，则启用 upnp 功能
if opkg list-installed | grep -q '^luci-app-upnp'; then
  if uci get upnpd.config.enabled >/dev/null 2>&1; then
    uci set upnpd.config.enabled='1'
    uci commit upnpd
    # upnp是自定义安装应用需自行重启
    /etc/init.d/upnpd restart
  else
    echo "upnpd 已安装但未检测到配置节，可能需要初始化配置文件。"
  fi
else
  echo "未安装 upnp 模块（luci-app-upnp），跳过启用。"
fi
# 加速模式切换为软件模式，x86硬件不支持硬件加速
# 好像不删除开启硬件加速也没有影响，暂时不修改