#!/bin/sh
# Alpine 3.23 旁路网关 + mihomo 一键安装脚本
set -e

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

trap 'log "脚本执行出错，退出码: $?"' ERR

if [ "$(id -u)" != "0" ]; then
    log "请使用root用户运行脚本！"
    exit 1
fi

# 检查内核版本是否匹配
log "检查内核版本..."
RUNNING_KERNEL=$(uname -r)
INSTALLED_KERNEL=""
for pkg in linux-lts linux-virt; do
    INSTALLED_KERNEL=$(apk list "$pkg" 2>/dev/null | grep "\[installed\]" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
    if [ -n "$INSTALLED_KERNEL" ]; then
        break
    fi
done

if [ -n "$INSTALLED_KERNEL" ]; then
    if ! echo "$RUNNING_KERNEL" | grep -q "^$INSTALLED_KERNEL"; then
        log "警告: 运行中的内核版本 ($RUNNING_KERNEL) 与已安装的内核版本 ($INSTALLED_KERNEL) 不匹配"
        log "请重启系统后再运行此脚本"
        exit 1
    fi
fi
log "内核版本检查通过: $RUNNING_KERNEL"

# 检测主网卡名称
log "检测网卡名称..."
PRIMARY_IFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -v '^lo$' | head -n 1)
if [ -z "$PRIMARY_IFACE" ]; then
    log "错误: 无法检测到网卡"
    exit 1
fi
log "检测到主网卡: $PRIMARY_IFACE"

# 获取系统架构
ARCH=$(uname -m)
case "$ARCH" in
    x86_64) MIHOMO_ARCH="amd64" ;;
    aarch64|arm64) MIHOMO_ARCH="arm64" ;;
    armv7l|arm) MIHOMO_ARCH="armv7" ;;
    *) log "不支持的架构: $ARCH"; exit 1 ;;
esac
log "检测到系统架构: $ARCH (mihomo: $MIHOMO_ARCH)"

# 更新系统并安装工具
log "更新系统并安装工具..."
apk update
apk upgrade
apk add curl iproute2 nftables openssh net-tools tzdata jq ca-certificates wget tcpdump htop iftop qemu-guest-agent

# 设置时区
log "设置时区..."
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
echo "Asia/Shanghai" > /etc/timezone

# 配置SSH允许root登录
# log "配置SSH..."
# if ! grep -q "^PermitRootLogin" /etc/ssh/sshd_config; then
#     echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
# fi

# 加载TUN内核模块
log "加载TUN内核模块..."
if ! lsmod | grep -q "^tun "; then
    modprobe tun
    grep -q "^tun$" /etc/modules 2>/dev/null || echo "tun" >> /etc/modules
fi
log "TUN模块已加载"

# 配置nftables
log "配置nftables防火墙..."
if [ -f "/etc/nftables.nft" ]; then
    TIMESTAMP=$(date '+%Y%m%d%H%M%S')
    mv /etc/nftables.nft "/etc/nftables.nft.bak.$TIMESTAMP"
fi

cat <<EOF > /etc/nftables.nft
table inet filter {
    # 允许的本地ipv4网段
    set local_ipv4_list {
        type ipv4_addr
        flags interval
        # 10.0.0.0/8:  私网 A 类
        # 172.16.0.0/12: 私网 B 类
        # 192.168.0.0/16: 私网 C 类
        elements = { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 }
    }
    # 允许的本地IPv6网段
    set local_ipv6_list {
        type ipv6_addr
        flags interval, timeout
        # fe80::/10: 链路本地地址 (Link-Local, 只有这个通了 RA 才会生效)
        # fc00::/7:  唯一本地地址 (ULA, 类似 IPv4 的私网地址)
        elements = { fe80::/10, fc00::/7 }
    }
    chain input {
        type filter hook input priority 0; policy drop;

        # 1. 允许本地回环 (lo)
        iif "lo" accept

        # 2. 允许已建立和相关的连接 (保证请求的回程包正常)
        ct state established,related accept

        # 3. 放行所有 ICMPv6 (涵盖了 RA, NS, NA, Ping 等所有必要协议)
        ip6 nexthdr icmpv6 accept

        # 4. 允许所有本地 IPv4 私网网段
        ip saddr @local_ipv4_list accept

        # 5. 允许所有本地 IPv6 私网与本地链路网段
        ip6 saddr @local_ipv6_list accept
    }
    chain forward {
        type filter hook forward priority 0; policy accept;
    }
    chain output {
        type filter hook output priority 0; policy accept;
    }
}
EOF

# 配置sysctl
log "配置系统参数..."
cat <<EOF > /etc/sysctl.d/99-network-gateway.conf
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.all.accept_ra = 2
net.ipv6.conf.$PRIMARY_IFACE.accept_ra = 2
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_syncookies = 1
fs.nr_open = 1048576
EOF
sysctl -p /etc/sysctl.d/99-network-gateway.conf

