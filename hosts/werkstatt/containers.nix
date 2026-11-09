# Werkstatt's selected Docker Compose projects. This module is imported only
# by this host's services.nix. Nix generates immutable Compose definitions;
# persistent data and manually supplied secrets remain under /home/jonas.
#
# Each long-running project is gated by <base>/<project>/.ready to prevent a
# first boot from initializing empty databases before restoration. Its systemd
# unit starts and stops the entire project; Docker restart policies cover
# individual container failures, but an active unit is not a health check.
# Bitwarden backup is a manually started one-shot, not an automatic daemon.
# See migration/README.md for required env files, backups and restoration order.
#
# Published ports retain the old LAN bindings. Docker can bypass the NixOS
# firewall, so exposure must also be controlled at the network/router level.
{ lib, pkgs, ... }:

let
  # Only paths, not secret values, are placed in generated Nix store files.
  base = "/home/jonas/services";
  # Raw env files preserve secret characters without Compose interpolation.
  secret = name: { path = "${base}/secrets/${name}.env"; format = "raw"; };
  # Digests match the inspected source images and prevent a mutable `latest`
  # tag from unexpectedly upgrading a database or app during the migration.
  # Plan explicit security upgrades after the restored stacks have been tested.
  image = name: digest: "${name}@sha256:${digest}";
  projects = {
    # Reverse proxy and certificate manager: public HTTP/HTTPS and admin UI.
    # Restore both directories, then review the old routes and certificates;
    # they may refer to retired Docker networks or the old Ubuntu VM.
    proxy = {
      app = {
        image = image "jc21/nginx-proxy-manager" "081c4c544ad5da81022b3b030c2ba50175923bc87a534bce8b52f870e695e9f1";
        restart = "unless-stopped";
        ports = [ "80:80" "81:81" "443:443" ];
        volumes = [ "${base}/proxy/data:/data" "${base}/proxy/letsencrypt:/etc/letsencrypt" ];
      };
    };
    # Norish recipe app, its PostgreSQL database, Redis and Obscura browser.
    # AUTH_URL must match the canonical address used for authentication.
    # Application and database passwords/tokens come from separate env files;
    # the app and Obscura must receive the same CDP token.
    norish = {
      norish = {
        image = image "norishapp/norish" "f96ba007c7bdd7b6640f34c2ffbe63a647a2f9e2a291afdf666f895e7f6f168b";
        restart = "unless-stopped";
        ports = [ "9901:3000" ];
        env_file = [ (secret "norish") ];
        environment.AUTH_URL = "http://werkstatt:9901";
        volumes = [ "${base}/norish/uploads:/app/uploads" ];
        depends_on = [ "db" "redis" "obscura" ];
      };
      # This is PostgreSQL 17, matching the source data directory. Back up or
      # stop the database before copying it; depends_on is ordering, not health.
      db = {
        image = image "postgres" "b0f9560a2de083e2cc7382e75f808c7381a32852a7ec49117deedb300e552b24";
        restart = "unless-stopped";
        env_file = [ (secret "norish-db") ];
        environment.POSTGRES_DB = "norish";
        volumes = [ "${base}/norish/postgres:/var/lib/postgresql/data" ];
      };
      redis = {
        image = image "redis" "8a1efc5f479551822b47424ccae982026b633f28818eab0387348120a61e10e2";
        restart = "unless-stopped";
        volumes = [ "${base}/norish/redis:/data" ];
      };
      obscura = {
        image = image "norishapp/obscura" "d3b30af8d88a73685422d9c29a7689c0952966e8d6e87eb00edcf6c2c85defe6";
        restart = "unless-stopped";
        env_file = [ (secret "norish-obscura") ];
      };
    };
    # The source all-in-one Guacamole image contains its PostgreSQL data in
    # /config. Keep the entire directory. PUID/PGID are supplied by the
    # migration so they match the actual Jonas account on the new host.
    guacamole = {
      guacamole = {
        image = image "jwetzell/guacamole" "6128500fa30f0c3cc3c9079bc977b7e2d2159d58d0fa16f084cb1d115ea6ce49";
        restart = "unless-stopped";
        ports = [ "9800:8080" ];
        env_file = [ (secret "guacamole") ];
        environment.TZ = "Europe/Bucharest";
        volumes = [ "${base}/guacamole/config:/config" ];
      };
    };
    # Firefly III's original app, MariaDB, Redis and daily cron container.
    # Preserve the database and application keys; DNS aliases keep the old
    # firefly-db/firefly-redis names valid on the new Compose network.
    firefly = {
      db = {
        image = image "mariadb" "9da6213d1a5714c4585c9c0003c51510b320d6f60e53d78701fe1e194126249f";
        restart = "unless-stopped";
        env_file = [ (secret "firefly-db") ];
        environment = { TZ = "Europe/Bucharest"; MYSQL_DATABASE = "firefly"; MYSQL_USER = "fireflyuser"; };
        networks.default.aliases = [ "firefly-db" ];
        volumes = [ "${base}/firefly/mysql:/var/lib/mysql" ];
      };
      redis = {
        image = image "redis" "a7cee7c8178ff9b5297cb109e6240f5072cdaaafd775ce6b586c3c704b06458e";
        restart = "unless-stopped";
        networks.default.aliases = [ "firefly-redis" ];
        volumes = [ "${base}/firefly/redis:/data" ];
      };
      firefly = {
        image = image "fireflyiii/core" "4d71e7207ac46661bed6fcd13e824c739dfdb331a5d58dc7e048fc60c5382da7";
        restart = "unless-stopped";
        ports = [ "6182:8080" ];
        env_file = [ (secret "firefly") ];
        # Source non-secret settings are declared here and override env_file
        # values. Update APP_URL for the canonical LAN/tailnet/proxy address.
        environment = {
          APP_ENV = "production";
          APP_URL = "http://werkstatt:6182";
          APP_DEBUG = "false";
          TZ = "Europe/Berlin";
          DEFAULT_LANGUAGE = "en_US";
          DEFAULT_LOCALE = "equal";
          DB_CONNECTION = "mysql";
          DB_HOST = "firefly-db";
          DB_PORT = "3306";
          DB_DATABASE = "firefly";
          DB_USERNAME = "fireflyuser";
          CACHE_DRIVER = "redis";
          SESSION_DRIVER = "redis";
          REDIS_SCHEME = "tcp";
          REDIS_HOST = "firefly-redis";
          REDIS_PORT = "6379";
          REDIS_DB = "0";
          REDIS_CACHE_DB = "1";
          LOG_CHANNEL = "stack";
          APP_LOG_LEVEL = "notice";
          AUDIT_LOG_LEVEL = "info";
          DKR_CHECK_SQLITE = "false";
          DKR_RUN_MIGRATION = "true";
          DKR_RUN_UPGRADE = "true";
          DKR_RUN_VERIFY = "true";
          DKR_RUN_REPORT = "true";
          DKR_RUN_PASSPORT_INSTALL = "true";
          MAIL_MAILER = "smtp";
          MAIL_HOST = "smtp.gmail.com";
          MAIL_PORT = "465";
          MAIL_FROM = "jonashoermann12@gmail.com";
          MAIL_ENCRYPTION = "SSL";
        };
        volumes = [ "${base}/firefly/upload:/var/www/html/storage/upload" ];
        depends_on = [ "db" "redis" ];
      };
      # Compose's $$ passes a literal $ to the container shell, which reads
      # STATIC_CRON_TOKEN from the private env file when creating the crontab.
      # The resulting container crontab contains that token and is sensitive.
      cron = {
        image = image "alpine" "51b67269f354137895d43f3b3d810bfacd3945438e94dc5ac55fdac340352f48";
        restart = "unless-stopped";
        env_file = [ (secret "firefly-cron") ];
        environment.TZ = "Europe/Berlin";
        depends_on = [ "firefly" ];
        command = [ "sh" "-c" ''echo "0 3 * * * wget -qO- http://firefly:8080/api/v1/cron/$$STATIC_CRON_TOKEN" | crontab - && crond -f -L /dev/stdout'' ];
      };
    };
    # One-shot backup to the Synology shared_common/backup_bitwarden directory.
    # Its systemd unit requires the share and checks it is actually mounted;
    # an unavailable NAS must not result in a misleading local backup.
    bitwarden-backup = {
      backup = {
        image = image "rounakdatta/bitwarden-backup" "3bc5253b3396af990318d5603bc45e3b7c40b418410eec4735f1b75a6abb1618";
        env_file = [ (secret "bitwarden-backup") ];
        volumes = [ "${base}/nas/shared-common/backup_bitwarden:/out" ];
      };
    };
  };
  # JSON is a supported Compose format. Its absolute bind mounts ensure paths
  # do not accidentally resolve relative to the generated Nix store file.
  compose = name: services: pkgs.writeText "werkstatt-${name}-compose.json" (builtins.toJSON { inherit services; });
  # Use a distinct Compose project name per stack to isolate networks. The
  # marker must be created only after data and env files are restored. A
  # oneshot unit staying active does not track the health of its containers.
  service = name: services: {
    description = "Werkstatt ${name} Compose project";
    after = [ "docker.service" "network-online.target" ];
    requires = [ "docker.service" ];
    wants = [ "network-online.target" ];
    wantedBy = lib.optional (name != "bitwarden-backup") "multi-user.target";
    unitConfig.ConditionPathExists = "${base}/${name}/.ready";
    unitConfig.RequiresMountsFor = [ "${base}/${name}" "${base}/secrets" ]
      ++ lib.optional (name == "bitwarden-backup") "${base}/nas/shared-common";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = name != "bitwarden-backup";
      ExecStartPre = lib.optionals (name == "bitwarden-backup") [
        "${pkgs.util-linux}/bin/mountpoint -q ${base}/nas/shared-common"
        "${pkgs.coreutils}/bin/test -d ${base}/nas/shared-common/backup_bitwarden"
      ];
      ExecStart = if name == "bitwarden-backup" then
        "${pkgs.docker-compose}/bin/docker-compose -p werkstatt-${name} -f ${compose name services} run --rm backup"
      else
        "${pkgs.docker-compose}/bin/docker-compose -p werkstatt-${name} -f ${compose name services} up -d --remove-orphans";
      ExecStop = lib.optionalString (name != "bitwarden-backup") "${pkgs.docker-compose}/bin/docker-compose -p werkstatt-${name} -f ${compose name services} down";
    };
  };
in
{
  # Published for inspection and `docker compose -f ... ps/logs`, not editing.
  # Change Nix and rebuild; editing the generated files is not persistent.
  environment.etc = lib.mapAttrs' (name: services: lib.nameValuePair "werkstatt/compose/${name}.json" { source = compose name services; }) projects;
  systemd.services = lib.mapAttrs' (name: services: lib.nameValuePair "werkstatt-${name}" (service name services)) projects;
}