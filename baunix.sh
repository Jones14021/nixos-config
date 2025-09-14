label="$(git -C ~/nixos-config log -1 --pretty=%s)"
# https://search.nixos.org/options?channel=25.05&show=system.nixos.label
sudo env NIXOS_LABEL="$label" nixos-rebuild switch --flake "$HOME/nixos-config#$(hostname)"

# Rebuild KService/KSycoca cache fully
kbuildsycoca6 --noincremental
