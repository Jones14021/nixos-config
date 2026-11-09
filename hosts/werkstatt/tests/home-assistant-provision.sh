#!/usr/bin/env bash
set -euo pipefail

script=$(cd "$(dirname "$0")/.." && pwd)/home-assistant-provision.sh
temporary=$(mktemp -d)
trap 'rm -rf -- "$temporary"' EXIT
mkdir "$temporary/bin"

qemu-img create -f qcow2 "$temporary/source.qcow2" 32M > /dev/null
xz --stdout -- "$temporary/source.qcow2" > "$temporary/image.qcow2.xz"
digest=$(sha256sum "$temporary/image.qcow2.xz" | cut -d ' ' -f 1)
jq -n --arg digest "sha256:$digest" '[
  {draft:false, prerelease:false, assets:[]},
  {draft:false, prerelease:false, assets:[{
    name:"haos_ova-18.4.qcow2.xz", digest:$digest,
    browser_download_url:"https://github.com/home-assistant/operating-system/releases/download/18.4/haos_ova-18.4.qcow2.xz"
  }]}
]' > "$temporary/releases.json"

cat > "$temporary/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
output=
url=
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) output=$2; shift 2 ;;
    https://*) url=$1; shift ;;
    --retry|--connect-timeout|--proto|--proto-redir) shift 2 ;;
    *) shift ;;
  esac
done
if [[ "$url" == https://api.github.com/* ]]; then
  cp "$TEST_RELEASES" "$output"
elif [[ "$url" == https://github.com/* ]]; then
  if [[ ${TEST_RACE:-0} == 1 ]]; then
    printf 'concurrent disk' > "$TEST_DISK"
  fi
  cp "$TEST_IMAGE" "$output"
else
  exit 1
fi
EOF
printf '#!/usr/bin/env bash\nexit 0\n' > "$temporary/bin/chown"
chmod +x "$temporary/bin/curl" "$temporary/bin/chown"
export PATH="$temporary/bin:$PATH"
export TEST_RELEASES="$temporary/releases.json"
export TEST_IMAGE="$temporary/image.qcow2.xz"

printf 'existing disk' > "$temporary/existing.qcow2"
bash "$script" "$temporary/existing.qcow2"
[[ $(cat "$temporary/existing.qcow2") == 'existing disk' ]]

bash "$script" "$temporary/new.qcow2"
qemu-img info --output=json "$temporary/new.qcow2" | jq -e '.format == "qcow2"' > /dev/null
bash "$script" "$temporary/new.qcow2"

jq '.[1].assets[0].digest = "sha256:0000000000000000000000000000000000000000000000000000000000000000"' \
  "$temporary/releases.json" > "$temporary/bad-releases.json"
if TEST_RELEASES="$temporary/bad-releases.json" bash "$script" "$temporary/bad.qcow2"; then
  echo 'Checksum failure was not rejected' >&2
  exit 1
fi
[[ ! -e "$temporary/bad.qcow2" ]]

export TEST_DISK="$temporary/race.qcow2"
if TEST_RACE=1 bash "$script" "$TEST_DISK"; then
  echo 'A concurrent disk was overwritten' >&2
  exit 1
fi
[[ $(cat "$TEST_DISK") == 'concurrent disk' ]]

if compgen -G "$temporary/.haos-provision.*" > /dev/null; then
  echo 'Temporary provisioning files were left behind' >&2
  exit 1
fi
echo 'Home Assistant disk provisioning tests passed'