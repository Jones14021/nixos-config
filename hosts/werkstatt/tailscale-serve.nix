# Publish werkstatt's HTTP services privately to its Tailscale tailnet.
# This module is imported only by werkstatt's services.nix. It does not enable
# Funnel and does not change the services' original LAN port bindings; Docker
# ports can still be reachable directly on the LAN or through router forwards.
#
# One-time setup: enroll the host with `sudo tailscale up`, enable MagicDNS and
# HTTPS certificates in the tailnet, and restrict access with tailnet ACLs.
# Restart werkstatt-tailscale-serve after enrollment, then inspect
# `tailscale serve status` and the unit's journal if certificates or routes fail.
# The unit retries until the node and HTTPS prerequisites are ready.
#
# The port list uses the original service ports for HTTPS on the tailnet and
# proxies each to the same port on localhost: 81 is proxy administration,
# 5000 Gitea, 6182 Firefly, 8096 Jellyfin, 9800 Guacamole, 9901 Norish and
# 19999 Netdata. Gitea SSH is not an HTTP route. Home Assistant uses its own
# Tailscale installation inside the bridged VM, so it is intentionally absent.
# Some apps require a canonical external URL or trusted-proxy settings; review
# them when choosing LAN, reverse-proxy or tailnet access.
#
# `--bg` stores routes in tailscaled's persistent state. Rebuilding reapplies
# listed routes but does not automatically remove old ones; inspect and remove
# stale routes deliberately. `tailscale serve reset` removes all Serve routes.
{ pkgs, ... }:

let
  routes = [ 81 5000 6182 8096 9800 9901 19999 ];
in
{
  systemd.services.werkstatt-tailscale-serve = {
    description = "Publish werkstatt services on the tailnet";
    after = [ "tailscaled.service" "network-online.target" ];
    requires = [ "tailscaled.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "30s";
    };
    script = builtins.concatStringsSep "\n" (map (port:
      "${pkgs.tailscale}/bin/tailscale serve --bg --yes --https=${toString port} http://127.0.0.1:${toString port}"
    ) routes);
  };
}