{ pkgs, unstablePkgs, nixosConfEditor, self, ... }:
{
  imports = [
    ./kde-plasma-6.nix
    ./tailscale.nix
    ./mobilesheets-companion.nix
    ./snapmaker-luban.nix
    ./nethogs-rootless.nix
    ./virtualisation.nix
  ];

  environment.systemPackages = with pkgs; [
    # essentials
    vim
    nano
    git
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
    nmap
    inetutils
    progress
    wineWowPackages.stable # support both 32-bit and 64-bit applications https://nixos.wiki/wiki/Wine
    killall
    poppler-utils
    avahi # for MDNS (SD) support (e.g. avahi-browse)
    
    # development
    nrfutil
    esptool
    espflash
    cmake
    gnumake
    file
    fileinfo
    htop
    hexdiff
    hexdump
    binutils

    # Python
    python312
    (python313.withPackages (ps: with ps; [
      pyserial
      requests
      numpy
      pandas
      matplotlib
      scipy
      pyftdi
    ]))
    
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
    freerdp
    baobab # Gnome disk usage viewer
    turnon # WoL utility
    gnome-logs
    tor-browser
    unrar # unfree
    upscaler
    handbrake
    snapshot # GNOME camera app

    # android stuff
    android-tools
    scrcpy

    # Windows apps
    self.packages.${pkgs.system}.fusion360
    p3x-onenote
    (unstablePkgs.winboat.override {nodejs_24 = pkgs.nodejs_24;}) # https://github.com/nixos/nixpkgs/issues/462513

    # flatpak related stuff
    warehouse

    # KDE stuff
    kdePackages.ksshaskpass
    kdePackages.kconfig # for kwriteconfig6
    kdePackages.plasma-sdk # for plasmoidviewer

    # If needed: (imported flake input/flaked package here, see below)
    # e.g. nixosConfEditor.packages.${pkgs.system}.nixos-conf-editor
    self.packages.${pkgs.system}.png2svg
    self.packages.${pkgs.system}.text2img
    self.packages.${pkgs.system}.google-fotos-takeout
  ];

  # overlays to customize certain packages
  nixpkgs.overlays = [
    # Example overlay to customize google-chrome
    (final: prev: {
      google-chrome = prev.google-chrome.override {
        commandLineArgs = "--disable-gpu";
      };
    })
  # You can add more overlays here to customize other packages
  ];

  # flatpaks
  # see documentation for declarative-flatpak https://github.com/in-a-dil-emma/declarative-flatpak
  services.flatpak = {
    enable = true;

    remotes = {
      "flathub" = "https://dl.flathub.org/repo/flathub.flatpakrepo";      
    };

    packages = [
      "flathub:app/com.github.tchx84.Flatseal//stable"
    ];
  };
  # see also imported module modules/mobilesheets-companion.nix

  # enable installed services and programs  
  networking.networkmanager.enable = true;
  programs.firefox.enable = true;
  programs.wireshark.enable = true;
  programs.wireshark.usbmon.enable = true;
  programs.wireshark.dumpcap.enable = true;
  virtualisation.docker.enable = true; # additional config in modules/virtualisation.nix

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
  nixpkgs.config.segger-jlink.acceptLicense = true; # for embedded development

  nixpkgs.config.permittedInsecurePackages = [
    "python3.12-ecdsa-0.19.1"  # for embedded development (nrfutil I think)
    "snapmaker-luban-4.15.0"
  ];

  # https://nixos.wiki/wiki/Fonts
  fonts.packages = with pkgs; [
    google-fonts
  ];

  environment.variables = {
    SUDO_ASKPASS = "${pkgs.kdePackages.ksshaskpass}/bin/ksshaskpass";
  };
}
