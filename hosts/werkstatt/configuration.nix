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

  home-manager.users.jonas.imports = [ ../../modules/home-manager/plasma-manager/werkstatt-power.nix ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "werkstatt";
  networking.networkmanager.enable = true;
  networking.networkmanager.ensureProfiles.profiles = {
    werkstatt-bridge = {
      connection = { id = "werkstatt-bridge"; type = "bridge"; interface-name = "br0"; autoconnect = true; autoconnect-ports = 1; };
      bridge.stp = false;
      ipv4 = {
        method = "manual";
        address1 = "${hostIPv4},10.0.1.1";
        dns = "10.0.1.1;";
        may-fail = false;
        # Prefer the directly connected LAN over the identical Tailscale subnet route.
        routing-rule1 = "priority 5000 to 10.0.0.0/16 table 254";
      };
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
    before = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" "network-online.target" ];
    path = [ pkgs.networkmanager pkgs.coreutils pkgs.iproute2 ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; TimeoutStartSec = 150; };
    script = ''
      if [[ "$(nmcli -g GENERAL.CONNECTION device show br0 2>/dev/null)" != "werkstatt-bridge" ]]; then
        nmcli --wait 60 connection up id werkstatt-bridge
      fi
      if [[ "$(nmcli -g GENERAL.CONNECTION device show ${lib.escapeShellArg lanInterface})" != "werkstatt-bridge-port" ]] ||
         [[ "$(readlink -f /sys/class/net/${lanInterface}/master)" != "/sys/devices/virtual/net/br0" ]]; then
        nmcli --wait 60 connection up id werkstatt-bridge-port ifname ${lib.escapeShellArg lanInterface}
      fi
      for attempt in {1..60}; do
        if [[ "$(nmcli -g GENERAL.STATE device show br0)" == 100* ]] &&
           [[ "$(nmcli -g GENERAL.CONNECTION device show ${lib.escapeShellArg lanInterface})" == "werkstatt-bridge-port" ]] &&
           [[ "$(readlink -f /sys/class/net/${lanInterface}/master)" == "/sys/devices/virtual/net/br0" ]]; then
          break
        fi
        sleep 1
      done
      [[ "$(nmcli -g GENERAL.STATE device show br0)" == 100* ]]
      if ! nmcli -g IP4.ADDRESS device show br0 | grep -Fxq ${lib.escapeShellArg hostIPv4} ||
         ! ip -4 rule show | grep -Eq '^5000:[[:space:]]+from all to 10[.]0[.]0[.]0/16 lookup (main|254)([[:space:]]|$)'; then
        nmcli --wait 60 device reapply br0
      fi
      [[ "$(nmcli -g GENERAL.CONNECTION device show ${lib.escapeShellArg lanInterface})" == "werkstatt-bridge-port" ]]
      [[ "$(readlink -f /sys/class/net/${lanInterface}/master)" == "/sys/devices/virtual/net/br0" ]]
      nmcli -g IP4.ADDRESS device show br0 | grep -Fxq ${lib.escapeShellArg hostIPv4}
      ip -4 rule show | grep -Eq '^5000:[[:space:]]+from all to 10[.]0[.]0[.]0/16 lookup (main|254)([[:space:]]|$)'
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