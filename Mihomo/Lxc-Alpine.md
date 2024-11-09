## 在lxc中部署alpine镜像步骤

#### 安装必要软件
``` sh
apk update
apk upgrade
apk add curl nftables openssh net-tools
```

#### 配置服务开机启动
``` sh
rc-service nftables start
rc-update add nftables default
rc-service sshd start
rc-update add sshd default
# 开机执行脚本服务
rc-update add local default
```

#### 配置系统内核允许转发
转发是作为网关的必要能力，否则流量进入后不经过代理就不能到达外网。不开代理不能访问外网，开启代理只能访问被代理处理的流量。绕过代理的流量不能访问外网。
```
# 添加到/etc/sysctl.conf
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
```
```
# 或者执行
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv6.conf.all.forwarding=1
```
```
# 启用转发
sysctl -p
# 确认转发启用
cat /proc/sys/net/ipv4/ip_forward
# 或
sysctl net.ipv4.ip_forward
```
#### 添加转发开启脚本到开机启动
允许转发重启后会失效
```
# 脚本存放目录/etc/local.d/
echo -e "#!/bin/sh\nsysctl -w net.ipv4.ip_forward=1\nsysctl -w net.ipv6.conf.all.forwarding=1" > /etc/local.d/enable_forwarding.start
chmod +x /etc/local.d/enable_forwarding.start
```
#### 路由表设置
```
ip route add local default dev lo table 100
ip rule add fwmark 1 table 100
```

nftables配置文件：
```
/etc/nftables.nft
```

修改配置文件后应用修改：
```
rc-service nftables restart
```

查看确认路由规则：
```
nft list ruleset
```

注意默认规则入站出站转发的接受或拒绝

#### 安装应用，如shellcrash
#### 安装测试版软件，如sing-box
```
apk add sing-box --update-cache --repository http://dl-cdn.alpinelinux.org/alpine/edge/testing/ --allow-untrusted
```
