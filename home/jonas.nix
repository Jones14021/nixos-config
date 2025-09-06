{ config, pkgs, lib, ... }:

{
  # match system.stateVersion, but keep and upgrade independently
  # same considerations as for system.stateVersion
  home.stateVersion = "25.05";
  home.packages = with pkgs; [
    # Add any personal packages or scripts you want just for jonas here
  ];

  imports = [
    #../modules/onedrive.nix
    # Import other personal Home Manager modules here if needed
  ];

  # activation scripts
  home.activation.setKdeShortcuts = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    # Set shortcut for opening Konsole with Meta+T
    kwriteconfig6 --file 'kglobalshortcutsrc' --group 'org.kde.konsole.desktop' --key '_launch' 'Meta+T'

    # Set shortcut for launching System Settings Info page with Meta+I
    kwriteconfig6 --file 'kglobalshortcutsrc' --group 'org.kde.kdecontroller.desktop' --key '_launch' 'Meta+I'
  '';

}
