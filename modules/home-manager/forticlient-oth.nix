{ config, pkgs, ... }:

let
  nmcli = "${pkgs.networkmanager}/bin/nmcli";
  user = "hoj43157";
  gateway = "sslvpn.oth-regensburg.de:443";
  trustedCert = "2d275478298edc3577bd3ca1e22a898b916e149d677aea8f507758424fa47603";
in {
  # Make sure NetworkManager and the FortiSSLVPN plugin are installed
  home.packages = with pkgs; [
    networkmanager
    networkmanager-fortisslvpn
  ];

  systemd.user.services."setup-oth-vpn" = {
    Unit = {
      Description = "One-shot: create OTH FortiSSLVPN connection in NetworkManager";
      After = [ "network.target" "NetworkManager.service" ];
    };

    Service = {
      Type = "oneshot";
      Environment = "PATH=${pkgs.lib.makeBinPath [ pkgs.networkmanager ]}";

      # First delete any existing connection named OTH (ignore failure),
      # then create it, then configure the VPN parameters.
      ExecStart = "${pkgs.writeShellScript "setup-oth-vpn-script" ''
        NMCLI=\"${pkgs.networkmanager}/bin/nmcli\"

        # Check if the connection exists (sends output to null)
        if ! $NMCLI con show \"OTH\" >/dev/null 2>&1; then
          # If it doesn't exist, create it
          $NMCLI con add type vpn vpn-type org.freedesktop.NetworkManager.fortisslvpn con-name \"OTH\"
        fi

        # Always update the configuration in case gateway, cert, or user changes.
        # This will NOT overwrite an existing stored password (vpn.secrets).
        $NMCLI con mod \"OTH\" vpn.data \"gateway=${gateway},otp-flags=0,password-flags=1,realm=vpn-default,trusted-cert=${trustedCert},user=${user}\"
      ''}";

      # NOTE:
      # - To set the VPN password permanently, run:
      #     nmcli con mod OTH vpn.secrets "password=YOUR_STRONG_PASSWORD"
      #
      # - This service intentionally does NOT bring the VPN up.
      #   You must activate it manually, either via the NetworkManager UI
      #   or with:
      #     nmcli con up OTH
      #
      # - If you ever want to recreate the connection, just re-run:
      #     systemctl --user start setup-oth-vpn.service
    };

    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
