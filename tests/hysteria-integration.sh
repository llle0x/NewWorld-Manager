#!/usr/bin/env bash
set -Eeuo pipefail

source ./newworld-manager.sh

integration_dir=""
new_temp_dir integration_dir
hysteria="$integration_dir/hysteria"
download "https://download.hysteria.network/app/latest/$(hysteria_asset)" "$hysteria"
chmod +x "$hysteria"
"$hysteria" version

certificate="$integration_dir/certificate.pem"
private_key="$integration_dir/private.key"
openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 1 -subj '/CN=example.com' \
    -addext 'subjectAltName=DNS:example.com' -keyout "$private_key" -out "$certificate" >/dev/null 2>&1

config="$integration_dir/config.yaml"
cat >"$config" <<EOF
listen: :24443
tls:
  cert: $certificate
  key: $private_key
auth:
  type: password
  password: integration-password
obfs:
  type: salamander
  salamander:
    password: integration-obfs
EOF

set +e
timeout 2 "$hysteria" server -c "$config" >/dev/null 2>&1
status=$?
set -e
[[ "$status" == 124 ]]
printf 'Hysteria 2 integration tests passed\n'
