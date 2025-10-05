{ config, pkgs, lib, ... }:

{
  # match system.stateVersion, but keep and upgrade independently
  # same considerations as for system.stateVersion
  home.stateVersion = "25.05";

  imports = [
    # Import other personal Home Manager/personal modules here if needed
    ../modules/home-manager/onedrive.nix
    ../modules/home-manager/git.nix
    ../modules/home-manager/calibre-plugins.nix
  ];

  home.packages = with pkgs; [
    # Add any personal packages or scripts you want just for the user here
  ];

  # plasma-manager exposes its Home Manager integration as a NixOS/Home Manager module.
  # This module registers options under programs.plasma.*
  #
  # find examples here: https://github.com/nix-community/plasma-manager/blob/trunk/examples/home.nix
  programs.plasma = {
    enable = true; # activates and enables the plasma-manager integration in Home Manager user environment

    shortcuts = {
      # helper: Run rc2nix to generate Nix expressions off of current config:
      #   nix run github:nix-community/plasma-manager -- rc2nix ~/.config/kglobalshortcutsrc > shortcuts-generated.nix

      # open Konsole with Meta+T
      "services/org.kde.konsole.desktop" = {
        _launch = "Meta+T";
      };

      # open KDE System Settings with Meta+I
      "services/systemsettings.desktop" = {
        _launch = "Meta+I";
      };

      # open Dolphin with Meta+E
      "services/org.kde.dolphin.desktop" = {
        _launch = "Meta+E";
      };

      # open "Task Manager" :)
      "services/io.missioncenter.MissionCenter.desktop" = {
        _launch="Ctrl+Shift+Esc";
      };

      # take screenshot
      "services/org.kde.spectacle.desktop" = {
        RectangularRegionScreenShot="Meta+Shift+S";
        _launch="Print";
      };
    };
  };

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
