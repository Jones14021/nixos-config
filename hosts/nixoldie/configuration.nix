{ config, pkgs, lib, ... }:

{
  imports = [
    ../../modules/common-packages.nix
    ../../modules/linux-kernel.nix
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
    extraGroups = [ "networkmanager" "wheel" "fuse" ];
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
}
