{ pkgs, nixosConfEditor, ... }:
{
  imports = [
    ./nix-software-center.nix
  ];

  environment.systemPackages = with pkgs; [
    # essentials
    vim
    nano
    git
    python314
    rclone
    fuse
    wget
    
    # 3rd party
    google-chrome
    snapmaker-luban
    cura-appimage
    vscode
    tailscale
    trayscale

    # ease of life with nix os
    nix-software-center
    nixosConfEditor.packages.${pkgs.system}.nixos-conf-editor

    # KDE stuff
    kdePackages.ksshaskpass

    # If needed: (imported flake input/flaked package here, see below)
  ];

  nixpkgs.config.allowUnfree = true;

  nixpkgs.config.permittedInsecurePackages = [
    "snapmaker-luban-4.15.0"
  ];

  environment.variables = {
    SUDO_ASKPASS = "${pkgs.kdePackages.ksshaskpass}/bin/ksshaskpass";
  };
}
