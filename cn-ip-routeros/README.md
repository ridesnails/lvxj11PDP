# CN IP RouterOS Script Generator

一个用于下载中国IP地址列表并生成RouterOS脚本的工具，包含IPv4和IPv6地址段。

## 功能特性

- 自动从 GitHub 下载最新的中国IP列表（IPv4和IPv6）
- 自动区分IPv4和IPv6网段
- 生成符合RouterOS格式的脚本文件
- 支持自定义地址列表名称
- 脚本具有幂等性，可重复执行

## 依赖

- `curl` 或 `wget`

## 使用方法

### 方法一：直接下载仓库中已生成的脚本

```bash
# 直接下载最新版本
curl -o cn-ip-routeros.rsc https://raw.githubusercontent.com/lvxj11/lvxj11Mixed/main/cn-ip-routeros/dist/cn-ip-routeros.rsc
```

### 方法二：本地运行脚本生成

```bash
# 基本用法
./download-cn-ip.sh

# 自定义列表名称和输出文件
./download-cn-ip.sh -l china-ip -o china-ip.rsc
```

## 选项

| 选项 | 描述 | 默认值 |
|------|------|--------|
| `-l, --list-name NAME` | 设置地址列表名称 | CN-IP |
| `-o, --output FILE` | 设置输出文件名 | cn-ip-routeros.rsc |
| `-h, --help` | 显示帮助信息 | - |

## 在RouterOS中导入脚本

### 方法一：通过Winbox

1. 打开Winbox
2. 进入 `Files` 菜单
3. 上传生成的 `.rsc` 文件到RouterOS设备
4. 在终端中执行：`/import cn-ip-routeros.rsc`

### 方法二：通过SSH

```bash
scp cn-ip-routeros.rsc admin@router-ip:/
ssh admin@router-ip "/import cn-ip-routeros.rsc"
```

## 生成的脚本内容

生成的RouterOS脚本包含以下操作：

1. 定义列表名称变量
2. 清除旧的地址列表条目（确保幂等性）
3. 添加所有IPv4地址段到地址列表
4. 添加所有IPv6地址段到地址列表
5. 输出完成信息

## 数据源

IP列表来源于：[MetaCubeX/meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat)

## 注意事项

- 该列表包含大量IP段，导入时可能需要几分钟时间
- 建议在维护窗口执行导入操作
- 脚本执行前会清除同名列表的所有条目，请确保列表名称不会影响其他配置