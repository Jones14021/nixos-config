{ pkgs, ... }:

let
  waydroidInitScript = pkgs.writeShellScriptBin "waydroid-once-init-gapps" ''
    set -euo pipefail

    # Detect initialization: presence of data directory is a practical indicator on most setups
    if ${pkgs.waydroid}/bin/waydroid status 2>/dev/null | grep -q "Session: RUNNING"; then
      # Running session implies already initialized
      exit 0
    fi

    # Try a more direct check using the global instance props
    if ${pkgs.waydroid}/bin/waydroid status 2>/dev/null | grep -q "Android with user 0"; then
      exit 0
    fi

    # If not initialized, run GAPPS image init once
    # Note: requires network and may take a while
    ${pkgs.waydroid}/bin/waydroid init -s GAPPS
  '';
in
{
  systemd.services.waydroid-init-once = {
    description = "One-shot Waydroid initialization with GAPPS if not yet initialized";
    after = [ "network.target" ];
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${waydroidInitScript}/bin/waydroid-once-init-gapps";
      RemainAfterExit = true;
    };
  };
}
