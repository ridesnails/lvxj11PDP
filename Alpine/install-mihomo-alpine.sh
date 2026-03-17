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
    if [ -n "${INSTALLED_KERNEL}" ]; then
        break
    fi
done

if [ -n "${INSTALLED_KERNEL}" ]; then
    if ! echo "${RUNNING_KERNEL}" | grep -q "^${INSTALLED_KERNEL}"; then
        log "警告: 运行中的内核版本 (${RUNNING_KERNEL}) 与已安装的内核版本 (${INSTALLED_KERNEL}) 不匹配"
        log "请重启系统后再运行此脚本"
        exit 1
    fi
fi
log "内核版本检查通过: ${RUNNING_KERNEL}"

# 检测主网卡名称
log "检测网卡名称..."
PRIMARY_IFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -v '^lo$' | head -n 1)
if [ -z "${PRIMARY_IFACE}" ]; then
    log "错误: 无法检测到网卡"
    exit 1
fi
log "检测到主网卡: ${PRIMARY_IFACE}"

# 检查并开启网卡多队列
log "检查网卡多队列支持..."
if [ -d "/sys/class/net/${PRIMARY_IFACE}/queues" ]; then
    QUEUE_COUNT=$(ls -d /sys/class/net/${PRIMARY_IFACE}/queues/rx-* 2>/dev/null | wc -l)
    if [ "${QUEUE_COUNT}" -gt 1 ]; then
        log "检测到 ${QUEUE_COUNT} 个接收队列，开启多队列支持..."
        # 持久化配置
        if [ ! -f "/etc/sysctl.d/99-network-multiqueue.conf" ]; then
            cat <<EOF > /etc/sysctl.d/99-network-multiqueue.conf
# 开启网卡多队列支持
net.core.rps_sock_flow_entries = 32768
# 增加网络设备接收队列长度
net.core.netdev_max_backlog = 5000
EOF
        fi
        log "网卡多队列配置完成"
    else
        log "该网卡不支持多队列或只有一个队列"
    fi
else
    log "无法检查网卡队列信息"
fi

# 创建 if-up.d 网络优化脚本
log "创建网络接口启动优化脚本..."
mkdir -p /etc/network/if-up.d
cat <<EOF > /etc/network/if-up.d/network-optimization
#!/bin/sh

# 跳过回环接口
if [ "\$IFACE" = "lo" ]; then
    exit 0
fi

# 等待网卡就绪
sleep 2

# 检查队列是否存在
if [ -d "/sys/class/net/\$IFACE/queues" ]; then
    # 自动检测 CPU 核心数
    CPU_COUNT=\$(nproc)
    # 使用全部核心
    # 生成对应的十六进制掩码
    MASK=\$(printf "%x" \$(( (1 << \$CPU_COUNT) - 1 )))
    
    # 开启 RPS (让所有 CPU 核心都能处理中断)
    for queue in /sys/class/net/\$IFACE/queues/rx-*; do
        if [ -f "\$queue/rps_cpus" ]; then
            # 启用对应 CPU 核心
            echo "\$MASK" > "\$queue/rps_cpus"
        fi
        if [ -f "\$queue/rps_flow_cnt" ]; then
            # 开启 RFS (分配 16384 流)
            echo "16384" > "\$queue/rps_flow_cnt"
        fi
    done
    
    # 额外优化：增大发送队列长度
    ip link set \$IFACE txqueuelen 5000
    
    # 启用网络卸载功能
    ethtool -K \$IFACE gro on 2>/dev/null || true
    ethtool -K \$IFACE gso on 2>/dev/null || true
    ethtool -K \$IFACE tso on 2>/dev/null || true
    ethtool -K \$IFACE tx on 2>/dev/null || true
    ethtool -K \$IFACE rx on 2>/dev/null || true
    
    echo "Network optimization applied to \$IFACE"
fi
EOF
chmod +x /etc/network/if-up.d/network-optimization
log "网络接口启动优化脚本创建完成"

# 获取系统架构
ARCH=$(uname -m)
case "${ARCH}" in
    x86_64) MIHOMO_ARCH="amd64" ;;
    aarch64|arm64) MIHOMO_ARCH="arm64" ;;
    armv7l|arm) MIHOMO_ARCH="armv7" ;;
    *) log "不支持的架构: ${ARCH}"; exit 1 ;;
esac
log "检测到系统架构: ${ARCH} (mihomo: ${MIHOMO_ARCH})"

# 更新系统并安装工具
log "更新系统并安装工具..."
apk update
apk upgrade
apk add curl iproute2 nftables openssh net-tools tzdata jq ca-certificates wget tcpdump htop iftop qemu-guest-agent ethtool

# 设置时区
log "设置时区..."
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
echo "Asia/Shanghai" > /etc/timezone

# 加载TUN内核模块
log "加载TUN内核模块..."
if ! lsmod | grep -q "^tun "; then
    modprobe tun
    grep -q "^tun$" /etc/modules 2>/dev/null || echo "tun" >> /etc/modules
fi
log "TUN模块已加载"

# 加载br_netfilter模块（用于网络命名空间和容器支持）
log "加载br_netfilter模块..."
if ! lsmod | grep -q "^br_netfilter "; then
    modprobe br_netfilter
    grep -q "^br_netfilter$" /etc/modules 2>/dev/null || echo "br_netfilter" >> /etc/modules
