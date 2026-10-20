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
    if ! ${pkgs.util-linux}/bin/findmnt --target "$HOME/OneDrive" >/dev/null 2>&1; then
      mkdir -p "$HOME/OneDrive"
    fi
  '';

  systemd.user.services.onedrive = {
    Unit = {
      Description = "Rclone mount for OneDrive";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
      StartLimitBurst = 10;
      StartLimitIntervalSec = 300;
    };
    Service = {
      Type = "simple";
      # * umask 022: mode 755 for directories and 644 for files
      # * Directory metadata is cached for 5 minutes to reduce directory listing requests to OneDrive.
      #   This means changes made externally or in another client may not be reflected locally for up to 5 minutes
      # * Full VFS cache: reads and writes are cached locally (max 5G / 72h), so repeated reads by
      #   Dolphin, thumbnailers or viewers don't re-download the file over and over.
      # * fusermount3 must be the setuid wrapper, the plain store binary can't unmount ("Operation not permitted")
      ExecStartPre = [
        "-/run/wrappers/bin/fusermount3 -uz %h/OneDrive"
        "${pkgs.stdenv.shell} -c '${pkgs.rclone}/bin/rclone listremotes | grep -q \'^onedrive:$\''"
      ];
      # * cmount (libfuse) + subtype=sshfs: the mount shows up as "fuse.sshfs", which KDE knows is a
      #   network filesystem, so Dolphin skips thumbnails (fuse.rclone is treated as a local disk)
      ExecStart = ''
        ${pkgs.rclone}/bin/rclone cmount onedrive: %h/OneDrive \
          -o subtype=sshfs \
          --config=%h/.config/rclone/rclone.conf \
          --vfs-cache-mode full \
          --vfs-cache-max-size 5G \
          --vfs-cache-max-age 72h \
          --dir-cache-time 5m \
          --poll-interval 30s \
          --umask 022
      '';
      ExecStopPost = "-/run/wrappers/bin/fusermount3 -uz %h/OneDrive";
      Restart = "on-failure";
      RestartSec = "30s";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  programs.plasma.configFile = {
    # keep Baloo from reading (= downloading) every file on the mount
    baloofilerc.General."exclude folders" = "${config.home.homeDirectory}/OneDrive/";

    # KIO network-mount optimizations, e.g. MIME type from file extension instead of reading content
    network_mounts.General = {
      EnableOptimizations = true;
      SmbPaths = "${config.home.homeDirectory}/OneDrive/";
    };

    # no previews/thumbnails for remote locations
    kdeglobals.PreviewSettings = {
      MaximumRemoteSize = 0;
      EnableRemoteFolderThumbnail = false;
    };
  };

  # baloo_file only reads its config on startup
  home.activation.reloadBaloo = lib.hm.dag.entryAfter [ "configure-plasma" ] ''
    export XDG_RUNTIME_DIR=''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
    run ${pkgs.systemd}/bin/systemctl --user try-restart kde-baloo.service || true
  '';
}
