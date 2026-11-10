label="$(git -C ~/nixos-config log -1 --pretty=%s)"
# Mission Center's collector can trigger unavailable automounts during the switch.
sudo pkill -KILL -f '^([^[:space:]]*/)?[.]?missioncenter(-magpie)?(-wrapped)?([[:space:]]|$)' || {
	status=$?
	if [[ "$status" -ne 1 ]]; then
		echo "Could not stop Mission Center (pkill exit $status)" >&2
		exit "$status"
	fi
}
# https://search.nixos.org/options?channel=25.05&show=system.nixos.label
sudo env NIXOS_LABEL="$label" nixos-rebuild switch --flake "$HOME/nixos-config#$(hostname)"

# cleanup old nixos generations
echo "wiping old nixos generations..."
sudo nix-env --delete-generations +3 --profile /nix/var/nix/profiles/system

# Rebuild KService/KSycoca cache fully
XDG_MENU_PREFIX=plasma- kbuildsycoca6 --noincremental
