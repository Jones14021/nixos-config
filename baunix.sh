label="$(git -C ~/nixos-config log -1 --pretty=%s)"
# https://search.nixos.org/options?channel=25.05&show=system.nixos.label
sudo env NIXOS_LABEL="$label" nixos-rebuild switch --flake "$HOME/nixos-config#$(hostname)"

# cleanup old nixos generations
echo "wiping old nixos generations..."
sudo nix-env --delete-generations +3 --profile /nix/var/nix/profiles/system

# Rebuild KService/KSycoca cache fully
kbuildsycoca6 --noincremental
