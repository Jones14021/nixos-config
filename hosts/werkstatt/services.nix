# Host-only services for werkstatt. configuration.nix imports this module;
# the other hosts do not. It combines native applications with separately
# managed Compose projects, a libvirt Home Assistant OS VM and tailnet routes.
#
# Application state is placed under /home/jonas/services and must be backed
# up independently of Nix. Readiness markers deliberately prevent Gitea,
# Jellyfin and Compose projects from starting before data is restored. The
# Home Assistant VM provisions a fresh disk when no existing disk is present.
# Secrets are provided manually, never as Nix values.
{ lib, pkgs, ... }:

let
  netdataDashboard = pkgs.fetchzip {
    url = "https://web.archive.org/web/20251210212517if_/https://app.netdata.cloud/agent.tar.gz";
    hash = "sha256-8ovYkvt324l6f0YT6wTG+Y2u7VaVqotAdssnNTtHIEk=";
  };
in
{
  imports = [ ./containers ./nas.nix ./home-assistant.nix ./tailscale-serve.nix ];

  # OpenSSH is for the desktop host; Gitea runs its own SSH listener on 2221.
  # Gitea and Jellyfin keep their old LAN ports. Docker's published ports are
  # separate and may bypass these firewall rules; see containers/README.md.
  services.openssh.enable = true;
  networking.firewall.allowedTCPPorts = [ 2221 5000 8096 ];

  # Migrate the Docker Gitea instance into native Gitea and SQLite. Nix writes
  # its app.ini on startup, while repositories, database, LFS and secrets stay
  # under Jonas's home. Review ROOT_URL when the final hostname is known.
  services.gitea = {
    enable = true;
    user = "jonas";
    group = "users";
    stateDir = "/home/jonas/services/gitea";
    repositoryRoot = "/home/jonas/services/gitea/repositories";
    database.path = "/home/jonas/services/gitea/data/gitea.db";
    lfs.enable = true;
    settings = {
      server = {
        HTTP_PORT = 5000;
        DOMAIN = "werkstatt";
        ROOT_URL = "http://werkstatt:5000/";
        START_SSH_SERVER = true;
        SSH_PORT = 2221;
        SSH_LISTEN_PORT = 2221;
      };
      # These registration and OpenID choices match the source, including
      # open registration. Review them before exposing Gitea beyond the LAN.
      service = {
        DISABLE_REGISTRATION = false;
        REQUIRE_SIGNIN_VIEW = false;
        REGISTER_EMAIL_CONFIRM = false;
        ENABLE_NOTIFY_MAIL = false;
        ALLOW_ONLY_EXTERNAL_REGISTRATION = false;
        ENABLE_CAPTCHA = false;
        DEFAULT_KEEP_EMAIL_PRIVATE = false;
        DEFAULT_ALLOW_CREATE_ORGANIZATION = true;
        DEFAULT_ENABLE_TIMETRACKING = true;
        NO_REPLY_ADDRESS = "noreply.localhost";
      };
      openid = { ENABLE_OPENID_SIGNIN = true; ENABLE_OPENID_SIGNUP = true; };
      "cron.update_checker".ENABLED = true;
      "repository.pull-request".DEFAULT_MERGE_STYLE = "merge";
      "repository.signing".DEFAULT_TRUST_MODEL = "committer";
      migrations.ALLOW_LOCALNETWORKS = true;
    };
  };
  # Do not let a first boot initialize or upgrade an incomplete migration.
  systemd.services.gitea.unitConfig.ConditionPathExists = "/home/jonas/services/gitea/.ready";
  systemd.services.gitea.unitConfig.RequiresMountsFor = [ "/home/jonas/services/gitea" ];
  # The upstream sandbox normally hides /home; keep it read-only except for
  # Gitea's existing ReadWritePaths so its configured data remains writable.
  systemd.services.gitea.serviceConfig.ProtectHome = lib.mkForce "read-only";

  # Keep the node identity in the home tree; enrollment is performed manually.
  # The shared desktop module also configures Jonas as the Tailscale operator.
  services.tailscale = {
    enable = true;
    extraDaemonFlags = [ "--state=/home/jonas/services/tailscale/tailscaled.state" ];
  };
  systemd.services.tailscaled.unitConfig.RequiresMountsFor = [ "/home/jonas/services/tailscale" ];

  # Native Jellyfin uses the same service account as the desktop user so it
  # can access media and its migrated state in /home/jonas without broad ACLs.
  services.jellyfin = {
    enable = true;
    user = "jonas";
    group = "users";
    dataDir = "/home/jonas/services/jellyfin/data";
    configDir = "/home/jonas/services/jellyfin/config";
    cacheDir = "/home/jonas/services/jellyfin/cache";
    logDir = "/home/jonas/services/jellyfin/log";
  };
  # Start only after the old configuration and data have been restored.
  systemd.services.jellyfin.unitConfig.ConditionPathExists = "/home/jonas/services/jellyfin/.ready";
  # The legacy library path /mnt/nas is a bind mount of the Synology workouts
  # share. Require it before startup so an offline NAS cannot look like an
  # empty local media library.
  systemd.services.jellyfin.unitConfig.RequiresMountsFor = [ "/home/jonas/services/jellyfin" "/mnt/nas" ];

  # Netdata replaces Portainer as the monitoring dashboard. Container metrics
  # come from Docker/cgroups; systemd unit collection needs an explicit job.
  # Bind only to localhost and expose it through tailnet Serve. Netdata runs
  # as Jonas, whose Docker group membership grants significant privileges.
  services.netdata = {
    enable = true;
    user = "jonas";
    group = "users";
    configDir."go.d/systemdunits.conf" = pkgs.writeText "systemdunits.conf" ''
      jobs:
        - name: services
          include:
            - '*.service'
    '';
    config = {
      directories.web = "${netdataDashboard}/agent";
      global = {
        "cache directory" = "/home/jonas/services/netdata/cache";
        "lib directory" = "/home/jonas/services/netdata/lib";
        "log directory" = "/home/jonas/services/netdata/log";
      };
      web."bind to" = "127.0.0.1";
    };
  };
  # Netdata's default ProtectHome=read-only otherwise blocks its state writes.
  systemd.services.netdata.serviceConfig.ReadWritePaths = [ "/home/jonas/services/netdata" ];
  systemd.services.netdata.unitConfig.RequiresMountsFor = [ "/home/jonas/services/netdata" ];

  # Docker's configured data root stays under home. Application data uses
  # explicit bind mounts in the Compose files rather than named volumes. Runtime
  # and libvirt system metadata can still be stored in standard system paths.
  virtualisation.docker = {
    enable = true;
    daemon.settings.data-root = "/home/jonas/services/docker";
    # Docker 29's containerd image store can use /var/lib/containerd instead
    # of data-root. Use the classic store to keep image layers under home too.
    daemon.settings.features.containerd-snapshotter = false;
  };
  systemd.services.docker.unitConfig.RequiresMountsFor = [ "/home/jonas/services/docker" ];
  # Libvirt manages the independently updated Home Assistant OS guest.
  virtualisation.libvirtd.enable = true;
  programs.virt-manager.enable = true;

  # Secret files are supplied manually and never embedded in the Nix store.
  # Other application directories are created as part of the migration.
  systemd.tmpfiles.rules = [
    "d /home/jonas/services 0755 jonas users -"
    "d /home/jonas/services/tailscale 0700 root root -"
    "d /home/jonas/services/netdata 0750 jonas users -"
    "d /home/jonas/services/netdata/cache 0750 jonas users -"
    "d /home/jonas/services/netdata/lib 0750 jonas users -"
    "d /home/jonas/services/netdata/log 0750 jonas users -"
    "d /home/jonas/services/jellyfin 0750 jonas users -"
    "d /home/jonas/services/secrets 0700 root root -"
    "d /home/jonas/services/home-assistant 0750 jonas users -"
  ];
}