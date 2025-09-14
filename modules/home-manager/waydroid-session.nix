{ config, lib, pkgs, ... }:

let
  fdroidApk = pkgs.fetchurl {
    # specific versions are available as org.fdroid.fdroid_<versionCode>.apk
    url = "https://f-droid.org/repo/org.fdroid.fdroid_1015053.apk";
    # To discover the correct sha256, temporarily set sha256 = lib.fakeSha256;
    sha256 = "sha256-gibQW+GImbk364WHdWEwQtpSVV5ojR6PvzAi/s6xEHs=";
  };

  kindleApk = builtins.path {
    # https://kindle.de.uptodown.com/android/versions
    # https://www.reddit.com/r/Calibre/comments/1is090x/feb_2025_macfriendly_android_emulator_guide_for/?tl=de
    # version 4.16.0.75 recommended
    path = ../../apks/kindle-4-16-0-75.apk;
    name = "kindle-4-16-0-75.apk";
    recursive = false; # since this is a single file
  };

  appInstallerScript = pkgs.writeShellScriptBin "waydroid-app-installer" ''
    set -euo pipefail

    # Config: list of APKs to ensure installed
    APKS=(
      "${fdroidApk}"
      "${kindleApk}"
    )

    # Start session in a new process if not running
    if ! systemctl --user is-active --quiet waydroid-session; then
      waydroid session start &
    fi

    install_apk() {
      local apk="$1"
      waydroid app install "$apk" || true
    }

    for apk in "''${APKS[@]}"; do
      install_apk "$apk"
    done
  '';

  waydroidSettingsScript = pkgs.writeShellScriptBin "waydroid-persist-settings" ''
    set -euo pipefail

    # Stop session if running
    waydroid session stop || true

    # waydroid by default always runs in fullscreen.
    # Enable Window integration with Desktop Window Manager
    waydroid prop set persist.waydroid.multi_windows true
    waydroid prop set persist.waydroid.suspend true

    waydroid session start &
  '';
in
{
  # 1) One-shot initializer: runs only if not initialized
  # done in system service

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