# 获取mihomo最新版本
log "获取mihomo最新版本..."
GITHUB_API_URL="https://api.github.com/repos/MetaCubeX/mihomo/releases/latest"
RELEASE_INFO=$(wget -qO- "$GITHUB_API_URL")
VERSION=$(echo "$RELEASE_INFO" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')

if [ -z "$VERSION" ]; then
    log "无法获取版本信息"
    exit 1
fi
log "最新版本: $VERSION"

# 检测CPU指令集等级（仅AMD64）
if [ "$MIHOMO_ARCH" = "amd64" ]; then
    if grep -q "avx2" /proc/cpuinfo; then
        CPU_LEVEL="v3"
    elif grep -q "avx" /proc/cpuinfo; then
        CPU_LEVEL="v2"
    else
        CPU_LEVEL="v1"
    fi
    log "CPU指令集等级: $CPU_LEVEL"
else
    CPU_LEVEL="compatible"
fi

# 下载mihomo
DOWNLOAD_URL=$(echo "$RELEASE_INFO" | grep "browser_download_url" | grep "linux-$MIHOMO_ARCH-$CPU_LEVEL-$VERSION.gz" | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/')

if [ -z "$DOWNLOAD_URL" ]; then
    log "无法找到下载链接"
    exit 1
fi
log "下载链接: $DOWNLOAD_URL"

log "下载mihomo..."
cd /tmp
wget -O mihomo.gz "$DOWNLOAD_URL"
gunzip -c mihomo.gz > /usr/local/bin/mihomo
chmod +x /usr/local/bin/mihomo
rm -f mihomo.gz

INSTALLED_VERSION=$(/usr/local/bin/mihomo -v | head -n 1)
log "mihomo安装成功: $INSTALLED_VERSION"

# 创建配置目录
mkdir -p /etc/mihomo
mkdir -p /var/lib/mihomo
mkdir -p /var/log/mihomo

# 创建默认配置（如果不存在）
if [ ! -f "/etc/mihomo/config.yaml" ]; then
    log "创建默认配置..."
    cat <<'EOF' > /etc/mihomo/config.yaml
mixed-port: 7890
allow-lan: true
bind-address: "*"
mode: rule
log-level: info
external-controller: 0.0.0.0:9090
external-ui: ui
external-ui-name: Zashboard
external-ui-url: https://gh-proxy.com/https://github.com/Zephyruso/zashboard/releases/latest/download/dist-cdn-fonts.zip

dns:
  enable: true
  ipv6: true
  listen: 0.0.0.0:53
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  nameserver:
    - 223.5.5.5
    - 119.29.29.29

proxies: []
proxy-groups:
  - name: "Proxy"
    type: select
    proxies:
      - DIRECT

rules:
  - GEOIP,CN,DIRECT
  - MATCH,Proxy
EOF
fi

# 创建OpenRC服务
log "创建mihomo服务..."
cat <<'EOF' > /etc/init.d/mihomo
#!/sbin/openrc-run
name="mihomo"
description="Mihomo Proxy Service"
command="/usr/local/bin/mihomo"
command_args="-d /etc/mihomo"
command_background=true
pidfile="/run/mihomo.pid"
output_log="/var/log/mihomo/mihomo.log"
error_log="/var/log/mihomo/mihomo.log"

depend() {
    need net
    after firewall
    use logger
}

start_pre() {
    checkpath --directory --mode 0755 /run/mihomo
    checkpath --directory --mode 0755 /var/lib/mihomo
    checkpath --directory --mode 0755 /var/log/mihomo
}
EOF
chmod +x /etc/init.d/mihomo

# 创建日志轮转配置
cat <<EOF > /etc/logrotate.d/mihomo
/var/log/mihomo/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
EOF

# 配置并启动服务
log "配置服务启动项..."
rc-update add nftables boot
rc-update add sshd default
rc-update add mihomo default
rc-update add crond default
rc-update add qemu-guest-agent default

log "启动服务..."
rc-service nftables restart
rc-service sshd restart
rc-service qemu-guest-agent start
rc-service mihomo start

sleep 2
if rc-service mihomo status | grep -q "started"; then
    log "mihomo服务启动成功"
else
    log "mihomo服务启动失败，请检查日志"
fi

log "=========================================="
log "安装完成！"
log "配置文件: /etc/mihomo/config.yaml"
log "Web UI: http://<服务器IP>:9090/ui"
log "=========================================="
log "管理命令:"
log "  启动: rc-service mihomo start"
log "  停止: rc-service mihomo stop"
log "  重启: rc-service mihomo restart"
log "  状态: rc-service mihomo status"
log "=========================================="

exit 0
