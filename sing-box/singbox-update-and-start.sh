#!/bin/sh

# 克隆订阅转换脚本到/root目录下
echo "克隆订阅转换脚本..."
git clone https://github.com/Toperlock/sing-box-subscribe.git /root
echo "移动到opt目录并删除自带模板文件..."
mv /root/sing-box-subscribe /opt/sing-box-subscribe
rm -f /opt/sing-box-subscribe/config_template/*
echo "下载自定义配置模板到模板目录..."
curl -L https://raw.githubusercontent.com/lvxj11/lvxj11PDP/refs/heads/main/sing-box/singbox-qcy-mod-tun.json \
    -o /opt/sing-box-subscribe/config_template/
