#!/usr/bin/env bash
set -euo pipefail

IP_BIN="${IP_BIN:-${IP:-ip}}"

: "${interface:?Missing DHCP interface}"
: "${IPERF_READY_FILE:?Missing readiness file}"

case "${1:-}" in
  deconfig)
    "$IP_BIN" -4 addr flush dev "$interface"
    "$IP_BIN" -4 route flush dev "$interface"
    rm -f "$IPERF_READY_FILE"
    ;;

  bound|renew)
    : "${ip:?Missing DHCP address}"

    mask="${subnet:-255.255.255.0}"
    IFS=. read -r -a octets <<< "$mask"

    if (( ${#octets[@]} != 4 )); then
      echo "Invalid DHCP subnet mask: $mask" >&2
      exit 1
    fi

    prefix=0
    partial=0

    for octet in "${octets[@]}"; do
      case "$octet" in
        255) bits=8 ;;
        254) bits=7 ;;
        252) bits=6 ;;
        248) bits=5 ;;
        240) bits=4 ;;
        224) bits=3 ;;
        192) bits=2 ;;
        128) bits=1 ;;
        0)   bits=0 ;;
        *)
          echo "Invalid DHCP subnet mask: $mask" >&2
          exit 1
          ;;
      esac

      if (( partial && bits != 0 )); then
        echo "Non-contiguous DHCP subnet mask: $mask" >&2
        exit 1
      fi

      prefix=$((prefix + bits))
      if (( bits < 8 )); then
        partial=1
      fi
    done

    "$IP_BIN" -4 addr flush dev "$interface"
    "$IP_BIN" -4 route flush dev "$interface"
    "$IP_BIN" -4 addr add "$ip/$prefix" dev "$interface"

    gateways=()
    read -r -a gateways <<< "${router:-}"
    if (( ${#gateways[@]} > 0 )); then
      "$IP_BIN" -4 route replace default via "${gateways[0]}" dev "$interface"
    fi

    printf '%s\n' "$ip" > "$IPERF_READY_FILE.tmp"
    mv "$IPERF_READY_FILE.tmp" "$IPERF_READY_FILE"
    ;;
esac
