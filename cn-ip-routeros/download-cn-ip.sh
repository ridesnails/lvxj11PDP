#!/usr/bin/env bash

set -euo pipefail

CN_LIST_URL="https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geoip/cn.list"
CN_LIST_FILE="cn.list"
OUTPUT_ROS_FILE="cn-ip-routeros.rsc"
LIST_NAME=${LIST_NAME:-"CN-IP"}

# 代理IP列表配置
TELEGRAM_LIST_URL="https://core.telegram.org/resources/cidr.txt"
TELEGRAM_LIST_FILE="telegram-cidr.txt"
PROXY_OUTPUT_FILE="proxy-ip-routeros.rsc"
PROXY_LIST_NAME=${PROXY_LIST_NAME:-"PROXY-IP"}
# fake-ip-range (Clash/Mihomo 的 fake-ip 地址段)
FAKE_IP_RANGE="198.18.128.1/17"
FAKE_IP_RANGE6="fdfe:dcba:9876::1/64"


RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

download_cn_list() {
    log_info "正在从 $CN_LIST_URL 下载中国IP列表"
    
    if command -v curl &> /dev/null; then
        curl -s -o "$CN_LIST_FILE" "$CN_LIST_URL"
    elif command -v wget &> /dev/null; then
        wget -q -O "$CN_LIST_FILE" "$CN_LIST_URL"
    else
        log_error "未找到 curl 或 wget，请安装其中一个工具。"
        exit 1
    fi
    
    if [ ! -f "$CN_LIST_FILE" ]; then
        log_error "下载 cn.list 失败"
        exit 1
    fi
    
    log_info "下载完成，文件共 $(wc -l < "$CN_LIST_FILE") 行"
}

download_telegram_list() {
    log_info "正在从 $TELEGRAM_LIST_URL 下载Telegram IP列表"
    
    if command -v curl &> /dev/null; then
        curl -s -o "$TELEGRAM_LIST_FILE" "$TELEGRAM_LIST_URL"
    elif command -v wget &> /dev/null; then
        wget -q -O "$TELEGRAM_LIST_FILE" "$TELEGRAM_LIST_URL"
    else
        log_error "未找到 curl 或 wget，请安装其中一个工具。"
        exit 1
    fi
    
    if [ ! -f "$TELEGRAM_LIST_FILE" ]; then
        log_error "下载 telegram-cidr.txt 失败"
        exit 1
    fi
    
    log_info "下载完成，文件共 $(wc -l < "$TELEGRAM_LIST_FILE") 行"
}

