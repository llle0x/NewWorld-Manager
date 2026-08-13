# NewWorld-Manager

用于管理 Linux BBR、Snell Server、shadowsocks-rust（SS-2022）、ShadowTLS v3 和 V2Fly VMess 的独立 Bash 脚本。组件只从各自官方发布源下载，不执行第三方安装脚本。

## 主要功能

- Snell、SS-2022、ShadowTLS、VMess 均支持 `1–99` 多实例。
- 首次安装直接回车使用实例 `1`。
- 已有实例时，输入新编号创建实例，直接回车检查并更新全部现有实例。
- 查看配置时选择组件即可显示该组件全部实例；命令行可指定单个实例。
- ShadowTLS 可绑定到指定 Snell/SS-2022 实例，同一后端也可配置多个 ShadowTLS 入口。
- VMess 使用 V2Fly 官方核心，支持 TCP 和 WebSocket + TLS，默认使用 AEAD（`alterId: 0`）。
- 更新前先检查官方版本；已是最新版时不下载、不重启。
- 多实例批量更新任一服务启动失败时，恢复旧二进制并重启全部实例。
- 旧版单实例配置会自动迁移为实例 `1`。

## 支持环境

- 使用 systemd 的 Linux。
- 包管理器：APT、DNF、YUM、Zypper、Pacman、APK。
- 发行版包括 Debian/Ubuntu、Fedora/RHEL/Oracle/Rocky/Alma/Amazon Linux、openSUSE、Arch Linux，以及运行 systemd 的 Alpine。
- 架构：x86_64、aarch64；部分组件还提供 armv7/arm。

SS-2022 与 ShadowTLS 使用官方 musl 静态构建，V2Fly 也提供多种 Linux 架构发行包。Snell 官方 Linux 二进制通常要求 glibc；在 Alpine/musl 上可能需要兼容层，脚本会在二进制无法执行时给出明确错误。

建议至少 256 MiB 内存。依赖按组件延迟安装：Snell 不需要 `jq`/`xz`；SS-2022、ShadowTLS 和 VMess 使用 `jq` 解析 GitHub 官方发布信息或管理 JSON 配置。

## 安装与使用

打开交互菜单：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/nihcuijp/NewWorld-Manager/main/newworld-manager.sh)"
```

安装全局命令后使用：

```bash
nw-manager
nw-manager status
nw-manager doctor
nw-manager check-update
```

常用命令：

```bash
nw-manager install snell
nw-manager install ss2022
nw-manager install shadowtls
nw-manager install vmess
nw-manager update snell
nw-manager update vmess
nw-manager configure snell
nw-manager config snell          # 显示全部 Snell 实例
nw-manager config snell 1        # 只显示实例 1
nw-manager logs shadowtls 100 1
nw-manager restart ss2022 1
nw-manager remove shadowtls 1
```

## 实例与更新规则

- 首次安装提示 `首次安装实例编号 [1]`，直接回车创建实例 `1`。
- 已有实例时提示 `输入新编号安装实例，直接回车更新现有实例`。
- 输入已存在编号不会覆盖配置；脚本会提示直接回车执行更新。
- Snell 多实例共享官方服务端二进制，因此新增实例会沿用现有实例的 v5/v6 协议，避免混用导致服务异常。
- 更新只替换二进制并保留端口、密码、PSK、SNI 和其他配置。
- 命令行 `nw-manager update <组件>` 不再询问实例号，会直接检查并更新该组件的全部实例，便于自动化。
- `configure` 会重新生成所选实例配置；若失败会恢复此前配置和服务状态。
- VMess WebSocket + TLS 会将已有证书和私钥安全复制到实例目录；证书续期后执行 `nw-manager update vmess` 可同步并重启相应实例。

## 配置输出

- Snell：Surge `[Proxy]` 配置行及完整服务端配置。
- SS-2022：`ss://` 链接或经 ShadowTLS 的 Surge 配置，以及完整服务端 JSON。
- ShadowTLS：外部地址、端口、密码、SNI、后端实例和配套的后端客户端配置。
- VMess：完整 `vmess://` 链接、客户端 JSON 及服务器 JSON。
- 一个后端绑定多个 ShadowTLS 时，会分别输出每个 ShadowTLS 入口的客户端配置。

配置包含密钥，请勿公开分享。

## 安全与可靠性

- 配置文件权限为 `0640`，仅 root 和专用服务用户 `newworld-proxy` 可读。
- 普通 VPS 上服务使用低权限用户和 systemd 加固；受限容器中自动采用兼容模式。
- 二进制原子替换，批量更新失败时整体回滚。
- shadowsocks-rust 发布资产提供摘要时会校验 SHA-256；没有机器可读摘要时会明确警告并验证二进制可执行。
- 防火墙只删除脚本自己添加并记录的 UFW/firewalld 规则。
- BBR 使用独立的 `/etc/sysctl.d/99-newworld-bbr.conf`，不修改 `/etc/sysctl.conf`。
- 自更新先执行 Bash 语法检查，再原子替换全局脚本。

## 文件位置

- 配置：`/etc/newworld-manager`
- 二进制：`/usr/local/lib/newworld-manager`
- systemd：`newworld-snell-<实例>.service`、`newworld-ss2022-<实例>.service`、`newworld-shadowtls-<实例>.service`、`newworld-vmess-<实例>.service`
- 全局命令：`/usr/local/bin/nw-manager` → `/usr/local/sbin/newworld-manager`

## 官方来源

- [Snell 官方发布说明](https://kb.nssurge.com/surge-knowledge-base/release-notes/snell)
- [shadowsocks-rust](https://github.com/shadowsocks/shadowsocks-rust)
- [ShadowTLS](https://github.com/ihciah/shadow-tls)
- [V2Fly / V2Ray Core](https://github.com/v2fly/v2ray-core)
- [VMess 官方配置文档](https://www.v2fly.org/config/protocols/vmess.html)
- [Linux 网络 sysctl 文档](https://docs.kernel.org/admin-guide/sysctl/net.html)

## 许可

MIT
