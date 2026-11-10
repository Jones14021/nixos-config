{ lib, pkgs, ... }:

let
  lanInterface = "enp1s0";
  hostIPv4 = "10.0.2.135/16";
in
{
  imports = [
    ../../modules/common-packages.nix
    ../../modules/linux-kernel.nix
    ../../modules/printing.nix
    ../../modules/scanning.nix
    ../../modules/bluetooth.nix
    ./services.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "werkstatt";
  networking.networkmanager.enable = true;
  networking.networkmanager.ensureProfiles.profiles = {
    werkstatt-bridge = {
      connection = { id = "werkstatt-bridge"; type = "bridge"; interface-name = "br0"; autoconnect = true; autoconnect-ports = 1; };
      bridge.stp = false;
      ipv4 = { method = "manual"; address1 = "${hostIPv4},10.0.1.1"; dns = "10.0.1.1;"; may-fail = false; };
      ipv6.method = "auto";
    };
    werkstatt-bridge-port = {
      connection = { id = "werkstatt-bridge-port"; type = "ethernet"; interface-name = lanInterface; master = "br0"; slave-type = "bridge"; autoconnect = true; };
      ethernet = { };
    };
  };

  systemd.services.werkstatt-lan-bridge = {
    description = "Activate the Werkstatt LAN bridge";
    requires = [ "NetworkManager.service" "NetworkManager-ensure-profiles.service" ];
    after = [ "NetworkManager.service" "NetworkManager-ensure-profiles.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.networkmanager pkgs.coreutils ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; TimeoutStartSec = 150; };
    script = ''
      if [[ "$(nmcli -g GENERAL.CONNECTION device show ${lib.escapeShellArg lanInterface})" != "werkstatt-bridge-port" ]] ||
         [[ "$(readlink -f /sys/class/net/${lanInterface}/master)" != "/sys/devices/virtual/net/br0" ]]; then
        nmcli --wait 60 connection up id werkstatt-bridge-port ifname ${lib.escapeShellArg lanInterface}
      fi
      if [[ -z "$(nmcli -g IP4.ADDRESS device show br0)" ]]; then
        nmcli --wait 60 connection up id werkstatt-bridge
      fi
      if ! nmcli -g IP4.ADDRESS device show br0 | grep -Fxq ${lib.escapeShellArg hostIPv4}; then
        nmcli --wait 60 device reapply br0
      fi
      [[ "$(nmcli -g GENERAL.CONNECTION device show ${lib.escapeShellArg lanInterface})" == "werkstatt-bridge-port" ]]
      [[ "$(readlink -f /sys/class/net/${lanInterface}/master)" == "/sys/devices/virtual/net/br0" ]]
      nmcli -g IP4.ADDRESS device show br0 | grep -Fxq ${lib.escapeShellArg hostIPv4}
    '';
  };

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
    extraGroups = [ "networkmanager" "wheel" "fuse" "dialout" "wireshark" "scanner" "lp" "docker" "plugdev" "libvirtd" ];
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  system.stateVersion = "26.05";
}