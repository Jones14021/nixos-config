# To debug, use
#   systemctl status tailscale-config-set.service
#   journalctl -u tailscale-config-set.service
#
#   tailscale dns status
#
#   When using '--accept-dns=true', make sure to set a global nameserver
#   in the Tailscale admin console, otherwise public DNS resolution will fail.
#
# https://login.tailscale.com/admin

{ pkgs, ... }:

let
  tailscalePath = "${pkgs.tailscale}/bin/tailscale";
  operatorUser = "jonas";  # tailscale supports only one operator
in
{
  services.tailscale.enable = true;

  systemd.services.tailscale-config-set = {
    description = "Set Tailscale config once";
    after = [ "network.target" "tailscaled.service" ];
    requires = [ "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.stdenv.shell} -c '${tailscalePath} set --operator=${operatorUser} && ${tailscalePath} set --accept-routes=true --accept-dns=true'";
      RemainAfterExit = true;
      # Optional but recommended: retry a few times if the daemon is slow to open its socket
      Restart = "on-failure";
      RestartSec = "2s";
    };
  };
}
