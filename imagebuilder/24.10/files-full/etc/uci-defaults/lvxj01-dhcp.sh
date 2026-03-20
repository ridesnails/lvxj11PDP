#!/bin/sh
# 自用镜像dhcp配置脚本
# 获取lan口IP段
LAN_IP_SEGMENT=$(uci get network.lan.ipaddr | awk -F. '{print $1"."$2"."$3"."}')
SAVE_FOLDER="/etc/custom-scripts/"
# 配置dhcp服务自动分配IP段
uci set dhcp.lan.start=128
uci set dhcp.lan.limit=112
uci set dhcp.lan.leasetime=2h
# 取消dns劫持
uci delete dhcp.@dnsmasq[0].dns_redirect
# 添加dhcp配置标签，标签选项3为dns，6为网关
uci add_list dhcp.lan.dhcp_option="tag:t_bypass3,3,${LAN_IP_SEGMENT}3"
uci add_list dhcp.lan.dhcp_option="tag:t_bypass3,6,${LAN_IP_SEGMENT}3"
uci add_list dhcp.lan.dhcp_option="tag:t_bypass4,3,${LAN_IP_SEGMENT}4"
uci add_list dhcp.lan.dhcp_option="tag:t_bypass4,6,${LAN_IP_SEGMENT}4"
uci add_list dhcp.lan.dhcp_option="tag:t_bypass5,3,${LAN_IP_SEGMENT}5"
uci add_list dhcp.lan.dhcp_option="tag:t_bypass5,6,${LAN_IP_SEGMENT}5"
uci add_list dhcp.lan.dhcp_option="tag:t_reject,3,${LAN_IP_SEGMENT}11"
uci add_list dhcp.lan.dhcp_option="tag:t_reject,6,${LAN_IP_SEGMENT}11"
strip_quotes() {
  s="$1"
  s="${s%\"}"; s="${s#\"}"
  s="${s%\'}"; s="${s#\'}"
  printf "%s\n" "$s"
}
write_dhcp() {
    # echo "主机名称：${dhcp_name}    MAC地址：${dhcp_mac}    IP地址：${dhcp_ip}    标签：${dhcp_tag}"
    # 添加静态ip绑定
    # 如果IP段格式正确则替换IP段
    if echo "${LAN_IP_SEGMENT}" | grep -qE '^([1-2]?[0-9]{1,2}\.){3}$'; then
        dhcp_ip="${LAN_IP_SEGMENT}$(echo "${dhcp_ip}" | awk -F. '{print $4}')"
    fi
    # echo "主机名称：${dhcp_name}    MAC地址：${dhcp_mac}    IP地址：${dhcp_ip}    标签：${dhcp_tag}"
    if echo "${dhcp_ip}" | grep -qE '^([1-2]?[0-9]{1,2}\.){3}[1-2]?[0-9]{1,2}$'; then
        # echo "主机名称：${dhcp_name}    MAC地址：${dhcp_mac}    IP地址：${dhcp_ip}    标签：${dhcp_tag}"
        uci add dhcp host
        uci set dhcp.@host[-1].name="${dhcp_name}"
        for mac in ${dhcp_mac}; do
            uci add_list dhcp.@host[-1].mac="${mac}"
        done
        uci set dhcp.@host[-1].ip="${dhcp_ip}"
        if [ -n "${dhcp_tag}" ]; then
            # 按空格分隔遍历
            for tag in ${dhcp_tag}; do
                uci add_list dhcp.@host[-1].tag="${tag}"
            done
        fi
    fi
    # 写入完成清空变量
    dhcp_name=""
    dhcp_mac=""
    dhcp_ip=""
    dhcp_tag=""
}
if [ -f "${SAVE_FOLDER}dhcp" ]; then
    # 如果当前文件夹存在dhcp文件则解析DHCP静态地址绑定信息
    find_host=0
    tr -d '\r' < ${SAVE_FOLDER}dhcp | while read -r line; do
        if echo "${line}" | grep -qE '^config'; then
            write_dhcp
            if echo "${line}" | grep -qE '^config host'; then
                find_host=1
            else
                find_host=0
            fi
            continue
        fi
        if [ ${find_host} -eq 1 ]; then
            case ${line} in
                "option name"*)
                    dhcp_name=$(strip_quotes $(echo ${line} | awk '{print $3}'))
                    ;;
                "list mac"*)
                    mac=$(strip_quotes $(echo ${line} | awk '{print $3}'))
                    if [ -z "${dhcp_mac}" ]; then
                        dhcp_mac="${mac}"
                    else
                        dhcp_mac="${dhcp_mac} ${mac}"
                    fi
                    ;;
                "option ip"*)
                    dhcp_ip=$(strip_quotes $(echo ${line} | awk '{print $3}'))
                    ;;
                "list tag"*)
                    tag=$(strip_quotes $(echo ${line} | awk '{print $3}'))
                    if [ -z "${dhcp_tag}" ]; then
                        dhcp_tag="${tag}"
                    else
                        dhcp_tag="${dhcp_tag} ${tag}"
                    fi
                    ;;
            esac
        fi
    done
elif [ -f "${SAVE_FOLDER}dhcp.csv" ]; then
    echo "存在dhcp.csv"
    # 读取静态IP列表：dhcp.csv
    # 1. 序号 2. IP地址，前三段替换为LAN_IP_SEGMENT 3. 绑定的MAC地址 4. 备注信息 5. 绑定的标签（多个以空格分隔）
    # 多个标签或mac地址用空格隔开，和csv格式的逗号分隔不干扰
    tr -d '\r' < ${SAVE_FOLDER}dhcp.csv | while read -r line; do
        dhcp_ip=$(echo "${line}" | awk -F, '{print $2}')
        dhcp_mac=$(echo "${line}" | awk -F, '{print $3}')
        dhcp_name=$(echo "${line}" | awk -F, '{print $4}')
        dhcp_tag=$(echo "${line}" | awk -F, '{print $5}')
        write_dhcp
    done
fi
uci commit dhcp
