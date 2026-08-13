#!/usr/bin/env bash
# NewWorld-Manager
# Independent Linux manager for BBR, Snell, Shadowsocks 2022 and ShadowTLS.
# It never downloads or executes third-party installation scripts.

set -Eeuo pipefail
umask 027

readonly APP="NewWorld-Manager"
readonly VERSION="5.0.0"
readonly SOURCE_URL="https://raw.githubusercontent.com/nihcuijp/NewWorld-Manager/main/newworld-manager.sh"
readonly ROOT_DIR="/etc/newworld-manager"
readonly LIB_DIR="/usr/local/lib/newworld-manager"
readonly BIN_DIR="/usr/local/bin"
readonly SYSTEMD_DIR="/etc/systemd/system"
readonly SERVICE_USER="newworld-proxy"
readonly FIREWALL_DB="$ROOT_DIR/firewall.rules"
readonly SNELL_BIN="$LIB_DIR/snell-server"
readonly SS_BIN="$LIB_DIR/ssserver"
readonly STLS_BIN="$LIB_DIR/shadow-tls"
readonly SNELL_SERVICE="newworld-snell.service"
readonly SS_SERVICE="newworld-ss2022.service"
readonly SNELL_ROOT="$ROOT_DIR/snell"
readonly SS_ROOT="$ROOT_DIR/ss2022"
readonly STLS_SERVICE_PREFIX="newworld-shadowtls"
readonly STLS_ROOT="$ROOT_DIR/shadowtls"

YES=false
UPDATE_ONLY=false
NO_COLOR="${NO_COLOR:-}"
PUBLIC_IP_CACHE=""
declare -a TEMP_PATHS=()
for _arg in "$@"; do [[ "$_arg" == "--no-color" ]] && NO_COLOR=1; done
unset _arg

if [[ -t 1 && -z "$NO_COLOR" ]]; then
    readonly RED=$'\033[31m' GREEN=$'\033[32m' YELLOW=$'\033[33m'
    readonly CYAN=$'\033[36m' BOLD=$'\033[1m' RESET=$'\033[0m'
else
    readonly RED='' GREEN='' YELLOW='' CYAN='' BOLD='' RESET=''
fi

info() { printf '%s[信息]%s %s\n' "$CYAN" "$RESET" "$*"; }
ok() { printf '%s[完成]%s %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '%s[警告]%s %s\n' "$YELLOW" "$RESET" "$*" >&2; }
die() { printf '%s[错误]%s %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

new_temp_file() {
    local variable="$1" path
    path="$(mktemp /tmp/newworld-manager.XXXXXX)"
    TEMP_PATHS+=("$path")
    printf -v "$variable" '%s' "$path"
}

new_temp_dir() {
    local variable="$1" path
    path="$(mktemp -d /tmp/newworld-manager.XXXXXX)"
    TEMP_PATHS+=("$path")
    printf -v "$variable" '%s' "$path"
}

cleanup_temp_paths() {
    local path
    trap - EXIT
    for path in "${TEMP_PATHS[@]}"; do
        [[ "$path" == /tmp/newworld-manager.* ]] && rm -rf -- "$path"
    done
}

trap cleanup_temp_paths EXIT

require_linux() { [[ "$(uname -s)" == Linux ]] || die "仅支持 Linux。"; }
require_root() { [[ "$(id -u)" -eq 0 ]] || die "请使用 root 或 sudo 运行。"; }
require_systemd() { [[ -d /run/systemd/system ]] || die "系统未运行 systemd。"; }

confirm() {
    local message="$1" answer
    $YES && return 0
    [[ -t 0 ]] || return 1
    read -r -p "$message [y/N] " answer
    [[ "$answer" =~ ^[Yy]$ ]]
}

prompt_default() {
    local prompt="$1" default="$2" value
    read -r -p "$prompt [$default]: " value
    printf '%s' "${value:-$default}"
}

select_boolean() {
    local label="$1" default="$2" input default_number
    [[ "$default" == true ]] && default_number=1 || default_number=2
    printf '%s：1) 开启（true）  2) 关闭（false）\n' "$label" >&2
    read -r -p "请选择 [1-2，默认 $default_number]: " input
    case "$input" in
        ""|"$default_number"|"$default") printf '%s' "$default" ;;
        1|true) printf true ;;
        2|false) printf false ;;
        *) die "$label 请选择 1 或 2。" ;;
    esac
}

select_snell_protocol() {
    local default="$1" input
    printf 'Snell 协议：5) v5 稳定版  6) v6（自动优先正式版）\n' >&2
    read -r -p "请选择 [5/6，默认 $default]: " input
    case "$input" in
        ""|"$default") printf '%s' "$default" ;;
        5) printf 5 ;;
        6) printf 6 ;;
        *) die "Snell 协议版本请选择 5 或 6。" ;;
    esac
}

select_dns_preference() {
    local input
    printf 'DNS IP 偏好：1) default  2) prefer-ipv4  3) prefer-ipv6  4) ipv4-only  5) ipv6-only\n' >&2
    read -r -p '请选择 [1-5，默认 1]: ' input
    case "$input" in
        ""|1|default) printf default ;;
        2|prefer-ipv4) printf prefer-ipv4 ;;
        3|prefer-ipv6) printf prefer-ipv6 ;;
        4|ipv4-only) printf ipv4-only ;;
        5|ipv6-only) printf ipv6-only ;;
        *) die "DNS IP 偏好请选择 1-5。" ;;
    esac
}

select_snell_mode() {
    local input
    printf 'v6 流量模式：1) default  2) unshaped  3) unsafe-raw\n' >&2
    read -r -p '请选择 [1-3，默认 1]: ' input
    case "$input" in
        ""|1|default) printf default ;;
        2|unshaped) printf unshaped ;;
        3|unsafe-raw) printf unsafe-raw ;;
        *) die "v6 流量模式请选择 1-3。" ;;
    esac
}

select_snell_obfs() {
    local input
    printf 'HTTP OBFS：1) 关闭（off）  2) HTTP（http）\n' >&2
    read -r -p '请选择 [1-2，默认 1]: ' input
    case "$input" in
        ""|1|off) printf off ;;
        2|http) printf http ;;
        *) die "HTTP OBFS 请选择 1 或 2。" ;;
    esac
}

select_component() {
    local include_bbr="${1:-false}" input
    printf '组件：1) Snell  2) ss-2022  3) ShadowTLS' >&2
    [[ "$include_bbr" != true ]] || printf '  4) BBR' >&2
    printf '\n' >&2
    if [[ "$include_bbr" == true ]]; then
        read -r -p '请选择 [1-4]: ' input
    else
        read -r -p '请选择 [1-3]: ' input
    fi
    case "$input" in
        1) printf snell ;;
        2) printf ss2022 ;;
        3) printf shadowtls ;;
        4)
            if [[ "$include_bbr" == true ]]; then printf bbr; else die "请选择 1-3。"; fi ;;
        *)
            if [[ "$include_bbr" == true ]]; then die "请选择 1-4。"; else die "请选择 1-3。"; fi ;;
    esac
}

