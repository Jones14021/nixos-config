
#!/usr/bin/env bash

# ----------------------------------------------------------------------------
# Custom App: WireGuard Secret Extractor
# Parses a directory of .conf files, moves the private keys out of the Nix 
# store into /var/lib/wireguard/keys, and generates the Nix code block.
# ----------------------------------------------------------------------------

if [ -z "$1" ]; then
  echo "Usage: sudo wireguard-extract-secrets <directory_with_conf_files>"
  exit 1
fi

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root to set correct permissions on the key files."
  exit 1
fi

DIR="$1"
OUT_DIR="/var/lib/wireguard/keys"

mkdir -p "$OUT_DIR"
chmod 700 "$OUT_DIR"

echo "🔐 Extracting keys to $OUT_DIR..."
echo "✂️  Paste the following into your 'vpns' list in Nix:"
echo "----------------------------------------------------------------------"

for conf in "$DIR"/*.conf; do
  [ -e "$conf" ] || continue
  
  name=$(basename "$conf" .conf)

  # 1. Strip hyphens/underscores and remove "Windscribe" (case-insensitive)
  # Piping through 'xargs' cleanly removes any duplicate, leading, or trailing spaces left behind
  temp_name=$(echo "$name" | sed -e 's/[-_]/ /g' -e 's/[Ww][Ii][Nn][Dd][Ss][Cc][Rr][Ii][Bb][Ee]//g' | xargs)
  
  # 2. Rebuild the name word-by-word, respecting the 15-character limit
  iface_name=""
  for word in $temp_name; do
    if [ -z "$iface_name" ]; then
      # First word: hard truncate to 15 chars if it is exceptionally long
      iface_name="${word:0:15}" 
    else
      # Only append the next word if it fits within 15 chars (including the hyphen)
      if [ $((${#iface_name} + ${#word} + 1)) -le 15 ]; then
        iface_name="${iface_name}-${word}"
      else
        # Adding this word would exceed 15 chars, so we stop here
        break 
      fi
    fi
  done
  
  # 3. Final safety cleanup (removes any stray invalid characters)
  iface_name=$(echo "$iface_name" | tr -cd 'a-zA-Z0-9-')
  
  # Fallback just in case the filename was literally just "Windscribe.conf"
  if [ -z "$iface_name" ]; then
    iface_name="wg-${RANDOM:0:5}"
  fi

   # Extract values (using -f2- to preserve Base64 '=' padding at the end)
  privkey=$(grep -i '^PrivateKey' "$conf" | cut -d'=' -f2- | tr -d ' \r')
  psk=$(grep -i '^PresharedKey' "$conf" | cut -d'=' -f2- | tr -d ' \r')
  address=$(grep -i '^Address' "$conf" | cut -d'=' -f2- | tr -d ' \r')
  dns=$(grep -i '^DNS' "$conf" | cut -d'=' -f2- | tr -d ' \r')
  pubkey=$(grep -i '^PublicKey' "$conf" | cut -d'=' -f2- | tr -d ' \r')
  endpoint=$(grep -i '^Endpoint' "$conf" | cut -d'=' -f2- | tr -d ' \r')
  raw_allowed=$(grep -i '^AllowedIPs' "$conf" | cut -d'=' -f2- | tr -d ' \r')
  
  # Format AllowedIPs for Nix array (e.g., "0.0.0.0/0, ::/0" -> "[ "0.0.0.0/0" "::/0" ]")
  allowed_nix="[ "
  IFS=',' read -ra ADDR <<< "$raw_allowed"
  for i in "${ADDR[@]}"; do
      allowed_nix+="\"$i\" "
  done
  allowed_nix+="]"
  
  keyfile="$OUT_DIR/$name.key"
  echo "$privkey" > "$keyfile"
  chmod 400 "$keyfile"

  # Initialize the psk_nix string as empty
  psk_nix=""
  
  # If a PresharedKey exists, write it to a file and prepare the Nix string
  if [ -n "$psk" ]; then
    pskfile="$OUT_DIR/$name.psk"
    echo "$psk" > "$pskfile"
    chmod 400 "$pskfile"
    psk_nix="presharedKeyFile = \"$pskfile\";"
  fi
  
  cat <<EOF
{
  name = "$iface_name";
  description = "$name";
  address = [ "$address" ];
  dns = [ "$dns" ];
  privateKeyFile = "$keyfile";
  $psk_nix
  publicKey = "$pubkey";
  endpoint = "$endpoint";
  allowedIPs = $allowed_nix;
  killswitch = true;
}
EOF
done
echo "----------------------------------------------------------------------"
