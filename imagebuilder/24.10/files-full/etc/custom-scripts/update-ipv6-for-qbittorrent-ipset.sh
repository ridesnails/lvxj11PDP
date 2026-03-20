#!/bin/sh
# 设定变量
INPUT=$(cat)   # 读取 POST 内容
IPSET_NAME="ipv6-for-qbittorrent"   # IP集名称
# 输出响应头（带 UTF-8 编码）
echo "Content-type: text/plain; charset=utf-8"
echo ""

# 逐行处理每个 IPv6 地址
OLDIFS="${IFS}"    # 保存当前 IFS 值
IFS=$'\n'    # 设置 IFS 为换行符
for ipv6_addr in ${INPUT}; do
    # 添加到数据集
    /etc/custom-scripts/update-ipset.sh "${IPSET_NAME}" "${ipv6_addr}"
    if [ $? -eq 0 ]; then
        echo "更新完成"
    else
        echo "IPv6 地址 ${ipv6_addr} 向IP集 ${IPSET_NAME} 更新失败"
    fi
done
IFS="${OLDIFS}"
