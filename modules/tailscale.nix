{ pkgs, ... }:

let
  tailscalePath = "${pkgs.tailscale}/bin/tailscale";
  operatorUser = "jonas";  # tailscale supports only one operator
in
{
  services.tailscale.enable = true;

  systemd.services.tailscale-config-set = {
    description = "Set Tailscale config once";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.stdenv.shell} -c '${tailscalePath} set --operator=${operatorUser} && ${tailscalePath} set --accept-routes=true'";
      RemainAfterExit = true;
    };
  };
}
