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
```

#### 配置系统内核允许转发
```
# 添加到/etc/sysctl.conf
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
```
```
# 启用转发
sysctl -p
# 确认转发启用
cat /proc/sys/net/ipv4/ip_forward
# 或
sysctl net.ipv4.ip_forward
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
