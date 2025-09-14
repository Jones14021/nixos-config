{ config, pkgs, lib, ... }:

####### NOTICE ########
#
# manual step required to configure rclone for onedrive in a compatible way to this service:
#
# rclone --config=$HOME/.config/rclone/rclone.conf config create onedrive onedrive
#
#######################

{
  home.activation.createOnedriveDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/OneDrive"
  '';

  systemd.user.services.onedrive = {
    Unit = {
      Description = "Rclone mount for OneDrive";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
      StartLimitBurst = 3;
      StartLimitIntervalSec = 10;
    };
    Service = {
      Type = "simple";
      # * umask 022: mode 755 for directories and 644 for files
      # * Directory metadata is cached for 5 minutes to reduce directory listing requests to OneDrive.
      #   This means changes made externally or in another client may not be reflected locally for up to 5 minutes
      # * Enables write caching in the Virtual File System (VFS) layer. Files you write are cached locally until
      #   fully written, then uploaded immediately once closed.
      ExecStartPre = "${pkgs.stdenv.shell} -c '${pkgs.rclone}/bin/rclone listremotes | grep -q \'^onedrive:$\''";
      ExecStart = ''
        ${pkgs.rclone}/bin/rclone mount onedrive: %h/OneDrive \
          --config=%h/.config/rclone/rclone.conf \
          --vfs-cache-mode writes \
          --dir-cache-time 5m \
          --poll-interval 30s \
          --umask 022 \
      '';
      Restart = "on-failure";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
