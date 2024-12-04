#!/bin/sh
# 在alpine中部署singbox和订阅转换，并自动化更新。
set -e
# 判断脚本是否有root权限
if [ "$(id -u)" != "0" ]; then
    echo "请使用root用户运行脚本！"
    exit 1
fi
SINGBOX_RUNSCRIBE="https://mirror.ghproxy.com/https://raw.githubusercontent.com/lvxj11/lvxj11PDP/refs/heads/main/sing-box/singbox-update-and-start.sh"
# 初始化Alpine系统，适配版本3.20
echo "初始化 Alpine 系统..."
apk update
apk upgrade
echo "安装常用工具..."
apk add curl nftables openssh net-tools tzdata jq git python3 py3-pip
# 设定时区
echo "设置时区..."
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
echo "Asia/Shanghai" > /etc/timezone
# 修改sshd_config，允许root远程登录
echo "修改 sshd 配置，允许root远程登录..."
echo -e "PermitRootLogin yes" >> /etc/ssh/sshd_config
# 备份并清空nftables.nft文件，防止默认规则影响。
echo "清空 nftables 规则..."
mv /etc/nftables.nft /etc/nftables.nft.bak
# 新建空nft文件
touch /etc/nftables.nft

# 启动服务,并将所需服务添加到系统启动项
echo "启动nftables, sshd服务..."
rc-service nftables start
rc-service sshd start
echo "添加服务到启动项..."
# 给与nftables服务boot运行级
rc-update add nftables boot
# 其他服务使用默认运行级
rc-update add sshd default
# 开机执行脚本服务
rc-update add local default
# 计划任务服务
rc-update add crond default
# 开启转发
echo "设置开启转发支持..."
echo -e "#!/bin/sh\nsysctl -w net.ipv4.ip_forward=1\nsysctl -w net.ipv6.conf.all.forwarding=1" > /etc/local.d/enable_forwarding.start
chmod +x /etc/local.d/enable_forwarding.start
/etc/local.d/enable_forwarding.start

# 安装singbox
apk add sing-box --update-cache --repository http://dl-cdn.alpinelinux.org/alpine/edge/testing/ --allow-untrusted
rc-update add sing-box default
# 建立/opt/sing-box-update-and-start文件夹
mkdir -p /opt/sing-box-update-and-start
# 下载singbox升级和开始脚本
wget -O /opt/sing-box-update-and-start/singbox-update-and-start.sh ${SINGBOX_RUNSCRIBE}
chmod +x /opt/sing-box-update-and-start/singbox-update-and-start.sh
echo "{}" > /opt/sing-box-update-and-start/settings.json
# 添加计划任务每天凌晨2点运行一次
echo "添加计划任务..."
echo "0 2 * * * /opt/sing-box-update-and-start/singbox-update-and-start.sh" >> /etc/crontabs/root
# 安装完成
echo "安装完成。"
echo "在/opt/sing-box-update-and-start/settings.json文件中添加参数，"
echo "或修改/opt/sing-box-update-and-start/singbox-update-and-start.sh脚本中的参数。"
echo "执行一次获取配置文件，测试是否正常运行。"
echo "建议重启一次应用所有更改并验证。"
exit 0