valid_port() { [[ "$1" =~ ^[0-9]+$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 )); }
valid_host() { [[ "$1" =~ ^[A-Za-z0-9.-]+$ && "$1" == *.* && "$1" != .* && "$1" != *. ]]; }
valid_psk() { [[ ${#1} -ge 16 && ${#1} -le 255 && "$1" =~ ^[A-Za-z0-9._~-]+$ ]]; }
valid_dns() { [[ "$1" =~ ^[A-Za-z0-9.,:_-]+$ ]]; }
port_unused() { ! ss -H -lntup 2>/dev/null | awk '{print $5}' | grep -Eq "(^|[.:])$1$"; }
ipv6_available() {
    [[ -r /proc/sys/net/ipv6/conf/all/disable_ipv6 ]] && [[ "$(</proc/sys/net/ipv6/conf/all/disable_ipv6)" == 0 ]] && ip -6 addr show scope global 2>/dev/null | grep -q 'inet6 '
}

version_is_newer() {
    local candidate="$1" current="$2" candidate_major candidate_minor candidate_patch current_major current_minor current_patch
    [[ "$candidate" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || return 1
    candidate_major="${BASH_REMATCH[1]}"; candidate_minor="${BASH_REMATCH[2]}"; candidate_patch="${BASH_REMATCH[3]}"
    [[ "$current" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || return 1
    current_major="${BASH_REMATCH[1]}"; current_minor="${BASH_REMATCH[2]}"; current_patch="${BASH_REMATCH[3]}"
    (( 10#$candidate_major > 10#$current_major )) ||
        (( 10#$candidate_major == 10#$current_major && 10#$candidate_minor > 10#$current_minor )) ||
        (( 10#$candidate_major == 10#$current_major && 10#$candidate_minor == 10#$current_minor && 10#$candidate_patch > 10#$current_patch ))
}

random_port() {
    local port
    for _ in {1..100}; do
        port=$((RANDOM % 45536 + 20000))
        port_unused "$port" && { printf '%s' "$port"; return 0; }
    done
    return 1
}

random_text() {
    local length="$1"
    openssl rand -hex "$(( (length + 1) / 2 ))" | cut -c "1-$length"
}

random_base64() {
    local bytes="$1"
    if have openssl; then openssl rand -base64 "$bytes" | tr -d '\n'
    else head -c "$bytes" /dev/urandom | base64 | tr -d '\n'; fi
}

base64url() { base64 | tr '+/' '-_' | tr -d '=\n'; }

print_config_block() {
    local title="$1" content="$2"
    printf '\n========== %s ==========' "$title"
    printf '\n%s\n' "$content"
    printf '%s\n' '================================'
}

shadowtls_target_active() {
    local target="$1" backend_instance="${2:-}" instance candidate
    shadowtls_migrate_legacy
    while read -r instance; do
        [[ -z "$instance" ]] && continue
        [[ "$(read_meta "$(shadowtls_instance_dir "$instance")/meta" TARGET 2>/dev/null || true)" == "$target" ]] || continue
        candidate="$(read_meta "$(shadowtls_instance_dir "$instance")/meta" TARGET_INSTANCE 2>/dev/null || printf 1)"
        [[ -z "$backend_instance" || "$candidate" == "$backend_instance" ]] && return 0
    done < <(shadowtls_instance_dirs)
    return 1
}

shadowtls_surge_options() {
    local instance_dir="$1" env="$1/environment" password sni
    password="$(read_meta "$env" PASSWORD)"; sni="$(read_meta "$env" TLS_HOST)"
    printf 'shadow-tls-password=%s, shadow-tls-sni=%s, shadow-tls-version=3' "$password" "$sni"
}

shadowtls_service() { printf '%s-%s.service' "$STLS_SERVICE_PREFIX" "$1"; }
shadowtls_instance_dir() { printf '%s/instances/%s' "$STLS_ROOT" "$1"; }
valid_instance_id() { [[ "$1" =~ ^[1-9][0-9]?$ ]]; }

snell_service() { printf 'newworld-snell-%s.service' "$1"; }
ss_service() { printf 'newworld-ss2022-%s.service' "$1"; }
snell_instance_dir() { printf '%s/instances/%s' "$SNELL_ROOT" "$1"; }
ss_instance_dir() { printf '%s/instances/%s' "$SS_ROOT" "$1"; }

migrate_proxy_legacy() {
    local kind="$1" root instance_dir old_config old_meta service new_service
    case "$kind" in
        snell) root="$SNELL_ROOT"; old_config="$root/snell.conf"; old_meta="$root/meta"; service="$SNELL_SERVICE"; new_service="$(snell_service 1)" ;;
        ss2022) root="$SS_ROOT"; old_config="$root/config.json"; old_meta="$root/meta"; service="$SS_SERVICE"; new_service="$(ss_service 1)" ;;
        *) return 1 ;;
    esac
    [[ -f "$old_config" ]] || return 0
    [[ "$(id -u)" -eq 0 ]] || { warn "检测到旧版 $kind 配置，请使用 root 运行一次菜单完成迁移。"; return 0; }
    instance_dir="$root/instances/1"; install -d -m 0750 -o root -g "$SERVICE_USER" "$root/instances" "$instance_dir"
    mv "$old_config" "$instance_dir/"
    [[ ! -f "$old_meta" ]] || mv "$old_meta" "$instance_dir/"
    systemctl disable --now "$service" >/dev/null 2>&1 || true; rm -f "$SYSTEMD_DIR/$service"
    case "$kind" in
        snell) write_service "$new_service" "NewWorld Snell Instance 1" "$SNELL_BIN -c $instance_dir/snell.conf" ;;
        ss2022) write_service "$new_service" "NewWorld SS-2022 Instance 1" "$SS_BIN -c $instance_dir/config.json" ;;
    esac
    reload_start "$new_service" || die "旧 $kind 配置迁移后的服务启动失败。"
    ok "已将原 $kind 配置迁移为实例 1。"
}

proxy_instance_dirs() {
    local kind="$1" root
    migrate_proxy_legacy "$kind"
    [[ "$kind" == snell ]] && root="$SNELL_ROOT" || root="$SS_ROOT"
    find "$root/instances" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort -n || true
}

snell_installed_protocol() {
    local instance protocol detected=""
    while read -r instance; do
        [[ -z "$instance" ]] && continue
        protocol="$(read_meta "$(snell_instance_dir "$instance")/meta" PROTOCOL 2>/dev/null || printf 5)"
        [[ -z "$detected" || "$detected" == "$protocol" ]] || die "检测到 Snell v5 与 v6 混合实例；请先修复实例配置。"
        detected="$protocol"
    done < <(proxy_instance_dirs snell)
    printf '%s' "$detected"
}

refresh_snell_tfo_sysctl() {
    local instance enabled=false config="/etc/sysctl.d/99-newworld-snell.conf"
    while read -r instance; do
        [[ -z "$instance" ]] && continue
        grep -Eq '^tfo[[:space:]]*=[[:space:]]*true$' "$(snell_instance_dir "$instance")/snell.conf" 2>/dev/null && { enabled=true; break; }
    done < <(proxy_instance_dirs snell)
    if [[ "$enabled" == true ]]; then
        printf 'net.ipv4.tcp_fastopen = 3\n' >"$config"
        sysctl -p "$config" >/dev/null 2>&1 || warn "内核未接受 TCP Fast Open 参数，配置文件已保留。"
    else
        rm -f "$config"
    fi
}

show_existing_instances() {
    local kind="$1" instance instances=()
    if [[ "$kind" == shadowtls ]]; then
        while read -r instance; do [[ -z "$instance" ]] || instances+=("$instance"); done < <(shadowtls_instance_dirs)
    else
        while read -r instance; do [[ -z "$instance" ]] || instances+=("$instance"); done < <(proxy_instance_dirs "$kind")
    fi
    if ((${#instances[@]})); then
        printf '已安装实例：%s\n' "${instances[*]}"
    fi
    return 0
}

select_proxy_instance() {
    local kind="$1" instance input instances=()
    while read -r instance; do [[ -z "$instance" ]] || instances+=("$instance"); done < <(proxy_instance_dirs "$kind")
    ((${#instances[@]})) || die "未安装 ${kind} 实例。"
    printf '%s 实例：' "$kind" >&2; for instance in "${instances[@]}"; do printf ' %s)' "$instance" >&2; done; printf '\n' >&2
    read -r -p '请选择实例编号: ' input; valid_instance_id "$input" || die "实例编号无效。"
    [[ " ${instances[*]} " == *" $input "* ]] || die "实例不存在。"; printf '%s' "$input"
}

shadowtls_migrate_legacy() {
    local instance_dir
    [[ -f "$STLS_ROOT/environment" ]] || return 0
    [[ "$(id -u)" -eq 0 ]] || { warn "检测到旧版 ShadowTLS 配置，请使用 root 运行一次菜单完成迁移。"; return 0; }
    instance_dir="$(shadowtls_instance_dir 1)"
    install -d -m 0750 -o root -g "$SERVICE_USER" "$STLS_ROOT/instances" "$instance_dir"
    mv "$STLS_ROOT/environment" "$STLS_ROOT/meta" "$instance_dir/"
    grep -q '^TARGET_INSTANCE=' "$instance_dir/meta" || printf 'TARGET_INSTANCE=1\n' >>"$instance_dir/meta"
    systemctl disable --now "${STLS_SERVICE_PREFIX}.service" >/dev/null 2>&1 || true
    rm -f "$SYSTEMD_DIR/${STLS_SERVICE_PREFIX}.service"
    write_service "$(shadowtls_service 1)" "NewWorld ShadowTLS v3 Instance 1" \
        "$STLS_BIN --v3 server --listen 0.0.0.0:\${LISTEN_PORT} --server 127.0.0.1:\${BACKEND_PORT} --tls \${TLS_HOST} --password \${PASSWORD}" "$instance_dir/environment"
    reload_start "$(shadowtls_service 1)" || die "旧 ShadowTLS 配置迁移后的服务启动失败。"
    systemctl daemon-reload
    ok "已将原 ShadowTLS 配置迁移为实例 1。"
}

shadowtls_instance_dirs() {
    shadowtls_migrate_legacy
    find "$STLS_ROOT/instances" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort -n || true
}

select_shadowtls_instance() {
    local instance input instances=()
    while read -r instance; do [[ -z "$instance" ]] || instances+=("$instance"); done < <(shadowtls_instance_dirs)
    ((${#instances[@]})) || die "未安装 ShadowTLS 实例。"
    printf 'ShadowTLS 实例：' >&2
    for instance in "${instances[@]}"; do
        printf ' %s) %s #%s' "$instance" "$(read_meta "$(shadowtls_instance_dir "$instance")/meta" TARGET)" \
            "$(read_meta "$(shadowtls_instance_dir "$instance")/meta" TARGET_INSTANCE 2>/dev/null || printf 1)" >&2
    done
    printf '\n' >&2
    read -r -p '请选择实例编号: ' input
    valid_instance_id "$input" && [[ -d "$(shadowtls_instance_dir "$input")" ]] || die "实例不存在。"
    printf '%s' "$input"
}

shadowtls_instances_for_target() {
    local target="$1" backend_instance="$2" instance candidate
    while read -r instance; do
        [[ -z "$instance" ]] && continue
        [[ "$(read_meta "$(shadowtls_instance_dir "$instance")/meta" TARGET 2>/dev/null || true)" == "$target" ]] || continue
        candidate="$(read_meta "$(shadowtls_instance_dir "$instance")/meta" TARGET_INSTANCE 2>/dev/null || printf 1)"
        [[ "$candidate" == "$backend_instance" ]] && printf '%s\n' "$instance"
    done < <(shadowtls_instance_dirs)
}

shadowtls_backend_in_use() {
    local target="$1" backend_instance="${2:-}" instance candidate
    while read -r instance; do
        [[ -z "$instance" ]] && continue
        [[ "$(read_meta "$(shadowtls_instance_dir "$instance")/meta" TARGET 2>/dev/null || true)" == "$target" ]] || continue
        candidate="$(read_meta "$(shadowtls_instance_dir "$instance")/meta" TARGET_INSTANCE 2>/dev/null || printf 1)"
        [[ -z "$backend_instance" || "$candidate" == "$backend_instance" ]] && return 0
    done < <(shadowtls_instance_dirs)
    return 1
}

architecture() {
    case "$(uname -m)" in
        x86_64|amd64) printf 'x86_64' ;;
        aarch64|arm64) printf 'aarch64' ;;
        armv7l|armv7) printf 'armv7' ;;
        armv6l|arm) printf 'arm' ;;
        *) die "不支持的架构：$(uname -m)" ;;
    esac
}

package_manager() {
    if have apt-get; then printf apt
    elif have dnf; then printf dnf
    elif have yum; then printf yum
    elif have zypper; then printf zypper
    elif have pacman; then printf pacman
    elif have apk; then printf apk
    else return 1
    fi
}

ensure_dependencies() {
    local profile="${1:-base}" commands=() missing=() packages=() command manager package memory_limit=""
    case "$profile" in
        base) return 0 ;;
        bbr) commands=(sysctl) ;;
        snell) commands=(curl unzip openssl ip ss) ;;
        ss|ss2022) commands=(base64 curl jq tar xz openssl sha256sum ip ss) ;;
        shadowtls) commands=(curl jq openssl sha256sum ip ss) ;;
        self-install) commands=(curl) ;;
        *) die "未知的依赖配置：$profile" ;;
    esac
    for command in "${commands[@]}"; do
        have "$command" || missing+=("$command")
    done
    ((${#missing[@]} == 0)) && return 0
    manager="$(package_manager)" || die "不支持当前系统的包管理器。"
    info "安装运行依赖：${missing[*]}"
    if [[ -r /sys/fs/cgroup/memory.max ]]; then memory_limit="$(</sys/fs/cgroup/memory.max)"
    elif [[ -r /sys/fs/cgroup/memory/memory.limit_in_bytes ]]; then memory_limit="$(</sys/fs/cgroup/memory/memory.limit_in_bytes)"; fi
    if [[ "$memory_limit" =~ ^[0-9]+$ ]] && (( memory_limit < 134217728 )); then
        warn "当前内存限制不足 128 MiB，包管理器可能被系统杀死；建议至少 256 MiB。"
    fi
    for command in "${missing[@]}"; do
        case "$manager:$command" in
            apt:xz) package=xz-utils;; apt:ss|apt:ip) package=iproute2;;
            apt:sysctl) package=procps;;
            dnf:sysctl|yum:sysctl) package=procps-ng;;
            zypper:sysctl|pacman:sysctl|apk:sysctl) package=procps;;
            dnf:ss|dnf:ip|yum:ss|yum:ip) package=iproute;;
            zypper:ss|zypper:ip|pacman:ss|pacman:ip|apk:ss|apk:ip) package=iproute2;;
            *:base64|*:sha256sum) package=coreutils;;
            *) package="$command";;
        esac
        [[ " ${packages[*]} " == *" $package "* ]] || packages+=("$package")
    done
    if [[ " ${missing[*]} " == *' curl '* ]]; then packages+=(ca-certificates); fi
    case "$manager" in
        apt)
            apt-get -o Acquire::Languages=none -o Acquire::PDiffs=false update || die "apt-get update 失败；若显示 Killed，请增加内存。"
            DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${packages[@]}" || die "依赖安装失败；若显示 Killed，请增加内存。" ;;
        dnf) dnf install -y "${packages[@]}" || die "dnf 依赖安装失败。" ;;
        yum) yum install -y "${packages[@]}" || die "yum 依赖安装失败。" ;;
        zypper) zypper --non-interactive install --no-recommends "${packages[@]}" || die "zypper 依赖安装失败。" ;;
        pacman) pacman -S --needed --noconfirm "${packages[@]}" || die "pacman 依赖安装失败；请先更新系统软件包数据库。" ;;
        apk) apk add --no-cache "${packages[@]}" || die "apk 依赖安装失败。" ;;
    esac
}

ensure_service_user() {
    local nologin_shell
    id "$SERVICE_USER" >/dev/null 2>&1 && return 0
    nologin_shell="$(command -v nologin 2>/dev/null || printf /bin/false)"
    if have useradd; then
        useradd --system --no-create-home --home-dir /nonexistent --shell "$nologin_shell" "$SERVICE_USER"
    elif have adduser; then
        adduser -S -D -H -h /nonexistent -s "$nologin_shell" "$SERVICE_USER"
    else
        die "无法创建服务用户。"
    fi
}

make_layout() {
    install -d -m 0750 -o root -g "$SERVICE_USER" \
        "$ROOT_DIR" "$LIB_DIR" "$ROOT_DIR/snell" "$ROOT_DIR/ss2022" "$ROOT_DIR/shadowtls"
    touch "$FIREWALL_DB"
    chmod 0600 "$FIREWALL_DB"
}

