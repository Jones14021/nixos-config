#!/usr/bin/env bash
set -euo pipefail

if (( EUID != 0 )); then
  echo "This tool must be run with sudo."
  echo "Run with:"
  echo "  sudo $0"
  exit 1
fi

if [[ ! -t 0 ]]; then
  echo "An interactive terminal is required." >&2
  exit 1
fi

print_disclaimer() {
  cat <<'EOF'
Isolation and limitations:
- No host firewall flushing, Tailscale changes, Docker changes, route changes, or DNS changes.
- The existing physical adapter stays in the host namespace; only the newly created macvlan is moved.
- DHCP continues running to renew the lease. Its hook handles lease configuration exclusively inside the namespace.
- Normal exit, Ctrl-C, SIGHUP, and SIGTERM trigger cleanup. SIGKILL or a machine crash cannot execute shell cleanup.
- The selected network must allow an additional MAC address. Ordinary Wi-Fi station links often do not support this arrangement.
- The parent host normally cannot directly reach its macvlan child. Test from another LAN device.
- The namespace has no application firewall. The server is accessible from the LAN while running; WAN exposure still requires your router's port forward.
- A fresh invocation creates a fresh macvlan MAC unless a persisted one is reused. For a stable WAN-forwarding destination, choose a reserved static IP outside the DHCP allocation pool.
EOF
}

print_disclaimer

die() {
  echo "Error: $*" >&2
  exit 1
}

persist_dir="${XDG_CONFIG_HOME:-$HOME/.config}/iper3-server-isolated-macvlan"
persist_file="$persist_dir/mac"

