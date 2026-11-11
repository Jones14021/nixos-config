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
# Serve uses separate HTTPS ports because its tailnet listeners otherwise
# conflict with services listening on all interfaces at their original ports.
# 10081 proxies 81 (proxy administration), 15000 proxies 5000 (Gitea), 16182
# proxies 6182 (Firefly), 18096 proxies 8096 (Jellyfin), 19800 proxies 9800
# (Guacamole), 19901 proxies 9901 (Norish), and 19999 proxies 19999 (Netdata).
# Gitea SSH is not an HTTP route. Home Assistant uses its own
# Tailscale installation inside the bridged VM, so it is intentionally absent.
# Some apps require a canonical external URL or trusted-proxy settings; review
# them when choosing LAN, reverse-proxy or tailnet access.
#
# `--bg` stores routes in tailscaled's persistent state. Rebuilding reapplies
# listed routes but does not automatically remove old ones; inspect and remove
# stale routes deliberately. `tailscale serve reset` removes all Serve routes.
{ pkgs, ... }:

let
  routes = [
    { serve = 10081; backend = 81; }     # Nginx Proxy Manager administration
    { serve = 15000; backend = 5000; }   # Gitea
    { serve = 16182; backend = 6182; }   # Firefly III
    { serve = 18096; backend = 8096; }   # Jellyfin
    { serve = 19800; backend = 9800; }   # Guacamole
    { serve = 19901; backend = 9901; }   # Norish
    { serve = 19999; backend = 19999; }  # Netdata
  ];
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
    script = builtins.concatStringsSep "\n" (map (route:
      "${pkgs.tailscale}/bin/tailscale serve --bg --yes --https=${toString route.serve} http://127.0.0.1:${toString route.backend}"
    ) routes);
  };

  systemd.services.werkstatt-neugier-tailscale-serve = {
    description = "Publish NEUGIER on its existing Tailscale identity";
    after = [ "werkstatt-neugier.service" ];
    requires = [ "werkstatt-neugier.service" ];
    partOf = [ "werkstatt-neugier.service" ];
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = "/home/jonas/services/neugier/.ready";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "30s";
    };
    script = ''
      ${pkgs.docker-compose}/bin/docker-compose -p werkstatt-neugier --env-file /home/jonas/services/neugier/neugier.env -f ${./containers/neugier.yaml} exec -T tailscale tailscale serve --bg --yes --https=443 http://127.0.0.1:8080
    '';
  };
}