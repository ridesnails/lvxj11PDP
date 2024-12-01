#!/bin/sh
set -e
SCRIPT_DIR=$(dirname "$(realpath "$0")")
CURRENT_DATE=$(date '+%Y%m%d%H%M%S')
LOG_FILE="${SCRIPT_DIR}/singbox-update-and-start.log"
# 设定订阅转换脚本过期时间，单位为天
SUBSCRIBE_EXPIRE_TIME=7
# 代理订阅地址
SUBSCRIBE_URL=""
USER_AGENT="clashmeta"
# 代理节点排除关键字
EXCLUDE_KEYWORD="网站|地址|剩余|过期|时间|有效|到期|官网"
# 配置模板文件，建议使用远程url
# 如果模板文件使用本地文件一定保存到其他目录，不要保存到默认的模板目录。脚本会清空默认模板目录后自动拷贝副本到模板目录，以保证使用正确的配置模板。
CONFIG_TEMPLATE_FILE="https://mirror.ghproxy.com/https://raw.githubusercontent.com/lvxj11/lvxj11PDP/refs/heads/main/sing-box/singbox-tun-template.json"
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
# 从配置文件获取配置
get_settings() {
    # 如果settings.json文件存在，则从settings.json文件中获取配置
    settings_file="${SCRIPT_DIR}/settings.json"
    if [ -f "${settings_file}" ]; then
        # 读取setup.json文件中的配置,如配置文件中没有配置，则使用默认配置
        log "INFO" "从setup.json文件中获取配置..."
        local new_value=$(jq -r '.subscribe_expire_time // empty' "${settings_file}")
        [ -n "${new_value}" ] && SUBSCRIBE_EXPIRE_TIME=${new_value}
        new_value=$(jq -r '.subscribe_url // empty' "${settings_file}")
        [ -n "${new_value}" ] && SUBSCRIBE_URL=${new_value}
        new_value=$(jq -r '.user_agent // empty' "${settings_file}")
        [ -n "${new_value}" ] && USER_AGENT=${new_value}
        new_value=$(jq -r '.exclude_keyword // empty' "${settings_file}")
        [ -n "${new_value}" ] && EXCLUDE_KEYWORD=${new_value}
        new_value=$(jq -r '.config_template_file // empty' "${settings_file}")
        [ -n "${new_value}" ] && CONFIG_TEMPLATE_FILE=${new_value}
        if [ -z "$SUBSCRIBE_URL" ]; then
            log "ERROR" "没有配置订阅地址，请检查！"
            exit 1
        fi
    fi
}
update_app() {
    # 检查是否需要更新
    if [ ! -f "${SCRIPT_DIR}/update.date" ] || [ $(( $(date +%s) - $(date +%s -r ${SCRIPT_DIR}/update.date) )) -gt $(${SUBSCRIBE_EXPIRE_TIME} * 24 * 60 * 60) ]; then
        log "INFO" "更新时间过期，开始更新..."
        rm -f ${SCRIPT_DIR}/update.date
        rm -rf /root/sing-box-subscribe
        rm -rf /opt/sing-box-subscribe
        log "INFO" "更新系统及应用..."
        apk update
        apk upgrade
        apk upgrade sing-box --update-cache --repository http://dl-cdn.alpinelinux.org/alpine/edge/testing/ --allow-untrusted
        # 克隆订阅转换脚本到/root目录下
        log "INFO" "更新订阅转换脚本..."
        git clone https://mirror.ghproxy.com/https://github.com/Toperlock/sing-box-subscribe.git /root/sing-box-subscribe
        mv /root/sing-box-subscribe /opt/sing-box-subscribe
        # 建立python虚拟环境
        log "INFO" "建立python虚拟环境..."
        python3 -m venv /opt/sing-box-subscribe/venv
        source /opt/sing-box-subscribe/venv/bin/activate
        # 更新pip
        log "INFO" "更新pip..."
        python3 -m pip install --upgrade pip
        # 安装依赖包
        log "INFO" "安装依赖包..."
        python3 -m pip install -r /opt/sing-box-subscribe/requirements.txt
        # 退出虚拟环境
        deactivate
        # 将当前日期存储到update.date文件中
        log "INFO" "更新完成，保存更新日期..."
        date > ${SCRIPT_DIR}/update.date
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
            "User-Agent":"${USER_AGENT}"
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
    case "$CONFIG_TEMPLATE_FILE" in
        http://*|https://*)
            # 替换providers.json中的onfig_template
            log "INFO" "配置模板为远程url，修改providers.json文件..."
            jq --arg config_template_url "${CONFIG_TEMPLATE_FILE}" '.config_template=$config_template_url' /opt/sing-box-subscribe/providers.json > /tmp/providers.json
            mv /tmp/providers.json /opt/sing-box-subscribe/providers.json
            # 使用子线程，防止环境变量丢失
            (
                cd /opt/sing-box-subscribe
                # 激活虚拟环境
                source ./venv/bin/activate
                python3 main.py
                # 退出虚拟环境
                deactivate
            )
            ;;
        *)
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
            # 使用子线程，防止环境变量丢失
            (
                cd /opt/sing-box-subscribe
                # 激活虚拟环境
                source ./venv/bin/activate
                python3 main.py --template_index=0
                # 退出虚拟环境
                deactivate
            )
            ;;
    esac
    # 检查转换结果
    if ! sing-box check -c /opt/sing-box-subscribe/config.json; then
        log "ERROR" "配置文件验证失败，退出脚本..."
        return
    fi
    # 备份原配置文件
    log "INFO" "备份原配置文件..."
    mv /etc/sing-box/config.json /etc/sing-box/config.json.${CURRENT_DATE}
    # 替换配置文件
    log "INFO" "替换配置文件..."
    mv /opt/sing-box-subscribe/config.json /etc/sing-box/config.json
}
# 获取配置
get_settings
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