verify_service_executable() {
    local binary="$1"
    is_container && return 0
    if have runuser; then
        runuser -u "$SERVICE_USER" -- test -x "$binary"
    elif have su; then
        su -s /bin/sh -c "test -x '$binary'" "$SERVICE_USER"
    else
        [[ -x "$binary" && -x "$LIB_DIR" ]]
    fi || die "${SERVICE_USER} 无法执行 ${binary}；请检查文件及上级目录权限。"
}

download() {
    local url="$1" output="$2"
    curl --proto '=https' --tlsv1.2 -fL --retry 3 --retry-delay 1 \
        --connect-timeout 10 --max-time 300 -o "$output" "$url"
}

sha256() { sha256sum "$1" | awk '{print $1}'; }

download_github_release() {
    local repo="$1" pattern="$2" output="$3" json url digest count token_config="" token_args=()
    new_temp_file json
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        [[ "$GITHUB_TOKEN" =~ ^[A-Za-z0-9_]+$ ]] || die "GITHUB_TOKEN 格式无效。"
        new_temp_file token_config
        printf 'header = "Authorization: Bearer %s"\n' "$GITHUB_TOKEN" >"$token_config"
        token_args=(--config "$token_config")
    fi
    curl --proto '=https' --tlsv1.2 -fsSL --retry 3 "${token_args[@]}" \
        "https://api.github.com/repos/$repo/releases/latest" -o "$json"
    DOWNLOADED_VERSION="$(jq -er '.tag_name' "$json")"
    count="$(jq --arg re "$pattern" '[.assets[] | select(.name | test($re))] | length' "$json")"
    [[ "$count" == 1 ]] || die "官方发布中匹配到 $count 个文件：$pattern"
    url="$(jq -er --arg re "$pattern" '.assets[] | select(.name | test($re)) | .browser_download_url' "$json")"
    digest="$(jq -r --arg re "$pattern" '.assets[] | select(.name | test($re)) | (.digest // "")' "$json")"
    rm -f "$json"
    [[ "${RELEASE_CHECK_ONLY:-false}" == true ]] && return 0
    info "下载 $repo $DOWNLOADED_VERSION"
    download "$url" "$output"
    if [[ "$digest" == sha256:* ]]; then
        [[ "$(sha256 "$output")" == "${digest#sha256:}" ]] || die "SHA-256 校验失败。"
        ok "SHA-256 校验通过。"
    else
        warn "上游未发布机器可读的 SHA-256；已使用 HTTPS 下载并将在安装前验证二进制。"
    fi
}

atomic_binary_install() {
    local source="$1" destination="$2"
    [[ -f "$destination" ]] && cp -a "$destination" "${destination}.previous"
    install -m 0755 -o root -g root "$source" "${destination}.new"
    mv -f "${destination}.new" "$destination"
}

restart_services_or_rollback() {
    local binary="$1" service failed=""; shift
    local -a services=("$@")
    if ((${#services[@]} == 0)); then rm -f "${binary}.previous"; return 0; fi
    for service in "${services[@]}"; do
        if ! systemctl restart "$service" || ! systemctl is-active --quiet "$service"; then
            failed="$service"
            break
        fi
    done
    if [[ -n "$failed" ]]; then
        journalctl -u "$failed" -n 30 --no-pager >&2 || true
        if [[ -f "${binary}.previous" ]]; then
            warn "批量更新启动失败，正在恢复旧二进制并重启全部实例。"
            mv -f "${binary}.previous" "$binary"
            for service in "${services[@]}"; do systemctl restart "$service" >/dev/null 2>&1 || true; done
        fi
        die "$failed 更新失败，已尝试回滚全部实例。"
    fi
    rm -f "${binary}.previous"
}

read_meta() {
    local file="$1" key="$2"
    [[ -f "$file" ]] || return 1
    awk -v key="$key" 'index($0,key "=")==1 {print substr($0,length(key)+2); exit}' "$file"
}

write_meta() {
    local file="$1" tmp; shift
    new_temp_file tmp
    printf '%s\n' "$@" >"$tmp"
    install -m 0640 -o root -g "$SERVICE_USER" "$tmp" "$file"
    rm -f "$tmp"
}

sync_snell_meta_versions() {
    local instance meta
    while read -r instance; do
        [[ -z "$instance" ]] && continue; meta="$(snell_instance_dir "$instance")/meta"
        write_meta "$meta" "VERSION=$SNELL_VERSION" "PROTOCOL=$(read_meta "$meta" PROTOCOL)" \
            "PORT=$(read_meta "$meta" PORT)" "BIND=$(read_meta "$meta" BIND)"
    done < <(proxy_instance_dirs snell)
}

sync_ss_meta_versions() {
    local instance meta
    while read -r instance; do
        [[ -z "$instance" ]] && continue; meta="$(ss_instance_dir "$instance")/meta"
        write_meta "$meta" "VERSION=$SS_VERSION" "PORT=$(read_meta "$meta" PORT)" "BIND=$(read_meta "$meta" BIND)"
    done < <(proxy_instance_dirs ss2022)
}

sync_stls_meta_versions() {
    local instance meta
    while read -r instance; do
        [[ -z "$instance" ]] && continue; meta="$(shadowtls_instance_dir "$instance")/meta"
        write_meta "$meta" "VERSION=$STLS_VERSION" "TARGET=$(read_meta "$meta" TARGET)" \
            "TARGET_INSTANCE=$(read_meta "$meta" TARGET_INSTANCE 2>/dev/null || printf 1)" "PORT=$(read_meta "$meta" PORT)" \
            "BACKEND_PORT=$(read_meta "$meta" BACKEND_PORT)" "PREVIOUS_BIND=$(read_meta "$meta" PREVIOUS_BIND)"
    done < <(shadowtls_instance_dirs)
}

service_user_group() { id -gn "$SERVICE_USER"; }

is_container() {
    if have systemd-detect-virt && systemd-detect-virt --container --quiet; then return 0; fi
    [[ -f /.dockerenv ]] || grep -qaE '(docker|lxc|containerd|kubepods)' /proc/1/cgroup 2>/dev/null
}

write_service() {
    local name="$1" description="$2" exec_start="$3" env_file="${4:-}" run_user run_group unit_tmp
    if is_container; then
        run_user=root; run_group=root
        warn "检测到受限容器：$name 将以 root 运行，并跳过 systemd 命名空间隔离。"
    else
        run_user="$SERVICE_USER"; run_group="$(service_user_group)"
        verify_service_executable "${exec_start%% *}"
    fi
    new_temp_file unit_tmp
    {
        printf '[Unit]\nDescription=%s\nAfter=network-online.target\nWants=network-online.target\n\n' "$description"
        printf '[Service]\nType=simple\nUser=%s\nGroup=%s\n' "$run_user" "$run_group"
        [[ -n "$env_file" ]] && printf 'EnvironmentFile=%s\n' "$env_file"
        printf 'ExecStart=%s\nRestart=on-failure\nRestartSec=3s\nLimitNOFILE=1048576\nUMask=0027\n' "$exec_start"
        if ! is_container; then
            printf 'AmbientCapabilities=CAP_NET_BIND_SERVICE\nCapabilityBoundingSet=CAP_NET_BIND_SERVICE\n'
            printf 'NoNewPrivileges=true\nPrivateTmp=true\nProtectSystem=strict\nProtectHome=true\n'
            printf 'ProtectKernelTunables=true\nProtectKernelModules=true\nProtectControlGroups=true\n'
            printf 'RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX\n'
        fi
        printf '\n[Install]\nWantedBy=multi-user.target\n'
    } >"$unit_tmp"
    install -m 0644 -o root -g root "$unit_tmp" "$SYSTEMD_DIR/$name"; rm -f "$unit_tmp"
}

reload_start() {
    local attempt=0
    systemctl daemon-reload
    systemctl enable "$1" >/dev/null
    systemctl reset-failed "$1" >/dev/null 2>&1 || true
    systemctl restart "$1"
    while ((attempt < 5)); do
        systemctl is-active --quiet "$1" && return 0
        sleep 1
        attempt=$((attempt + 1))
    done
    journalctl -u "$1" -n 30 --no-pager >&2 || true
    systemctl stop "$1" >/dev/null 2>&1 || true
    return 1
}

firewall_active() {
    case "$1" in
        ufw) have ufw && ufw status 2>/dev/null | grep -q '^Status: active' ;;
        firewalld) have firewall-cmd && firewall-cmd --state >/dev/null 2>&1 ;;
    esac
}

firewall_rule_present() {
    local tool="$1" rule="$2"
    case "$tool" in
        ufw) ufw status 2>/dev/null | grep -Eq "^${rule//\//\\/}[[:space:]]+ALLOW" ;;
        firewalld) firewall-cmd --quiet --query-port="$rule" ;;
        *) return 1 ;;
    esac
}

firewall_open() {
    local port="$1" proto="$2" rule tool recorded
    rule="$port/$proto"
    recorded="$(awk -F'|' -v rule="$rule" '$1==rule {print $2; exit}' "$FIREWALL_DB" 2>/dev/null || true)"
    if [[ -n "$recorded" ]] && firewall_active "$recorded"; then
        firewall_rule_present "$recorded" "$rule" || {
            case "$recorded" in
                ufw) ufw allow "$rule" >/dev/null ;;
                firewalld) firewall-cmd --permanent --add-port="$rule" >/dev/null; firewall-cmd --reload >/dev/null ;;
            esac
        }
        return 0
    fi
    if firewall_active ufw; then tool=ufw
    elif firewall_active firewalld; then
        tool=firewalld
    else
        warn "未检测到启用的 UFW/firewalld，请在云防火墙中开放 ${rule}。"
        return 0
    fi
    if firewall_rule_present "$tool" "$rule"; then
        warn "${rule} 已存在于 ${tool}；将保留为用户管理规则。"
        return 0
    fi
    case "$tool" in
        ufw) ufw allow "$rule" >/dev/null ;;
        firewalld) firewall-cmd --permanent --add-port="$rule" >/dev/null; firewall-cmd --reload >/dev/null ;;
    esac
    grep -Fxq "$rule|$tool" "$FIREWALL_DB" || printf '%s|%s\n' "$rule" "$tool" >>"$FIREWALL_DB"
    ok "已通过 ${tool} 开放 ${rule}。"
}

firewall_close() {
    local port="$1" proto="$2" rule line tool tmp
    rule="$port/$proto"
    [[ -f "$FIREWALL_DB" ]] || return 0
    line="$(awk -F'|' -v rule="$rule" '$1==rule {print; exit}' "$FIREWALL_DB")"
    [[ -n "$line" ]] || return 0
    tool="${line##*|}"
    case "$tool" in
        ufw) firewall_active ufw && ufw --force delete allow "$rule" >/dev/null || true ;;
        firewalld)
            if firewall_active firewalld; then
                firewall-cmd --permanent --remove-port="$rule" >/dev/null || true
                firewall-cmd --reload >/dev/null || true
            fi ;;
    esac
    new_temp_file tmp; grep -Fvx "$line" "$FIREWALL_DB" >"$tmp" || true
    install -m 0600 "$tmp" "$FIREWALL_DB"; rm -f "$tmp"
}

snapshot_manager_state() {
    local variable="$1" state_dir service file
    local -a service_files=()
    new_temp_dir state_dir
    install -d -m 0700 "$state_dir/root" "$state_dir/services" "$state_dir/sysctl" "$state_dir/bin"
    cp -a "$ROOT_DIR/." "$state_dir/root/"
    : >"$state_dir/active"
    shopt -s nullglob
    service_files=("$SYSTEMD_DIR"/newworld-snell*.service "$SYSTEMD_DIR"/newworld-ss2022*.service "$SYSTEMD_DIR"/newworld-shadowtls*.service)
    shopt -u nullglob
    for file in "${service_files[@]}"; do
        service="${file##*/}"
        cp -a "$file" "$state_dir/services/$service"
        systemctl is-active --quiet "$service" && printf '%s\n' "$service" >>"$state_dir/active" || true
    done
    for file in /etc/sysctl.d/99-newworld-snell.conf /etc/sysctl.d/99-newworld-bbr.conf; do
        [[ ! -f "$file" ]] || cp -a "$file" "$state_dir/sysctl/${file##*/}"
    done
    for file in "$SNELL_BIN" "$SS_BIN" "$STLS_BIN"; do
        [[ ! -f "$file" ]] || cp -a "$file" "$state_dir/bin/${file##*/}"
    done
    printf -v "$variable" '%s' "$state_dir"
}

