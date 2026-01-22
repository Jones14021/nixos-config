{ config, pkgs, lib, ... }:

{
  # match system.stateVersion, but keep and upgrade independently
  # same considerations as for system.stateVersion
  home.stateVersion = "25.05";

  imports = [
    # Import other personal Home Manager/personal modules here if needed
    ../modules/home-manager/onedrive.nix
    ../modules/home-manager/git.nix
    ../modules/home-manager/plasma-manager/shortcuts.nix
    ../modules/home-manager/plasma-manager/widgets.nix
  ];

  home.packages = with pkgs; [
    # Add any personal packages or scripts you want just for the user here
  ];

  # plasma-manager exposes its Home Manager integration as a NixOS/Home Manager module.
  # This module registers options under programs.plasma.*
  #
  # documentation: https://github.com/nix-community/plasma-manager
  # find examples here: https://github.com/nix-community/plasma-manager/blob/trunk/examples/home.nix
  programs.plasma.enable = true; # activates and enables the plasma-manager integration in Home Manager user environment

  # fix bug where luban config dir is not writeable
  systemd.user.services.seed-luban-config = {
      Unit.Description = "Seed writable Snapmaker Luban config";
      Service = {
          Type = "oneshot";
          ExecStart = ''
          ${pkgs.bash}/bin/bash -c '\
          cfg=\"$HOME/.config/snapmaker-luban/Config\"; \
          recovercfg=\"$HOME/.config/snapmaker-luban/snapmaker-recover\"; \
          find \"$cfg\" -type d -exec chmod u+rwx {} +; \
          find \"$cfg\" -type f -exec chmod u+rw {} +; \
          find \"$recovercfg\" -type d -exec chmod u+rwx {} +; \
          find \"$recovercfg\" -type f -exec chmod u+rw {} +; \
          '
          '';
      };
      Install.WantedBy = [ "default.target" ];
  };
}
