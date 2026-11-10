#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/../../.." && pwd)
temporary=$(mktemp -d)
trap 'rm -rf -- "$temporary"' EXIT
drv=$(cd "$root" && nix eval --raw .#nixosConfigurations.werkstatt.config.home-manager.users.jonas.systemd.user.services.setup-oth-vpn.Service.ExecStart --apply 'value: builtins.head (builtins.attrNames (builtins.getContext (builtins.head value)))')
script=$(nix build --no-link --print-out-paths "$drv^out")
nmcli=$(cd "$root" && nix eval --raw .#nixosConfigurations.werkstatt.pkgs.networkmanager.outPath)/bin/nmcli

cat > "$temporary/nmcli" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$test_state/calls"
if [[ "$*" == 'con show OTH' && ! -e "$test_state/exists" ]]; then exit 10; fi
EOF
chmod +x "$temporary/nmcli"
export test_state="$temporary"

sed "s|$nmcli|$temporary/nmcli|g" "$script" | bash -e
grep -Fxq 'con show OTH' "$temporary/calls"
grep -Fxq 'con add type vpn vpn-type org.freedesktop.NetworkManager.fortisslvpn con-name OTH' "$temporary/calls"
grep -Eq '^con mod OTH vpn.data gateway=sslvpn\.oth-regensburg\.de:443,.*user=hoj43157$' "$temporary/calls"

rm "$temporary/calls"
touch "$temporary/exists"
sed "s|$nmcli|$temporary/nmcli|g" "$script" | bash -e
[[ $(wc -l < "$temporary/calls") == 2 ]]
! grep -q '^con add ' "$temporary/calls"
echo 'OTH VPN setup tests passed'