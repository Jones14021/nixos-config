{ config, pkgs, lib, ... }:

{
  # plasma-manager exposes its Home Manager integration as a NixOS/Home Manager module.
  # This module registers options under programs.plasma.*
  #
  # find examples here: https://github.com/nix-community/plasma-manager/blob/trunk/examples/home.nix
  programs.plasma = {

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
}