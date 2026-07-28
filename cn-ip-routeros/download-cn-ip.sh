#!/usr/bin/env bash

set -euo pipefail

CN_LIST_URL="https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geoip/cn.list"
CN_LIST_FILE="cn.list"
OUTPUT_ROS_FILE="cn-ip-routeros.rsc"
LIST_NAME=${LIST_NAME:-"CN-IP"}

# 代理IP列表配置
TELEGRAM_LIST_URL="https://core.telegram.org/resources/cidr.txt"
TELEGRAM_LIST_FILE="telegram-cidr.txt"
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

download_file() {
    local url="$1"
    local output_file="$2"
    local desc="$3"
    
    log_info "正在从 $url 下载$desc"
    
    if command -v curl &> /dev/null; then
        curl -s -o "$output_file" "$url"
    elif command -v wget &> /dev/null; then
        wget -q -O "$output_file" "$url"
    else
        log_error "未找到 curl 或 wget，请安装其中一个工具。"
        exit 1
    fi
    
    if [ ! -f "$output_file" ]; then
        log_error "下载 $output_file 失败"
        exit 1
    fi
    
    log_info "下载完成，文件共 $(wc -l < "$output_file") 行"
}

download_cn_list() {
    download_file "$CN_LIST_URL" "$CN_LIST_FILE" "中国IP列表"
}

download_telegram_list() {
    download_file "$TELEGRAM_LIST_URL" "$TELEGRAM_LIST_FILE" "Telegram IP列表"
}

generate_routeros_script() {
    log_info "正在生成RouterOS脚本..."
    
    mkdir -p dist
    
    {
        echo ":local listName \"$LIST_NAME\""
        echo ":local proxyListName \"$PROXY_LIST_NAME\""
        echo ""
        echo "# ========== CN-IP 地址列表 =========="
        echo "# 清除已有的CN-IP列表条目"
        echo "/ip firewall address-list remove [find list=\$listName]"
        echo "/ipv6 firewall address-list remove [find list=\$listName]"
        echo ""
        echo "# 添加CN-IP IPv4地址"
        
        grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' "$CN_LIST_FILE" | while read -r cidr; do
            echo "/ip firewall address-list add address=\"$cidr\" list=\$listName"
        done
        
        echo ""
        echo "# 添加CN-IP IPv6地址"
        
        grep -E '^[0-9a-fA-F]+:' "$CN_LIST_FILE" | while read -r cidr; do
            echo "/ipv6 firewall address-list add address=\"$cidr\" list=\$listName"
        done
        
        echo ""
        echo "# ========== PROXY-IP 地址列表 =========="
        echo "# 清除已有的PROXY-IP列表条目"
        echo "/ip firewall address-list remove [find list=\$proxyListName]"
        echo "/ipv6 firewall address-list remove [find list=\$proxyListName]"
        echo ""
        echo "# 添加fake-ip-range (Clash/Mihomo fake-ip地址段)"
        echo "/ip firewall address-list add address=\"$FAKE_IP_RANGE\" list=\$proxyListName"
        echo "/ipv6 firewall address-list add address=\"$FAKE_IP_RANGE6\" list=\$proxyListName"
        echo ""
        echo "# 添加Telegram IPv4地址"
        
        grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' "$TELEGRAM_LIST_FILE" | while read -r cidr; do
            echo "/ip firewall address-list add address=\"$cidr\" list=\$proxyListName"
        done
        
        echo ""
        echo "# 添加Telegram IPv6地址"
        
        grep -E '^[0-9a-fA-F]+:' "$TELEGRAM_LIST_FILE" | while read -r cidr; do
            echo "/ipv6 firewall address-list add address=\"$cidr\" list=\$proxyListName"
        done
        
        echo ""
        echo ":put \"CN-IP and PROXY-IP lists updated successfully.\""
    } > "$OUTPUT_ROS_FILE"
    
    local cn_ipv4_count=$(grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' "$CN_LIST_FILE" | wc -l)
    local cn_ipv6_count=$(grep -E '^[0-9a-fA-F]+:' "$CN_LIST_FILE" | wc -l)
    local tg_ipv4_count=$(grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' "$TELEGRAM_LIST_FILE" | wc -l)
    local tg_ipv6_count=$(grep -E '^[0-9a-fA-F]+:' "$TELEGRAM_LIST_FILE" | wc -l)
    
    log_info "RouterOS脚本已生成: $OUTPUT_ROS_FILE"
    log_info "  [CN-IP]"
    log_info "    - IPv4地址数量: $cn_ipv4_count"
    log_info "    - IPv6地址数量: $cn_ipv6_count"
    log_info "  [PROXY-IP]"
    log_info "    - fake-ip-range: 1 (IPv4)"
    log_info "    - fake-ip-range6: 1 (IPv6)"
    log_info "    - Telegram IPv4地址数量: $tg_ipv4_count"
    log_info "    - Telegram IPv6地址数量: $tg_ipv6_count"
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
    echo "  -o, --output FILE             设置输出文件名 (默认: cn-ip-routeros.rsc)"
    echo "  -p, --proxy-list-name NAME    设置代理IP地址列表名称 (默认: PROXY-IP)"
    echo "  -h, --help                    显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 -l china-ip -p proxy-ip -o output.rsc"
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
    download_telegram_list
    generate_routeros_script
    cleanup
    
    log_info "完成！RouterOS脚本已保存至: $OUTPUT_ROS_FILE"
}

main "$@"