#!/usr/bin/env bash

set -euo pipefail

CN_LIST_URL="https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geoip/cn.list"
CN_LIST_FILE="cn.list"
OUTPUT_ROS_FILE="cn-ip-routeros.rsc"
LIST_NAME=${LIST_NAME:-"CN-IP"}

# 代理IP列表配置（统一使用MetaCubeX数据源）
TELEGRAM_LIST_URL="https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geoip/telegram.list"
TELEGRAM_LIST_FILE="telegram.list"
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

# 生成单个address-list配置
# 参数: list_name(列表名称), input_file, include_fake_ip(可选), comment(可选)
generate_address_list() {
    local list_name="$1"
    local input_file="$2"
    local include_fake_ip="${3:-false}"
    local comment="${4:-}"
    
    echo "# ========== ${comment:-$list_name} 地址列表 =========="
    echo "# 清除已有的列表条目"
    echo "/ip firewall address-list remove [find list=\"$list_name\"]"
    echo "/ipv6 firewall address-list remove [find list=\"$list_name\"]"
    
    if [ "$include_fake_ip" = "true" ]; then
        echo ""
        echo "# 添加fake-ip-range (Clash/Mihomo fake-ip地址段)"
        echo "/ip firewall address-list add address=\"$FAKE_IP_RANGE\" list=\"$list_name\""
        echo "/ipv6 firewall address-list add address=\"$FAKE_IP_RANGE6\" list=\"$list_name\""
    fi
    
    echo ""
    echo "# 添加IPv4地址"
    grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' "$input_file" | while read -r cidr; do
        echo "/ip firewall address-list add address=\"$cidr\" list=\"$list_name\""
    done
    
    echo ""
    echo "# 添加IPv6地址"
    grep -E '^[0-9a-fA-F]+:' "$input_file" | while read -r cidr; do
        echo "/ipv6 firewall address-list add address=\"$cidr\" list=\"$list_name\""
    done
}

# 统计address-list条目数
# 参数: input_file, list_name
count_address_list() {
    local input_file="$1"
    local list_name="$2"
    
    local ipv4_count=$(grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' "$input_file" | wc -l)
    local ipv6_count=$(grep -E '^[0-9a-fA-F]+:' "$input_file" | wc -l)
    
    log_info "  [$list_name]"
    log_info "    - IPv4地址数量: $ipv4_count"
    log_info "    - IPv6地址数量: $ipv6_count"
}

generate_routeros_script() {
    log_info "正在生成RouterOS脚本..."
    
    mkdir -p dist
    
    {
        # 生成CN-IP列表
        generate_address_list "$LIST_NAME" "$CN_LIST_FILE" "false" "CN-IP"
        
        echo ""
        
        # 生成PROXY-IP列表（包含fake-ip）
        generate_address_list "$PROXY_LIST_NAME" "$TELEGRAM_LIST_FILE" "true" "PROXY-IP"
        
        echo ""
        echo ":put \"CN-IP and PROXY-IP lists updated successfully.\""
    } > "$OUTPUT_ROS_FILE"
    
    log_info "RouterOS脚本已生成: $OUTPUT_ROS_FILE"
    count_address_list "$CN_LIST_FILE" "CN-IP"
    log_info "  [PROXY-IP]"
    log_info "    - fake-ip-range: 1 (IPv4)"
    log_info "    - fake-ip-range6: 1 (IPv6)"
    count_address_list "$TELEGRAM_LIST_FILE" "Telegram"
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