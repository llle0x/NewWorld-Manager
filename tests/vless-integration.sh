#!/usr/bin/env bash
set -Eeuo pipefail

source ./newworld-manager.sh

integration_dir=""
new_temp_dir integration_dir
archive="$integration_dir/xray.zip"
download_github_release XTLS/Xray-core 'Xray-linux-64\.zip$' "$archive"
unzip -q "$archive" -d "$integration_dir/release"
xray="$(find "$integration_dir/release" -type f -name xray -print -quit)"
[[ -n "$xray" ]]
chmod +x "$xray"
"$xray" version

parse_reality_keys "$("$xray" x25519)"
[[ "$REALITY_PRIVATE_KEY" =~ ^[A-Za-z0-9_-]+$ ]]
[[ "$REALITY_PASSWORD" =~ ^[A-Za-z0-9_-]+$ ]]

uuid="$(random_uuid)"
short_id="$(openssl rand -hex 8)"
reality_server="$integration_dir/reality-server.json"
write_vless_server_config "$reality_server" reality 20443 "$uuid" www.microsoft.com:443 www.microsoft.com "$REALITY_PRIVATE_KEY" "$short_id"
"$xray" run -test -config "$reality_server"
jq -e '.inbounds[0].protocol == "vless" and .inbounds[0].settings.clients[0].flow == "xtls-rprx-vision" and .inbounds[0].streamSettings.security == "reality"' "$reality_server" >/dev/null

reality_client="$integration_dir/reality-client.json"
write_vless_client_config "$reality_client" reality 203.0.113.1 20443 "$uuid" www.microsoft.com "$REALITY_PASSWORD" "$short_id"
"$xray" run -test -config "$reality_client"
jq -e '.outbounds[0].streamSettings.realitySettings.password == $password' --arg password "$REALITY_PASSWORD" "$reality_client" >/dev/null

certificate="$integration_dir/certificate.pem"
private_key="$integration_dir/private.key"
openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 1 -subj '/CN=example.com' \
    -addext 'subjectAltName=DNS:example.com' -keyout "$private_key" -out "$certificate" >/dev/null 2>&1
validate_tls_material example.com "$certificate" "$private_key"

ws_server="$integration_dir/ws-server.json"
write_vless_server_config "$ws_server" ws-tls 21443 "$uuid" /vless-test "$certificate" "$private_key"
"$xray" run -test -config "$ws_server"
jq -e '.inbounds[0].streamSettings.network == "ws" and .inbounds[0].streamSettings.security == "tls"' "$ws_server" >/dev/null

ws_client="$integration_dir/ws-client.json"
write_vless_client_config "$ws_client" ws-tls example.com 21443 "$uuid" example.com /vless-test
"$xray" run -test -config "$ws_client"
jq -e '.outbounds[0].streamSettings.wsSettings.path == "/vless-test"' "$ws_client" >/dev/null

printf 'VLESS integration tests passed\n'
