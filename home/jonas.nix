{ config, pkgs, lib, ... }:

{
  # match system.stateVersion, but keep and upgrade independently
  # same considerations as for system.stateVersion
  home.stateVersion = "25.05";
  home.packages = with pkgs; [
    # Add any personal packages or scripts you want just for the user here
  ];

  imports = [
    # Import other personal Home Manager modules here if needed
    #../modules/onedrive.nix    
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
    };
  };
}
