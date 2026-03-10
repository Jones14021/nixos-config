{ config, pkgs, lib, ... }:

let
  gio = "${pkgs.glib.bin}/bin/gio";
  nmcli = "${pkgs.networkmanager}/bin/nmcli";

  # Define all your SMB mounts here. 
  # Each mount is an attribute set prefixed by its unique name (e.g., "othHome").
  smbMounts = {
    othHome = {
      user = "hoj43157";
      password = "YOUR_STRONG_PASSWORD"; # TODO: securely handle this (e.g., via sops-nix/agenix)
      domain = "hs-regensburg.de";
      server = "fs.hs-regensburg.de";
      
      # Split the share name from the subpath for proper FUSE unmounting fallback
      shareName = "storage";
      subPath = "Home/hoj43157"; 
      
      # The grep regex pattern nmcli looks for to detect if the required network/VPN is active
      vpnPattern = "(OTH|ppp0)"; 
      bookmarkTitle = "hoj43157";
    };

    # Example of how easily you can add another mount:
    # homeNas = {
    #   user = "jonas";
    #   password = "NAS_PASSWORD";
    #   domain = "WORKGROUP";
    #   server = "nas.local";
    #   shareName = "backups";
    #   subPath = "nixos";
    #   vpnPattern = "(WireGuard|wg0)"; 
    #   bookmarkTitle = "NAS Backups";
    # };
  };

