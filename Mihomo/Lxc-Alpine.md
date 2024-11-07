## 在lxc中部署alpine镜像步骤

#### 安装必要软件

··· sh
apk update
apk upgrade
apk add curl nftables openssh net-tools
···

#### 配置服务开机启动

··· sh
rc-service nftables start
rc-update add nftables default
rc-service sshd start
rc-update add sshd default
···

nftables配置文件：
`/etc/nftables.nft`

查看路由规则
`nft list ruleset`

注意默认规则入站出站转发的接受或拒绝

#### 安装应用，如shellcrash
