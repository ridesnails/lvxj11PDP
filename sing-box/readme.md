## sing-box折腾笔记
#### 感谢七尺宇，不良林，悟空的日常，安格视界，索拉里斯风
#### 部署方案
1. pve下使用lxc方式安装alpine3.20系统
2. 初始状态的alpine无ssh服务，在pve虚拟机控制台执行以下命令下载初始化脚本并运行，会自动进行以下工作：
   - 安装防火墙、ssh等必备软件
   - 清空防火墙规则，设置时区，允许root远程登陆
   - 配置开机启动防火墙，sshd，local，crond
   - 配置开机启用网络转发支持
   - 安装singbox并添加到开机启动
   - 下载更新脚本并添加到计划任务，默认每天凌晨2点运行
3. 重启lxc容器，之后可以使用ssh终端连接系统
4. 更新脚本中添加订阅地址，如有需要修改其他配置，比如模板文件
5. 手动执行一次更新脚本
#### 初始状态的alpine无ssh服务，在pve虚拟机控制台执行以下命令下载初始化脚本并运行
```
wget https://raw.githubusercontent.com/lvxj11/lvxj11PDP/refs/heads/main/sing-box/singbox-autoinit-alpine.sh
chmod +x singbox-autoinit-alpine.sh
./singbox-autoinit-alpine.sh
```
