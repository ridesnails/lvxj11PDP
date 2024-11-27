#!/bin/sh
set -e
LOG_FILE="./singbox-update-and-start.log"
# 设定订阅转换脚本过期时间，单位为天
SUBSCRIBE_EXPIRE_TIME=7
# 代理订阅地址
SUBSCRIBE_URL=""
USER_AGENT="clashmeta"
# 代理节点排除关键字
EXCLUDE_KEYWORD="网站|地址|剩余|过期|时间|有效|到期|官网"
# 配置模板文件，建议使用远程url
# 如果模板文件使用本地文件一定保存到其他目录，不要保存到默认的模板目录。脚本会清空默认模板目录后自动拷贝副本到模板目录，以保证使用正确的配置模板。
CONFIG_TEMPLATE_FILE="https://mirror.ghproxy.com/https://raw.githubusercontent.com/lvxj11/lvxj11PDP/refs/heads/main/sing-box/singbox-qcy-mod-tun.json"
# 如果要自定义其他选项，请找到脚本中选项的生成位置自行修改。

rotate_log() {
  local max_size=1048576  # 最大大小：1MB
  if [ -f "$LOG_FILE" ] && [ "$(stat -c%s "$LOG_FILE")" -ge "$max_size" ]; then
    mv "$LOG_FILE" "$LOG_FILE.$(date '+%Y%m%d%H%M%S')"
    touch "$LOG_FILE"
  fi
}

log() {
  rotate_log
  local level=$1
  shift
  local message="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
  echo "$message" | tee -a "$LOG_FILE"
}

update_app() {
    # 检查是否需要更新
    if [ ! -f "./update.data" ] || [ $(( $(date +%s) - $(date +%s -r /root/update.data) )) -gt $(${SUBSCRIBE_EXPIRE_TIME} * 24 * 60 * 60) ]; then
        log "INFO" "更新时间过期，开始更新..."
        rm -f /root/update.data
        rm -rf /root/sing-box-subscribe
        rm -rf /opt/sing-box-subscribe
        log "INFO" "更新系统及应用..."
        apk update
        apk upgrade
        python3 -m pip install --upgrade pip
        apk upgrade sing-box --update-cache --repository http://dl-cdn.alpinelinux.org/alpine/edge/testing/ --allow-untrusted
        # 克隆订阅转换脚本到/root目录下
        log "INFO" "更新订阅转换脚本..."
        git clone https://mirror.ghproxy.com/https://github.com/Toperlock/sing-box-subscribe.git /root/
        mv /root/sing-box-subscribe /opt/sing-box-subscribe
        # 安装依赖包
        log "INFO" "安装依赖包..."
        cd /opt/sing-box-subscribe
        python3 -m pip install -r requirements.txt
        # 将当前日期存储到update.data文件中
        log "INFO" "更新完成，保存更新日期..."
        date > /root/update.data
    else
        log "INFO" "订阅转换脚本未过期，跳过更新..."
    fi
}
# 配置参数并转换订阅
convert_subscription() {
    # 配置转换脚本providers.json文件
    log "INFO" "配置转换脚本providers.json文件..."
    rm -f /opt/sing-box-subscribe/providers.json
    # config_template先配置为空，随后根据是url还是文件路径采取不同的操作
    cat > /opt/sing-box-subscribe/providers.json << EOF
{
    "subscribes":[
        {
            "url": "${SUBSCRIBE_URL}",
            "tag": "SUB1",
            "enabled": true,
            "emoji": 1,
            "subgroup": "",
            "prefix": "",
            "ex-node-name": "${EXCLUDE_KEYWORD}",
            "User-Agent":"clashmeta"
        }
    ],
    "auto_set_outbounds_dns":{
        "proxy": "",
        "direct": ""
    },
    "save_config_path": "./config.json",
    "auto_backup": false,
    "exclude_protocol":"ssr",
    "config_template": "",
    "Only-nodes": false
}
EOF
    # 开始订阅转换
    log "INFO" "转换订阅..."
    # 如果配置文件路径以http://或https://开头，则下载，否则作为本地文件移动到指定位置
    if [[ ${CONFIG_TEMPLATE_FILE} =~ ^(http|https):// ]]; then
        # 替换providers.json中的onfig_template
        log "INFO" "配置模板为远程url，修改providers.json文件..."
        jq --arg config_template_url "${CONFIG_TEMPLATE_FILE}" '.config_template=$config_template_url' /opt/sing-box-subscribe/providers.json > /tmp/providers.json
        mv /tmp/providers.json /opt/sing-box-subscribe/providers.json
        python3 main.py
    else
        # 判断文件是否存在
        if [ ! -f ${CONFIG_TEMPLATE_FILE} ]; then
            log "ERROR" "配置文件不存在，请检查配置模板路径是否正确！"
            exit 1
        fi
        log "INFO" "配置模板为远程本地路径，修改providers.json文件..."
        jq '.config_template=""' /opt/sing-box-subscribe/providers.json > /tmp/providers.json
        mv /tmp/providers.json /opt/sing-box-subscribe/providers.json
        # 保证配置模板为模板目录下唯一文件
        mv ${CONFIG_TEMPLATE_FILE} /tmp/config_template.json
        rm -f /opt/sing-box-subscribe/config_template/*
        mv /tmp/config_template.json /opt/sing-box-subscribe/config_template/
    fi
    # 备份原配置文件
    log "INFO" "备份原配置文件..."
    mv /etc/sing-box/config.json /etc/sing-box/config.json.$(date '+%Y%m%d%H%M%S')
    # 替换配置文件
    log "INFO" "替换配置文件..."
    mv /opt/sing-box-subscribe/config.json /etc/sing-box/config.json
}

# 停止sing-box
log "INFO" "停止sing-box..."
rc-service sing-box stop
sleep 3
# 更新应用
update_app
# 转换订阅
convert_subscription
# 重启sing-box
log "INFO" "重启sing-box..."
rc-service sing-box restart
log "INFO" "更新启动完成！"
exit 0
