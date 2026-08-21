#!/usr/bin/env bash
# Release-channel upgrade reference
#
# Use this when changing NixOS from one stable release channel to the next,
# for example nixos-26.05 to nixos-26.11. It intentionally performs no action.
# Read the release notes before running any of the commands below:
#   https://nixos.org/manual/nixos/stable/release-notes.html
#   https://nix-community.github.io/home-manager/release-notes.html

# 1. In flake.nix, change both matching stable inputs:
#      nixpkgs.url = "github:NixOS/nixpkgs/nixos-<release>";
#      home-manager.url = "github:nix-community/home-manager/release-<release>";
#    Keep nixpkgs-unstable on nixpkgs-unstable unless it needs separate attention.

# 2. Review the release notes for incompatible options and data migrations.
#    Do not increase system.stateVersion or home.stateVersion merely because the
#    channel changes. Those values preserve historical defaults for each host.

# 3. Lock the new stable revisions without updating unrelated flake inputs.
nix flake update nixpkgs home-manager --commit-lock-file

# 4. Check the resulting diff and evaluate the target host before activation.
# git diff --check
nixos-rebuild dry-build --flake "$HOME/nixos-config#$(hostname)"

# 5. Use `boot` and reboot when the release notes describe a switch inhibitor
#    or a change that cannot safely happen in a live session. For example,
#    NixOS 26.05 changes the default D-Bus implementation, so `switch` is
#    deliberately refused and this sequence is required:
sudo nixos-rebuild boot --flake "$HOME/nixos-config#$(hostname)"
sudo reboot

# Otherwise, activate normally with ./baunix.sh after the dry build succeeds.
