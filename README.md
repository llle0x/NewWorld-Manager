# NewWorld Manager

一个完全独立实现的 Linux 管理脚本，用于管理：

- Linux 原生 BBR
- Snell Server
- shadowsocks-rust / SS-2022
- ShadowTLS v3

组件程序仅从各自官方发布源下载，不执行第三方安装脚本。

## 安全设计

- BBR 使用独立的 `/etc/sysctl.d/99-newworld-bbr.conf`，不会覆盖 `/etc/sysctl.conf`。
- shadowsocks-rust 使用 GitHub 官方发布的 SHA-256 摘要校验。
- 所有代理服务使用专用的低权限系统用户 `newworld-proxy`。
- 程序与配置目录归属 `root:newworld-proxy` 且使用 `0750`，启动前会验证服务用户确实能够执行二进制。
- 配置和密钥只允许 root 与服务用户读取。
- systemd 单元启用权限收敛与文件系统保护。
- 防火墙只管理本工具自己添加的 UFW/firewalld 规则。
- ShadowTLS 启用时自动把后端绑定到回环地址；卸载时恢复原绑定。
- 二进制更新使用原子替换；新版本启动失败时自动回滚旧版本。
- 重新配置和 Snell 协议切换失败时自动恢复原配置、二进制与服务状态。

## Snell 可选项

- Snell v5 稳定版或 Snell v6；版本始终从 Surge 官方发布页解析，优先正式版，没有正式版时选择编号最高的预发布版。
- 自定义端口与 PSK，或生成 32 位随机 PSK。
- TCP Fast Open 与自定义 DNS。
- v5：IPv6 解析、HTTP OBFS 与 OBFS 域名；同时管理 QUIC Proxy 所需的 UDP 端口。
- v6：IPv4/IPv6 双栈监听、DNS IP 偏好，以及 `default`、`unshaped`、`unsafe-raw` 流量模式。

Snell v6 目前仍是官方 RC 版本；脚本会在安装预发布版时明确提示。未来 v6 正式版沿用官方命名与配置格式时会被自动采用。`unsafe-raw` 会降低流量整形保护，除非了解其影响，否则保留 `default`。
已停止维护的 Snell v2-v4 不列入新安装选项。
新的主协议版本（例如 v7）不会自动启用；需要先核对官方配置和兼容性，再更新本工具。

> ShadowTLS 官方当前没有为发布资产提供机器可读校验摘要。本工具会明确警告，并验证下载的程序能够正常报告版本后才安装。

## 支持环境

- 使用 systemd 的 Linux
- Debian / Ubuntu、Fedora / RHEL 系、Alpine（Snell 官方二进制依赖 glibc）
- x86_64、aarch64；部分组件支持 armv7/arm

建议至少 256 MiB 内存。依赖会按组件延迟安装：Snell 不需要 `jq` 或 `xz`；ss-2022 和 ShadowTLS 才会安装各自需要的额外工具。
在受限 Docker/LXC 容器中，服务会自动改为 root 运行并移除依赖 Linux 命名空间的 systemd 沙箱选项；普通 VPS 仍以低权限用户运行并保留加固。

Snell 协议直接使用 `5/6` 选择对应版本；布尔项、DNS IP 偏好、流量模式与 HTTP OBFS 使用 `1/2/3` 数字选择，同时兼容对应的文本值输入。
菜单中的查看配置、日志、重启与卸载操作也使用数字选择组件，无需手动输入组件名称。

## 使用

直接打开交互菜单：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/nihcuijp/world-manager/main/newworld-manager.sh)"
```

或下载后运行：

```bash
curl -fsSLo newworld-manager.sh https://raw.githubusercontent.com/nihcuijp/world-manager/main/newworld-manager.sh
chmod +x newworld-manager.sh
sudo ./newworld-manager.sh
```

安装全局命令：

```bash
sudo ./newworld-manager.sh self-install
sudo nw-manager status
```

命令行示例：

```bash
sudo ./newworld-manager.sh install bbr
sudo ./newworld-manager.sh install snell
sudo ./newworld-manager.sh install ss2022
sudo ./newworld-manager.sh install shadowtls

sudo ./newworld-manager.sh update ss2022
sudo ./newworld-manager.sh configure ss2022
sudo ./newworld-manager.sh config snell
sudo ./newworld-manager.sh logs shadowtls 200
sudo ./newworld-manager.sh remove shadowtls
sudo ./newworld-manager.sh check-update
```

菜单选项 `11` 或命令 `check-update` 会从公开仓库下载脚本、通过 Bash 语法检查并比较版本；发现新版后可直接更新全局 `nw-manager` 命令。搭配 `-y` 可自动确认更新。

## 文件位置

- 配置：`/etc/newworld-manager`
- 二进制：`/usr/local/lib/newworld-manager`
- systemd：`newworld-snell.service`、`newworld-ss2022.service`、`newworld-shadowtls.service`
- 全局命令：`/usr/local/bin/nw-manager`

## 官方来源

- Snell: <https://kb.nssurge.com/surge-knowledge-base/release-notes/snell>
- shadowsocks-rust: <https://github.com/shadowsocks/shadowsocks-rust>
- ShadowTLS: <https://github.com/ihciah/shadow-tls>
- Linux 网络参数文档: <https://docs.kernel.org/admin-guide/sysctl/net.html>

## 许可

MIT
