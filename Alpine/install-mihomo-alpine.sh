#!/bin/sh
# Alpine 3.23 旁路网关 + mihomo 一键安装脚本
set -e

# ============================================================================
# 全局变量定义
# ============================================================================

# 脚本信息
SCRIPT_NAME="install-mihomo-alpine.sh"
SCRIPT_VERSION="1.0.0"

# 系统配置变量
TIMEZONE="Asia/Shanghai"
LOCALE_TIMEZONE="/usr/share/zoneinfo/Asia/Shanghai"

# 网络配置变量
NETWORK_IFACE=""
NETWORK_TX_QUEUE_LEN=5000
NETWORK_RPS_SOCK_FLOW_ENTRIES=32768
NETWORK_NETDEV_MAX_BACKLOG=5000

# 系统资源限制
MAX_FILE_DESCRIPTORS=1048576
MAX_CONNTRACK=1048576
CONNTRACK_TIMEOUT=3600

# IPv6 连接跟踪配置
CONNTRACK_FRAG6_TIMEOUT=60
CONNTRACK_FRAG6_HIGH_THRESH=4194304

# ARP 缓存配置
NEIGH_GC_THRESH1=1024
NEIGH_GC_THRESH2=4096
NEIGH_GC_THRESH3=8192

# TCP 缓冲区配置
TCP_RMEM_MAX=16777216
TCP_WMEM_MAX=16777216
TCP_RMEM="4096 87380 16777216"
TCP_WMEM="4096 65536 16777216"

# TCP 超时配置
TCP_FIN_TIMEOUT=30
TCP_MAX_SYN_BACKLOG=4096

# mihomo 配置
MIHOMO_CONFIG_DIR="/etc/mihomo"
MIHOMO_LOG_DIR="/var/log/mihomo"
MIHOMO_BIN_PATH="/usr/local/bin/mihomo"
MIHOMO_PID_FILE="/run/mihomo.pid"
MIHOMO_LOG_FILE="/var/log/mihomo/mihomo.log"
MIHOMO_PORT=7890
MIHOMO_UI_PORT=9090
MIHOMO_DNS_PORT=53

# GitHub API 配置
GITHUB_API_URL="https://api.github.com/repos/MetaCubeX/mihomo/releases/latest"

# 系统架构映射
ARCH_MAP="x86_64:amd64 aarch64:arm64 armv7l:armv7 arm:armv7"

# 软件包列表
PACKAGES_BASE="curl iproute2 nftables openssh net-tools tzdata jq ca-certificates wget tcpdump htop iftop qemu-guest-agent ethtool"

# 内核模块列表
KERNEL_MODULES="tun br_netfilter nf_conntrack"

# 服务列表
SERVICES_BOOT="nftables"
SERVICES_DEFAULT="sshd mihomo crond qemu-guest-agent"

# 文件路径
ASSETS_DIR="./assets"
NFTABLES_CONFIG="/etc/nftables.nft"
SYSCTL_CONFIG="/etc/sysctl.d/99-network-gateway.conf"
SYSCTL_MULTIQUEUE_CONFIG="/etc/sysctl.d/99-network-multiqueue.conf"
IF_UP_DIR="/etc/network/if-up.d"
MIHOMO_SERVICE="/etc/init.d/mihomo"
LOGROTATE_CONFIG="/etc/logrotate.d/mihomo"

# ============================================================================
# 工具函数
# ============================================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

error_exit() {
    log "错误: $1"
    exit 1
}

check_root() {
    if [ "$(id -u)" != "0" ]; then
        error_exit "请使用root用户运行脚本！"
    fi
}

detect_network_interface() {
    log "检测网卡名称..."
    NETWORK_IFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -v '^lo$' | head -n 1)
    if [ -z "${NETWORK_IFACE}" ]; then
        error_exit "无法检测到网卡"
    fi
    log "检测到主网卡: ${NETWORK_IFACE}"
}