restore_manager_state() {
    local snapshot="$1" service file name rule tool port proto current_rules
    local -a service_files=()
    warn "操作失败，正在恢复此前配置与服务状态。"
    set +e
    new_temp_file current_rules
    [[ ! -f "$FIREWALL_DB" ]] || cp -a "$FIREWALL_DB" "$current_rules"
    while IFS='|' read -r rule tool; do
        [[ -n "$rule" && -n "$tool" ]] || continue
        firewall_close "${rule%/*}" "${rule##*/}"
    done <"$current_rules"
    for name in snell ss2022 shadowtls firewall.rules; do rm -rf -- "${ROOT_DIR:?}/$name"; done
    cp -a "$snapshot/root/." "$ROOT_DIR/"
    shopt -s nullglob
    service_files=("$SYSTEMD_DIR"/newworld-snell*.service "$SYSTEMD_DIR"/newworld-ss2022*.service "$SYSTEMD_DIR"/newworld-shadowtls*.service)
    for file in "${service_files[@]}"; do systemctl stop "${file##*/}" >/dev/null 2>&1 || true; rm -f "$file"; done
    service_files=("$snapshot/services"/*.service)
    for file in "${service_files[@]}"; do cp -a "$file" "$SYSTEMD_DIR/${file##*/}"; done
    shopt -u nullglob
    for name in 99-newworld-snell.conf 99-newworld-bbr.conf; do
        file="/etc/sysctl.d/$name"
        if [[ -f "$snapshot/sysctl/$name" ]]; then cp -a "$snapshot/sysctl/$name" "$file"; else rm -f "$file"; fi
    done
    for name in snell-server ssserver shadow-tls; do
        file="$LIB_DIR/$name"
        rm -f "${file}.previous" "${file}.new"
        [[ ! -f "$snapshot/bin/$name" ]] || cp -a "$snapshot/bin/$name" "$file"
    done
    systemctl daemon-reload
    shopt -s nullglob; service_files=("$snapshot/services"/*.service); shopt -u nullglob
    for file in "${service_files[@]}"; do
        service="${file##*/}"
        if grep -Fxq "$service" "$snapshot/active"; then systemctl restart "$service"
        else systemctl stop "$service" >/dev/null 2>&1; fi
    done
    while IFS='|' read -r rule tool; do
        [[ -n "$rule" && -n "$tool" ]] || continue
        port="${rule%/*}"; proto="${rule##*/}"
        firewall_open "$port" "$proto"
    done <"$FIREWALL_DB"
    sysctl -p /etc/sysctl.d/99-newworld-snell.conf >/dev/null 2>&1 || true
    set -e
}

public_ip() {
    if [[ -z "$PUBLIC_IP_CACHE" ]]; then
        PUBLIC_IP_CACHE="$(curl --proto '=https' --tlsv1.2 -4fsS --max-time 5 https://api.ipify.org 2>/dev/null || \
            curl --proto '=https' --tlsv1.2 -6fsS --max-time 5 https://api64.ipify.org 2>/dev/null || printf '<服务器IP>')"
    fi
    printf '%s' "$PUBLIC_IP_CACHE"
}

install_snell_binary() {
    local protocol="$1" arch version versions stable page url tmpdir zip candidate pattern probe_status
    [[ "$protocol" == 5 || "$protocol" == 6 ]] || die "Snell 版本只能是 5 或 6。"
    arch="$(architecture)"; [[ "$arch" == x86_64 ]] && arch=amd64; [[ "$arch" == armv7 ]] && arch=armv7l
    if [[ "$protocol" == 6 ]]; then
        [[ "$arch" == aarch64 || "$arch" == amd64 ]] || die "Snell v6 官方目前仅提供 amd64/aarch64。"
    else
        [[ "$arch" == aarch64 || "$arch" == amd64 || "$arch" == armv7l ]] || die "当前架构没有受支持的 Snell v5 官方包。"
    fi
    new_temp_dir tmpdir
    page="$tmpdir/release-notes"
    download "https://kb.nssurge.com/surge-knowledge-base/release-notes/snell" "$page"
    pattern="snell-server-v${protocol}\\.[0-9]+\\.[0-9]+[A-Za-z0-9]*-linux-${arch}\\.zip"
    versions="$(grep -Eo "$pattern" "$page" | sed -E 's/snell-server-(v[^-]+)-.*/\1/' | sort -u || true)"
    stable="$(grep -E "^v${protocol}\\.[0-9]+\\.[0-9]+$" <<<"$versions" | sort -V | tail -n1 || true)"
    if [[ -n "$stable" ]]; then
        version="$stable"
    else
        version="$(awk '{ key=$0; if (key ~ /[[:alpha:]]+$/) key=key "0"; print key "\t" $0 }' <<<"$versions" | sort -V -k1,1 | tail -n1 | cut -f2-)"
    fi
    [[ -n "$version" ]] || die "无法从 Snell 官方发布页取得 v${protocol} 的 ${arch} 版本。"
    SNELL_VERSION="$version"
    if [[ "${SNELL_CHECK_ONLY:-false}" == true ]]; then rm -rf "$tmpdir"; return 0; fi
    url="https://dl.nssurge.com/snell/snell-server-${version}-linux-${arch}.zip"
    zip="$tmpdir/snell.zip"; info "下载 Snell $version"; download "$url" "$zip"
    unzip -q "$zip" -d "$tmpdir/unpack"
    candidate="$(find "$tmpdir/unpack" -type f -name snell-server -print -quit)"
    [[ -n "$candidate" ]] || die "Snell 压缩包中缺少服务器程序。"
    chmod +x "$candidate"
    set +e; "$candidate" --help >/dev/null 2>&1; probe_status=$?; set -e
    ((probe_status != 126 && probe_status != 127)) || die "Snell 二进制无法在当前系统运行；Alpine/musl 通常需要 glibc 兼容层。"
    atomic_binary_install "$candidate" "$SNELL_BIN"
    rm -rf "$tmpdir"
}

configure_snell() {
    local protocol="${1:-}" instance="${2:-}" port psk bind listen tfo dns config config_tmp meta ipv6 obfs obfs_host dns_pref mode service
    migrate_proxy_legacy snell
    [[ -n "$instance" ]] || { show_existing_instances snell; read -r -p '实例编号（1-99）: ' instance; }
    valid_instance_id "$instance" || die "实例编号必须为 1-99 的正整数。"
    [[ ! -d "$(snell_instance_dir "$instance")" ]] || die "Snell 实例 $instance 已存在。"
    install -d -m 0750 -o root -g "$SERVICE_USER" "$SNELL_ROOT/instances" "$(snell_instance_dir "$instance")"
    config="$(snell_instance_dir "$instance")/snell.conf"; meta="$(snell_instance_dir "$instance")/meta"
    new_temp_file config_tmp
    if [[ -z "$protocol" ]]; then
        protocol="$(select_snell_protocol 5)"
    fi
    [[ "$protocol" == 5 || "$protocol" == 6 ]] || die "Snell 协议版本无效。"
    port="$(prompt_default '监听端口' "$(random_port)")"; valid_port "$port" || die "端口无效。"
    port_unused "$port" || die "端口 $port 已被占用。"
    read -r -p 'PSK（留空自动生成 32 位随机密钥）: ' psk
    psk="${psk:-$(random_text 32)}"; valid_psk "$psk" || die "PSK 必须为 16-255 位安全字符。"
    tfo="$(select_boolean 'TCP Fast Open' true)"
    dns="$(prompt_default 'DNS（逗号分隔）' '1.1.1.1,8.8.8.8')"; valid_dns "$dns" || die "DNS 格式无效。"
    if [[ "$protocol" == 6 ]]; then
        if ipv6_available; then bind=dual; listen="0.0.0.0:${port},[::]:${port}"
        else bind="0.0.0.0"; listen="${bind}:${port}"; warn "未检测到可用的全局 IPv6，Snell v6 将仅监听 IPv4。"; fi
        dns_pref="$(select_dns_preference)"
        [[ "$dns_pref" != ipv6-only || "$bind" == dual ]] || die "当前系统没有可用 IPv6，不能选择 ipv6-only。"
        mode="$(select_snell_mode)"
        [[ "$mode" != unsafe-raw ]] || warn "unsafe-raw 会降低流量整形保护，仅在明确了解风险时使用。"
        cat >"$config_tmp" <<EOF
[snell-server]
listen = ${listen}
psk = ${psk}
tfo = ${tfo}
dns = ${dns}
dns-ip-preference = ${dns_pref}
mode = ${mode}
version = 6
EOF
    else
        bind="0.0.0.0"; listen="${bind}:${port}"
        ipv6="$(select_boolean '启用 IPv6 解析' true)"
        obfs="$(select_snell_obfs)"
        obfs_host=""
        if [[ "$obfs" == http ]]; then obfs_host="$(prompt_default 'OBFS 域名' 'www.bing.com')"; valid_host "$obfs_host" || die "OBFS 域名无效。"; fi
        cat >"$config_tmp" <<EOF
[snell-server]
listen = ${listen}
ipv6 = ${ipv6}
psk = ${psk}
obfs = ${obfs}
${obfs_host:+obfs-host = ${obfs_host}}
tfo = ${tfo}
dns = ${dns}
version = 5
EOF
    fi
    install -m 0640 -o root -g "$SERVICE_USER" "$config_tmp" "$config"; rm -f "$config_tmp"
    write_meta "$meta" "VERSION=${SNELL_VERSION:-unknown}" "PROTOCOL=$protocol" "PORT=$port" "BIND=$bind"
    refresh_snell_tfo_sysctl
    service="$(snell_service "$instance")"
    write_service "$service" "NewWorld Snell Instance $instance" "$SNELL_BIN -c $config"
    if ! reload_start "$service"; then
        systemctl disable --now "$service" >/dev/null 2>&1 || true
        rm -f "$SYSTEMD_DIR/$service"; rm -rf "$(snell_instance_dir "$instance")"; systemctl daemon-reload
        die "Snell 实例 $instance 启动失败，已清理未完成安装。"
    fi
    firewall_open "$port" tcp
    [[ "$protocol" != 5 ]] || firewall_open "$port" udp
    local surge_config
    surge_config="$(hostname)-Snell-${instance} = snell, $(public_ip), ${port}, psk=${psk}, version=${protocol}, tfo=${tfo}, reuse=true, ecn=true"
    [[ "$protocol" == 6 && "$mode" != default ]] && surge_config+=", mode=${mode}"
    [[ "$protocol" == 5 && "$obfs" == http ]] && surge_config+=", obfs=http, obfs-host=${obfs_host}"
    print_config_block "Snell 客户端配置（实例 ${instance}，Surge [Proxy]）" "$surge_config"
    print_config_block "Snell 服务器配置（${SNELL_VERSION:-unknown}）" "$(cat "$config")"
}

