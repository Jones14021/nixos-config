{ config, lib, pkgs, ... }:
let
  cfg = config.services.fusion360-bottles;
  bottleName = "fusion360";
in
{
  options.services.fusion360-bottles = {
    enable = lib.mkEnableOption "Automated Fusion 360 via Bottles (Flatpak)";
  };

  config = lib.mkIf cfg.enable {
    # 1) Flatpak + Bottles declarative
    services.flatpak.enable = true;
    services.flatpak.remotes = {
        "flathub" = "https://dl.flathub.org/repo/flathub.flatpakrepo";      
    };
    services.flatpak.packages = [
      "com.usebottles.bottles"
    ];

    # 2) One-shot activation step: ensure runner + bottle exist
    #    Uses Bottles CLI through Flatpak. Safe to re-run (idempotent checks).
    systemd.services.fusion360-bottles-provision = {
      description = "Provision Bottles runner and Fusion 360 bottle";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" "flatpak-system-helper.service" ];
      requires = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [ pkgs.coreutils pkgs.jq pkgs.gnugrep pkgs.gawk pkgs.findutils pkgs.bash ];
      script = ''
        set -euo pipefail

        run_cli() {
          flatpak run --command=bottles-cli com.usebottles.bottles "$@"
        }

        # Detect if bottle exists
        if run_cli list -j bottles | jq -e --arg name "${bottleName}" '.bottles[]?.Name==$name' >/dev/null 2>&1; then
          echo "Bottle '${bottleName}' already present."
        else
          echo "Ensuring runner caffe-9.7 is available..." 
          # Newer Bottles exposes CLI subcommands; fall back gracefully if not present.
          if run_cli --help | grep -q "new Create a new bottle"; then
            # Try to prefetch runner via CLI if available (some versions may only fetch on demand).
            # If runner management is not exposed, bottle creation still works and will fetch as needed.
            run_cli new -h >/dev/null || true

            echo "Creating bottle '${bottleName}' with runner caffe-9.7 (Application env)..."
            # Create an "Application" environment bottle, set Windows to win10, and prefer DXVK.
            # Bottles will fetch caffe-9.7 if missing.
            run_cli new \
              --name "${bottleName}" \
              --environment "Application" \
              --arch "auto" \
              --runner "caffe-9.7" \
              --version "win10" \
              --dxvk true || true
          else
            echo "Unsupported Bottles CLI; skipping automated creation. Open Bottles once and create bottle manually." >&2
            exit 0
          fi
        fi

        # Register a Fusion 360 installer program entry in the bottle, if not present.
        # We create a desktop file that opens Bottles filtered to the bottle.
        mkdir -p /usr/local/share/applications
        cat > /usr/local/share/applications/fusion360-installer.desktop <<EOF
        [Desktop Entry]
        Type=Application
        Name=Fusion 360 Installer (Bottles)
        Comment=Run Fusion 360 installer inside the '${bottleName}' bottle
        Exec=flatpak run com.usebottles.bottles --action run --bottle "${bottleName}"
        Icon=com.usebottles.bottles
        Categories=Graphics;Engineering;Utility;
        Terminal=false
        EOF

        # Helper script to complete login (AskIdentityManager.exe) with copied token URL.
        install -Dm0755 /dev/stdin /usr/local/bin/fusion360-complete-login <<'EOS'
        #!/usr/bin/env bash
        set -euo pipefail
        if [ $# -lt 1 ]; then
          echo "Usage: fusion360-complete-login \"adskidmgr:/login?code=...\"" >&2
          exit 1
        fi
        TOKEN="$1"
        # Resolve bottle path (JSON query for prefix dir)
        BOTTLE_JSON="$(flatpak run --command=bottles-cli com.usebottles.bottles info -j -b "${bottleName}")"
        PREFIX_DIR="$(echo "$BOTTLE_JSON" | jq -r '.path')"
        if [ -z "$PREFIX_DIR" ] || [ ! -d "$PREFIX_DIR" ]; then
          echo "Bottle path not found; ensure bottle '${bottleName}' exists." >&2
          exit 2
        fi
        # Use wine inside Bottles toolchain via bottles-cli run
        flatpak run --command=bottles-cli com.usebottles.bottles run \
          -b "${bottleName}" \
          --file "C:\\\\Program Files\\\\Autodesk\\\\webdeploy\\\\production\\\\AskIdentityManager\\\\AskIdentityManager.exe" \
          --args "$TOKEN" || {
            # Fallback to the commonly used path with varying digits
            flatpak run --command=bottles-cli com.usebottles.bottles run \
              -b "${bottleName}" \
              --file "C:\\\\Program Files\\\\Autodesk\\\\webdeploy\\\\production\\\\Autodesk Identity Manager\\\\AskIdentityManager.exe" \
              --args "$TOKEN"
          }
        EOS
      '';
    };

    # 3) Ship desktop entries system-wide
    environment.systemPackages = [
      pkgs.makeDesktopItem {
        name = "fusion360-bottles";
        desktopName = "Fusion 360 (via Bottles)";
        genericName = "Autodesk Fusion 360";
        comment = "Open the Fusion 360 bottle";
        exec = "flatpak run com.usebottles.bottles --bottle ${bottleName}";
        icon = "com.usebottles.bottles";
        categories = [ "Graphics" "Engineering" "Utility" ];
        terminal = false;
      }
    ];
  };
}
