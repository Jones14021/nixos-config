{ pkgs, unstablePkgs, nixosConfEditor, self, ... }:
{
  imports = [
    ./nix-software-center.nix
    ./kde-plasma-6.nix
    ./tailscale.nix
    ./mobilesheets-companion.nix
    ./snapmaker-luban.nix
    ./nethogs-rootless.nix
  ];

  environment.systemPackages = with pkgs; [
    # essentials
    vim
    nano
    git
    python314
    python312
    unstablePkgs.uv
    rclone
    fuse
    wget
    gparted
    usbutils
    bash
    git-lfs
    wireshark
    nethogs
    
    # 3rd party
    google-chrome
    snapmaker-luban
    cura-appimage
    vscode
    tailscale
    trayscale
    unstablePkgs.mission-center
    usbview
    iperf
    onlyoffice-desktopeditors
    pdfarranger
    pdftricks
    foliate
    calibre
    pinta
    audacity
    simple-scan
    textsnatcher # OCR
    planify

    # android stuff
    android-tools
    scrcpy

    # Windows apps
    self.packages.${pkgs.system}.fusion360

    # flatpak related stuff
    warehouse

    # ease of life with nix os
    nix-software-center
    nixosConfEditor.packages.${pkgs.system}.nixos-conf-editor

    # KDE stuff
    kdePackages.ksshaskpass
    kdePackages.kconfig # for kwriteconfig6

    # If needed: (imported flake input/flaked package here, see below)
  ];

  # enable installed services and programs  
  networking.networkmanager.enable = true;
  programs.firefox.enable = true;
  programs.wireshark.enable = true;
  programs.wireshark.usbmon.enable = true;
  programs.wireshark.dumpcap.enable = true;

  # Audio & multimedia
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  nixpkgs.config.allowUnfree = true;

  environment.variables = {
    SUDO_ASKPASS = "${pkgs.kdePackages.ksshaskpass}/bin/ksshaskpass";
  };
}
