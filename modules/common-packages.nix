{ pkgs, unstablePkgs, nixosConfEditor, self, ... }:
{
  imports = [
    ./kde-plasma-6.nix
    ./tailscale.nix
    ./mobilesheets-companion.nix
    ./snapmaker-luban.nix
    ./nethogs-rootless.nix
    ./virtualisation.nix
    ./wireguard.nix
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
    appimage-run # for running AppImages with access to necessary dynamically linked libs https://nixos.wiki/wiki/AppImage
    vulkan-loader # for Vulkan support, needed for e.g. Upscaler
    vulkan-tools
    gvfs  # gio binary + SMB backend
    cifs-utils
    samba
    tree
    wireguard-tools # 'wg' command
    
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
    circup
    picocom
    thonny
    nrfconnect

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
    pdfgrep
    foliate
    calibre
    pinta
    audacity
    simple-scan
    planify
    freerdp
    baobab # Gnome disk usage viewer
    turnon # WoL utility
    gnome-logs
    tor-browser
    unrar # unfree
    handbrake
    snapshot # GNOME camera app
    spotify
    openfortivpn
    ppp # for openfortivpn
    pandoc
    zotero
    haruna # video player
    freecad

    # android stuff
    android-tools
    scrcpy

    # Windows apps
    self.packages.${pkgs.stdenv.hostPlatform.system}.fusion360
    p3x-onenote
    unstablePkgs.winboat

    # flatpak related stuff
    warehouse

    # KDE stuff
    kdePackages.ksshaskpass
    kdePackages.kconfig # for kwriteconfig6
    kdePackages.plasma-sdk # for plasmoidviewer

    # If needed: (imported flake input/flaked package here, see below)
    # e.g. nixosConfEditor.packages.${pkgs.stdenv.hostPlatform.system}.nixos-conf-editor
    self.packages.${pkgs.stdenv.hostPlatform.system}.png2svg
    self.packages.${pkgs.stdenv.hostPlatform.system}.text2img
    self.packages.${pkgs.stdenv.hostPlatform.system}.upscaler
    self.packages.${pkgs.stdenv.hostPlatform.system}.bms-tools
    self.packages.${pkgs.stdenv.hostPlatform.system}.md2pdf
    self.packages.${pkgs.stdenv.hostPlatform.system}.dns-leak-test
    self.packages.${pkgs.stdenv.hostPlatform.system}.wireguard-extract-secrets
    self.packages.${pkgs.stdenv.hostPlatform.system}.vpn-tray
    self.packages.${pkgs.stdenv.hostPlatform.system}.latex-vscode
    self.packages.${pkgs.stdenv.hostPlatform.system}.sm2uploader
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
      "flathub:app/com.thincast.client//1.1.687" # as a Windows-like RDP client
    ];
  };
  # see also imported module modules/mobilesheets-companion.nix

  # common hardware support
  hardware.graphics = { # for GPU support (MESA stack, OpenGL, Vulkan, etc.), needed for e.g. Upscaler
    enable = true;
    enable32Bit = true;  # for 32‑bit stuff (Wine etc.)
  };

  # enable installed services and programs  
  networking.networkmanager = {
    enable = true;
    plugins = with pkgs; [
      networkmanager-fortisslvpn
    ];
  };
  programs.firefox.enable = true;
  programs.wireshark.enable = true;
  programs.wireshark.usbmon.enable = true;
  programs.wireshark.dumpcap.enable = true;
  virtualisation.docker.enable = true; # additional config in modules/virtualisation.nix
  services.gvfs.enable = true;

  # disable PackageKit to prevent it from interfering with manual package management (e.g. via nix-env or home-manager)
  #and to avoid unnecessary background processes
  services.packagekit.enable = false;

  # Audio & multimedia
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  services.udev.packages = with pkgs; [
    nrf-udev
    segger-jlink
  ];

  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.segger-jlink.acceptLicense = true; # for embedded development

  nixpkgs.config.permittedInsecurePackages = [
    "python3.12-ecdsa-0.19.1"  # for embedded development (nrfutil I think)
    "snapmaker-luban-4.15.0"
    "segger-jlink-qt4-874"
  ];

  # https://nixos.wiki/wiki/Fonts
  fonts.packages = with pkgs; [
    google-fonts
  ];

  environment.variables = {
    SUDO_ASKPASS = "${pkgs.kdePackages.ksshaskpass}/bin/ksshaskpass";
  };
}