fi
log "br_netfilter模块已加载"

# 加载nf_conntrack模块（用于连接跟踪）
log "加载nf_conntrack模块..."
if ! lsmod | grep -q "^nf_conntrack "; then
    modprobe nf_conntrack
    grep -q "^nf_conntrack$" /etc/modules 2>/dev/null || echo "nf_conntrack" >> /etc/modules
fi
log "nf_conntrack模块已加载"

# 配置nftables
log "配置nftables防火墙..."
if [ -f "/etc/nftables.nft" ]; then
    TIMESTAMP=$(date '+%Y%m%d%H%M%S')
    mv /etc/nftables.nft "/etc/nftables.nft.bak.${TIMESTAMP}"
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

        # 1. 允许本地回环
        iif "lo" accept

        # 2. 允许已建立和相关的连接
        ct state established,related accept

        # 3. 丢弃无效连接
        ct state invalid drop

        # 4. 放行所有 ICMPv6
        ip6 nexthdr icmpv6 accept

        # 5. 允许所有本地 IPv4 私网网段
        ip saddr @local_ipv4_list accept

        # 6. 允许所有本地 IPv6 私网与本地链路网段
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
# --- 基础转发与核心设置 ---
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
# 确保即使开启转发也能接受 IPv6 路由通告
net.ipv6.conf.all.accept_ra = 2
net.ipv6.conf.default.accept_ra = 2
net.ipv6.conf.${PRIMARY_IFACE}.accept_ra = 2

# --- 旁路网关关键：禁用重定向 (强制流量过代理) ---
# 防止网关把流量甩回给 ROS，解决掉线和绕过问题
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
# 如果有特定网卡（如 eth0），建议显式指定
net.ipv4.conf.${PRIMARY_IFACE}.send_redirects = 0
net.ipv4.conf.${PRIMARY_IFACE}.accept_redirects = 0

# --- 拥塞控制与队列优化 ---
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3

# --- 缓冲区与内存优化 ---
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# --- 连接跟踪与并发优化 ---
# 提高最大文件句柄，防止并发过高时报错
fs.nr_open = 1048576
fs.file-max = 1048576

# 调大内核连接跟踪表（旁路网关处理全家流量时很重要）
net.netfilter.nf_conntrack_max = 1048576
net.netfilter.nf_conntrack_tcp_timeout_established = 3600

# IPv6 连接跟踪
net.netfilter.nf_conntrack_frag6_timeout = 60
net.netfilter.nf_conntrack_frag6_high_thresh = 262144

# --- 网络安全与稳定性 ---
# 允许 ICMP 流量
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# 防止 ARP 缓存溢出
net.ipv4.neigh.default.gc_thresh1 = 1024
net.ipv4.neigh.default.gc_thresh2 = 4096
net.ipv4.neigh.default.gc_thresh3 = 8192
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_syncookies = 1
# 减少处于 FIN-WAIT-2 状态的时间，快速回收端口
net.ipv4.tcp_fin_timeout = 30
# 开启重用，应对大量短连接
net.ipv4.tcp_tw_reuse = 1
EOF
sysctl -p /etc/sysctl.d/99-network-gateway.conf

# 获取mihomo最新版本
log "获取mihomo最新版本..."
GITHUB_API_URL="https://api.github.com/repos/MetaCubeX/mihomo/releases/latest"
RELEASE_INFO=$(wget -qO- "${GITHUB_API_URL}")
VERSION=$(echo "${RELEASE_INFO}" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')

if [ -z "${VERSION}" ]; then
    log "无法获取版本信息"
    exit 1
fi
log "最新版本: ${VERSION}"

# 检测CPU指令集等级（仅AMD64）
if [ "${MIHOMO_ARCH}" = "amd64" ]; then
    if grep -q "avx2" /proc/cpuinfo; then
        FILE_NAME="mihomo-linux-${MIHOMO_ARCH}-v3-${VERSION}.gz"
    elif grep -q "avx" /proc/cpuinfo; then
        FILE_NAME="mihomo-linux-${MIHOMO_ARCH}-v2-${VERSION}.gz"
    else
        FILE_NAME="mihomo-linux-${MIHOMO_ARCH}-v1-${VERSION}.gz"
    fi
else
    FILE_NAME="mihomo-linux-${MIHOMO_ARCH}-${VERSION}.gz"
fi

# 下载mihomo
DOWNLOAD_URL=$(echo "${RELEASE_INFO}" | grep "browser_download_url" | grep "${FILE_NAME}" | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/')

if [ -z "${DOWNLOAD_URL}" ]; then
    log "无法找到下载链接"
    exit 1
fi
log "下载链接: ${DOWNLOAD_URL}"

log "下载mihomo..."
cd /tmp
wget -O mihomo.gz "${DOWNLOAD_URL}"
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

dns:
  enable: true
  listen: 0.0.0.0:53
  nameserver:
    - 223.5.5.5

proxies: []
proxy-groups:
  - name: "Proxy"
    type: select
    proxies:
      - DIRECT

rules:
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
    # 设置最大文件描述符数
    ulimit -n 1048576
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
