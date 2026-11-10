#!/usr/bin/env bash
set -euo pipefail

disk=${1:?Expected the destination disk path}

if [[ -e "$disk" || -L "$disk" ]]; then
  if [[ ! -f "$disk" || ! -s "$disk" ]]; then
    echo "Existing Home Assistant disk is not a nonempty regular file: $disk" >&2
    exit 1
  fi
  echo "Using existing Home Assistant disk: $disk"
  exit 0
fi

directory=$(dirname -- "$disk")
temporary=$(mktemp -d -- "$directory/.haos-provision.XXXXXXXX")
trap 'rm -rf -- "$temporary"' EXIT

curl --fail --silent --show-error --location --retry 3 --connect-timeout 20 \
  --proto '=https' --proto-redir '=https' \
  'https://api.github.com/repos/home-assistant/operating-system/releases?per_page=30' \
  --output "$temporary/releases.json"

asset=$(jq -ce '
  [.[] | select(.draft == false and .prerelease == false) | .assets[]
   | select(.name | test("^haos_ova-[0-9.]+\\.qcow2\\.xz$"))
   | select((.digest // "") | test("^sha256:[0-9a-f]{64}$"))][0]
  // error("No stable Home Assistant OS QCOW2 image with a SHA-256 digest found")
' "$temporary/releases.json")
url=$(jq -er '.browser_download_url' <<< "$asset")
digest=$(jq -er '.digest | ltrimstr("sha256:")' <<< "$asset")

if [[ "$url" != https://github.com/home-assistant/operating-system/releases/download/* ]]; then
  echo "Unexpected Home Assistant OS download URL" >&2
  exit 1
fi

echo "Downloading $(jq -r '.name' <<< "$asset")"
curl --fail --silent --show-error --location --retry 3 --connect-timeout 20 \
  --proto '=https' --proto-redir '=https' "$url" --output "$temporary/image.qcow2.xz"
if ! printf '%s  %s\n' "$digest" "$temporary/image.qcow2.xz" | sha256sum --check --status; then
  echo "Home Assistant OS image checksum verification failed" >&2
  exit 1
fi
xz --decompress --stdout -- "$temporary/image.qcow2.xz" > "$temporary/image.qcow2"
qemu-img info --output=json -- "$temporary/image.qcow2" \
  | jq -e '.format == "qcow2" and .["backing-filename"] == null and .["virtual-size"] > 0' > /dev/null
qemu-img check -f qcow2 -- "$temporary/image.qcow2"
chown jonas:users "$temporary/image.qcow2"
chmod 0640 "$temporary/image.qcow2"

# A hard link publishes the verified image atomically and never replaces a disk
# that appeared while the download was in progress.
ln -- "$temporary/image.qcow2" "$disk"
echo "Provisioned Home Assistant OS disk: $disk"