在 Alpine 3.20 系统上使用 `nftables` 配置 `sing-box` 代理，以实现 `tproxy` 模式透明代理的步骤如下。此流程包括清空防火墙、DNS 劫持、TCP/UDP 流量劫持，以及绕过中国大陆 IP 的设置。请按照以下步骤进行配置。

### 1. 清空防火墙规则

首先，确保没有其他规则影响配置。

```bash
nft flush ruleset
```

### 2. 设置 `nftables` 基本表和链

新建一个 `nftables` 配置文件（例如 `/etc/nftables.conf`），并定义表和链。也可以直接在命令行配置。

```bash
# 创建新表
nft add table ip myfilter

# 创建新链 prerouting 用于处理入站流量
nft add chain ip myfilter prerouting { type filter hook prerouting priority mangle\; }
```

### 3. 配置 DNS 请求劫持

将所有 DNS 请求劫持到代理的 DNS 端口，以确保域名解析通过代理进行。

```bash
# 劫持 DNS 到代理端口，例如代理的 DNS 端口为 1053
nft add rule ip myfilter prerouting udp dport 53 redirect to 1053
```

### 4. 配置 TCP 和 UDP 流量劫持

为了确保 `sing-box` 能够接管 TCP 和 UDP 流量，我们将指定的 TCP 端口和所有 UDP 流量转发到代理。例如，假设代理监听的透明代理端口为 `7893`。（如果只劫持ipv4流量将meta l4proto替换为ip protocol）

```bash
# 劫持常用的 TCP 端口到代理
nft add rule ip myfilter prerouting meta l4proto tcp \
    tcp dport { 22, 80, 443, 465, 993, 995, 8080, 8443 } \
    tproxy to :7893

# 劫持所有 UDP 流量到代理
nft add rule ip myfilter prerouting meta l4proto udp \
    tproxy to :7893
```

### 5. 绕过中国大陆 IP

要绕过大陆 IP，使用 `chnroute` 或其他国内 IP 段列表，将其导入到 `nftables` 配置中。这样，匹配大陆 IP 的流量将直接通过，不经过代理。

1. **生成 `chnroute` 列表**：从 `ipip.net` 或其他资源下载最新的中国大陆 IP 列表，生成 `chnroute.nft` 文件。

2. **导入 `chnroute` 列表到 `nftables`**：

   ```bash
   nft -f /path/to/chnroute.nft
   ```

3. **设置绕过规则**：对于 `chnroute` 中的 IP 地址，直接接受，不走代理。

   ```bash
   # 假设 chnroute 列表已导入
   nft add rule ip myfilter prerouting ip daddr @chnroute return
   ```

   在这条规则中，`ip daddr @chnroute return` 表示当目标 IP 地址在 `chnroute` 列表中时，直接通过，不劫持流量。

### 6. 配置默认代理规则

确保剩余的非大陆 IP 流量被 `tproxy` 代理接管。在链末尾添加默认规则，将其他 TCP 和 UDP 流量代理至 `sing-box`。

```bash
# 劫持所有 TCP 和 UDP 流量至透明代理
nft add rule ip myfilter prerouting meta l4proto { tcp, udp } tproxy to :7893
```

### 7. 启用和测试配置

1. 启用 `nftables` 防火墙配置：

   ```bash
   nft -f /etc/nftables.conf
   ```

2. 确保 `sing-box` 代理正常运行，并正确监听透明代理端口 `7893` 和 DNS 劫持端口 `1053`。

3. **测试连接**：验证流量是否按预期通过代理。可以通过检查流量路由或代理日志确认流量是否正常劫持。
## 其他相关
`chnroute.nft` 文件是一个包含中国大陆 IP 段的 `nftables` 配置文件，通常用于在防火墙中定义一组 IP 地址，以实现流量绕过。生成该文件的过程通常涉及下载或更新大陆 IP 列表，并将其格式化为 `nftables` 支持的方式。

### 1. `chnroute.nft` 文件的格式

在 `nftables` 中，可以通过设置 IP 集合（set）来存储 `chnroute` IP 段。下面是一个 `chnroute.nft` 文件的基本格式示例：

```nft
table ip myfilter {
    set chnroute {
        type ipv4_addr
        flags interval
        elements = { 
            1.0.1.0/24,
            1.0.2.0/23,
            1.0.8.0/21,
            1.1.0.0/24,
            1.1.1.0/30,
            1.2.0.0/16,
            ...
        }
    }
}
```

在这个文件中：

- `table ip myfilter` 是创建的 `nftables` 表。
- `set chnroute` 定义了一个名为 `chnroute` 的集合，用于存储中国大陆 IP 地址段。
- `type ipv4_addr` 指定集合的元素类型为 IPv4 地址。
- `flags interval` 允许使用 IP 段（如 `1.0.1.0/24`）作为集合元素。
- `elements = { ... }` 是大陆 IP 段列表。

### 2. 如何生成 `chnroute.nft`

以下是生成 `chnroute.nft` 的步骤：

#### 步骤 1：下载最新的大陆 IP 列表

可以从公开资源（如 `ipip.net` 或 GitHub 上的 `chnroute` 项目）获取最新的大陆 IP 列表。运行以下命令下载并保存：

```bash
curl -o chnroute.txt https://raw.githubusercontent.com/17mon/china_ip_list/master/china_ip_list.txt
```

#### 步骤 2：格式化大陆 IP 列表为 `nftables` 格式

运行以下命令，将 `chnroute.txt` 转换为 `chnroute.nft` 文件的格式：

```bash
echo "table ip myfilter {" > chnroute.nft
echo "    set chnroute {" >> chnroute.nft
echo "        type ipv4_addr" >> chnroute.nft
echo "        flags interval" >> chnroute.nft
echo -n "        elements = { " >> chnroute.nft

# 将每行 IP 段转化为 nftables 格式，添加逗号并去掉最后一个逗号
awk '{ printf "%s, ", $1 }' chnroute.txt | sed 's/, $//g' >> chnroute.nft

echo " }" >> chnroute.nft
echo "    }" >> chnroute.nft
echo "}" >> chnroute.nft
```

这样会生成包含 `chnroute` 集合的 `chnroute.nft` 文件。

#### 步骤 3：在 `nftables` 中导入 `chnroute.nft`

将生成的 `chnroute.nft` 文件导入 `nftables` 配置：

```bash
nft -f chnroute.nft
```

或者将其包含在主配置文件 `/etc/nftables.conf` 中：

```nft
include "/path/to/chnroute.nft"
```

完成上述步骤后，`chnroute` 集合即包含了所有大陆 IP 段，可以在防火墙规则中使用 `ip daddr @chnroute` 来绕过国内 IP。