check_kernel_version() {
    log "检查内核版本..."
    local running_kernel=$(uname -r)
    local installed_kernel=""
    local pkg=""
    
    for pkg in linux-lts linux-virt; do
        installed_kernel=$(apk list "${pkg}" 2>/dev/null | grep "\[installed\]" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
        if [ -n "${installed_kernel}" ]; then
            break
        fi
    done
    
    if [ -n "${installed_kernel}" ]; then
        if ! echo "${running_kernel}" | grep -q "^${installed_kernel}"; then
            log "警告: 运行中的内核版本 (${running_kernel}) 与已安装的内核版本 (${installed_kernel}) 不匹配"
            log "请重启系统后再运行此脚本"
            exit 1
        fi
    fi
    log "内核版本检查通过: ${running_kernel}"
}

# ============================================================================
# 系统初始化函数
# ============================================================================

update_system() {
    log "更新系统并安装工具..."
    apk update
    apk upgrade
    apk add ${PACKAGES_BASE}
}

set_timezone() {
    log "设置时区..."
    ln -sf "${LOCALE_TIMEZONE}" /etc/localtime
    echo "${TIMEZONE}" > /etc/timezone
}

load_kernel_modules() {
    log "加载内核模块..."
    for module in ${KERNEL_MODULES}; do
        if ! lsmod | grep -q "^${module} "; then
            modprobe "${module}"
            grep -q "^${module}$" /etc/modules 2>/dev/null || echo "${module}" >> /etc/modules
            log "${module}模块已加载"
        fi
    done
}

check_network_multiqueue() {
    log "检查网卡多队列支持..."
    local queue_count=""
    
    if [ -d "/sys/class/net/${NETWORK_IFACE}/queues" ]; then
        queue_count=$(ls -d /sys/class/net/${NETWORK_IFACE}/queues/rx-* 2>/dev/null | wc -l)
        if [ "${queue_count}" -gt 1 ]; then
            log "检测到 ${queue_count} 个接收队列，开启多队列支持..."
            if [ ! -f "${SYSCTL_MULTIQUEUE_CONFIG}" ]; then
                cat <<EOF > "${SYSCTL_MULTIQUEUE_CONFIG}"
# 开启网卡多队列支持
net.core.rps_sock_flow_entries = ${NETWORK_RPS_SOCK_FLOW_ENTRIES}
# 增加网络设备接收队列长度
net.core.netdev_max_backlog = ${NETWORK_NETDEV_MAX_BACKLOG}
EOF
            fi
            log "网卡多队列配置完成"
        else
            log "该网卡不支持多队列或只有一个队列"
        fi
    else
        log "无法检查网卡队列信息"
    fi
}

# ============================================================================
# 网络配置函数
# ============================================================================

configure_nftables() {
    log "配置nftables防火墙..."
    local timestamp=""
    
    if [ -f "${NFTABLES_CONFIG}" ]; then
        timestamp=$(date '+%Y%m%d%H%M%S')
        mv "${NFTABLES_CONFIG}" "${NFTABLES_CONFIG}.bak.${timestamp}"
    fi
    
    if [ -f "${ASSETS_DIR}/nftables.conf" ]; then
        cp "${ASSETS_DIR}/nftables.conf" "${NFTABLES_CONFIG}"
        log "nftables配置文件复制完成"
    else
        log "警告: 未找到nftables配置文件 ${ASSETS_DIR}/nftables.conf"
        error_exit "无法配置nftables防火墙"
    fi
    
    # 安装 IPv6 网段更新脚本
    log "安装 IPv6 网段更新脚本..."
    if [ -f "${ASSETS_DIR}/update-ipv6-set" ]; then
        mkdir -p /etc/periodic/15min
        cp "${ASSETS_DIR}/update-ipv6-set" /etc/periodic/15min/
        chmod +x /etc/periodic/15min/update-ipv6-set
        log "IPv6 网段更新脚本安装完成"
    else
        log "警告: 未找到 IPv6 网段更新脚本 ${ASSETS_DIR}/update-ipv6-set"
    fi
}

configure_sysctl() {
    log "配置系统参数..."
    cat <<EOF > "${SYSCTL_CONFIG}"
# --- 基础转发与核心设置 ---
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
# 确保即使开启转发也能接受 IPv6 路由通告
net.ipv6.conf.all.accept_ra = 2
net.ipv6.conf.default.accept_ra = 2
net.ipv6.conf.${NETWORK_IFACE}.accept_ra = 2

# --- 旁路网关关键：禁用重定向 (强制流量过代理) ---
# 防止网关把流量甩回给 ROS，解决掉线和绕过问题
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
# 如果有特定网卡（如 eth0），建议显式指定
net.ipv4.conf.${NETWORK_IFACE}.send_redirects = 0
net.ipv4.conf.${NETWORK_IFACE}.accept_redirects = 0

# --- 拥塞控制与队列优化 ---
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3

# --- 缓冲区与内存优化 ---
net.core.rmem_max = ${TCP_RMEM_MAX}
net.core.wmem_max = ${TCP_WMEM_MAX}
net.ipv4.tcp_rmem = ${TCP_RMEM}
net.ipv4.tcp_wmem = ${TCP_WMEM}

# --- 连接跟踪与并发优化 ---
# 提高最大文件句柄，防止并发过高时报错
fs.nr_open = ${MAX_FILE_DESCRIPTORS}
fs.file-max = ${MAX_FILE_DESCRIPTORS}

# 调大内核连接跟踪表（旁路网关处理全家流量时很重要）
net.netfilter.nf_conntrack_max = ${MAX_CONNTRACK}
net.netfilter.nf_conntrack_tcp_timeout_established = ${CONNTRACK_TIMEOUT}

# IPv6 连接跟踪
net.netfilter.nf_conntrack_frag6_timeout = ${CONNTRACK_FRAG6_TIMEOUT}
net.netfilter.nf_conntrack_frag6_high_thresh = ${CONNTRACK_FRAG6_HIGH_THRESH}

# --- 网络安全与稳定性 ---
# 允许 ICMP 流量
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# 防止 ARP 缓存溢出
net.ipv4.neigh.default.gc_thresh1 = ${NEIGH_GC_THRESH1}
net.ipv4.neigh.default.gc_thresh2 = ${NEIGH_GC_THRESH2}
net.ipv4.neigh.default.gc_thresh3 = ${NEIGH_GC_THRESH3}
net.ipv4.tcp_max_syn_backlog = ${TCP_MAX_SYN_BACKLOG}
net.ipv4.tcp_syncookies = 1
# 减少处于 FIN-WAIT-2 状态的时间，快速回收端口
net.ipv4.tcp_fin_timeout = ${TCP_FIN_TIMEOUT}
# 开启重用，应对大量短连接
net.ipv4.tcp_tw_reuse = 2
EOF
    sysctl -p "${SYSCTL_CONFIG}"
}

install_network_optimization_script() {
    log "安装网络优化脚本..."
    if [ -f "${ASSETS_DIR}/network-optimization" ]; then
        mkdir -p "${IF_UP_DIR}"
        cp "${ASSETS_DIR}/network-optimization" "${IF_UP_DIR}/network-optimization"
        chmod +x "${IF_UP_DIR}/network-optimization"
        log "网络优化脚本安装完成"
    else
        log "警告: 未找到网络优化脚本 ${ASSETS_DIR}/network-optimization"
    fi
}

# ============================================================================
# mihomo 安装函数
# ============================================================================
download_mihomo() {
    log "检测系统架构..."
    local arch=$(uname -m)
    local mihomo_arch=""
    local sys_arch=""
    local release_info=$(wget -qO- "${GITHUB_API_URL}")
    local version=$(echo "${release_info}" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
    local file_name=""
    local download_url=""
    
    for mapping in ${ARCH_MAP}; do
        sys_arch=$(echo "${mapping}" | cut -d':' -f1)
        mihomo_arch=$(echo "${mapping}" | cut -d':' -f2)
        if [ "${arch}" = "${sys_arch}" ]; then
            break
        fi
    done
    
    if [ -z "${mihomo_arch}" ]; then
        error_exit "不支持的架构: ${arch}"
    fi
    
    log "检测到系统架构: ${arch} (mihomo: ${mihomo_arch})"

    if [ -z "${version}" ]; then
        error_exit "无法获取版本信息"
    fi
    log "最新版本: ${version}"
    if [ "${mihomo_arch}" = "amd64" ]; then
        if grep -q "avx2" /proc/cpuinfo; then
            file_name="mihomo-linux-${mihomo_arch}-v3-${version}.gz"
        elif grep -q "avx" /proc/cpuinfo; then
            file_name="mihomo-linux-${mihomo_arch}-v2-${version}.gz"
        else
            file_name="mihomo-linux-${mihomo_arch}-v1-${version}.gz"
        fi
    else
        file_name="mihomo-linux-${mihomo_arch}-${version}.gz"
    fi
    download_url=$(echo "${release_info}" | grep "browser_download_url" | grep "${file_name}" | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/')
    if [ -z "${download_url}" ]; then
        error_exit "无法找到下载链接"
    fi
    log "下载链接: ${download_url}"
    
    cd /tmp
    wget -O mihomo.gz "${download_url}"
    gunzip -c mihomo.gz > "${MIHOMO_BIN_PATH}"
    chmod +x "${MIHOMO_BIN_PATH}"
    rm -f mihomo.gz
    
    local installed_version=$("${MIHOMO_BIN_PATH}" -v | head -n 1)
    log "mihomo安装成功: ${installed_version}"
}

install_mihomo_service() {
    log "安装mihomo服务..."
    if [ -f "${ASSETS_DIR}/mihomo-service" ]; then
        cp "${ASSETS_DIR}/mihomo-service" "${MIHOMO_SERVICE}"
        chmod +x "${MIHOMO_SERVICE}"
        log "mihomo服务安装完成"
    else
        log "警告: 未找到mihomo服务脚本 ${ASSETS_DIR}/mihomo-service"
    fi
    
    # 确保配置文件存在
    if [ ! -f "${MIHOMO_CONFIG_DIR}/config.yaml" ]; then
        log "配置文件不存在，正在添加..."
        if [ -f "${ASSETS_DIR}/config.yaml" ]; then
            mkdir -p "${MIHOMO_CONFIG_DIR}"
            cp "${ASSETS_DIR}/config.yaml" "${MIHOMO_CONFIG_DIR}/"
            log "mihomo配置文件添加完成"
        else
            log "警告: 未找到mihomo配置文件 ${ASSETS_DIR}/config.yaml"
        fi
    fi
}

create_logrotate_config() {
    log "创建日志轮转配置..."
    cat <<EOF > "${LOGROTATE_CONFIG}"
${MIHOMO_LOG_DIR}/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
EOF
}

# ============================================================================
# 服务管理函数
# ============================================================================

configure_services() {
    log "配置服务启动项..."
    for service in ${SERVICES_BOOT}; do
        rc-update add "${service}" boot
    done
    for service in ${SERVICES_DEFAULT}; do
        rc-update add "${service}" default
    done
}

start_services() {
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
}

# ============================================================================
# 主函数
# ============================================================================

main() {
    log "=========================================="
    log "Alpine 3.23 旁路网关 + mihomo 安装脚本"
    log "版本: ${SCRIPT_VERSION}"
    log "=========================================="
    
    # 错误处理
    trap 'log "脚本执行出错，退出码: $?"' ERR
    
    # 检查root权限
    check_root
    
    # 系统检测
    check_kernel_version
    detect_network_interface
    
    # 系统初始化
    update_system
    set_timezone
    load_kernel_modules
    check_network_multiqueue
    
    # 网络配置
    configure_nftables
    configure_sysctl
    install_network_optimization_script
    
    # mihomo 安装
    download_mihomo
    install_mihomo_service
    create_logrotate_config
    
    # 服务配置
    configure_services
    start_services
    
    # 完成信息
    log "=========================================="
    log "安装完成！"
    log "配置文件: ${MIHOMO_CONFIG_DIR}/config.yaml"
    log "Web UI: http://<服务器IP>:${MIHOMO_UI_PORT}/ui"
    log "=========================================="
    log "管理命令:"
    log "  启动: rc-service mihomo start"
    log "  停止: rc-service mihomo stop"
    log "  重启: rc-service mihomo restart"
    log "  状态: rc-service mihomo status"
    log "=========================================="
    
    exit 0
}

# 执行主函数
main "$@"