install_snell() {
    local target_protocol instance meta port bind current_protocol updated=0 detected_protocol="" instances
    local -a services=()
    migrate_proxy_legacy snell
    instances="$(proxy_instance_dirs snell)"
    if [[ "$UPDATE_ONLY" == true ]]; then
        [[ -n "$instances" ]] || die "尚未安装 Snell 实例，无法执行更新。"
        instance=""
    elif [[ -z "$instances" ]]; then
        read -r -p '首次安装实例编号 [1]: ' instance; instance="${instance:-1}"
    else
        show_existing_instances snell
        read -r -p '实例编号（1–99）：输入新编号安装实例，直接回车更新现有实例: ' instance
    fi
    if [[ -z "$instance" ]]; then
        while read -r instance; do
            [[ -z "$instance" ]] && continue
            meta="$(snell_instance_dir "$instance")/meta"; current_protocol="$(read_meta "$meta" PROTOCOL)"
            [[ -z "$detected_protocol" || "$detected_protocol" == "$current_protocol" ]] || die "检测到 Snell v5 与 v6 混合实例；共享二进制无法安全批量更新，请先统一协议配置。"
            detected_protocol="$current_protocol"
        done < <(proxy_instance_dirs snell)
        [[ -n "$detected_protocol" ]] || die "没有可更新的 Snell 实例。"
        SNELL_CHECK_ONLY=true install_snell_binary "$detected_protocol"
        updated=0
        while read -r instance; do
            [[ -z "$instance" ]] && continue
            [[ "$(read_meta "$(snell_instance_dir "$instance")/meta" VERSION)" == "$SNELL_VERSION" ]] || updated=$((updated + 1))
        done < <(proxy_instance_dirs snell)
        ((updated > 0)) || { ok "Snell 已是最新版本：$SNELL_VERSION（无需更新）。"; return; }
        install_snell_binary "$detected_protocol"
        [[ ! "$SNELL_VERSION" =~ [A-Za-z] ]] || warn "Snell $SNELL_VERSION 是官方预发布版本。"
        while read -r instance; do
            [[ -z "$instance" ]] && continue
            services+=("$(snell_service "$instance")")
        done < <(proxy_instance_dirs snell)
        restart_services_or_rollback "$SNELL_BIN" "${services[@]}"
        updated=0
        while read -r instance; do
            [[ -z "$instance" ]] && continue
            meta="$(snell_instance_dir "$instance")/meta"; current_protocol="$(read_meta "$meta" PROTOCOL)"
            port="$(read_meta "$meta" PORT)"; bind="$(read_meta "$meta" BIND)"
            write_meta "$meta" "VERSION=$SNELL_VERSION" "PROTOCOL=$current_protocol" "PORT=$port" "BIND=$bind"
            updated=$((updated + 1))
        done < <(proxy_instance_dirs snell)
        ok "已更新全部 ${updated} 个 Snell 实例到 ${SNELL_VERSION}。"
        return
    fi
    valid_instance_id "$instance" || die "实例编号必须为 1-99 的正整数。"
    [[ ! -d "$(snell_instance_dir "$instance")" ]] || die "Snell 实例 $instance 已存在；直接回车可更新全部现有实例。"
    detected_protocol="$(snell_installed_protocol)"
    if [[ -n "$detected_protocol" ]]; then
        target_protocol="$detected_protocol"
        info "新实例将沿用现有 Snell v${target_protocol} 协议。"
    else
        target_protocol="$(select_snell_protocol 5)"
    fi
    SNELL_CHECK_ONLY=true install_snell_binary "$target_protocol"
    if [[ -x "$SNELL_BIN" && -n "$instances" ]] && [[ "$(read_meta "$(snell_instance_dir "${instances%%$'\n'*}")/meta" VERSION)" == "$SNELL_VERSION" ]]; then
        info "Snell 二进制已是最新版：${SNELL_VERSION}，直接创建新实例。"
    else
        install_snell_binary "$target_protocol"
        while read -r current_protocol; do [[ -z "$current_protocol" ]] || services+=("$(snell_service "$current_protocol")"); done < <(proxy_instance_dirs snell)
        restart_services_or_rollback "$SNELL_BIN" "${services[@]}"
        sync_snell_meta_versions
    fi
    [[ ! "$SNELL_VERSION" =~ [A-Za-z] ]] || warn "Snell $SNELL_VERSION 是官方预发布版本。"
    configure_snell "$target_protocol" "$instance"
}

ss_asset_pattern() {
    case "$(architecture)" in
        x86_64) printf 'x86_64-unknown-linux-musl\.tar\.xz$' ;;
        aarch64) printf 'aarch64-unknown-linux-musl\.tar\.xz$' ;;
        armv7) printf 'armv7-unknown-linux-musleabihf\.tar\.xz$' ;;
        arm) printf 'arm-unknown-linux-musleabi\.tar\.xz$' ;;
    esac
}

install_ss_binary() {
    local tmpdir archive candidate
    new_temp_dir tmpdir
    archive="$tmpdir/ss.tar.xz"
    download_github_release shadowsocks/shadowsocks-rust "$(ss_asset_pattern)" "$archive"
    tar -xJf "$archive" -C "$tmpdir"
    candidate="$(find "$tmpdir" -type f -name ssserver -print -quit)"
    [[ -n "$candidate" ]] || die "官方压缩包中缺少 ssserver。"
    chmod +x "$candidate"; "$candidate" --version >/dev/null
    atomic_binary_install "$candidate" "$SS_BIN"
    SS_VERSION="$DOWNLOADED_VERSION"
    rm -rf "$tmpdir"
}

configure_ss() {
    local instance="${1:-}" port password method bind config config_tmp meta service
    migrate_proxy_legacy ss2022
    [[ -n "$instance" ]] || { show_existing_instances ss2022; read -r -p '实例编号（1-99）: ' instance; }
    valid_instance_id "$instance" || die "实例编号必须为 1-99 的正整数。"
    [[ ! -d "$(ss_instance_dir "$instance")" ]] || die "SS-2022 实例 $instance 已存在。"
    install -d -m 0750 -o root -g "$SERVICE_USER" "$SS_ROOT/instances" "$(ss_instance_dir "$instance")"
    config="$(ss_instance_dir "$instance")/config.json"; meta="$(ss_instance_dir "$instance")/meta"
    new_temp_file config_tmp
    port="$(prompt_default '监听端口' "$(random_port)")"; valid_port "$port" || die "端口无效。"
    port_unused "$port" || die "端口 $port 已被占用。"
    method="$(prompt_default '加密方式' '2022-blake3-aes-256-gcm')"
    case "$method" in 2022-blake3-aes-128-gcm) password="$(random_base64 16)";; 2022-blake3-aes-256-gcm) password="$(random_base64 32)";; *) die "仅允许标准 SS-2022 AES 方法。";; esac
    bind="0.0.0.0"
    jq -n --arg server "$bind" --argjson port "$port" --arg password "$password" --arg method "$method" \
        '{server:$server,server_port:$port,password:$password,method:$method,mode:"tcp_and_udp"}' >"$config_tmp"
    install -m 0640 -o root -g "$SERVICE_USER" "$config_tmp" "$config"; rm -f "$config_tmp"
    write_meta "$meta" "VERSION=${SS_VERSION:-unknown}" "PORT=$port" "BIND=$bind"
    service="$(ss_service "$instance")"
    write_service "$service" "NewWorld SS-2022 Instance $instance" "$SS_BIN -c $config"
    if ! reload_start "$service"; then
        systemctl disable --now "$service" >/dev/null 2>&1 || true
        rm -f "$SYSTEMD_DIR/$service"; rm -rf "$(ss_instance_dir "$instance")"; systemctl daemon-reload
        die "SS-2022 实例 $instance 启动失败，已清理未完成安装。"
    fi
    firewall_open "$port" tcp; firewall_open "$port" udp
    local ss_url
    ss_url="ss://$(printf '%s' "${method}:${password}" | base64url)@$(public_ip):${port}#NewWorld-SS2022-${instance}"
    print_config_block "SS-2022 客户端链接（实例 ${instance}）" "$ss_url"
    print_config_block "SS-2022 服务器配置（实例 ${instance}）" "$(cat "$config")"
}

install_ss() {
    local instance meta port bind updated=0 instances current
    local -a services=()
    migrate_proxy_legacy ss2022
    instances="$(proxy_instance_dirs ss2022)"
    if [[ "$UPDATE_ONLY" == true ]]; then
        [[ -n "$instances" ]] || die "尚未安装 SS-2022 实例，无法执行更新。"
        instance=""
    elif [[ -z "$instances" ]]; then
        read -r -p '首次安装实例编号 [1]: ' instance; instance="${instance:-1}"
    else
        show_existing_instances ss2022
        read -r -p '实例编号（1–99）：输入新编号安装实例，直接回车更新现有实例: ' instance
    fi
    RELEASE_CHECK_ONLY=true download_github_release shadowsocks/shadowsocks-rust "$(ss_asset_pattern)" /dev/null
    SS_VERSION="$DOWNLOADED_VERSION"
    if [[ -z "$instance" ]]; then
        updated=0
        while read -r instance; do [[ -z "$instance" ]] || [[ "$(read_meta "$(ss_instance_dir "$instance")/meta" VERSION)" != "$SS_VERSION" ]] && updated=$((updated + 1)); done < <(proxy_instance_dirs ss2022)
        ((updated > 0)) || { ok "SS-2022 已是最新版本：$SS_VERSION（无需更新）。"; return; }
        install_ss_binary
        while read -r current; do [[ -z "$current" ]] || services+=("$(ss_service "$current")"); done < <(proxy_instance_dirs ss2022)
        restart_services_or_rollback "$SS_BIN" "${services[@]}"
        sync_ss_meta_versions
        updated=0
        while read -r instance; do
            [[ -z "$instance" ]] && continue
            meta="$(ss_instance_dir "$instance")/meta"; port="$(read_meta "$meta" PORT)"; bind="$(read_meta "$meta" BIND)"
            write_meta "$meta" "VERSION=$SS_VERSION" "PORT=$port" "BIND=$bind"
            firewall_open "$port" tcp; firewall_open "$port" udp; updated=$((updated + 1))
        done < <(proxy_instance_dirs ss2022)
        ((updated > 0)) || die "没有可更新的 SS-2022 实例。"
        ok "已更新全部 ${updated} 个 SS-2022 实例到 ${SS_VERSION}。"
        return
    fi
    valid_instance_id "$instance" || die "实例编号必须为 1-99 的正整数。"
    [[ ! -d "$(ss_instance_dir "$instance")" ]] || die "SS-2022 实例 $instance 已存在；直接回车可更新全部现有实例。"
    if [[ -x "$SS_BIN" && -n "$instances" ]] && [[ "$(read_meta "$(ss_instance_dir "${instances%%$'\n'*}")/meta" VERSION)" == "$SS_VERSION" ]]; then
        info "SS-2022 二进制已是最新版：${SS_VERSION}，直接创建新实例。"
    else
        install_ss_binary
        while read -r current; do [[ -z "$current" ]] || services+=("$(ss_service "$current")"); done < <(proxy_instance_dirs ss2022)
        restart_services_or_rollback "$SS_BIN" "${services[@]}"
        sync_ss_meta_versions
    fi
    configure_ss "$instance"
}

stls_asset_pattern() {
    case "$(architecture)" in
        x86_64) printf 'shadow-tls-x86_64-unknown-linux-musl$' ;;
        aarch64) printf 'shadow-tls-aarch64-unknown-linux-musl$' ;;
        armv7) printf 'shadow-tls-armv7-unknown-linux-musleabihf$' ;;
        arm) printf 'shadow-tls-arm-unknown-linux-musleabi$' ;;
    esac
}

install_stls_binary() {
    local tmpdir candidate
    new_temp_dir tmpdir
    candidate="$tmpdir/shadow-tls"
    download_github_release ihciah/shadow-tls "$(stls_asset_pattern)" "$candidate"
    chmod +x "$candidate"; "$candidate" --version >/dev/null
    atomic_binary_install "$candidate" "$STLS_BIN"
    STLS_VERSION="$DOWNLOADED_VERSION"
    rm -rf "$tmpdir"
}

