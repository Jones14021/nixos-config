{ pkgs, unstablePkgs, nixosConfEditor, self, ... }:
{
  imports = [
    ./flatpak.nix
    ./kde-plasma-6.nix
    ./tailscale.nix
    ./snapmaker-luban.nix
    ./nethogs-rootless.nix
    ./virtualisation.nix
    ./wireguard.nix
    ./mounts.nix
    ./freecad.nix
  ];

  environment.systemPackages = with pkgs; [
    # essentials
    vim
    nano
    git
    unstablePkgs.vscode
    unstablePkgs.uv
    unstablePkgs.opencode
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
    wineWow64Packages.stable # support both 32-bit and 64-bit applications https://nixos.wiki/wiki/Wine
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
    jdk25
    p7zip
    quota

    ### AI agent tools
    bubblewrap # often a prerequisite for AI agent sandboxing
    socat # often a prerequisite for AI agent sandboxing

    # Search & Discovery
    # (e.g., tools for finding and indexing files, web search, etc.)
    ripgrep # ripgrep, for searching text in files
    ripgrep-all # ripgrep-all, for searching text in files (including PDFs, EPUBs, ...)
    fd # A simple, fast, and user-friendly alternative to find
    fzf # A general-purpose command-line fuzzy finder

    # Data Parsing & Structuring
    jq # A lightweight and flexible command-line JSON processor used to query, parse, and filter API responses and JSON configurations
    yq # A lightweight and flexible command-line YAML processor used to query, parse, and filter API responses and YAML configurations
    fq # A tool for inspecting, querying, and decoding binary and protocol formats


    # Web & API Interaction
    hurl # A command-line tool that runs HTTP requests defined in a simple plain text format, useful for agent-driven API testing and web interactions.
    defuddle # Specialized utilities used to extract clean article text or fetch heavy JavaScript web pages for agent consumption.
    obscura # Specialized utilities used to extract clean article text or fetch heavy JavaScript web pages for agent consumption.

    # Process & Environment Management
    procs # A modern replacement for ps that provides structured output (like JSON) when inspecting running system processes and resource usage.
    dust # A more intuitive disk usage analyzer that helps agents identify large directories and storage consumers.

    # Git & Source Control
    gh # The official GitHub CLI tool, allowing AI agents to interact directly with repositories, pull requests, issues, and workflows.


    # Filesystem tools for GParted
    bcachefs-tools # bcachefs
    btrfs-progs    # Btrfs
    exfatprogs     # exFAT
    e2fsprogs      # ext2 / ext3 / ext4
    f2fs-tools     # F2FS
    dosfstools     # FAT16 / FAT32
    mtools        # FAT labels and UUIDs
    hfsutils      # HFS
    hfsprogs      # HFS+
    jfsutils      # JFS
    lvm2          # LVM physical volumes
    util-linux    # Minix, Linux swap, blkid and swaplabel
    nilfs-utils   # NILFS2
    ntfs3g        # NTFS — Nixpkgs name for ntfs-3g
    udftools      # UDF
    xfsprogs      # XFS
    xfsdump       # XFS copying via xfsdump / xfsrestore

    # Encryption support in GParted
    cryptsetup    # LUKS
    
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
    tailscale
    trayscale
    unstablePkgs.mission-center
    usbview
    iperf
    onlyoffice-desktopeditors
    pdfarranger
    pdftricks
    pdfgrep
    calibre
    foliate
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
    diffpdf

    # android stuff
    android-tools
    scrcpy

    # Windows apps
    p3x-onenote
    unstablePkgs.winboat

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
    self.packages.${pkgs.stdenv.hostPlatform.system}.vidname
    self.packages.${pkgs.stdenv.hostPlatform.system}.iper3-server-isolated-macvlan
  ];

  # overlays to customize certain packages
  nixpkgs.overlays = [
    # Example overlay to customize google-chrome
    (final: prev: {
      google-chrome = prev.google-chrome.override {
        commandLineArgs = "--disable-gpu";
      };
      foliate = prev.foliate.overrideAttrs (old: {
        postFixup = (old.postFixup or "") + ''
          wrapProgram "$out/bin/foliate" --set GDK_BACKEND x11
        '';
      });
      # https://github.com/NixOS/nixpkgs/issues/499166
      python312 = prev.python312.overrideAttrs (old: {
        passthru = old.passthru // {
          doc = prev.emptyDirectory;
        };
      });
    })
  # You can add more overlays here to customize other packages
  ];

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
  services.resolved.enable = true; # DNS resolver https://wiki.nixos.org/wiki/Systemd/resolved

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
    "docker-28.5.2"
    "electron-40.10.5" # required by unstablePkgs.vscode
    "NetworkManager-fortisslvpn-gnome-1.4.0"
  ];

  # https://nixos.wiki/wiki/Fonts
  fonts.packages = with pkgs; [
    google-fonts
  ];

  environment.variables = {
    SUDO_ASKPASS = "${pkgs.kdePackages.ksshaskpass}/bin/ksshaskpass";
  };
}
