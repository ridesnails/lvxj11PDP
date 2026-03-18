#!/bin/sh
# Alpine 3.23 旁路网关 + mihomo 一键安装脚本
set -e

# ============================================================================
# 全局变量定义
# ============================================================================

# 脚本信息
SCRIPT_NAME="install-mihomo-alpine.sh"
SCRIPT_VERSION="1.2.0"

# 系统配置变量
TIMEZONE="Asia/Shanghai"
LOCALE_TIMEZONE="/usr/share/zoneinfo/Asia/Shanghai"

# 网络配置变量
NETWORK_IFACE=""

# mihomo 配置
MIHOMO_CONFIG_DIR="/etc/mihomo"
MIHOMO_BIN_PATH="/usr/local/bin/mihomo"

# GitHub API 配置
GITHUB_API_URL="https://api.github.com/repos/MetaCubeX/mihomo/releases/latest"

# 系统架构映射
ARCH_MAP="x86_64:amd64 aarch64:arm64 armv7l:armv7 arm:armv7"

# 软件包列表
PACKAGES_BASE="curl iproute2 nftables openssh net-tools tzdata jq ca-certificates wget tcpdump htop iftop qemu-guest-agent ethtool radvd"

# 内核模块列表
KERNEL_MODULES="tun br_netfilter nf_conntrack"

# 服务列表
SERVICES_BOOT="nftables"
SERVICES_DEFAULT="sshd mihomo crond qemu-guest-agent radvd"

# 文件路径
ASSETS_DIR="./assets"
SYSCTL_CONFIG="/etc/sysctl.d/99-network-gateway.conf"
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

# ============================================================================
# 网络配置函数
# ============================================================================

configure_nftables() {
    log "配置nftables防火墙..."
    local timestamp=""
    local nftables_config="/etc/nftables.nft"
    
    if [ -f "${nftables_config}" ]; then
        timestamp=$(date '+%Y%m%d%H%M%S')
        mv "${nftables_config}" "${nftables_config}.bak.${timestamp}"
    fi
    
    if [ -f "${ASSETS_DIR}/nftables.conf" ]; then
        cp "${ASSETS_DIR}/nftables.conf" "${nftables_config}"
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
    if [ -f "${ASSETS_DIR}/sysctl.conf.template" ]; then
        if [ "${NETWORK_IFACE}" != "eth0" ] && [ -n "${NETWORK_IFACE}" ]; then
            log "检测到网卡为 ${NETWORK_IFACE}，替换配置中的网卡名称..."
            sed "s/eth0/${NETWORK_IFACE}/g" "${ASSETS_DIR}/sysctl.conf.template" > "${SYSCTL_CONFIG}"
        else
            log "使用默认网卡 eth0 配置..."
            cp "${ASSETS_DIR}/sysctl.conf.template" "${SYSCTL_CONFIG}"
        fi
        log "系统参数配置文件复制完成"
    else
        log "警告: 未找到系统参数配置模板 ${ASSETS_DIR}/sysctl.conf.template"
        error_exit "无法配置系统参数"
    fi
    sysctl -p "${SYSCTL_CONFIG}"
}

install_network_optimization_script() {
    log "安装网络优化脚本..."
    local if_up_dir="/etc/network/if-up.d"
    if [ -f "${ASSETS_DIR}/network-optimization" ]; then
        mkdir -p "${if_up_dir}"
        cp "${ASSETS_DIR}/network-optimization" "${if_up_dir}/network-optimization"
        chmod +x "${if_up_dir}/network-optimization"
        log "网络优化脚本安装完成"
    else
        log "警告: 未找到网络优化脚本 ${ASSETS_DIR}/network-optimization"
    fi
}

configure_radvd() {
    log "配置 radvd 服务..."
    local radvd_config="/etc/radvd.conf"
    local ula_address=""
    local link_local_address=""
    
    # 检测 ULA 地址 (fc00::/7)
    ula_address=$(ip -6 addr show dev "${NETWORK_IFACE}" scope global | grep -E 'fd00:' | head -n 1 | awk '{print $2}' | cut -d'/' -f1)
    
    # 如果没有 ULA 地址，使用 link-local 地址
    if [ -z "${ula_address}" ]; then
        link_local_address=$(ip -6 addr show dev "${NETWORK_IFACE}" scope link | grep -E 'fe80::' | head -n 1 | awk '{print $2}' | cut -d'/' -f1)
        if [ -z "${link_local_address}" ]; then
            log "警告: 未找到 IPv6 地址，跳过 radvd 配置"
            return
        fi
        ula_address="${link_local_address}"
        log "未找到 ULA 地址，使用 link-local 地址: ${ula_address}"
    else
        log "找到 ULA 地址: ${ula_address}"
    fi
    
    # 生成配置文件
    if [ -f "${ASSETS_DIR}/radvd.conf.template" ]; then
        # 替换网卡名称和 IPv6 地址
        sed -e "s/eth0/${NETWORK_IFACE}/g" \
            -e "s/fe80::abc:123/${ula_address}/g" \
            "${ASSETS_DIR}/radvd.conf.template" > "${radvd_config}"
        log "radvd 配置文件生成完成"
        
        # 启动服务
        rc-update add radvd default 2>/dev/null || true
        rc-service radvd start 2>/dev/null || true
        log "radvd 服务配置完成"
    else
        log "警告: 未找到 radvd 配置模板 ${ASSETS_DIR}/radvd.conf.template，跳过 radvd 配置"
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
    if [ -f "${ASSETS_DIR}/logrotate.conf.template" ]; then
        cp "${ASSETS_DIR}/logrotate.conf.template" "${LOGROTATE_CONFIG}"
        log "日志轮转配置文件复制完成"
    else
        log "警告: 未找到日志轮转配置模板 ${ASSETS_DIR}/logrotate.conf.template，跳过日志轮转配置"
    fi
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
    
    # 网络配置
    configure_nftables
    configure_sysctl
    install_network_optimization_script
    configure_radvd
    
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
