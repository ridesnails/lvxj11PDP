#!/bin/sh
set -e
# 设定配置模板下载链接
CONFIG_URL="https://mirror.ghproxy.com/https://raw.githubusercontent.com/lvxj11/lvxj11PDP/refs/heads/main/sing-box/singbox-qcy-mod-tun.json"
LOG_FILE="./singbox-update-and-start.log"

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

# 检查subscribe-update.data文件不存在或者其中保存的日期超过30天
if [ ! -f "./subscribe-update.data" ] || [ $(( $(date +%s) - $(date +%s -r /root/subscribe-update.data) )) -gt 2592000 ]; then
    log "INFO" "订阅转换脚本已过期，重新下载..."
    rm -f /root/subscribe-update.data
    rm -rf /root/sing-box-subscribe
    rm -rf /opt/sing-box-subscribe
    # 克隆订阅转换脚本到/root目录下
    log "INFO" "更新订阅脚本..."
    git clone https://mirror.ghproxy.com/https://github.com/Toperlock/sing-box-subscribe.git /root/
    mv /root/sing-box-subscribe /opt/sing-box-subscribe
    # 安装依赖包
    log "INFO" "安装依赖包..."
    cd /opt/sing-box-subscribe
    python3 -m pip install -r requirements.txt
    rm -f /opt/sing-box-subscribe/config_template/*
    # 替换配置模板
    log "INFO" "下载配置模板..."
    curl -L ${CONFIG_URL} \
        -o /opt/sing-box-subscribe/config_template/
    # 将当前日期存储到subscribe-update.data文件中
    log "INFO" "更新完成，保存更新日期..."
    date > /root/subscribe-update.data
fi
# 转换订阅
log "INFO" "转换订阅..."
python3 main.py --template_index=0
# 备份原配置文件
log "INFO" "备份原配置文件..."
mv /etc/sing-box/config.json /etc/sing-box/config.json.$(date '+%Y%m%d%H%M%S')
# 替换配置文件
log "INFO" "替换配置文件..."
mv /opt/sing-box-subscribe/config.json /etc/sing-box/config.json
# 重启sing-box
log "INFO" "重启sing-box..."
rc-service sing-box restart
log "INFO" "更新启动完成！"
exit 0