load_or_create_mac() {
  mkdir -p "$persist_dir"

  if [[ -s "$persist_file" ]]; then
    local stored
    stored="$(tr -d '[:space:]' < "$persist_file")"
    if [[ "$stored" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
      printf '%s\n' "${stored,,}"
      return 0
    fi
  fi

  local random_hex
  random_hex="$(od -An -tx1 -N6 /dev/urandom | tr -d ' \n')"

  local first_byte="${random_hex:0:2}"
  local first_dec=$((16#$first_byte | 0x02))
  first_byte="$(printf '%02x' "$first_dec")"

  local mac
  mac="$(printf '%s:%s:%s:%s:%s:%s' \
    "$first_byte" \
    "${random_hex:2:2}" \
    "${random_hex:4:2}" \
    "${random_hex:6:2}" \
    "${random_hex:8:2}" \
    "${random_hex:10:2}")"

  printf '%s\n' "$mac" > "$persist_file"
  printf '%s\n' "$mac"
}

# Only enumerate device-backed Ethernet interfaces.
# Exclude common Wi-Fi interfaces: macvlan generally requires
# upstream support for multiple source MAC addresses.
interfaces=()

echo "Physical Ethernet interfaces:"
echo

for path in /sys/class/net/*; do
  [[ -e "$path/device" ]] || continue
  [[ -f "$path/type" ]] || continue
  [[ "$(cat "$path/type")" == 1 ]] || continue
  [[ -d "$path/wireless" ]] && continue
  [[ -e "$path/phy80211" ]] && continue

  iface="${path##*/}"
  interfaces+=("$iface")

  state="$(cat "$path/operstate")"
  mac="$(cat "$path/address")"
  addresses="$(
    ip -o -4 addr show dev "$iface" |
      awk '{ print $4 }' |
      paste -sd ',' -
  )"

  printf '  %d) %s  state=%s  MAC=%s  IPv4=%s\n' \
    "${#interfaces[@]}" "$iface" "$state" "$mac" \
    "${addresses:--}"
done

(( ${#interfaces[@]} > 0 )) || die "No physical Ethernet interfaces found."

echo
while true; do
  read -r -p "Interface number: " choice

  if [[ "$choice" =~ ^[0-9]{1,3}$ ]]; then
    index=$((10#$choice))
    if (( index >= 1 && index <= ${#interfaces[@]} )); then
      parent="${interfaces[index - 1]}"
      break
    fi
  fi

  echo "Choose one of the listed interface numbers."
done

# Do not bring up or otherwise reconfigure the host interface.
if ! ip -o link show dev "$parent" |
  grep -Eq '<([^>]*,)?UP(,|>)'; then
  die "$parent is administratively down. This tool will not change it."
fi

echo
echo "IPv4 configuration:"
echo "  1) DHCP"
echo "  2) Static"
echo

while true; do
  read -r -p "Configuration [1]: " mode
  mode="${mode:-1}"
  case "$mode" in
    1|2) break ;;
    *) echo "Enter 1 or 2." ;;
  esac
done

address=""
gateway=""

if [[ "$mode" == 2 ]]; then
  echo
  echo "Use an unused address, reserved/excluded from DHCP."
  read -r -p "IPv4 address/CIDR (e.g. 192.168.5.250/24): " address
  [[ -n "$address" ]] || die "An address is required."

  read -r -p "Gateway IPv4 (blank for LAN-only): " gateway
fi

read -r -p "iperf3 TCP port [5102]: " port
port="${port:-5102}"

[[ "$port" =~ ^[0-9]{1,5}$ ]] || die "Invalid port."
port=$((10#$port))
(( port >= 1 && port <= 65535 )) || die "Invalid port."

# Unique namespace and interface names per invocation.
ns="iperf-mv-$$"
link="ipfmv$$"
work="$(mktemp -d /run/iperf-macvlan.XXXXXX)"

ns_created=0
link_created=0
dhcp_pid=""
server_pid=""

# shellcheck disable=SC2329
cleanup() {
  local status="${1:-$?}"
  trap - EXIT INT TERM HUP
  set +e

  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" 2>/dev/null
    wait "$server_pid" 2>/dev/null
  fi

  if [[ -n "$dhcp_pid" ]]; then
    kill "$dhcp_pid" 2>/dev/null
    wait "$dhcp_pid" 2>/dev/null
  fi

  if (( ns_created )); then
    ip netns delete "$ns" 2>/dev/null
  fi

  if (( link_created )); then
    ip link delete "$link" 2>/dev/null
  fi

  rm -rf -- "$work"
  echo
  echo "Removed this invocation's namespace and macvlan."
  exit "$status"
}

trap 'cleanup "$?"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

ip netns add "$ns"
ns_created=1

mac="$(load_or_create_mac)"

ip link add link "$parent" name "$link" address "$mac" type macvlan mode bridge
link_created=1

ip link set "$link" netns "$ns"
ip -n "$ns" link set "$link" name lan0
link_created=0

ip -n "$ns" link set lo up

# Disable IPv6 only inside the newly created namespace.
ip netns exec "$ns" sh -c '
  printf "1\n" > /proc/sys/net/ipv6/conf/all/disable_ipv6
  printf "1\n" > /proc/sys/net/ipv6/conf/default/disable_ipv6
  printf "1\n" > /proc/sys/net/ipv6/conf/lan0/disable_ipv6
'

ip -n "$ns" link set lan0 up

if [[ "$mode" == 1 ]]; then
  echo
  echo "Requesting DHCP on $parent using macvlan MAC $mac ..."

  export IPERF_READY_FILE="$work/ready"
  export IPERF_HOST_INTERFACE="lan0"

  ip netns exec "$ns" \
    busybox udhcpc \
      -f -R -n -t 10 -T 3 \
      -i lan0 \
      -p "$work/udhcpc.pid" \
      -s "${DHCP_HOOK_PATH}" \
      > "$work/dhcp.log" 2>&1 &
  dhcp_pid=$!

  ready=0
  for ((attempt=0; attempt<45; attempt++)); do
    if [[ -s "$work/ready" ]]; then
      ready=1
      break
    fi

    if ! kill -0 "$dhcp_pid" 2>/dev/null; then
      break
    fi

    sleep 1
done

  if (( ! ready )); then
    cat "$work/dhcp.log" >&2
    die "DHCP failed or timed out."
  fi
else
  ip -n "$ns" -4 addr add "$address" dev lan0
  if [[ -n "$gateway" ]]; then
    ip -n "$ns" -4 route add default via "$gateway" dev lan0
  fi
fi

server_ip="$(ip -n "$ns" -o -4 addr show dev lan0 |
  awk 'NR == 1 { split($4, a, "/"); print a[1] }')"
[[ -n "$server_ip" ]] || die "No IPv4 address configured."

echo
echo "Namespace: $ns"
echo "Parent:    $parent (unchanged)"
echo "MAC:       $mac"
echo "Server:    $server_ip:$port"
echo
echo "For WAN access, forward TCP $port to $server_ip:$port."
echo "Test from another LAN device, not this parent host."
echo "Press Ctrl-C to stop and clean up."
echo
ip -n "$ns" -4 route show
echo

ip netns exec "$ns" iperf3 -s -4 -p "$port" &
server_pid=$!

status=0
wait "$server_pid" || status=$?
server_pid=""
exit "$status"
