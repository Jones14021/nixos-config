{ config, pkgs, lib, ... }:

let
  gio = "${pkgs.glib.bin}/bin/gio";
  nmcli = "${pkgs.networkmanager}/bin/nmcli";
  user = "hoj43157";
  password = "YOUR_STRONG_PASSWORD"; # TODO: securely handle this
  server = "fs.hs-regensburg.de";
  share = "storage/Home";
  address = "smb://${server}/${share}/${user}";
  # The URI path Dolphin uses for GVfs mounts
  gvfsUri = "file:///run/user/1000/gvfs/smb-share:server=${server},share=${share}/${user}";
in {
  # We do not need manual daemons (gvfs-daemon, gvfsd-fuser);
  # NixOS dbus activation handles it now.

  systemd.user.services."oth-smb-credentials" = {
    Unit.Description = "Create SMB credentials file for OTH mount";
    Service = {
      Type = "oneshot";
      # Check if the file exists before writing, but always apply chmod at the end.
      ExecStart = "${pkgs.writeShellScript "create-smb-creds" ''
        FILE="$HOME/.smboth"
        
        if [ ! -f "$FILE" ]; then
          echo "${user}" > "$FILE"
          echo "hs-regensburg.de" >> "$FILE"
          echo "${password}" >> "$FILE"
        fi
        
        # Always secure it, even if it already existed
        chmod 600 "$FILE"
      ''}";
    };
    Install.WantedBy = [ "default.target" ];
  };

  # This service will create a persistent SMB mount using gio when the user logs in.
  systemd.user.services."oth-userhome-mount" = {
    Unit = {
      Description = "One-shot: create OTH SMB mount with gio";
      After = [ "network.target" "NetworkManager.service" "oth-smb-credentials.service" ];
      Requires = [ "oth-smb-credentials.service" ];
    };

    Service = {
      Type = "oneshot";
      # This is required so systemd knows the service is still "running" after the mount command finishes
      RemainAfterExit = true;
      Environment = [
        # Provide the exact path to the GVfs modules so gio knows how to handle smb://
        "GIO_EXTRA_MODULES=${pkgs.gvfs}/lib/gio/modules"
      ];
      # Note the '< %h/.smboth' which feeds the credentials to the command.
      # %h resolves to your home directory in systemd.
      ExecStart = "${pkgs.runtimeShell} -c \"${gio} mount ${address} < %h/.smboth\"";

      # Stop: Graceful unmount with a lazy unmount fallback for frozen networks
      # If you manually run systemctl --user stop oth-userhome-mount while connected,
      # it cleanly unmounts via gio.
      ExecStop = "${pkgs.writeShellScript "unmount-oth-smb" ''
        echo "Unmounting OTH share..."
        ${gio} mount -u ${address} || true
        
        # Fallback hard-kill for the FUSE mount if the network is totally dead
        MOUNT_DIR=\"/run/user/$(id -u)/gvfs/smb-share:server=fs.hs-regensburg.de,share=storage\"
        if mountpoint -q \"$MOUNT_DIR\"; then
          umount -l \"$MOUNT_DIR\" || true
        fi
      ''}";
    };

    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  # Monitor Service (Runs continuously, watches for VPN connect/disconnect)
  systemd.user.services."oth-vpn-monitor" = {
    Unit = {
      Description = "Monitor OTH VPN state and toggle SMB mount";
      After = [ "NetworkManager.service" ];
    };

    Service = {
      Type = "simple";
      ExecStart = "${pkgs.writeShellScript "oth-vpn-monitor-script" ''
        NMCLI="${nmcli}"

        # Keep track of our own perceived state so we don't spam start/stop commands
        CURRENT_STATE="down"

        # Check initial state on boot
        if $NMCLI con show --active | grep -q "OTH"; then
           CURRENT_STATE="up"
           systemctl --user start oth-userhome-mount
        fi

        # Listen to NetworkManager events
        $NMCLI monitor | while read -r line; do
          
          # We only care if the output mentions OTH, ppp0 (the vpn tunnel), or NetworkManager state
          if echo "$line" | grep -E -q "(OTH|ppp0)"; then
            
            # Give NetworkManager 1 second to settle its internal state
            sleep 1

            # Check the *actual* current state of the connection
            if $NMCLI con show --active | grep -q "OTH"; then
               # VPN is UP
               if [ "$CURRENT_STATE" = "down" ]; then
                  echo "VPN connected. Starting mount..."
                  systemctl --user start oth-userhome-mount
                  CURRENT_STATE="up"
               fi
            else
               # VPN is DOWN
               if [ "$CURRENT_STATE" = "up" ]; then
                  echo "VPN disconnected. Stopping mount..."
                  systemctl --user stop oth-userhome-mount
                  CURRENT_STATE="down"
               fi
            fi

          fi
        done
      ''}";
      Restart = "always";
      RestartSec = 5;
    };

    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  # Make `gio` available in your regular shell
  home.packages = [ pkgs.glib.bin ];
  # Use an interpolated bash variable to safely append to the existing path
  home.sessionVariables = {
    GIO_EXTRA_MODULES = "\${GIO_EXTRA_MODULES}\${GIO_EXTRA_MODULES:+:}${pkgs.gvfs}/lib/gio/modules";
  };

  # Use a Home-Manager activation script to inject the bookmark into Dolphin's Places
  home.activation.addOthDolphinBookmark = lib.hm.dag.entryAfter ["writeBoundary"] ''
    PLACES_FILE="$HOME/.local/share/user-places.xbel"
    
    # Check if the file exists (KDE creates it on first run, but we create a basic one if missing)
    if [ ! -f "$PLACES_FILE" ]; then
      mkdir -p "$HOME/.local/share"
      echo '<?xml version="1.0" encoding="UTF-8"?>' > "$PLACES_FILE"
      echo '<!DOCTYPE xbel>' >> "$PLACES_FILE"
      echo '<xbel xmlns:bookmark="http://www.freedesktop.org/standards/desktop-bookmarks" xmlns:mime="http://www.freedesktop.org/standards/shared-mime-info">' >> "$PLACES_FILE"
      echo '</xbel>' >> "$PLACES_FILE"
    fi

    # Check if the bookmark already exists to avoid duplicates
    if ! grep -q "${gvfsUri}" "$PLACES_FILE"; then
      # Insert the bookmark right before the closing </xbel> tag using sed
      sed -i '/<\/xbel>/i \
      <bookmark href="${gvfsUri}">\n\
        <title>${user}</title>\n\
        <info>\n\
          <metadata owner="http://freedesktop.org">\n\
            <bookmark:icon name="network-server"/>\n\
          </metadata>\n\
          <metadata owner="http://www.kde.org">\n\
            <ID>1</ID>\n\
            <isSystemItem>false</isSystemItem>\n\
          </metadata>\n\
        </info>\n\
      </bookmark>' "$PLACES_FILE"
    fi
  '';
}