set_backend_bind() {
    local target="$1" instance="$2" bind="$3" port tmp protocol listen dir meta config service
    case "$target" in
        snell)
            dir="$(snell_instance_dir "$instance")"; meta="$dir/meta"; config="$dir/snell.conf"; service="$(snell_service "$instance")"
            port="$(read_meta "$meta" PORT)"
            protocol="$(read_meta "$meta" PROTOCOL 2>/dev/null || printf 5)"
            if [[ "$bind" == dual ]]; then listen="0.0.0.0:${port},[::]:${port}"; else listen="${bind}:${port}"; fi
            new_temp_file tmp; sed -E "s|^listen[[:space:]]*=.*|listen = ${listen}|" "$config" >"$tmp"
            install -m 0640 -o root -g "$SERVICE_USER" "$tmp" "$config"; rm -f "$tmp"
            write_meta "$meta" "VERSION=$(read_meta "$meta" VERSION)" "PROTOCOL=$protocol" "PORT=$port" "BIND=$bind"
            systemctl restart "$service" ;;
        ss2022)
            dir="$(ss_instance_dir "$instance")"; meta="$dir/meta"; config="$dir/config.json"; service="$(ss_service "$instance")"
            port="$(read_meta "$meta" PORT)"
            new_temp_file tmp; jq --arg bind "$bind" '.server=$bind' "$config" >"$tmp"
            install -m 0640 -o root -g "$SERVICE_USER" "$tmp" "$config"; rm -f "$tmp"
            write_meta "$meta" "VERSION=$(read_meta "$meta" VERSION)" "PORT=$port" "BIND=$bind"
            systemctl restart "$service" ;;
    esac
}

configure_stls() {
    local instance="${1:-}" target backend_instance backend_dir listen_port backend_port previous_bind tls_host password env meta backend_protocol service first_for_backend=false
    shadowtls_migrate_legacy
    [[ -n "$instance" ]] || { show_existing_instances shadowtls; read -r -p '首次安装实例编号 [1]: ' instance; instance="${instance:-1}"; }
    valid_instance_id "$instance" || die "实例编号必须为 1-99 的正整数。"
    [[ ! -d "$(shadowtls_instance_dir "$instance")" ]] || die "实例 $instance 已存在；请先卸载该实例，或使用更新功能。"
    printf '后端：1) Snell  2) ss-2022\n'; read -r -p '请选择 [1-2]: ' target
    case "$target" in
        1) target=snell ;;
        2) target=ss2022 ;;
        *) die "选择无效。" ;;
    esac
    backend_instance="$(select_proxy_instance "$target")"
    if [[ "$target" == snell ]]; then backend_dir="$(snell_instance_dir "$backend_instance")"; else backend_dir="$(ss_instance_dir "$backend_instance")"; fi
    backend_port="$(read_meta "$backend_dir/meta" PORT)"
    previous_bind="$(read_meta "$backend_dir/meta" BIND)"
    listen_port="$(prompt_default 'ShadowTLS 监听端口' '443')"; valid_port "$listen_port" || die "端口无效。"
    port_unused "$listen_port" || die "端口 $listen_port 已被占用。"
    tls_host="$(prompt_default 'TLS 伪装域名（必须支持 TLS 1.3）' 'www.microsoft.com')"
    valid_host "$tls_host" || die "域名格式无效。"
    install -d -m 0750 -o root -g "$SERVICE_USER" "$STLS_ROOT/instances" "$(shadowtls_instance_dir "$instance")"
    password="$(random_text 32)"; env="$(shadowtls_instance_dir "$instance")/environment"; meta="$(shadowtls_instance_dir "$instance")/meta"
    write_meta "$env" "LISTEN_PORT=$listen_port" "BACKEND_PORT=$backend_port" "TLS_HOST=$tls_host" "PASSWORD=$password" "MONOIO_FORCE_LEGACY_DRIVER=1"
    write_meta "$meta" "VERSION=${STLS_VERSION:-unknown}" "TARGET=$target" "TARGET_INSTANCE=$backend_instance" "PORT=$listen_port" "BACKEND_PORT=$backend_port" "PREVIOUS_BIND=$previous_bind"
    if ! shadowtls_backend_in_use "$target" "$backend_instance"; then first_for_backend=true; set_backend_bind "$target" "$backend_instance" "127.0.0.1"; firewall_close "$backend_port" tcp; fi
    if [[ "$first_for_backend" == true && "$target" == ss2022 ]]; then
        firewall_close "$backend_port" udp
    elif [[ "$first_for_backend" == true ]]; then
        backend_protocol="$(read_meta "$backend_dir/meta" PROTOCOL 2>/dev/null || printf 5)"
        [[ "$backend_protocol" != 5 ]] || firewall_close "$backend_port" udp
    fi
    service="$(shadowtls_service "$instance")"
    write_service "$service" "NewWorld ShadowTLS v3 Instance $instance" \
        "$STLS_BIN --v3 server --listen 0.0.0.0:\${LISTEN_PORT} --server 127.0.0.1:\${BACKEND_PORT} --tls \${TLS_HOST} --password \${PASSWORD}" "$env"
    if ! reload_start "$service"; then
        systemctl disable --now "$service" >/dev/null 2>&1 || true
        rm -f "$SYSTEMD_DIR/$service"; rm -rf "$(shadowtls_instance_dir "$instance")"; systemctl daemon-reload
        if [[ "$first_for_backend" == true ]]; then
            set_backend_bind "$target" "$backend_instance" "$previous_bind" || true
            firewall_open "$backend_port" tcp
            if [[ "$target" == ss2022 || "$backend_protocol" == 5 ]]; then firewall_open "$backend_port" udp; fi
        fi
        die "ShadowTLS 实例 $instance 启动失败，已恢复后端并清理未完成安装。"
    fi
    firewall_open "$listen_port" tcp
    print_config_block "ShadowTLS v3 完整服务器配置（实例 ${instance}）" "地址 = $(public_ip)
$(cat "$env")
后端 = ${target} #${backend_instance} (127.0.0.1:${backend_port})"
    show_config "$target" "$backend_instance"
}

install_stls() {
    local instance meta port updated=0 instances current
    local -a services=()
    shadowtls_migrate_legacy
    instances="$(shadowtls_instance_dirs)"
    if [[ "$UPDATE_ONLY" == true ]]; then
        [[ -n "$instances" ]] || die "尚未安装 ShadowTLS 实例，无法执行更新。"
        instance=""
    elif [[ -n "$instances" ]]; then
        show_existing_instances shadowtls
        read -r -p '实例编号（1–99）：输入新编号安装实例，直接回车更新现有实例: ' instance
        if [[ -n "$instance" ]]; then
            valid_instance_id "$instance" || die "实例编号必须为 1-99 的正整数。"
            [[ ! -d "$(shadowtls_instance_dir "$instance")" ]] || die "ShadowTLS 实例 $instance 已存在；直接回车可更新全部实例。"
            RELEASE_CHECK_ONLY=true download_github_release ihciah/shadow-tls "$(stls_asset_pattern)" /dev/null
            STLS_VERSION="$DOWNLOADED_VERSION"
            if [[ -x "$STLS_BIN" ]] && [[ "$(read_meta "$(shadowtls_instance_dir "${instances%%$'\n'*}")/meta" VERSION)" == "$STLS_VERSION" ]]; then
                info "ShadowTLS 二进制已是最新版：${STLS_VERSION}，直接创建新实例。"
            else
                install_stls_binary
                while read -r current; do [[ -z "$current" ]] || services+=("$(shadowtls_service "$current")"); done < <(shadowtls_instance_dirs)
                restart_services_or_rollback "$STLS_BIN" "${services[@]}"
                sync_stls_meta_versions
            fi
            configure_stls "$instance"; return
        fi
    fi
    if [[ -n "$instances" ]]; then
        RELEASE_CHECK_ONLY=true download_github_release ihciah/shadow-tls "$(stls_asset_pattern)" /dev/null
        STLS_VERSION="$DOWNLOADED_VERSION"
        while read -r instance; do
            [[ -z "$instance" ]] || [[ "$(read_meta "$(shadowtls_instance_dir "$instance")/meta" VERSION)" != "$STLS_VERSION" ]] && updated=$((updated + 1))
        done < <(shadowtls_instance_dirs)
        ((updated > 0)) || { ok "ShadowTLS 已是最新版本：$STLS_VERSION（无需更新）。"; return; }
        install_stls_binary
        while read -r current; do [[ -z "$current" ]] || services+=("$(shadowtls_service "$current")"); done < <(shadowtls_instance_dirs)
        restart_services_or_rollback "$STLS_BIN" "${services[@]}"
        while read -r instance; do
            [[ -z "$instance" ]] && continue
            meta="$(shadowtls_instance_dir "$instance")/meta"; port="$(read_meta "$meta" PORT)"
            write_meta "$meta" "VERSION=$STLS_VERSION" "TARGET=$(read_meta "$meta" TARGET)" "TARGET_INSTANCE=$(read_meta "$meta" TARGET_INSTANCE 2>/dev/null || printf 1)" "PORT=$port" \
                "BACKEND_PORT=$(read_meta "$meta" BACKEND_PORT)" "PREVIOUS_BIND=$(read_meta "$meta" PREVIOUS_BIND)"
            firewall_open "$port" tcp
        done < <(shadowtls_instance_dirs)
        ok "已更新全部 ShadowTLS 实例到 ${STLS_VERSION}。"
    else
        read -r -p '首次安装实例编号 [1]: ' instance; instance="${instance:-1}"
        valid_instance_id "$instance" || die "实例编号必须为 1-99 的正整数。"
        install_stls_binary; configure_stls "$instance"
    fi
}

enable_bbr() {
    local available config="/etc/sysctl.d/99-newworld-bbr.conf"
    modprobe tcp_bbr 2>/dev/null || true
    available="$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)"
    grep -qw bbr <<<"$available" || die "当前内核不支持 BBR，请升级到支持 BBR 的发行版内核。"
    : >"$config"
    if sysctl -n net.core.default_qdisc >/dev/null 2>&1; then
        printf 'net.core.default_qdisc = fq\n' >>"$config"
    else
        warn "当前内核或容器未暴露 net.core.default_qdisc，跳过 qdisc 设置。"
    fi
    printf 'net.ipv4.tcp_congestion_control = bbr\n' >>"$config"
    sysctl -p "$config" >/dev/null || die "BBR 参数无法应用；容器环境需要宿主机授权相关 sysctl。"
    [[ "$(sysctl -n net.ipv4.tcp_congestion_control)" == bbr ]] || die "BBR 未成功启用。"
    ok "BBR 已启用；未覆盖 /etc/sysctl.conf。"
}

disable_bbr() {
    rm -f /etc/sysctl.d/99-newworld-bbr.conf
    if sysctl -n net.ipv4.tcp_available_congestion_control | grep -qw cubic; then
        sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null 2>&1 || warn "无法立即切换为 cubic，重启后将不再应用本工具的 BBR 配置。"
    fi
    ok "已移除本工具的 BBR 配置。"
}

