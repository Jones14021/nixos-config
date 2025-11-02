{ config, pkgs, lib, ... }:

{
  imports = [
    ../../modules/common-packages.nix
    ../../modules/linux-kernel.nix
    ../../modules/printing.nix
    ../../modules/scanning.nix
    # host/role specific modules here    
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "nixoldie";
  time.timeZone = "Europe/Berlin";

  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "de_DE.UTF-8";
    LC_IDENTIFICATION = "de_DE.UTF-8";
    LC_MEASUREMENT = "de_DE.UTF-8";
    LC_MONETARY = "de_DE.UTF-8";
    LC_NAME = "de_DE.UTF-8";
    LC_NUMERIC = "de_DE.UTF-8";
    LC_PAPER = "de_DE.UTF-8";
    LC_TELEPHONE = "de_DE.UTF-8";
    LC_TIME = "de_DE.UTF-8";
  };

  users.users.jonas = {
    isNormalUser = true;
    description = "Jonas Hoermann";
    # To grant your user access to the scanner, add the user to the 'scanner' group or the 'lp' group if your device is also a printer
    extraGroups = [ "networkmanager" "wheel" "fuse" "dialout" "wireshark" "scanner" "lp" "docker"];
  };

  environment.systemPackages = with pkgs; [
    # host specific packages here

    # Host-specific packages: Add or override systemPackages inside the host config
    # as needed. Nix modules will merge (but not de-duplicate!) all package lists.
  ];

  nix.settings.experimental-features = [ "flakes" "nix-command" ];

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05";


  ######### Nvidia stuff #########

  nixpkgs.config.nvidia.acceptLicense = true;
  
  # Enable OpenGL
  hardware.graphics = {
    enable = true;
  };

  # Load nvidia driver for Xorg and Wayland
  services.xserver.videoDrivers = ["nvidia"];

  hardware.nvidia = {

    # Modesetting is required.
    modesetting.enable = true;

    # Nvidia power management. Experimental, and can cause sleep/suspend to fail.
    # Enable this if you have graphical corruption issues or application crashes after waking
    # up from sleep. This fixes it by saving the entire VRAM memory to /tmp/ instead 
    # of just the bare essentials.
    powerManagement.enable = false;

    # Fine-grained power management. Turns off GPU when not in use.
    # Experimental and only works on modern Nvidia GPUs (Turing or newer).
    powerManagement.finegrained = false;

    # Use the NVidia open source kernel module (not to be confused with the
    # independent third-party "nouveau" open source driver).
    # Support is limited to the Turing and later architectures. Full list of 
    # supported GPUs is at: 
    # https://github.com/NVIDIA/open-gpu-kernel-modules#compatible-gpus 
    # Only available from driver 515.43.04+
    open = false;

    # Enable the Nvidia settings menu,
	  # accessible via `nvidia-settings`.
    nvidiaSettings = true;

    # Optionally, you may need to select the appropriate driver version for your specific GPU.
    # GTX 650 Ti --> legacy 470 driver https://www.nvidia.com/en-us/drivers/unix/legacy-gpu/
    package = config.boot.kernelPackages.nvidiaPackages.legacy_470;
  };
}