in {
  # We do not need manual daemons (gvfs-daemon, gvfsd-fuser);
  # NixOS dbus activation handles it now.

  # Make `gio` available in your regular shell
  home.packages = [ pkgs.glib.bin ];
  
  # Use an interpolated bash variable to safely append to the existing path
  home.sessionVariables = {
    GIO_EXTRA_MODULES = "\${GIO_EXTRA_MODULES}\${GIO_EXTRA_MODULES:+:}${pkgs.gvfs}/lib/gio/modules";
  };

  # Dynamically generate systemd user services for all mounts defined in `smbMounts`
  systemd.user.services = lib.mkMerge (lib.mapAttrsToList (name: m: {
    
    # 1. Credentials Service
    "${name}-smb-credentials" = {
      Unit.Description = "Create SMB credentials file for ${name} mount";
      Service = {
        Type = "oneshot";

        Environment = [
          "PATH=${lib.makeBinPath [ pkgs.coreutils ]}"
        ];

        # Check if the file exists before writing, but always apply chmod at the end.
        ExecStart = "${pkgs.writeShellScript "create-smb-creds-${name}" ''
          FILE="$HOME/.smb_${name}"
          
          if [ ! -f "$FILE" ]; then
            echo "${m.user}" > "$FILE"
            echo "${m.domain}" >> "$FILE"
            echo "${m.password}" >> "$FILE"
          fi
          
          # Always secure it, even if it already existed
          chmod 600 "$FILE"
        ''}";
      };
      Install.WantedBy = [ "default.target" ];
    };

    # 2. Mount Service
    "${name}-mount" = {
      Unit = {
        Description = "One-shot: create ${name} SMB mount with gio";
        After = [ "network.target" "NetworkManager.service" "${name}-smb-credentials.service" ];
        Requires = [ "${name}-smb-credentials.service" ];
      };

      Service = {
        Type = "oneshot";
        RemainAfterExit = true;
        
        Environment = [
          "GIO_EXTRA_MODULES=${pkgs.gvfs}/lib/gio/modules"
          "PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.util-linux ]}"
        ];

        # %h resolves to home directory in systemd.
        ExecStart = "${pkgs.writeShellScript "mount-${name}-smb" ''

          MOUNT_DIR="/run/user/$(id -u)/gvfs/smb-share:server=${m.server},share=${m.shareName}"
          
          # If it's already mounted, exit with 0 so systemd marks it 'active'
          if mountpoint -q "$MOUNT_DIR"; then
            echo "Share ${name} is already mounted. Skipping mount command."
            exit 0
          else
            echo "Share ${name} is not mounted. Proceeding with mount command."
          fi

          # wait a moment to ensure network is fully up and DNS is resolved (especially important for VPNs)
          sleep 3
          echo "Mounting ${name} share..."
          echo "${gio} mount smb://${m.server}/${m.shareName}/${m.subPath} < %h/.smb_${name}"
          ${gio} mount smb://${m.server}/${m.shareName}/${m.subPath} < %h/.smb_${name}
        ''}";

        # Stop: Graceful unmount with a lazy unmount fallback for frozen networks
        ExecStop = "${pkgs.writeShellScript "unmount-${name}-smb" ''
          echo "Unmounting ${name} share..."
          
          # Wrap gio in a 3-second timeout
          ${pkgs.coreutils}/bin/timeout 3 ${gio} mount -u smb://${m.server}/${m.shareName}/${m.subPath} || true
          
          # hard-kill for the FUSE mount if the network is totally dead and gio hangs indefinitely.
          # Note: GVFS only mounts the root shareName internally.
          MOUNT_DIR="/run/user/$(id -u)/gvfs/smb-share:server=${m.server},share=${m.shareName}"
          if mountpoint -q "$MOUNT_DIR"; then
            umount -l "$MOUNT_DIR" || true
          fi
        ''}";
      };
      Install.WantedBy = [ "default.target" ];
    };

    # 3. Monitor Service
    "${name}-vpn-monitor" = {
      Unit = {
        Description = "Monitor ${name} network state and toggle SMB mount";
        After = [ "NetworkManager.service" ];
      };

      Service = {
        Type = "simple";

        Environment = [
          "PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.gnugrep pkgs.util-linux ]}"
        ];

        ExecStart = "${pkgs.writeShellScript "${name}-vpn-monitor-script" ''
          NMCLI="${nmcli}"

          # Check initial state on boot
          if $NMCLI con show --active | grep -qE "${m.vpnPattern}"; then
             CURRENT_STATE="up"
             echo "Network is up on startup. Starting mount ${name}..."
             systemctl --user start ${name}-mount
          fi

          # Listen to NetworkManager events
          $NMCLI monitor | while read -r line; do
            if echo "$line" | grep -qE "${m.vpnPattern}"; then
              
              # Give NetworkManager 1 second to settle its internal state
              sleep 1

              # Check the *actual* current state of the connection
              if $NMCLI con show --active | grep -qE "${m.vpnPattern}"; then
                 if [ "$CURRENT_STATE" = "down" ]; then
                    echo "Network connected. Starting mount ${name}..."
                    systemctl --user start ${name}-mount
                    CURRENT_STATE="up"
                 fi
              else
                 if [ "$CURRENT_STATE" = "up" ]; then
                    echo "Network disconnected. Stopping mount ${name}..."
                    systemctl --user stop ${name}-mount
                    CURRENT_STATE="down"
                 fi
              fi
            fi
          done
        ''}";
        Restart = "always";
        RestartSec = 5;
      };
      Install.WantedBy = [ "default.target" ];
    };

  }) smbMounts);


  # Generate Dolphin Bookmarks dynamically
  home.activation.addDolphinBookmarks = lib.hm.dag.entryAfter ["writeBoundary"] ''
    PLACES_FILE="$HOME/.local/share/user-places.xbel"
    
    # Check if the file exists (KDE creates it on first run, but we create a basic one if missing)
    if [ ! -f "$PLACES_FILE" ]; then
      mkdir -p "$HOME/.local/share"
      echo '<?xml version="1.0" encoding="UTF-8"?>' > "$PLACES_FILE"
      echo '<!DOCTYPE xbel>' >> "$PLACES_FILE"
      echo '<xbel xmlns:bookmark="http://www.freedesktop.org/standards/desktop-bookmarks" xmlns:mime="http://www.freedesktop.org/standards/shared-mime-info">' >> "$PLACES_FILE"
      echo '</xbel>' >> "$PLACES_FILE"
    fi

    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: m: ''
      GVFS_URI="file:///run/user/1000/gvfs/smb-share:server=${m.server},share=${m.shareName}/${m.subPath}"
      
      if ! grep -q "$GVFS_URI" "$PLACES_FILE"; then
        sed -i '/<\/xbel>/i \
        <bookmark href="'"$GVFS_URI"'">\n\
          <title>${m.bookmarkTitle}</title>\n\
          <info>\n\
            <metadata owner="http://freedesktop.org">\n\
              <bookmark:icon name="network-server"/>\n\
            </metadata>\n\
            <metadata owner="http://www.kde.org">\n\
              <ID>${name}</ID>\n\
              <isSystemItem>false</isSystemItem>\n\
            </metadata>\n\
          </info>\n\
        </bookmark>' "$PLACES_FILE"
      fi
    '') smbMounts)}
  '';
}
