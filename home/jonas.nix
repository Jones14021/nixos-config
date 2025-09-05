{ config, pkgs, ... }:

{
  # match system.stateVersion, but keep and upgrade independently
  # same considerations as for system.stateVersion
  home.stateVersion = "25.05";
  home.packages = with pkgs; [
    kdePackages.kate
    # Add any personal packages or scripts you want just for jonas here
  ];

  imports = [
    ../modules/onedrive.nix
    # Import other personal Home Manager modules here if needed
  ];
}
