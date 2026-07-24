#!/bin/sh

set -eu

if ! command -v curl >/dev/null 2>&1; then
    printf '%s\n' "Error: curl is required to look up the WAN IP address." >&2
    exit 1
fi

for endpoint in \
    "https://api.ipify.org" \
    "https://checkip.amazonaws.com" \
    "https://ifconfig.me/ip"
do
    wan_ip=$(curl --fail --silent --max-time 5 "$endpoint" 2>/dev/null) || continue
    wan_ip=$(printf '%s' "$wan_ip" | tr -d '[:space:]')

    if printf '%s\n' "$wan_ip" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$|^[0-9A-Fa-f:]+$'; then
        printf '%s\n' "$wan_ip"
        exit 0
    fi
done

printf '%s\n' "Error: unable to determine the WAN IP address." >&2
exit 1
