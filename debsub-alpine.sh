#!/bin/sh
# 基础系统alpine3.20，安装python3用以部署sing-box-subscribe
# 安装必要软件
apk add --no-cache python3 py3-pip git
# 从github克隆sing-box-subscribe仓库
git clone -q https://github.com/Toperlock/sing-box-subscribe.git
# 改名为sing-box-subs
mv sing-box-subscribe sing-box-subs
cd sing-box-subs
# 建立虚拟环境
python3 -m venv venv
source venv/bin/activate
# 安装依赖包
pip3 install -r requirements.txt
