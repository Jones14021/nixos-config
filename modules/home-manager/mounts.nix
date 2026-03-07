{ config, pkgs, ... }:

let
  gio = "${pkgs.glib.bin}/bin/gio";
  user = "hoj43157";
  password = "YOUR_STRONG_PASSWORD"; # TODO: securely handle this
  address = "smb://fs.hs-regensburg.de/storage/home/${user}";
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
      Environment = [
        # Provide the exact path to the GVfs modules so gio knows how to handle smb://
        "GIO_EXTRA_MODULES=${pkgs.gvfs}/lib/gio/modules"
      ];
      # Note the '< %h/.smboth' which feeds the credentials to the command.
      # %h resolves to your home directory in systemd.
      ExecStart = "${pkgs.runtimeShell} -c \"${gio} mount ${address} < %h/.smboth\"";
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
}
