#!/usr/bin/env bash
set -Eeuo pipefail

source ./newworld-manager.sh

integration_dir=""
new_temp_dir integration_dir

ss_archive="$integration_dir/ss.tar.xz"
download_github_release shadowsocks/shadowsocks-rust 'x86_64-unknown-linux-musl\.tar\.xz$' "$ss_archive"
tar -xJf "$ss_archive" -C "$integration_dir"
ssserver="$(find "$integration_dir" -type f -name ssserver -print -quit)"
[[ -n "$ssserver" ]]
chmod +x "$ssserver"
"$ssserver" --version

ss_config="$integration_dir/ss.json"
ss_password="$(random_base64 32)"
ss_port="$(random_port)"
jq -n --arg password "$ss_password" --argjson port "$ss_port" '{server:"127.0.0.1",server_port:$port,password:$password,method:"2022-blake3-aes-256-gcm",mode:"tcp_and_udp"}' >"$ss_config"
set +e
timeout 2 "$ssserver" -c "$ss_config" >/dev/null 2>&1
ss_status=$?
set -e
[[ "$ss_status" == 124 ]]

shadowtls="$integration_dir/shadow-tls"
download_github_release ihciah/shadow-tls 'shadow-tls-x86_64-unknown-linux-musl$' "$shadowtls"
chmod +x "$shadowtls"
"$shadowtls" --version
"$shadowtls" --v3 server --help >/dev/null

printf 'Core integration tests passed\n'