remove_component() {
    local component="$1" target previous target_instance port protocol instance instance_dir label
    case "$component" in
        snell) migrate_proxy_legacy snell; instance="${2:-}"; [[ -n "$instance" ]] || instance="$(select_proxy_instance snell)"; label="Snell #$instance" ;;
        ss|ss2022) migrate_proxy_legacy ss2022; instance="${2:-}"; [[ -n "$instance" ]] || instance="$(select_proxy_instance ss2022)"; label="SS-2022 #$instance" ;;
        shadowtls) shadowtls_migrate_legacy; instance="${2:-}"; [[ -n "$instance" ]] || instance="$(select_shadowtls_instance)"; label="ShadowTLS #$instance" ;;
        bbr) label=BBR ;;
        *) die "未知组件：$component" ;;
    esac
    confirm "确定卸载 ${label} 及其配置？" || { warn "已取消。"; return 0; }
    case "$component" in
        snell)
            shadowtls_target_active snell "$instance" && die "该 Snell 实例仍被 ShadowTLS 使用。"
            instance_dir="$(snell_instance_dir "$instance")"; [[ -d "$instance_dir" ]] || die "实例不存在。"
            port="$(read_meta "$instance_dir/meta" PORT)"; protocol="$(read_meta "$instance_dir/meta" PROTOCOL 2>/dev/null || printf 5)"
            systemctl disable --now "$(snell_service "$instance")" >/dev/null 2>&1 || true; firewall_close "$port" tcp; [[ "$protocol" != 5 ]] || firewall_close "$port" udp
            rm -f "$SYSTEMD_DIR/$(snell_service "$instance")"; rm -rf "$instance_dir"; refresh_snell_tfo_sysctl
            [[ -n "$(proxy_instance_dirs snell)" ]] || { rm -f "$SNELL_BIN" "${SNELL_BIN}.previous" /etc/sysctl.d/99-newworld-snell.conf; rm -rf "$SNELL_ROOT"; } ;;
        ss|ss2022)
            shadowtls_target_active ss2022 "$instance" && die "该 SS-2022 实例仍被 ShadowTLS 使用。"
            instance_dir="$(ss_instance_dir "$instance")"; [[ -d "$instance_dir" ]] || die "实例不存在。"
            port="$(read_meta "$instance_dir/meta" PORT)"; systemctl disable --now "$(ss_service "$instance")" >/dev/null 2>&1 || true
            firewall_close "$port" tcp; firewall_close "$port" udp; rm -f "$SYSTEMD_DIR/$(ss_service "$instance")"; rm -rf "$instance_dir"
            [[ -n "$(proxy_instance_dirs ss2022)" ]] || { rm -f "$SS_BIN" "${SS_BIN}.previous"; rm -rf "$SS_ROOT"; } ;;
        shadowtls)
            valid_instance_id "$instance" || die "实例编号无效。"
            instance_dir="$(shadowtls_instance_dir "$instance")"; [[ -d "$instance_dir" ]] || die "实例不存在。"
            target="$(read_meta "$instance_dir/meta" TARGET)"; previous="$(read_meta "$instance_dir/meta" PREVIOUS_BIND)"; target_instance="$(read_meta "$instance_dir/meta" TARGET_INSTANCE 2>/dev/null || printf 1)"
            port="$(read_meta "$instance_dir/meta" PORT)"; systemctl disable --now "$(shadowtls_service "$instance")" >/dev/null 2>&1 || true
            firewall_close "$port" tcp; rm -f "$SYSTEMD_DIR/$(shadowtls_service "$instance")"; rm -rf "$instance_dir"
            if ! shadowtls_backend_in_use "$target" "$target_instance" && [[ -n "$target" && -n "$previous" ]]; then
                set_backend_bind "$target" "$target_instance" "$previous"
                if [[ "$target" == snell ]]; then instance_dir="$(snell_instance_dir "$target_instance")"; else instance_dir="$(ss_instance_dir "$target_instance")"; fi
                port="$(read_meta "$instance_dir/meta" PORT)"; firewall_open "$port" tcp
                if [[ "$target" == ss2022 ]]; then firewall_open "$port" udp
                else protocol="$(read_meta "$instance_dir/meta" PROTOCOL 2>/dev/null || printf 5)"; [[ "$protocol" != 5 ]] || firewall_open "$port" udp; fi
            fi
            if [[ -z "$(shadowtls_instance_dirs)" ]]; then rm -f "$STLS_BIN" "${STLS_BIN}.previous"; rm -rf "$STLS_ROOT"; fi ;;
        bbr) disable_bbr; return 0 ;;
    esac
    systemctl daemon-reload; systemctl reset-failed >/dev/null 2>&1 || true
    ok "$component 已卸载。"
}

component_service() {
    local component="$1" instance="${2:-}"
    case "$component" in
        snell)
            [[ -n "$instance" ]] || instance="$(select_proxy_instance snell)"; valid_instance_id "$instance" && [[ -d "$(snell_instance_dir "$instance")" ]] || die "Snell 实例 $instance 不存在。"
            snell_service "$instance" ;;
        ss|ss2022)
            [[ -n "$instance" ]] || instance="$(select_proxy_instance ss2022)"; valid_instance_id "$instance" && [[ -d "$(ss_instance_dir "$instance")" ]] || die "SS-2022 实例 $instance 不存在。"
            ss_service "$instance" ;;
        shadowtls)
            [[ -n "$instance" ]] || instance="$(select_shadowtls_instance)"; valid_instance_id "$instance" && [[ -d "$(shadowtls_instance_dir "$instance")" ]] || die "ShadowTLS 实例 $instance 不存在。"
            shadowtls_service "$instance" ;;
        *) return 1 ;;
    esac
}

select_component_service() {
    local component
    component="$(select_component)"
    component_service "$component"
}

service_state() {
    local service="$1"
    if ! systemctl cat "$service" >/dev/null 2>&1; then printf '未安装'
    elif systemctl is-active --quiet "$service"; then printf '运行中'
    else printf '已停止'; fi
}

show_status() {
    local algo qdisc instance instance_dir
    printf '\n%s%s %s%s\n' "$BOLD" "$APP" "$VERSION" "$RESET"
    printf '%-16s %-12s %-14s\n' '组件' '状态' '版本'
    migrate_proxy_legacy snell; migrate_proxy_legacy ss2022
    while read -r instance; do
        [[ -z "$instance" ]] && continue; instance_dir="$(snell_instance_dir "$instance")"
        printf '%-16s %-12s %-14s\n' "Snell #$instance" "$(service_state "$(snell_service "$instance")")" "$(read_meta "$instance_dir/meta" VERSION 2>/dev/null || printf '-')"
    done < <(proxy_instance_dirs snell)
    while read -r instance; do
        [[ -z "$instance" ]] && continue; instance_dir="$(ss_instance_dir "$instance")"
        printf '%-16s %-12s %-14s\n' "ss-2022 #$instance" "$(service_state "$(ss_service "$instance")")" "$(read_meta "$instance_dir/meta" VERSION 2>/dev/null || printf '-')"
    done < <(proxy_instance_dirs ss2022)
    shadowtls_migrate_legacy
    while read -r instance; do
        [[ -z "$instance" ]] && continue
        instance_dir="$(shadowtls_instance_dir "$instance")"
        printf '%-16s %-12s %-14s\n' "ShadowTLS #$instance" "$(service_state "$(shadowtls_service "$instance")")" "$(read_meta "$instance_dir/meta" VERSION 2>/dev/null || printf '-')"
    done < <(shadowtls_instance_dirs)
    algo="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || printf unknown)"
    qdisc="$(sysctl -n net.core.default_qdisc 2>/dev/null || printf unknown)"
    printf 'BBR：%s（qdisc=%s，kernel=%s）\n\n' "$algo" "$qdisc" "$(uname -r)"
}

show_config() {
    local component="$1" requested_instance="${2:-}" routed_stls="${3:-}" instance instances wrappers config meta port psk protocol tfo mode obfs obfs_host method password ss_url client_config external_port stls_options target
    require_root
    [[ -n "$PUBLIC_IP_CACHE" ]] || PUBLIC_IP_CACHE="$(public_ip)"
    if [[ -z "$requested_instance" ]]; then
        case "$component" in
            snell)
                instances="$(proxy_instance_dirs snell)"; [[ -n "$instances" ]] || die "未安装 Snell 实例。"
                while read -r instance; do [[ -z "$instance" ]] || show_config snell "$instance"; done <<<"$instances"
                return ;;
            ss|ss2022)
                instances="$(proxy_instance_dirs ss2022)"; [[ -n "$instances" ]] || die "未安装 SS-2022 实例。"
                while read -r instance; do [[ -z "$instance" ]] || show_config ss2022 "$instance"; done <<<"$instances"
                return ;;
            shadowtls)
                instances="$(shadowtls_instance_dirs)"; [[ -n "$instances" ]] || die "未安装 ShadowTLS 实例。"
                while read -r instance; do [[ -z "$instance" ]] || show_config shadowtls "$instance"; done <<<"$instances"
                return ;;
        esac
    fi
    case "$component" in
        snell)
            instance="$requested_instance"
            config="$(snell_instance_dir "$instance")/snell.conf"; meta="$(snell_instance_dir "$instance")/meta"; [[ -f "$config" ]] || die "未安装。"
            port="$(read_meta "$meta" PORT)"
            psk="$(sed -nE 's/^psk[[:space:]]*=[[:space:]]*(.*)$/\1/p' "$config")"
            protocol="$(sed -nE 's/^version[[:space:]]*=[[:space:]]*([0-9]+)$/\1/p' "$config")"
            tfo="$(sed -nE 's/^tfo[[:space:]]*=[[:space:]]*(.*)$/\1/p' "$config")"
            mode="$(sed -nE 's/^mode[[:space:]]*=[[:space:]]*(.*)$/\1/p' "$config")"
            obfs="$(sed -nE 's/^obfs[[:space:]]*=[[:space:]]*(.*)$/\1/p' "$config")"
            obfs_host="$(sed -nE 's/^obfs-host[[:space:]]*=[[:space:]]*(.*)$/\1/p' "$config")"
            wrappers="${routed_stls:-$(shadowtls_instances_for_target snell "$instance")}"
            if [[ -n "$wrappers" ]]; then
                while read -r target; do
                    [[ -z "$target" ]] && continue
                    external_port="$(read_meta "$(shadowtls_instance_dir "$target")/meta" PORT)"
                    stls_options="$(shadowtls_surge_options "$(shadowtls_instance_dir "$target")")"
                    client_config="$(hostname)-Snell-${instance}-STLS-${target} = snell, $(public_ip), ${external_port}, psk=${psk}, version=${protocol}, tfo=${tfo}, reuse=true, ecn=true"
                    [[ "$protocol" != 6 || "$mode" == default || -z "$mode" ]] || client_config+=", mode=${mode}"
                    [[ "$obfs" != http ]] || client_config+=", obfs=http, obfs-host=${obfs_host}"
                    client_config+=", ${stls_options}"
                    print_config_block "Snell 客户端配置（实例 ${instance}，经 ShadowTLS #${target}）" "$client_config"
                done <<<"$wrappers"
            else
                external_port="$port"; stls_options=""
                client_config="$(hostname)-Snell-${instance} = snell, $(public_ip), ${external_port}, psk=${psk}, version=${protocol}, tfo=${tfo}, reuse=true, ecn=true"
                [[ "$protocol" != 6 || "$mode" == default || -z "$mode" ]] || client_config+=", mode=${mode}"
                [[ "$obfs" != http ]] || client_config+=", obfs=http, obfs-host=${obfs_host}"
                print_config_block "Snell 客户端配置（实例 ${instance}，Surge [Proxy]）" "$client_config"
            fi
            print_config_block "Snell 服务器配置（实例 ${instance}，$(read_meta "$meta" VERSION 2>/dev/null || printf unknown)）" "$(cat "$config")" ;;
        ss|ss2022)
            instance="$requested_instance"
            config="$(ss_instance_dir "$instance")/config.json"; meta="$(ss_instance_dir "$instance")/meta"; [[ -f "$config" ]] || die "未安装。"
            method="$(jq -er '.method' "$config")"; password="$(jq -er '.password' "$config")"; port="$(jq -er '.server_port' "$config")"
            wrappers="${routed_stls:-$(shadowtls_instances_for_target ss2022 "$instance")}"
            if [[ -n "$wrappers" ]]; then
                while read -r target; do
                    [[ -z "$target" ]] && continue
                    external_port="$(read_meta "$(shadowtls_instance_dir "$target")/meta" PORT)"
                    stls_options="$(shadowtls_surge_options "$(shadowtls_instance_dir "$target")")"
                    client_config="$(hostname)-SS2022-${instance}-STLS-${target} = ss, $(public_ip), ${external_port}, encrypt-method=${method}, password=${password}, ${stls_options}"
                    print_config_block "SS-2022 客户端配置（实例 ${instance}，经 ShadowTLS #${target}）" "$client_config"
                done <<<"$wrappers"
            else
                ss_url="ss://$(printf '%s' "${method}:${password}" | base64url)@$(public_ip):${port}#NewWorld-SS2022-${instance}"
                print_config_block "SS-2022 客户端链接（实例 ${instance}）" "$ss_url"
            fi
            print_config_block "SS-2022 服务器配置（实例 ${instance}）" "$(jq . "$config")" ;;
        shadowtls)
            shadowtls_migrate_legacy
            target="$requested_instance"
            config="$(shadowtls_instance_dir "$target")/environment"; [[ -f "$config" ]] || die "实例不存在。"
            print_config_block "ShadowTLS v3 完整服务器配置（实例 ${target}）" "地址 = $(public_ip)
