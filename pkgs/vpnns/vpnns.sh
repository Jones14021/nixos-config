#!/usr/bin/env bash
set -euo pipefail

need(){ command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1" >&2; exit 1; }; }
need ip awk sed

ME_USER="$(id -un)"
ME_HOME="${HOME:-/tmp}"

have(){ command -v "$1" >/dev/null 2>&1; }
sudo_run(){ sudo "$@"; }

# ---------------- selection (annotated) ----------------
iface_has_ipv4_default_route() {
  local ifc="$1"
  ip -4 route show default dev "$ifc" table main 2>/dev/null | grep -q '^default '
}

pick_upstream_iface() {
  mapfile -t ifaces < <(ip -o link show | awk -F': ' '{print $2}' | sed 's/@.*//' | grep -vE '^(lo)$')
  ((${#ifaces[@]})) || { echo "No interfaces found." >&2; exit 1; }

  local labels=() ifc
  for ifc in "${ifaces[@]}"; do
    if iface_has_ipv4_default_route "$ifc"; then
      labels+=("$ifc")
    else
      labels+=("$ifc (no internet connectivity)")
    fi
  done

  echo "Select upstream interface (traffic will be forced to egress here):" >&2
  local choice=""
  select choice in "${labels[@]}"; do
    [[ -n "${choice:-}" ]] || continue
    local idx=$((REPLY-1))
    echo "${ifaces[$idx]}"
    break
  done
}

get_iface_ipv4() {
  local ifc="$1"
  ip -4 -o addr show dev "$ifc" scope global 2>/dev/null | awk '{print $4}' | head -n1
}

check_ip_forwarding_enabled_or_die() {
  local v
  v="$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || echo 0)"
  [[ "$v" == "1" ]] || { echo "IPv4 forwarding disabled (net.ipv4.ip_forward=$v). Enable it and retry." >&2; exit 1; }
}

# ---------------- DNS discovery (systemd-resolved -> NM -> resolv.conf) ----------------
get_dns_servers_for_iface() {
  local ifc="$1"

  if have resolvectl; then
    resolvectl dns "$ifc" 2>/dev/null \
      | tr ' ' '\n' \
      | sed -nE 's/^([0-9]{1,3}(\.[0-9]{1,3}){3}|[0-9a-fA-F:]+)$/\1/p' \
      | sort -u
    return 0
  fi

  if have nmcli; then
    nmcli -g IP4.DNS,IP6.DNS device show "$ifc" 2>/dev/null | sed '/^$/d' | sort -u
    return 0
  fi

  local src="/etc/resolv.conf"
  if grep -qE '^\s*nameserver\s+127\.0\.0\.53\s*$' /etc/resolv.conf 2>/dev/null; then
    [[ -r /run/systemd/resolve/resolv.conf ]] && src="/run/systemd/resolve/resolv.conf"
  fi
  awk '/^\s*nameserver\s+/ {print $2}' "$src" | sort -u
}

write_ns_resolvconf() {
  local ns="$1" ifc="$2"
  sudo_run mkdir -p "/etc/netns/$ns"
  local servers
  servers="$(get_dns_servers_for_iface "$ifc" | sed '/^$/d' || true)"
  [[ -n "$servers" ]] || servers="1.1.1.1"

  sudo_run bash -c ": > /etc/netns/$ns/resolv.conf"
  while read -r s; do
    [[ -n "$s" ]] && sudo_run bash -c "echo 'nameserver $s' >> /etc/netns/$ns/resolv.conf"
  done <<< "$servers"
}

# ---------------- firewall backend selection ----------------
FW="none"
have nft && FW="nft"
if [[ "$FW" == "none" && $(have iptables; echo $?) -eq 0 ]]; then FW="iptables"; fi
[[ "$FW" != "none" ]] || { echo "Neither nft nor iptables available; cannot configure NAT." >&2; exit 1; }

# ---------------- runtime values ----------------
UP_IF="$(pick_upstream_iface)"
[[ -n "${UP_IF:-}" ]] || { echo "Internal error: empty upstream interface selection." >&2; exit 1; }

UP_IP_CIDR="$(get_iface_ipv4 "$UP_IF" || true)"

NS="vpnns-$RANDOM-$$"
VETH_HOST="vethh-$$"
VETH_NS="vethn-$$"

OCT="$(( (RANDOM%200)+10 ))"
HOST_IP="10.200.${OCT}.1/30"
NS_IP="10.200.${OCT}.2/30"
P2P_NET="10.200.${OCT}.0/30"

TABLE_ID=1001
RULE_PRIO=1001

# nft
NFT_TABLE="vpnns_nat_${RANDOM}_$$"

# iptables chains
IPT_FWD_CHAIN="VPNNS_FWD_${RANDOM}_$$"
IPT_NAT_CHAIN="VPNNS_NAT_${RANDOM}_$$"
IPT_RAW_CHAIN="VPNNS_RAW_${RANDOM}_$$"

# conntrack zone (1..65535)
CT_ZONE="$(( (RANDOM % 65000) + 1 ))"

ADDED_RULE=0
ADDED_ROUTES=0
ADDED_FW=0
ADDED_RAW=0

RP_UP_PREV=""     RP_UP_CHANGED=0
RP_VETH_PREV=""   RP_VETH_CHANGED=0

cleanup() {
  set +e

  # Restore rp_filter early
  if ((RP_VETH_CHANGED)) && [[ -n "$RP_VETH_PREV" ]]; then
    sudo_run sysctl -q -w "net.ipv4.conf.$VETH_HOST.rp_filter=$RP_VETH_PREV" 2>/dev/null || true
  fi
  if ((RP_UP_CHANGED)) && [[ -n "$RP_UP_PREV" ]]; then
    sudo_run sysctl -q -w "net.ipv4.conf.$UP_IF.rp_filter=$RP_UP_PREV" 2>/dev/null || true
  fi

  # iptables raw cleanup (zones)
  if ((ADDED_RAW)); then
    sudo_run iptables -t raw -D PREROUTING -j "$IPT_RAW_CHAIN" 2>/dev/null
    sudo_run iptables -t raw -D OUTPUT     -j "$IPT_RAW_CHAIN" 2>/dev/null
    sudo_run iptables -t raw -F "$IPT_RAW_CHAIN" 2>/dev/null
    sudo_run iptables -t raw -X "$IPT_RAW_CHAIN" 2>/dev/null
  fi

  # Firewall cleanup
  if ((ADDED_FW)); then
    if [[ "$FW" == "nft" ]]; then
      sudo_run nft delete table ip "$NFT_TABLE" 2>/dev/null
    else
      sudo_run iptables -t filter -D FORWARD -j "$IPT_FWD_CHAIN" 2>/dev/null
      sudo_run iptables -t nat    -D POSTROUTING -j "$IPT_NAT_CHAIN" 2>/dev/null
      sudo_run iptables -t filter -F "$IPT_FWD_CHAIN" 2>/dev/null
      sudo_run iptables -t nat    -F "$IPT_NAT_CHAIN" 2>/dev/null
      sudo_run iptables -t filter -X "$IPT_FWD_CHAIN" 2>/dev/null
      sudo_run iptables -t nat    -X "$IPT_NAT_CHAIN" 2>/dev/null
    fi
  fi

  # Policy routing cleanup
  ((ADDED_RULE)) && sudo_run ip -4 rule del pref "$RULE_PRIO" 2>/dev/null
  ((ADDED_ROUTES)) && sudo_run ip -4 route flush table "$TABLE_ID" 2>/dev/null

  # Netns files cleanup
  sudo_run rm -f "/etc/netns/$NS/resolv.conf" 2>/dev/null
  sudo_run rmdir "/etc/netns/$NS" 2>/dev/null

  # Netns + veth cleanup
  sudo_run ip netns del "$NS" 2>/dev/null
  sudo_run ip link del "$VETH_HOST" 2>/dev/null
}
trap cleanup EXIT INT TERM

# ---------------- checks ----------------
check_ip_forwarding_enabled_or_die

DEF_ROUTE="$(ip -4 route show default dev "$UP_IF" table main | head -n1 || true)"
if [[ -z "$DEF_ROUTE" ]]; then
  echo "No IPv4 default route found on '$UP_IF' in the main table." >&2
  echo "Pick an interface that carries your default route, or configure one." >&2
  exit 1
fi
UP_SRC="$(awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}' <<<"$DEF_ROUTE")"
if [[ -z "$UP_SRC" ]]; then
  echo "No 'src' found in default route for '$UP_IF': $DEF_ROUTE" >&2
  echo "Cannot SNAT deterministically; aborting." >&2
  exit 1
fi

# ---------------- privileged setup ----------------
sudo_run ip netns add "$NS"

sudo_run ip link add "$VETH_HOST" type veth peer name "$VETH_NS"
sudo_run ip link set "$VETH_NS" netns "$NS"

sudo_run ip addr add "$HOST_IP" dev "$VETH_HOST"
sudo_run ip link set "$VETH_HOST" up

# rp_filter (Option A): disable for session, restore later
RP_UP_PREV="$(cat "/proc/sys/net/ipv4/conf/$UP_IF/rp_filter" 2>/dev/null || echo "")"
RP_VETH_PREV="$(cat "/proc/sys/net/ipv4/conf/$VETH_HOST/rp_filter" 2>/dev/null || echo "")"

if [[ -n "$RP_UP_PREV" && "$RP_UP_PREV" != "0" ]]; then
  sudo_run sysctl -q -w "net.ipv4.conf.$UP_IF.rp_filter=0"
  RP_UP_CHANGED=1
fi
if [[ -n "$RP_VETH_PREV" && "$RP_VETH_PREV" != "0" ]]; then
  sudo_run sysctl -q -w "net.ipv4.conf.$VETH_HOST.rp_filter=0"
  RP_VETH_CHANGED=1
fi

sudo_run ip netns exec "$NS" ip link set lo up
sudo_run ip netns exec "$NS" ip addr add "$NS_IP" dev "$VETH_NS"
sudo_run ip netns exec "$NS" ip link set "$VETH_NS" up
sudo_run ip netns exec "$NS" ip -4 route add default via "${HOST_IP%/*}"

write_ns_resolvconf "$NS" "$UP_IF"

# Policy routing
sudo_run ip -4 route add "$P2P_NET" dev "$VETH_HOST" table "$TABLE_ID"
sudo_run ip -4 route add table "$TABLE_ID" $DEF_ROUTE
ADDED_ROUTES=1
sudo_run ip -4 rule add pref "$RULE_PRIO" from "$P2P_NET" lookup "$TABLE_ID"
ADDED_RULE=1

# Allow unprivileged ping in the netns
sudo_run ip netns exec "$NS" sysctl -q -w net.ipv4.ping_group_range="0 2147483647"

# conntrack zone isolation (iptables raw): apply a dedicated CT zone to veth traffic
if [[ "$FW" == "iptables" ]]; then
  sudo_run iptables -t raw -N "$IPT_RAW_CHAIN"
  # Hook our chain (idempotent)
  sudo_run iptables -t raw -C PREROUTING -j "$IPT_RAW_CHAIN" 2>/dev/null || sudo_run iptables -t raw -I PREROUTING 1 -j "$IPT_RAW_CHAIN"
  sudo_run iptables -t raw -C OUTPUT     -j "$IPT_RAW_CHAIN" 2>/dev/null || sudo_run iptables -t raw -I OUTPUT 1 -j "$IPT_RAW_CHAIN"

  # Put veth traffic into a dedicated conntrack zone (both directions)
  sudo_run iptables -t raw -A "$IPT_RAW_CHAIN" -i "$VETH_HOST" -j CT --zone "$CT_ZONE"
  sudo_run iptables -t raw -A "$IPT_RAW_CHAIN" -o "$VETH_HOST" -j CT --zone "$CT_ZONE"
  sudo_run iptables -t raw -A "$IPT_RAW_CHAIN" -j RETURN

  ADDED_RAW=1
fi

# Firewall / NAT
if [[ "$FW" == "nft" ]]; then
  sudo_run nft add table ip "$NFT_TABLE"
  sudo_run nft "add chain ip $NFT_TABLE postrouting { type nat hook postrouting priority 100 ; policy accept ; }"
  sudo_run nft "add rule ip $NFT_TABLE postrouting ip saddr $P2P_NET oifname \"$UP_IF\" masquerade"
  ADDED_FW=1
else
  sudo_run iptables -t filter -N "$IPT_FWD_CHAIN"
  sudo_run iptables -t nat    -N "$IPT_NAT_CHAIN"

  sudo_run iptables -t filter -C FORWARD -j "$IPT_FWD_CHAIN" 2>/dev/null || sudo_run iptables -t filter -I FORWARD 1 -j "$IPT_FWD_CHAIN"
  sudo_run iptables -t nat    -C POSTROUTING -j "$IPT_NAT_CHAIN" 2>/dev/null || sudo_run iptables -t nat    -I POSTROUTING 1 -j "$IPT_NAT_CHAIN"

  # Deterministic SNAT
  sudo_run iptables -t nat -A "$IPT_NAT_CHAIN" -s "$P2P_NET" -o "$UP_IF" -j SNAT --to-source "$UP_SRC"
  sudo_run iptables -t nat -A "$IPT_NAT_CHAIN" -j RETURN

  # Forward rules
  sudo_run iptables -t filter -A "$IPT_FWD_CHAIN" -i "$VETH_HOST" -o "$UP_IF" -s "$P2P_NET" -j ACCEPT
  sudo_run iptables -t filter -A "$IPT_FWD_CHAIN" -i "$UP_IF" -o "$VETH_HOST" -d "$P2P_NET" -j ACCEPT
  sudo_run iptables -t filter -A "$IPT_FWD_CHAIN" -i "$VETH_HOST" ! -o "$UP_IF" -s "$P2P_NET" -j REJECT --reject-with icmp-port-unreachable
  sudo_run iptables -t filter -A "$IPT_FWD_CHAIN" -j RETURN

  ADDED_FW=1
fi

dns_in_ns="$(sudo cat "/etc/netns/$NS/resolv.conf" 2>/dev/null | awk '/^\s*nameserver\s+/ {printf "%s ", $2}' | sed 's/ $//')"

echo
echo "Netns:         $NS"
echo "Upstream:      $UP_IF"
echo "Upstream IP:   ${UP_IP_CIDR:-<none>}"
echo "Default route: $DEF_ROUTE"
echo "Upstream src:  $UP_SRC"
echo "P2P subnet:    $P2P_NET"
echo "Host veth IP:  $HOST_IP"
echo "NS veth IP:    $NS_IP"
echo "Policy table:  $TABLE_ID (rule pref $RULE_PRIO)"
echo "Firewall:      $FW"
if [[ "$FW" == "iptables" ]]; then
  echo "CT zone:       $CT_ZONE"
fi
echo "DNS (netns):   $dns_in_ns"
echo "User shell as: $ME_USER"
echo

echo "whois DNS $dns_in_ns:"
(command -v dig >/dev/null && dig +short -x "$dns_in_ns") || true
(command -v whois >/dev/null && whois "$dns_in_ns" | sed -n '1,25p') || true
echo

sudo --preserve-env ip netns exec "$NS" sudo --preserve-env -u "$ME_USER" env \
  PS1="[$NS via $UP_IF] \\u@\\h:\\w\\$ " \
  bash --noprofile --norc
