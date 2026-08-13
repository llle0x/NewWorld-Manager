#!/usr/bin/env bash
set -Eeuo pipefail

inline_output="$("${BASH:-bash}" -c "$(<newworld-manager.sh)" -- --version)"
[[ "$inline_output" == "NewWorld-Manager 5.2.1" ]]

# Sourcing the script must expose helpers without starting the menu.
source ./newworld-manager.sh
[[ "$VERSION" == "5.2.1" ]]
valid_instance_id 1
valid_instance_id 99
if valid_instance_id 0; then exit 1; fi
if valid_instance_id 100; then exit 1; fi
[[ "$(snell_service 12)" == "newworld-snell-12.service" ]]
[[ "$(ss_service 34)" == "newworld-ss2022-34.service" ]]
[[ "$(vmess_service 56)" == "newworld-vmess-56.service" ]]
[[ "$(vmess_instance_dir 56)" == "/etc/newworld-manager/vmess/instances/56" ]]
[[ "$(vless_service 78)" == "newworld-vless-78.service" ]]
[[ "$(vless_instance_dir 78)" == "/etc/newworld-manager/vless/instances/78" ]]
valid_uuid 123e4567-e89b-42d3-a456-426614174000
if command -v openssl >/dev/null 2>&1; then valid_uuid "$(random_uuid)"; fi
valid_ws_path /vmess-test_1
if valid_ws_path 'missing-leading-slash'; then exit 1; fi
valid_host example.com
valid_host sub-domain.example.com
if valid_host '-invalid.example.com'; then exit 1; fi
if valid_host 'invalid..example.com'; then exit 1; fi
valid_release_version v26.3.27
valid_release_version 1.24.0
if valid_release_version '../../payload'; then exit 1; fi
[[ "$(vmess_asset_pattern)" == 'v2ray-linux-64\.zip$' ]]
[[ "$(xray_asset_pattern)" == 'Xray-linux-64\.zip$' ]]
[[ "$(ss_asset_pattern_for_arch aarch64)" == 'aarch64-unknown-linux-musl\.tar\.xz$' ]]
[[ "$(stls_asset_pattern_for_arch aarch64)" == 'shadow-tls-aarch64-unknown-linux-musl$' ]]
[[ "$(vmess_asset_pattern_for_arch aarch64)" == 'v2ray-linux-arm64-v8a\.zip$' ]]
[[ "$(xray_asset_pattern_for_arch aarch64)" == 'Xray-linux-arm64-v8a\.zip$' ]]
[[ "$(ss_asset_pattern_for_arch armv7)" == 'armv7-unknown-linux-musleabihf\.tar\.xz$' ]]
[[ "$(stls_asset_pattern_for_arch armv7)" == 'shadow-tls-armv7-unknown-linux-musleabihf$' ]]
[[ "$(vmess_asset_pattern_for_arch armv7)" == 'v2ray-linux-arm32-v7a\.zip$' ]]
[[ "$(xray_asset_pattern_for_arch armv7)" == 'Xray-linux-arm32-v7a\.zip$' ]]
valid_reality_target example.com:443
if valid_reality_target example.com; then exit 1; fi
proxy_instance_dirs() { :; }
show_existing_instances snell
unset -f proxy_instance_dirs
[[ "$(select_snell_protocol 5 <<<6)" == 6 ]]
[[ "$(select_boolean test true <<<2)" == false ]]
[[ "$(select_dns_preference <<<4)" == ipv4-only ]]
[[ "$(select_snell_mode <<<2)" == unshaped ]]
[[ "$(select_snell_obfs <<<2)" == http ]]
[[ "$(select_vmess_transport <<<1)" == tcp ]]
[[ "$(select_vmess_transport <<<2)" == ws-tls ]]
[[ "$(select_vless_transport <<<1)" == reality ]]
[[ "$(select_vless_transport <<<2)" == ws-tls ]]
[[ "$(select_component <<<1)" == snell ]]
[[ "$(select_component <<<2)" == ss2022 ]]
[[ "$(select_component <<<3)" == shadowtls ]]
[[ "$(select_component <<<4)" == vmess ]]
[[ "$(select_component <<<5)" == vless ]]
[[ "$(select_component true <<<6)" == bbr ]]

checksum_file="$(mktemp /tmp/newworld-manager.checksum.XXXXXX)"
printf 'SHA2-256= ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789\n' >"$checksum_file"
[[ "$(parse_sha256_file "$checksum_file")" == abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789 ]]
printf '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef  archive.zip\n' >"$checksum_file"
[[ "$(parse_sha256_file "$checksum_file")" == 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef ]]
rm -f "$checksum_file"
version_is_newer 3.3.1 3.3.0
version_is_newer 4.0.0 3.9.9
if version_is_newer 3.3.0 3.3.0; then exit 1; fi
if version_is_newer 3.2.9 3.3.0; then exit 1; fi
grep -q "首次安装实例编号 \[1\]" newworld-manager.sh
(have() { [[ "$1" == zypper ]]; }; [[ "$(package_manager)" == zypper ]])
(have() { [[ "$1" == pacman ]]; }; [[ "$(package_manager)" == pacman ]])

declare -a SYSTEMCTL_CALLS=()
systemctl() {
    SYSTEMCTL_CALLS+=("$*")
    return 0
}
sleep() { :; }
reload_start smoke.service
[[ " ${SYSTEMCTL_CALLS[*]} " == *" daemon-reload "* ]]
[[ " ${SYSTEMCTL_CALLS[*]} " == *" enable smoke.service "* ]]
[[ " ${SYSTEMCTL_CALLS[*]} " == *" restart smoke.service "* ]]
unset -f systemctl sleep

systemctl() { [[ "$1" != restart ]] || return 0; [[ "$1" != is-active ]] || return 0; }
journalctl() { :; }
restart_service_checked smoke.service
unset -f systemctl journalctl

systemctl() { [[ "$1" != restart ]]; }
journalctl() { :; }
if (restart_service_checked broken.service); then exit 1; fi
unset -f systemctl journalctl

if command -v mktemp >/dev/null 2>&1 && command -v rm >/dev/null 2>&1; then
    # A failed batch restart must restore the previous shared binary.
    rollback_binary="$(mktemp /tmp/newworld-manager.rollback.XXXXXX)"
    printf 'new' >"$rollback_binary"
    printf 'old' >"${rollback_binary}.previous"
    systemctl() { [[ "$1 $2" != "restart broken.service" ]]; }
    journalctl() { :; }
    if (restart_services_or_rollback "$rollback_binary" good.service broken.service); then exit 1; fi
    [[ "$(<"$rollback_binary")" == old ]]
    rm -f "$rollback_binary" "${rollback_binary}.previous"
    unset -f systemctl journalctl

    smoke_temp=""
    new_temp_file smoke_temp
    [[ -f "$smoke_temp" && "$smoke_temp" == /tmp/newworld-manager.* ]]
    cleanup_temp_paths
    [[ ! -e "$smoke_temp" ]]
fi

printf 'smoke tests passed\n'