generate_routeros_script() {
    log_info "正在生成CN-IP RouterOS脚本..."
    
    mkdir -p dist
    
    {
        echo ":local listName \"$LIST_NAME\""
        echo ""
        echo "# 清除已有的列表条目"
        echo "/ip firewall address-list remove [find list=\$listName]"
        echo "/ipv6 firewall address-list remove [find list=\$listName]"
        echo ""
        echo "# 添加IPv4地址"
        
        grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' "$CN_LIST_FILE" | while read -r cidr; do
            echo "/ip firewall address-list add address=\"$cidr\" list=\$listName"
        done
        
        echo ""
        echo "# 添加IPv6地址"
        
        grep -E '^[0-9a-fA-F]+:' "$CN_LIST_FILE" | while read -r cidr; do
            echo "/ipv6 firewall address-list add address=\"$cidr\" list=\$listName"
        done
        
        echo ""
        echo ":put \"CN IP list updated successfully.\""
    } > "$OUTPUT_ROS_FILE"
    
    local ipv4_count=$(grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' "$CN_LIST_FILE" | wc -l)
    local ipv6_count=$(grep -E '^[0-9a-fA-F]+:' "$CN_LIST_FILE" | wc -l)
    
    log_info "RouterOS脚本已生成: $OUTPUT_ROS_FILE"
    log_info "  - IPv4地址数量: $ipv4_count"
    log_info "  - IPv6地址数量: $ipv6_count"
}

generate_proxy_routeros_script() {
    log_info "正在生成PROXY-IP RouterOS脚本..."
    
    mkdir -p dist
    
    {
        echo ":local listName \"$PROXY_LIST_NAME\""
        echo ""
        echo "# 清除已有的列表条目"
        echo "/ip firewall address-list remove [find list=\$listName]"
        echo "/ipv6 firewall address-list remove [find list=\$listName]"
        echo ""
        echo "# 添加fake-ip-range (Clash/Mihomo fake-ip地址段)"
        echo "/ip firewall address-list add address=\"$FAKE_IP_RANGE\" list=\$listName"
        echo "/ipv6 firewall address-list add address=\"$FAKE_IP_RANGE6\" list=\$listName"
        echo ""
        echo "# 添加Telegram IPv4地址"
        
        grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' "$TELEGRAM_LIST_FILE" | while read -r cidr; do
            echo "/ip firewall address-list add address=\"$cidr\" list=\$listName"
        done
        
        echo ""
        echo "# 添加Telegram IPv6地址"
        
        grep -E '^[0-9a-fA-F]+:' "$TELEGRAM_LIST_FILE" | while read -r cidr; do
            echo "/ipv6 firewall address-list add address=\"$cidr\" list=\$listName"
        done
        
        echo ""
        echo ":put \"Proxy IP list updated successfully.\""
    } > "$PROXY_OUTPUT_FILE"
    
    local tg_ipv4_count=$(grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' "$TELEGRAM_LIST_FILE" | wc -l)
    local tg_ipv6_count=$(grep -E '^[0-9a-fA-F]+:' "$TELEGRAM_LIST_FILE" | wc -l)
    
    log_info "RouterOS脚本已生成: $PROXY_OUTPUT_FILE"
    log_info "  - fake-ip-range: 1 (IPv4)"
    log_info "  - fake-ip-range6: 1 (IPv6)"
    log_info "  - Telegram IPv4地址数量: $tg_ipv4_count"
    log_info "  - Telegram IPv6地址数量: $tg_ipv6_count"
}

cleanup() {
    if [ -f "$CN_LIST_FILE" ]; then
        rm "$CN_LIST_FILE"
        log_info "已清理临时文件: $CN_LIST_FILE"
    fi
    if [ -f "$TELEGRAM_LIST_FILE" ]; then
        rm "$TELEGRAM_LIST_FILE"
        log_info "已清理临时文件: $TELEGRAM_LIST_FILE"
    fi
}

show_usage() {
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -l, --list-name NAME          设置中国IP地址列表名称 (默认: CN-IP)"
    echo "  -o, --output FILE             设置中国IP列表输出文件名 (默认: cn-ip-routeros.rsc)"
    echo "  -p, --proxy-list-name NAME    设置代理IP地址列表名称 (默认: PROXY-IP)"
    echo "  -po, --proxy-output FILE      设置代理IP列表输出文件名 (默认: proxy-ip-routeros.rsc)"
    echo "  -h, --help                    显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 -l china-ip -o china-ip.rsc"
    echo "  $0 -p proxy-ip -po proxy-ip.rsc"
}

main() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -l|--list-name)
                LIST_NAME="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_ROS_FILE="$2"
                shift 2
                ;;
            -p|--proxy-list-name)
                PROXY_LIST_NAME="$2"
                shift 2
                ;;
            -po|--proxy-output)
                PROXY_OUTPUT_FILE="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "未知选项: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    download_cn_list
    generate_routeros_script
    
    download_telegram_list
    generate_proxy_routeros_script
    
    cleanup
    
    log_info "完成！"
    log_info "  - CN-IP脚本已保存至: $OUTPUT_ROS_FILE"
    log_info "  - PROXY-IP脚本已保存至: $PROXY_OUTPUT_FILE"
}

main "$@"