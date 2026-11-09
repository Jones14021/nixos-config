# Shared Synology NAS access for werkstatt services. The NAS is assumed to be
# online when a consumer starts; if it is unavailable, the dependent service
# fails instead of silently using an empty local directory.
#
# Before use, create /home/jonas/services/secrets/nas.creds as root, mode 0600:
#   username=<Synology account>
#   password=<password>
#   domain=<optional domain>
# Grant that account access to both shares. Never add the credentials to Git.
# Mounts are started on demand by systemd dependencies, not at every boot.
{ pkgs, ... }:

let
  base = "/home/jonas/services/nas";
  credentials = "/home/jonas/services/secrets/nas.creds";
  share = device: {
    inherit device;
    fsType = "cifs";
    options = [
      "noauto"
      "_netdev"
      "x-systemd.mount-timeout=30s"
      "credentials=${credentials}"
      "uid=jonas"
      "gid=users"
      "file_mode=0640"
      "dir_mode=0750"
      "vers=3.0"
    ];
  };
in
{
  environment.systemPackages = [ pkgs.cifs-utils ];
  systemd.tmpfiles.rules = [
    "d ${base} 0750 jonas users -"
    "d ${base}/workouts 0750 jonas users -"
    "d ${base}/shared-common 0750 jonas users -"
    "d /mnt/nas 0755 root root -"
  ];

  fileSystems."${base}/workouts" = share "//10.0.2.200/workouts";
  fileSystems."${base}/shared-common" = share "//10.0.2.200/shared_common";

  # Preserve the old Jellyfin library path without storing media outside home.
  fileSystems."/mnt/nas" = {
    device = "${base}/workouts";
    fsType = "none";
    options = [ "bind" "noauto" "x-systemd.requires-mounts-for=${base}/workouts" ];
  };
}