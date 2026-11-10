#!/usr/bin/env bash
set -euo pipefail

case "${0##*/}" in
  nmcli)
    case "$*" in
      '-g GENERAL.CONNECTION device show enp1s0')
        if [[ -e "$test_state/connected" ]]; then echo werkstatt-bridge-port; else echo 'Wired connection 2'; fi
        ;;
      '--wait 60 connection up id werkstatt-bridge-port ifname enp1s0')
        echo activated >> "$test_state/activations"
        [[ ! -e "$test_state/activation-fails" ]] || exit 1
        [[ -e "$test_state/port-fails" ]] || touch "$test_state/connected"
        ;;
      '--wait 60 connection up id werkstatt-bridge')
        [[ ! -e "$test_state/activation-fails" ]] || exit 1
        ;;
      '--wait 60 device reapply br0')
        echo reapplied >> "$test_state/reapplications"
        [[ ! -e "$test_state/reapply-fails" ]] || exit 1
        [[ -e "$test_state/no-address" ]] || touch "$test_state/static-address"
        ;;
      '-g IP4.ADDRESS device show br0')
        if [[ -e "$test_state/static-address" ]]; then echo '10.0.2.135/16'; elif [[ ! -e "$test_state/no-address" ]]; then echo '10.0.1.78/16'; fi
        ;;
      *) echo "Unexpected nmcli command: $*" >&2; exit 1 ;;
    esac
    exit
    ;;
  readlink)
    [[ "$*" == '-f /sys/class/net/enp1s0/master' ]] || exit 1
    [[ ! -e "$test_state/connected" ]] || echo /sys/devices/virtual/net/br0
    exit
    ;;
esac

root=$(cd "$(dirname "$0")/../../.." && pwd)
temporary=$(mktemp -d)
trap 'rm -rf -- "$temporary"' EXIT
mkdir "$temporary/bin" "$temporary/state"
ln -s "$root/hosts/werkstatt/tests/home-assistant-bridge.sh" "$temporary/bin/nmcli"
ln -s "$root/hosts/werkstatt/tests/home-assistant-bridge.sh" "$temporary/bin/readlink"
export test_state="$temporary/state"
export PATH="$temporary/bin:$PATH"
script=$(cd "$root" && nix eval --raw .#nixosConfigurations.werkstatt.config.systemd.services.werkstatt-lan-bridge.script)

bash -e -c "$script"
[[ $(wc -l < "$test_state/activations") == 1 ]]
[[ $(wc -l < "$test_state/reapplications") == 1 ]]
bash -e -c "$script"
[[ $(wc -l < "$test_state/activations") == 1 ]]
[[ $(wc -l < "$test_state/reapplications") == 1 ]]

rm "$test_state/connected"
touch "$test_state/activation-fails"
if bash -e -c "$script"; then echo 'Activation failure was accepted' >&2; exit 1; fi
rm "$test_state/activation-fails"
touch "$test_state/port-fails"
if bash -e -c "$script"; then echo 'Missing bridge port was accepted' >&2; exit 1; fi
rm "$test_state/port-fails"
rm "$test_state/static-address"
touch "$test_state/reapply-fails"
if bash -e -c "$script"; then echo 'Reapply failure was accepted' >&2; exit 1; fi
rm "$test_state/reapply-fails"
touch "$test_state/connected" "$test_state/no-address"
if bash -e -c "$script"; then echo 'Missing IPv4 address was accepted' >&2; exit 1; fi

echo 'Home Assistant bridge activation tests passed'