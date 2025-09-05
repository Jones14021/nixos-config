{ config, pkgs, lib, ... }:

{
  home.activation.createOnedriveDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/OneDrive"
  '';

  systemd.user.services.onedrive = {
    Unit = {
      Description = "Rclone mount for OneDrive";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = ''
        ${pkgs.rclone}/bin/rclone listremotes | grep -q "^onedrive:$" || exit 1
        ${pkgs.rclone}/bin/rclone mount onedrive: $HOME/OneDrive \
          --config=$HOME/.config/rclone/rclone.conf \
          --vfs-cache-mode writes \
          --dir-cache-time 1h \
          --poll-interval 30s \
          --umask 022 \
          --daemon-timeout 600s
      '';
      ExecStop = "${pkgs.fuse}/bin/fusermount -u $HOME/OneDrive";
      Restart = "on-failure";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  systemd.user.units."onedrive.automount".text = ''
    [Unit]
    Description=Automount OneDrive via rclone

    [Automount]
    Where=%h/OneDrive

    [Install]
    WantedBy=default.target
  '';
}