$(cat "$config")
后端 = $(read_meta "$(shadowtls_instance_dir "$target")/meta" TARGET 2>/dev/null || printf unknown) #$(read_meta "$(shadowtls_instance_dir "$target")/meta" TARGET_INSTANCE 2>/dev/null || printf 1) (127.0.0.1:$(read_meta "$(shadowtls_instance_dir "$target")/meta" BACKEND_PORT 2>/dev/null || printf unknown))"
            show_config "$(read_meta "$(shadowtls_instance_dir "$target")/meta" TARGET)" "$(read_meta "$(shadowtls_instance_dir "$target")/meta" TARGET_INSTANCE 2>/dev/null || printf 1)" "$target" ;;
        *) die "未知组件。" ;;
    esac
}

reconfigure_component() {
    local component="$1" snapshot instance version protocol binary snapshot_binary
    case "$component" in
        snell)
            instance="$(select_proxy_instance snell)"; shadowtls_target_active snell "$instance" && die "该实例正在被 ShadowTLS 使用。"
            version="$(read_meta "$(snell_instance_dir "$instance")/meta" VERSION)"; protocol="$(read_meta "$(snell_instance_dir "$instance")/meta" PROTOCOL)"
            binary="$SNELL_BIN" ;;
        ss|ss2022)
            instance="$(select_proxy_instance ss2022)"; shadowtls_target_active ss2022 "$instance" && die "该实例正在被 ShadowTLS 使用。"
            version="$(read_meta "$(ss_instance_dir "$instance")/meta" VERSION)"
            binary="$SS_BIN" ;;
        shadowtls)
            instance="$(select_shadowtls_instance)"; version="$(read_meta "$(shadowtls_instance_dir "$instance")/meta" VERSION)"
            binary="$STLS_BIN" ;;
        *) die "未知组件：$component" ;;
    esac
    snapshot_manager_state snapshot
    snapshot_binary="$snapshot/bin/${binary##*/}"
    if (
        YES=true
        remove_component "$component" "$instance"
        [[ ! -f "$snapshot_binary" ]] || install -m 0755 -o root -g root "$snapshot_binary" "$binary"
        case "$component" in
            snell) SNELL_VERSION="$version"; configure_snell "$protocol" "$instance" ;;
            ss|ss2022) SS_VERSION="$version"; configure_ss "$instance" ;;
            shadowtls) STLS_VERSION="$version"; configure_stls "$instance" ;;
        esac
    ); then
        rm -rf -- "$snapshot"
    else
        restore_manager_state "$snapshot"
        die "$component 重新配置失败，已恢复原配置。"
    fi
}

install_manager() {
    local source="${BASH_SOURCE[0]-}" target="/usr/local/sbin/newworld-manager" temporary=""
    if [[ -n "$source" && -f "$source" ]]; then
        source="$(readlink -f "$source")"
    else
        new_temp_file temporary
        download "$SOURCE_URL" "$temporary"
        bash -n "$temporary" || { rm -f "$temporary"; die "下载的管理脚本语法检查失败。"; }
        source="$temporary"
    fi
    install -d -m 0755 /usr/local/sbin "$BIN_DIR"
    if [[ "$source" -ef "$target" ]]; then
        info "管理脚本已位于 ${target}，跳过重复复制。"
    else
        install -m 0755 "$source" "$target"
    fi
    [[ -z "$temporary" ]] || rm -f "$temporary"
    ln -sfn "$target" "$BIN_DIR/nw-manager"
    ok "已安装命令：nw-manager"
}

check_manager_update() {
    local remote_script remote_version target="/usr/local/sbin/newworld-manager" staged="/usr/local/sbin/.newworld-manager.new"
    ensure_dependencies self-install
    new_temp_file remote_script
    info "检查 NewWorld-Manager 更新。"
    download "${SOURCE_URL}?cache=${RANDOM}-$$" "$remote_script"
    bash -n "$remote_script" || die "远端脚本语法检查失败，已取消更新。"
    remote_version="$(sed -nE 's/^readonly VERSION="([0-9]+\.[0-9]+\.[0-9]+)"$/\1/p' "$remote_script" | head -n1)"
    [[ -n "$remote_version" ]] || die "无法识别远端脚本版本。"
    if [[ "$remote_version" == "$VERSION" ]]; then
        ok "当前已是最新版：${VERSION}"
        return 0
    fi
    if ! version_is_newer "$remote_version" "$VERSION"; then
        warn "远端版本 ${remote_version} 不高于当前版本 ${VERSION}，不执行更新。"
        return 0
    fi
    info "发现新版本：${VERSION} → ${remote_version}"
    confirm "是否更新并安装 nw-manager ${remote_version}？" || { warn "已取消更新。"; return 0; }
    install -d -m 0755 /usr/local/sbin "$BIN_DIR"
    install -m 0755 -o root -g root "$remote_script" "$staged"
    mv -f "$staged" "$target"
    ln -sfn "$target" "$BIN_DIR/nw-manager"
    ok "已更新到 ${remote_version}；下次运行 nw-manager 时生效。"
}

doctor() {
    local failures=0 command os_name memory_limit="" reported="" commands=(bash curl systemctl ip ss)
    [[ ! -x "$SNELL_BIN" ]] || commands+=(unzip openssl)
    [[ ! -x "$SS_BIN" ]] || commands+=(jq tar xz sha256sum)
    [[ ! -x "$STLS_BIN" ]] || commands+=(jq openssl sha256sum)
    os_name="$(sed -nE 's/^PRETTY_NAME="?([^\"]*)"?$/\1/p' /etc/os-release 2>/dev/null | head -n1 || true)"
    printf '系统：%s\n架构：%s\n包管理器：' "${os_name:-未知 Linux}" "$(uname -m)"
    package_manager 2>/dev/null || printf '未支持'; printf '\n'
    if [[ -r /sys/fs/cgroup/memory.max ]]; then memory_limit="$(</sys/fs/cgroup/memory.max)"; fi
    [[ ! "$memory_limit" =~ ^[0-9]+$ ]] || printf '容器内存上限：%s MiB\n' "$((memory_limit / 1048576))"
    for command in "${commands[@]}"; do
        [[ " $reported " != *" $command "* ]] || continue; reported+=" $command"
        if have "$command"; then printf '%s✓%s %-12s %s\n' "$GREEN" "$RESET" "$command" "$(command -v "$command")"
        else printf '%s✗%s %-12s 缺失\n' "$RED" "$RESET" "$command"; failures=$((failures+1)); fi
    done
    [[ -d /run/systemd/system ]] || { warn "systemd 未运行。"; failures=$((failures+1)); }
    [[ "$(id -u)" -eq 0 ]] || warn "当前不是 root，仅执行只读检查。"
    return "$failures"
}

usage() {
    cat <<EOF
$APP $VERSION

用法：
  $(basename "$0") status
  $(basename "$0") install <bbr|snell|ss2022|shadowtls>
  $(basename "$0") update <snell|ss2022|shadowtls>
  $(basename "$0") configure <snell|ss2022|shadowtls>
  $(basename "$0") remove <bbr|snell|ss2022|shadowtls> [实例号]
  $(basename "$0") restart <snell|ss2022|shadowtls> [实例号]
  $(basename "$0") logs <snell|ss2022|shadowtls> [行数] [实例号]
  $(basename "$0") config <snell|ss2022|shadowtls> [实例号]
  $(basename "$0") doctor | check-update | self-install | menu

选项：-y/--yes  --no-color  -h/--help  -V/--version
EOF
}

install_component() {
    ensure_dependencies "$1"
    case "$1" in bbr) enable_bbr;; snell) install_snell;; ss|ss2022) install_ss;; shadowtls) install_stls;; *) die "未知组件：$1";; esac
}

menu() {
    local choice component
    while true; do
        clear 2>/dev/null || true; show_status
        printf '1. 启用 BBR          2. 安装/更新 Snell\n3. 安装/更新 ss-2022 4. 安装/更新 ShadowTLS\n5. 查看配置          6. 查看日志\n7. 重启服务          8. 卸载组件\n9. 环境检查          10. 安装 nw-manager 命令\n11. 检查脚本更新     0. 退出\n'
        read -r -p '请选择 [0-11]: ' choice
        case "$choice" in
            1) install_component bbr;; 2) install_component snell;; 3) install_component ss2022;; 4) install_component shadowtls;;
            5) component="$(select_component)"; case "$component" in ss2022) ensure_dependencies ss2022;; shadowtls) ensure_dependencies shadowtls;; esac; show_config "$component";;
            6) journalctl -u "$(select_component_service)" -n 100 --no-pager;;
            7) systemctl restart "$(select_component_service)";;
            8) component="$(select_component true)"; remove_component "$component";;
            9) doctor || true;; 10) install_manager;; 11) check_manager_update;; 0) return 0;; *) warn "选择无效。";;
        esac
        [[ -t 0 ]] && { printf '\n按回车返回...'; read -r _; }
    done
}

main() {
    local args=() command component lines service arg
    while (($#)); do
        arg="$1"; shift
        case "$arg" in -y|--yes) YES=true;; --no-color) :;; -h|--help) usage; return 0;; -V|--version) printf '%s %s\n' "$APP" "$VERSION"; return 0;; *) args+=("$arg");; esac
    done
    set -- "${args[@]}"; command="${1:-menu}"; (($# == 0)) || shift
    require_linux
    case "$command" in
        status) require_systemd; show_status;; doctor) doctor;; menu)
            require_root; require_systemd; ensure_service_user; make_layout; menu;;
        install)
            component="${1:-}"; [[ -n "$component" ]] || die "缺少组件名。"
            require_root; require_systemd; ensure_service_user; make_layout; install_component "$component";;
        update)
            component="${1:-}"; [[ -n "$component" ]] || die "缺少组件名。"
            [[ "$component" != bbr ]] || die "BBR 没有独立更新操作，请使用 install bbr 重新应用配置。"
            UPDATE_ONLY=true; require_root; require_systemd; ensure_service_user; make_layout; install_component "$component";;
        remove)
            component="${1:-}"; [[ -n "$component" ]] || die "缺少组件名。"
            shift || true; require_root; require_systemd; ensure_service_user; make_layout; remove_component "$component" "${1:-}";;
        restart)
            component="${1:-}"; shift || true; require_root; require_systemd
            service="$(component_service "$component" "${1:-}")" || die "未知组件。"
            systemctl restart "$service";;
        logs)
            component="${1:-}"; lines="${2:-100}"; require_systemd; [[ "$lines" =~ ^[1-9][0-9]*$ ]] || die "日志行数无效。"
            service="$(component_service "$component" "${3:-}")" || die "未知组件。"; journalctl -u "$service" -n "$lines" --no-pager;;
        config)
            component="${1:-}"; require_root
            case "$component" in ss|ss2022) ensure_dependencies ss2022;; shadowtls) ensure_dependencies shadowtls;; esac
            show_config "$component" "${2:-}";;
        configure)
            component="${1:-}"; [[ -n "$component" ]] || die "缺少组件名。"
            require_root; require_systemd; ensure_dependencies "$component"; ensure_service_user; make_layout; reconfigure_component "$component";;
        check-update) require_root; check_manager_update;;
        self-install) require_root; ensure_dependencies self-install; install_manager;; help) usage;; *) die "未知命令：$command";;
    esac
}

if [[ -z "${BASH_SOURCE[0]-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
