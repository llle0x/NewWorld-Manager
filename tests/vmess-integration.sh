#!/usr/bin/env bash
set -Eeuo pipefail

source ./newworld-manager.sh

integration_dir=""
new_temp_dir integration_dir
archive="$integration_dir/v2ray.zip"
download_github_release v2fly/v2ray-core 'v2ray-linux-64\.zip$' "$archive"
unzip -q "$archive" -d "$integration_dir/release"
v2ray="$(find "$integration_dir/release" -type f -name v2ray -print -quit)"
[[ -n "$v2ray" ]]
chmod +x "$v2ray"
"$v2ray" version

uuid="$(random_uuid)"
tcp_config="$integration_dir/tcp.json"
write_vmess_server_config "$tcp_config" tcp 20001 "$uuid"
"$v2ray" test -config "$tcp_config"
jq -e '.inbounds[0].settings.disableInsecureEncryption == true and .inbounds[0].settings.clients[0].alterId == 0' "$tcp_config" >/dev/null

certificate="$integration_dir/certificate.pem"
private_key="$integration_dir/private.key"
openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 1 -subj '/CN=example.com' \
    -addext 'subjectAltName=DNS:example.com' -keyout "$private_key" -out "$certificate" >/dev/null 2>&1
validate_vmess_tls_material example.com "$certificate" "$private_key"

tls_config="$integration_dir/ws-tls.json"
write_vmess_server_config "$tls_config" ws-tls 20443 "$uuid" /vmess-test "$certificate" "$private_key"
"$v2ray" test -config "$tls_config"
jq -e '.inbounds[0].streamSettings.network == "ws" and .inbounds[0].streamSettings.security == "tls"' "$tls_config" >/dev/null

printf 'VMess integration tests passed\n'
