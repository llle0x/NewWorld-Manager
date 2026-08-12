#!/usr/bin/env bash
set -Eeuo pipefail

inline_output="$("${BASH:-bash}" -c "$(<newworld-manager.sh)" -- --version)"
[[ "$inline_output" == "NewWorld-Manager 4.1.9" ]]

# Sourcing the script must expose helpers without starting the menu.
source ./newworld-manager.sh
[[ "$VERSION" == "4.1.9" ]]
valid_instance_id 1
valid_instance_id 99
if valid_instance_id 0; then exit 1; fi
if valid_instance_id 100; then exit 1; fi
[[ "$(snell_service 12)" == "newworld-snell-12.service" ]]
[[ "$(ss_service 34)" == "newworld-ss2022-34.service" ]]
[[ "$(select_snell_protocol 5 <<<6)" == 6 ]]
[[ "$(select_boolean test true <<<2)" == false ]]
[[ "$(select_dns_preference <<<4)" == ipv4-only ]]
[[ "$(select_snell_mode <<<2)" == unshaped ]]
[[ "$(select_snell_obfs <<<2)" == http ]]
[[ "$(select_component <<<1)" == snell ]]
[[ "$(select_component <<<2)" == ss2022 ]]
[[ "$(select_component <<<3)" == shadowtls ]]
[[ "$(select_component true <<<4)" == bbr ]]
version_is_newer 3.3.1 3.3.0
version_is_newer 4.0.0 3.9.9
if version_is_newer 3.3.0 3.3.0; then exit 1; fi
if version_is_newer 3.2.9 3.3.0; then exit 1; fi

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

if command -v mktemp >/dev/null 2>&1 && command -v rm >/dev/null 2>&1; then
    smoke_temp=""
    new_temp_file smoke_temp
    [[ -f "$smoke_temp" && "$smoke_temp" == /tmp/newworld-manager.* ]]
    cleanup_temp_paths
    [[ ! -e "$smoke_temp" ]]
fi

printf 'smoke tests passed\n'
