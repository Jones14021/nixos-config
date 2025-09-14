{ config, lib, pkgs, ... }:

let
  fdroidApk = pkgs.fetchurl {
    # specific versions are available as org.fdroid.fdroid_<versionCode>.apk
    url = "https://f-droid.org/repo/org.fdroid.fdroid_1015053.apk";
    # To discover the correct sha256, temporarily set sha256 = lib.fakeSha256;
    sha256 = "sha256-gibQW+GImbk364WHdWEwQtpSVV5ojR6PvzAi/s6xEHs=";
  };

  #kindleApk = pkgs.fetchurl {
  #  # APKMirror hosts multiple splits; prefer the universal/armv7 build that matches Waydroid image
  #  # Replace with the direct .apk URL for your version from the chosen mirror
  #  # https://kindle.de.uptodown.com/android/versions
  #  # https://www.reddit.com/r/Calibre/comments/1is090x/feb_2025_macfriendly_android_emulator_guide_for/?tl=de
  #  # version 4.16.0.75 recommended
  #  url = "https://www.apkmirror.com/wp-content/themes/APKMirror/download.php?id=8934498";
  #  # To discover the correct sha256, temporarily set sha256 = lib.fakeSha256;
  #  sha256 = "sha256-tkZRhJ7OtXRZBJ5wF+BDAI/OjxRqrR002Y8AJ9h+Tu8=";
  #};

  appInstallerScript = pkgs.writeShellScriptBin "waydroid-app-installer" ''
    set -euo pipefail

    # Config: list of APKs to ensure installed
    APKS=(
      "${fdroidApk}"
    )

    # Start session if not running
    if ! systemctl --user is-active --quiet waydroid-session; then
      waydroid session start || true
    fi

    # Wait up to 30 minutes for Android user 0 to be ready
    end=$(( $(date +%s) + 1800 ))
    until waydroid status 2>/dev/null | grep -q "Android with user 0 is ready"; do
      if [ $(date +%s) -ge $end ]; then
        echo "Timed out waiting for Waydroid session (30 minutes)."
        exit 0
      fi
      sleep 3
    done

    install_apk() {
      local apk="$1"
      waydroid app install "$apk" || true
    }

    for apk in "''${APKS[@]}"; do
      install_apk "$apk"
    done
  '';

  waydroidInitScript = pkgs.writeShellScriptBin "waydroid-once-init-gapps" ''
    set -euo pipefail

    # Detect initialization: presence of data directory is a practical indicator on most setups
    if waydroid status 2>/dev/null | grep -q "Session: RUNNING"; then
      # Running session implies already initialized
      exit 0
    fi

    # Try a more direct check using the global instance props
    if waydroid status 2>/dev/null | grep -q "Android with user 0"; then
      exit 0
    fi

    # If not initialized, run GAPPS image init once
    # Note: requires network and may take a while
    waydroid init -s GAPPS
  '';

  waydroidSettingsScript = pkgs.writeShellScriptBin "waydroid-persist-settings" ''
    set -euo pipefail

    # Stop session if running
    if systemctl --user is-active --quiet waydroid-session; then
      waydroid session stop
    fi

    # waydroid by default always runs in fullscreen.
    # Enable Window integration with Desktop Window Manager
    waydroid prop set persist.waydroid.multi_windows true

    waydroid session start
  '';
in
{
  # 1) One-shot initializer: runs only if not initialized
  systemd.user.services."waydroid-init-once" = {
    Unit = {
      Description = "One-shot Waydroid initialization with GAPPS if not yet initialized";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${waydroidInitScript}/bin/waydroid-once-init-gapps";
      # Avoid repeated runs; harmless if re-run but keep it tidy
      RemainAfterExit = true;
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  # 2) App installer: waits for waydroid session, installs a known set of apps, times out after 30 min
  systemd.user.services."waydroid-install-apps" = {
    Unit = {
      Description = "Install a known set of Waydroid apps idempotently";
      After = [ "waydroid-session.service" "network-online.target" ];
      Wants = [ "waydroid-session.service" "network-online.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${appInstallerScript}/bin/waydroid-app-installer";
      TimeoutSec = 1900; # a bit over 30 minutes to account for script plus exit
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  # 3) Persist settings to existing session
  systemd.user.services."waydroid-persist-settings" = {
    Unit = {
      Description = "Apply a known set of Waydroid settings idempotently";
      After = [ "waydroid-install-apps.service" "waydroid-session.service" "network-online.target" ];
      Wants = [ "waydroid-session.service" "network-online.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${waydroidSettingsScript}/bin/waydroid-persist-settings";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
