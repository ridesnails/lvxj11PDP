#!/bin/sh
################################################################################################
# Author: lvxj11
# Description: 订阅转换脚本自动更新和启动
# Version: 1.0
################################################################################################
# 根据配置的过期时间自动更新转换脚本和sing-box。
# 更新时会在原目录备份为.bak结尾的文件或目录。
# 如更新后不能正常使用，请查看官方文档修改配置，或暂时回复备份。
# 如不需要自动更新，请将SUBSCRIBE_EXPIRE_TIME设置为0。
set -e
SCRIPT_DIR=$(dirname "$(realpath "$0")")      # 脚本所在目录
CURRENT_DATE=$(date '+%Y%m%d%H%M%S')      # 当前日期和时间
DOWNLOAD_DIR="${SCRIPT_DIR}/downloads"      # 下载目录
EXTRACT_DIR="${SCRIPT_DIR}/extracted"       # 解压目录
LOG_FILE="${SCRIPT_DIR}/singbox-update-and-start.log"       # 日志文件
LOG_LEVEL=9       # 0：ERROR，1：WARN，2：INFO，3：DEBUG
SUBSCRIBE_EXPIRE_TIME=7      # 过期时间
SUBSCRIBE_URL=""      # 代理订阅地址
USER_AGENT="clashmeta"      # 订阅UA
EXCLUDE_KEYWORD="网站|地址|剩余|过期|时间|有效|到期|官网"      # 代理节点排除关键字
# 配置模板文件，建议使用远程url
# 如果模板文件使用本地文件一定保存到其他目录，不要保存到默认的模板目录。脚本会清空默认模板目录后自动拷贝副本到模板目录，以保证使用正确的配置模板。
CONFIG_TEMPLATE_FILE="https://raw.githubusercontent.com/lvxj11/lvxj11PDP/refs/heads/main/sing-box/singbox-tun-template.json"
# 以下为sing-box github更新配置
REPO="SagerNet/sing-box"        # GitHub 仓库名
VERSION_PREFIX="v1.11"           # 指定主版本号
ARCH="linux-amd64"              # 指定系统架构
TARGET_DIR="/usr/bin"           # 目标目录

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
    local level_str=$1
    local level=0
    case $level_str in
    "ERROR")
        level=0
        ;;
    "WARN")
        level=1
        ;;
    "INFO")
        level=2
        ;;
    "DEBUG")
        level=3
        ;;
    *)
        level=9
        ;;
    esac
    if [ $level -le $LOG_LEVEL ]; then
        shift
        local message="[$(date '+%Y-%m-%d %H:%M:%S')] [$level_str] $*"
        echo "$message" | tee -a "$LOG_FILE"
    fi
}
# 从配置文件获取配置
get_settings() {
    # 如果settings.json文件存在，则从settings.json文件中获取配置
    settings_file="${SCRIPT_DIR}/settings.json"
    if [ -f "${settings_file}" ]; then
        # 读取settings.json文件中的配置,如配置文件中没有配置，则使用默认配置
        log "INFO" "从settings.json文件中获取配置..."
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
    fi
    if [ -z "$SUBSCRIBE_URL" ]; then
        log "ERROR" "没有配置订阅地址，请检查！"
        exit 1
    fi
}
update_singbox() {
    ASSET_URL=$(curl -s "https://api.github.com/repos/$REPO/releases" | jq -r \
        --arg version_prefix "$VERSION_PREFIX" \
        --arg arch "$ARCH" \
        '.[] | select(.tag_name | startswith($version_prefix)) | .assets[] | select(.name | endswith($arch + ".tar.gz")) | .browser_download_url' | head -n 1)
    # 检查是否找到匹配的资产
    if [ -z "$ASSET_URL" ]; then
        log "WARN" "未找到符合条件的版本，退出更新sing-box。请检查版本号或系统架构。"
        return
    fi
    # 提取文件名
    FILENAME=$(basename "$ASSET_URL")
    # 下载文件
    log "INFO" "下载：$FILENAME"
    # 检查下载是否成功
    if ! curl -L -o "$DOWNLOAD_DIR/$FILENAME" "$ASSET_URL"; then
        log "WARN" "下载失败！"
        return
    fi
    # 解压文件
    log "INFO" "解压：$FILENAME"
    # 检查解压是否成功
    if ! tar -xzvf "$DOWNLOAD_DIR/$FILENAME" -C "$EXTRACT_DIR"; then
        log "WARN" "解压失败！"
        return
    fi
    # 查找解压目录中的 `sing-box` 文件
    SING_BOX_PATH=$(find "$EXTRACT_DIR" -type f -name "sing-box")
    if [ -z "$SING_BOX_PATH" ]; then
        log "WARN" "解压目录中未找到sing-box文件！"
        return
    else
        chmod +x "$SING_BOX_PATH"
    fi
    # 检查是否为新版本
    if [ -f "$TARGET_DIR/sing-box" ]; then
        CURRENT_VERSION=$(sing-box version | head -n 1 | awk '{print $3}')
        NEW_VERSION=$("$SING_BOX_PATH version" | head -n 1 | awk '{print $3}')
        if [ "$CURRENT_VERSION" = "$NEW_VERSION" ]; then
            log "INFO" "当前版本与最新版本一致，无需更新。"
            return
        else
            log "INFO" "当前版本：$CURRENT_VERSION，最新版本：$NEW_VERSION，将更新。"
            log "INFO" "停止sing-box服务并备份原版本..."
            rc-service sing-box stop
            sleep 1
            mv "$TARGET_DIR/sing-box" "$TARGET_DIR/sing-box.bak"
        fi
    else
        log "INFO" "未找到旧版本，将安装新版本。"
    fi
    # 复制到 /usr/bin 并覆盖
    mv "$SING_BOX_PATH" "$TARGET_DIR/sing-box"
    # 确保文件有执行权限
    chmod +x "$TARGET_DIR/sing-box"
    rc-service sing-box restart
    sleep 5
    # 检查sing-box是否已启动
    if ! rc-service sing-box status; then
        log "ERROR" "sing-box更新后启动失败，请检查..."
        # 如果存在备份
        if [ -f "$TARGET_DIR/sing-box.bak" ]; then
            log "WARN" "找到备份，将恢复原版本..."
            # 先将新版本移动到脚本目录，方便排错
            mv "$TARGET_DIR/sing-box" "$SCRIPT_DIR/sing-box.new"
            mv "$TARGET_DIR/sing-box.bak" "$TARGET_DIR/sing-box"
            return
        else
            log "ERROR" "未找到备份，请手动恢复！"
            exit 1
        fi
        return
    fi
    log "INFO" "已更新sing-box到最新版本：$NEW_VERSION"
}
update_subscribe() {
    log "DEBUG" "克隆订阅转换脚本..."
    if ! git clone https://github.com/Toperlock/sing-box-subscribe.git ${DOWNLOAD_DIR}/sing-box-subscribe >/dev/null 2>&1; then
        log "WARN" "克隆订阅转换脚本失败，请检查网络！"
        return
    fi
    log "DEBUG" "克隆成功"
    if [ -d "/opt/sing-box-subscribe" ]; then
        log "INFO" "检测到旧版本，备份旧版本..."
        rm -rf /opt/sing-box-subscribe.bak
        mv /opt/sing-box-subscribe /opt/sing-box-subscribe.bak
    fi
    log "DEBUG" "开始移动文件..."
    mv ${DOWNLOAD_DIR}/sing-box-subscribe /opt/sing-box-subscribe
    log "DEBUG" "建立python虚拟环境..."
    python3 -m venv /opt/sing-box-subscribe/venv
    log "DEBUG" "进入虚拟环境..."
    source /opt/sing-box-subscribe/venv/bin/activate
    log "DEBUG" "更新pip..."
    python3 -m pip install --upgrade pip
    log "DEBUG" "安装依赖包..."
    python3 -m pip install -r /opt/sing-box-subscribe/requirements.txt
    log "DEBUG" "退出虚拟环境..."
    deactivate
}
update_app() {
    # 如果过期时间为0则不做处理
    if [ "$SUBSCRIBE_EXPIRE_TIME" -eq 0 ]; then
        log "INFO" "过期时间为0，跳过更新..."
        return
    fi
    # 检查是否过期
    if [ ! -f "${SCRIPT_DIR}/update.date" ] || [ ! -d "/opt/sing-box-subscribe" ] || { 
        LAST_UPDATE=$(cat "${SCRIPT_DIR}/update.date" 2>/dev/null)
        CURRENT_TIME=$(date +%s)
        EXPIRE_TIME=$((SUBSCRIBE_EXPIRE_TIME * 24 * 60 * 60))
        # 确保LAST_UPDATE是数字
        [ "$LAST_UPDATE" -eq "$LAST_UPDATE" ] 2>/dev/null &&
        [ $((CURRENT_TIME - LAST_UPDATE)) -gt $EXPIRE_TIME ]
    }; then
        log "INFO" "需要更新或下载，开始更新..."
        rm -f ${SCRIPT_DIR}/update.date
        rm -rf ${DOWNLOAD_DIR}
        rm -rf ${EXTRACT_DIR}
        mkdir -p "$DOWNLOAD_DIR" "$EXTRACT_DIR"
        log "INFO" "更新系统及应用..."
        apk update
        apk upgrade
        log "INFO" "更新sing-box..."
        update_singbox
        log "INFO" "更新订阅转换脚本..."
        update_subscribe
        # 将当前日期存储到update.date文件中
        log "INFO" "更新完成，保存更新日期..."
        date +%s > ${SCRIPT_DIR}/update.date
    else
        log "INFO" "更新未过期，跳过更新..."
    fi
}
# 配置参数并转换订阅
convert_subscription() {
    # 检查是否存在转换脚本
    if [ ! -f "/opt/sing-box-subscribe/main.py" ]; then
        log "ERROR" "未找到转换脚本，请检查！"
        exit 1
    fi
    # 配置转换脚本providers.json文件
    log "DEBUG" "生成转换脚本providers.json文件..."
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
    # 如果配置文件路径以http://或https://开头，则下载，否则作为本地文件移动到指定位置
    case "$CONFIG_TEMPLATE_FILE" in
        http://*|https://*)
            # 替换providers.json中的onfig_template
            log "DEBUG" "配置模板为远程url，修改providers.json文件..."
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
            log "DEBUG" "配置模板为远程本地路径，修改providers.json文件..."
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
        log "ERROR" "新配置文件检查失败，退出脚本..."
        exit 1
    fi
    log "DEBUG" "新配置文件通过检查..."
    # 备份原配置文件
    log "DEBUG" "备份原配置文件..."
    rm -f /etc/sing-box/config.json.bak
    cp /etc/sing-box/config.json /etc/sing-box/config.json.bak
    mv /etc/sing-box/config.json /etc/sing-box/config.json.${CURRENT_DATE}
    # 替换配置文件
    log "INFO" "替换配置文件..."
    mv /opt/sing-box-subscribe/config.json /etc/sing-box/config.json
}
# 检查sing-box服务是否在开机启动
check_startup() {
    if [ $(rc-update -a show | grep -c "sing-box") -eq 0 ]; then
        log "INFO" "sing-box服务未在开机启动，添加到开机启动..."
        rc-update add sing-box default
    fi
}
# 清理/etc/sing-box/box.log日志文件
clear_singbox_log() {
    if [ -f /etc/sing-box/box.log ]; then
        # 删除上次备份的日志
        rm -f /etc/sing-box/box-bak.log
        # 备份一次日志文件，方便回溯查看
        mv /etc/sing-box/box.log /etc/sing-box/box-bak.log
    fi
}
# 主函数
main() {
    # 获取配置
    log "INFO" "获取配置..."
    get_settings
    # 更新应用
    log "INFO" "检查更新..."
    update_app
    # 转换订阅
    log "INFO" "转换订阅..."
    convert_subscription
    # 检查sing-box服务是否在开机启动
    check_startup
    # 清理singbox日志防止日志文件过大
    log "INFO" "清理sing-box日志文件..."
    clear_singbox_log
    # 重启sing-box
    log "INFO" "重启sing-box..."
    rc-service sing-box restart
    sleep 5
    # 检查sing-box是否已启动
    if ! rc-service sing-box status; then
        log "ERROR" "sing-box启动失败，请检查..."
        # 如果存在备份
        if [ -f "/etc/sing-box/config.json.bak" ]; then
            log "WARN" "找到备份配置文件，将恢复原配置文件并尝试启动..."
            # 先将新版本移动到脚本目录，方便排错
            mv "/etc/sing-box/config.json" "$SCRIPT_DIR/config.json.new"
            mv "/etc/sing-box/config.json.bak" "/etc/sing-box/config.json"
            rc-service sing-box restart
        else
            log "ERROR" "未找到备份，请手动恢复！"
            exit 1
        fi
    fi
    log "INFO" "更新启动完成！"
    exit 0
}

# 执行主函数
main
