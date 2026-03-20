#!/bin/sh
# 用来记录自定义脚本执行日志
set -e
LOGFILE=/var/log/custom-scripts.log

# 控制日志文件大小
check_logfile_size() {
    # 如果日志文件超过6000行则只保留5000行
    if [ $(wc -l < $LOGFILE) -gt 6000 ]; then
        tail -n 5000 $LOGFILE > $LOGFILE.tmp
        mv $LOGFILE.tmp $LOGFILE
    fi
}

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $*" >> $LOGFILE
}

log "$*"
check_logfile_size

set +e
exit 0
