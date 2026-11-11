{ lib, pkgs, ... }:

let
  base = "/home/jonas/services";
  projects = {
    proxy = ./proxy.yaml;
    norish = ./norish.yaml;
    neugier = ./neugier.yaml;
    guacamole = ./guacamole.yaml;
    firefly = ./firefly.yaml;
    bitwarden-backup = ./bitwarden-backup.yaml;
  };
  veth-renamer = pkgs.callPackage ./veth-renamer.nix { };
  service = name: compose: {
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
        "${pkgs.docker-compose}/bin/docker-compose -p werkstatt-${name} -f ${compose} run --rm backup"
      else
        "${pkgs.docker-compose}/bin/docker-compose -p werkstatt-${name} ${lib.optionalString (name == "neugier") "--env-file ${base}/neugier/neugier.env"} -f ${compose} up -d --remove-orphans";
      ExecStop = lib.optionalString (name != "bitwarden-backup") "${pkgs.docker-compose}/bin/docker-compose -p werkstatt-${name} ${lib.optionalString (name == "neugier") "--env-file ${base}/neugier/neugier.env"} -f ${compose} down";
    };
  };
in
{
  environment.systemPackages = [ veth-renamer ];
  environment.etc = lib.mapAttrs' (name: compose: lib.nameValuePair "werkstatt/compose/${name}.yaml" { source = compose; }) projects;
  systemd.services = (lib.mapAttrs' (name: compose: lib.nameValuePair "werkstatt-${name}" (service name compose)) projects) // {
    veth-renamer = {
      description = "Rename labeled Docker host veth interfaces";
      wantedBy = [ "multi-user.target" ];
      wants = [ "docker.service" ];
      after = [ "docker.service" ];
      path = [ pkgs.iproute2 pkgs.util-linux ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${veth-renamer}/bin/veth-renamer --mode=primary-repair --vnstat=off --mapping-file=/run/veth-renamer/mappings.json";
        Restart = "on-failure";
        RestartSec = 5;
        RuntimeDirectory = "veth-renamer";
        RuntimeDirectoryMode = "0700";
        UMask = "0077";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        CapabilityBoundingSet = [ "CAP_SYS_ADMIN" "CAP_NET_ADMIN" "CAP_SYS_PTRACE" "CAP_DAC_OVERRIDE" ];
        RestrictAddressFamilies = [ "AF_UNIX" "AF_NETLINK" ];
      };
    };
  };
}