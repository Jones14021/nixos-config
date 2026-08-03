/*
  Flatpak bootstrap and update behavior

  This module installs the apps in flatpakApps system-wide (/var/lib/flatpak)
  only when they are missing. Installation is done by a one-shot systemd
  service (`flatpak-bootstrap.service`) that is triggered once per
  `nixos-rebuild switch`; rebuild waits for its result and streams its journal
  output, while DNS or network failures do not abort activation. The service never runs
  `flatpak update`, never pins an app version after installation, and does not
  replace an already installed app. Flathub is added only if it has not already
  been configured.

  Warehouse sees these as System Flatpaks and can update, downgrade, or remove
  them normally; changing an app in Warehouse will not be undone by a rebuild.
  If Warehouse removes an app that remains in flatpakApps, the next rebuild
  installs it again because it is missing. Remove its entry from flatpakApps
  first if the removal should persist.

  External bundle entries are downloaded only when their appId is missing; the
  temporary bundle is deleted after installation. Rebuilds do not download an
  installed external-bundle app again.
*/
{ lib, pkgs, ... }:
let
  systemctl = "${pkgs.systemd}/bin/systemctl";
  journalctl = "${pkgs.systemd}/bin/journalctl";

  # Each item is either:
  # - { ref = "APPLICATION_ID//BRANCH"; } for an app from Flathub.
  # - { appId = "APPLICATION_ID"; bundleUrl = "https://.../app.flatpak"; }
  #   for an external Flatpak bundle. The app is downloaded and installed only
  #   when that application ID is not already installed system-wide.
  flatpakApps = [
    { ref = "com.github.tchx84.Flatseal//stable"; }
    { ref = "com.thincast.client//stable"; }
    {
      appId = "com.zubersoft.Mobilesheets";
      bundleUrl = "https://www.zubersoft.download/mobilesheets.flatpak";
    }
  ];

  flatpakBootstrapScript = let
    flatpak = lib.getExe pkgs.flatpak;
    curl = lib.getExe pkgs.curl;
  in ''
    set -eu

    if ! ${flatpak} remote-list --system --columns=name | ${pkgs.gnugrep}/bin/grep --fixed-strings --quiet --line-regexp flathub; then
      ${flatpak} remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    fi

    install_flathub_if_missing() {
      app_ref="$1"

      if ! ${flatpak} info --system "$app_ref" >/dev/null 2>&1; then
        ${flatpak} install --system --noninteractive flathub "$app_ref"
      fi
    }

    install_bundle_if_missing() {
      app_id="$1"
      bundle_url="$2"
      bundle_path="$(mktemp --tmpdir=/var/lib/flatpak --suffix=.flatpak)"

      if ! ${flatpak} info --system --app "$app_id" >/dev/null 2>&1; then
        trap 'rm --force "$bundle_path"' EXIT
        ${curl} --fail --location --output "$bundle_path" "$bundle_url"
        ${flatpak} install --system --noninteractive "$bundle_path"
        rm --force "$bundle_path"
        trap - EXIT
      fi
    }

    ${lib.concatMapStringsSep "\n" (app:
      if app ? ref then
        "install_flathub_if_missing ${lib.escapeShellArg app.ref}"
      else
        "install_bundle_if_missing ${lib.escapeShellArg app.appId} ${lib.escapeShellArg app.bundleUrl}"
    ) flatpakApps}
  '';
in
{
  environment.systemPackages = [ pkgs.warehouse ];

  # Native NixOS Flatpak support; Warehouse manages the system installation afterwards.
  services.flatpak.enable = true;

  systemd.services.flatpak-bootstrap = {
    description = "Bootstrap configured Flatpaks when network is available";
    after = [ "network-online.target" "nss-lookup.target" ];
    wants = [ "network-online.target" "nss-lookup.target" ];
    serviceConfig = {
      Type = "oneshot";
    };
    script = flatpakBootstrapScript;
  };

  system.activationScripts.triggerFlatpakBootstrap.text = ''
    # NixOS activation uses a minimal PATH without systemctl. It also runs
    # before switch-to-configuration reloads systemd.
    if ! ${systemctl} daemon-reload; then
      echo "flatpak-bootstrap: failed to reload systemd" >&2
    else
      ${journalctl} --unit=flatpak-bootstrap.service --follow --lines=0 --no-pager --output=cat &
      journal_pid=$!

      if ${systemctl} start flatpak-bootstrap.service; then
        bootstrap_status=0
      else
        bootstrap_status=$?
      fi

      kill "$journal_pid" 2>/dev/null || true
      wait "$journal_pid" 2>/dev/null || true

      if [ "$bootstrap_status" -ne 0 ]; then
        echo "flatpak-bootstrap: service failed (exit $bootstrap_status)" >&2
      fi
    fi
  '';
}
