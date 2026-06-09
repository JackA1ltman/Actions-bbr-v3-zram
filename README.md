# Actions BBRv3 + ZRAM Kernel

面向 Debian/Ubuntu VPS 的 BBRv3 内核自动构建与安装项目。

本项目的核心目标很明确：**BBRv3 补丁固定，内核自动跟随 kernel.org 最新 stable 版本更新**。构建流程每天检查最新 stable 内核，下载对应 Linux stable 分支源码，然后把仓库内固定的 BBRv3 patch 打到新内核上并生成 Debian 包。

本内核默认启用Zstd压缩为默认，但提供LZ4，LZ4HC，LZO，DEFALTE等压缩算法。

## 当前策略

- 内核版本：自动读取 kernel.org 最新 stable 版本。
- BBR 版本：固定使用仓库内的 BBRv3 port patch，不自动更新 BBR 实现。
- 支持架构：`x86_64`、`arm64`。
- 构建产物：`linux-image`、`linux-headers`、`linux-libc-dev` 等 `.deb` 包。
- Debug 包：默认不编译、不上传、不发布 `linux-image-*-dbg`。
- 发布方式：每个架构和内核版本生成独立 GitHub Release tag，例如 `x86_64-7.0.11`、`arm64-7.0.11`。

## 自动更新边界

同一个内核主线系列内的小版本更新会自动复用同一个 patch。

例如：

```text
7.0.11 -> 7.0.12
使用 patches/bbrv3-linux-7.0.patch
```

如果 kernel.org 最新 stable 跳到新的主线系列，例如：

```text
7.0.x -> 7.1.x
```

构建脚本会寻找：

```text
patches/bbrv3-linux-7.1.patch
```

如果该 patch 不存在，构建会明确失败并停止。这是有意设计：跨主线系列时 TCP/BBR 相关代码可能变化，不能盲目把旧 patch 打上去。

## 安装

在 Debian/Ubuntu VPS 上执行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/byJoey/Actions-bbr-v3/main/install.sh)
```

脚本会从当前 GitHub Releases 中选择适合本机架构的内核包，并提供安装、检查、切换队列算法和卸载入口。

## 支持环境

| 项目 | 要求 |
| --- | --- |
| 架构 | `x86_64` / `aarch64` |
| 系统 | Debian 10+ / Ubuntu 18.04+ |
| 引导 | GRUB |
| 场景 | VPS / 云服务器 / 独立服务器 |

不建议在树莓派、NanoPi 等使用 U-Boot 或厂商定制内核链路的设备上使用。

## GitHub Actions 构建流程

构建流程在 `.github/workflows/build.yml` 中定义：

1. 读取 kernel.org 最新 stable 版本。
2. 检查当前架构对应 release 是否已经存在，存在则跳过。
3. 下载 `gregkh/linux` 的 `linux-X.Y.y` stable 分支。
4. 使用 `scripts/apply-bbrv3-port.sh` 应用固定 BBRv3 patch。
5. 套用对应架构 `.config` 并运行 `olddefconfig`。
6. 强制关闭 debug info，避免生成 `-dbg` 包。
7. 构建 Debian 包并发布到 GitHub Release。

手动触发：

```bash
gh workflow run build.yml
```

查看最近构建：

```bash
gh run list --limit 5
```

## BBRv3 Patch 管理

当前固定 patch：

```text
patches/bbrv3-linux-7.0.patch
```

脚本会根据内核源码 `Makefile` 中的 `VERSION` 和 `PATCHLEVEL` 自动选择对应 patch：

```text
linux-7.0.y -> patches/bbrv3-linux-7.0.patch
linux-7.1.y -> patches/bbrv3-linux-7.1.patch
```

这保证了两点：

- 小版本自动更新时不需要改 BBR。
- 新主线系列不兼容时会明确失败，避免产出不可验证的内核。

## 安全与配置

构建流程会在 `.config` 中强制关闭以下风险面：

- `CONFIG_AFS_FS`
- `CONFIG_AF_RXRPC`
- `CONFIG_RXKAD`
- `CONFIG_XFRM_ESP`
- `CONFIG_INET_ESP`
- `CONFIG_INET6_ESP`
- `CONFIG_SYSTEM_TRUSTED_KEYS`
- `CONFIG_SYSTEM_REVOCATION_KEYS`

同时关闭 debug info：

- `CONFIG_DEBUG_INFO`
- `CONFIG_DEBUG_INFO_BTF`
- `CONFIG_DEBUG_INFO_BTF_MODULES`

构建结束后会检查是否生成 `*-dbg*.deb`。如果出现 debug deb，workflow 会直接失败。

## 检测脚本

仓库提供 CVE-2026-31431 风险面检测脚本：

```bash
command -v python3 >/dev/null 2>&1 || (sudo apt update && sudo apt install -y python3)
curl -fsSL -o cve_2026_31431_detector.py https://raw.githubusercontent.com/byJoey/Actions-bbr-v3/main/cve_2026_31431_detector.py
chmod +x cve_2026_31431_detector.py
sudo python3 cve_2026_31431_detector.py
```

检测脚本只做本机风险面检查，不执行漏洞利用。

## 常用命令

检查当前 TCP 拥塞算法：

```bash
sysctl net.ipv4.tcp_congestion_control
```

检查当前默认队列算法：

```bash
sysctl net.core.default_qdisc
```

启用常见组合：

```bash
sudo sysctl -w net.ipv4.tcp_congestion_control=bbr
sudo sysctl -w net.core.default_qdisc=fq
```

确认当前内核版本：

```bash
uname -r
```

## 免责声明

内核升级有风险。安装前建议保留可启动的旧内核，并确认 VPS 控制台或救援模式可用。使用本项目构建或安装的内核造成的系统启动失败、网络异常或数据损失，由使用者自行承担。
