#!/usr/bin/env bash
set -euo pipefail

domain=${1:?Expected the generated libvirt domain XML}
temporary=$(mktemp -d)
trap 'rm -rf -- "$temporary"' EXIT

uuid=01944b71-9a7e-4e16-bd59-096cc0ec3428
mac=52:54:00:12:34:56
[[ $(xmlstarlet sel -t -v 'count(/domain/devices/interface[1]/mac)' "$domain") == 0 ]]

xmlstarlet ed \
  -a '/domain/name' -t elem -n uuid -v "$uuid" \
  -s '/domain/devices/interface[1]' -t elem -n mac -v '' \
  -s '/domain/devices/interface[1]/mac' -t attr -n address -v "$mac" \
  "$domain" > "$temporary/updated.xml"

[[ $(xmlstarlet sel -t -v 'string(/domain/uuid)' "$temporary/updated.xml") == "$uuid" ]]
[[ $(xmlstarlet sel -t -v 'string(/domain/devices/interface[1]/mac/@address)' "$temporary/updated.xml") == "$mac" ]]
virt-xml-validate "$temporary/updated.xml"
echo 'Home Assistant VM identity preservation test passed'