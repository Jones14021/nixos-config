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

  Commands listed in `commands` (in flatpakApps or unmanagedFlatpakApps) get
  small wrapper scripts on the system PATH that call `flatpak run --command=...`,
  so CLIs packaged inside a Flatpak can be used and tab-completed in a terminal.
*/
{ lib, pkgs, ... }:
let
  systemctl = "${pkgs.systemd}/bin/systemctl";
  journalctl = "${pkgs.systemd}/bin/journalctl";
  flatpak = lib.getExe pkgs.flatpak;

  # Each item is either:
  # - { ref = "APPLICATION_ID//BRANCH"; } for an app from Flathub.
  # - { appId = "APPLICATION_ID"; bundleUrl = "https://.../app.flatpak"; }
  #   for an external Flatpak bundle. The app is downloaded and installed only
  #   when that application ID is not already installed system-wide.
  # Both forms may add permissions = [ "--FLATPAK-OVERRIDE-OPTION" ... ]; to
  # declare app-specific `flatpak override --system` options. For example,
  # permissions = [ "--filesystem=home" "--share=network" ];
  # Both forms may also add commands = [ "COMMAND" ... ]; to put executables
  # from the app's /app/bin on the host PATH.
  flatpakApps = [
    { ref = "com.github.tchx84.Flatseal//stable"; }
    { ref = "com.thincast.client//stable"; }
    {
      appId = "ai.storyteller.solidcraft";
      bundleUrl = "https://github.com/tangency-labs/solidcraft/releases/download/v0.16.2/solidcraft-linux-x86_64.flatpak";
      commands = [ "solidcraft-cli" "solvecraft-cli" "solidcraft" ];
      permissions = [
        "--filesystem=host"
        "--talk-name=org.freedesktop.Flatpak"
        "--share=network"
        # SolidCraft detects ACP agents with `opencode --version` on its own
        # PATH. These mounts make the NixOS wrapper, its store target, and the
        # OpenCode configuration and authentication state available there.
        "--filesystem=/run/current-system/sw/bin:ro"
        "--filesystem=/nix/store:ro"
        "--filesystem=~/.config/opencode:ro"
        "--filesystem=~/.local/share/opencode"
        "--env=PATH=/run/current-system/sw/bin:/app/bin:/usr/bin"
      ];
    }
    {
      appId = "ai.storyteller.artcraft-launcher";
      bundleUrl = "https://github.com/storytold/craft-launcher/releases/download/v0.5.1/artcraft-launcher-0.5.1-linux-x86_64.flatpak";
    }
    {
      appId = "com.zubersoft.mobileSheetsCompanion";
      bundleUrl = "https://www.zubersoft.download/mobilesheets.flatpak";
    }
  ];

  # Flatpaks installed and updated outside Nix (e.g. user-installed by the
  # ArtCraft launcher). Only their command wrappers are declared here; a missing
  # app does not break the rebuild, its wrapper just reports it as not installed.
  unmanagedFlatpakApps = [
    { appId = "ai.storyteller.wordcraft"; commands = [ "wordcraft" "wordcraft-cli" ]; }
    { appId = "ai.storyteller.cadcraft"; commands = [ "cadcraft" "cadcraft-cli" ]; }
    { appId = "ai.storyteller.deckcraft"; commands = [ "deckcraft" "deckcraft-cli" ]; }
    { appId = "ai.storyteller.gridcraft"; commands = [ "gridcraft" "gridcraft-cli" ]; }
    { appId = "ai.storyteller.pdfcraft"; commands = [ "pdfcraft" "pdfcraft-cli" ]; }
    { appId = "ai.storyteller.photocraft"; commands = [ "photocraft" "photocraft-cli" ]; }
    { appId = "ai.storyteller.soundcraft"; commands = [ "soundcraft" "soundcraft-cli" ]; }
  ];

  appIdOf = app: app.appId or (builtins.head (lib.splitString "//" app.ref));

  # Without a scope flag, `flatpak run` finds the app in the user or system installation.
  mkFlatpakCommand = scopeArgs: appId: command:
    pkgs.writeShellScriptBin command ''
      exec ${flatpak} run ${scopeArgs} --command=${lib.escapeShellArg command} ${lib.escapeShellArg appId} "$@"
    '';

  flatpakCommandWrappers =
    lib.concatMap (app: map (mkFlatpakCommand "--system" (appIdOf app)) (app.commands or [ ])) flatpakApps
    ++ lib.concatMap (app: map (mkFlatpakCommand "" app.appId) app.commands) unmanagedFlatpakApps;

  flatpakBootstrapScript = let
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

      if ! ${flatpak} info --system "$app_id" >/dev/null 2>&1; then
        trap 'rm --force "$bundle_path"' EXIT
        ${curl} --fail --location --output "$bundle_path" "$bundle_url"
        ${flatpak} install --system --noninteractive "$bundle_path"
        rm --force "$bundle_path"
        trap - EXIT
      fi
    }

    apply_permission_override() {
      app_id="$1"
      shift
      ${flatpak} override --system "$@" "$app_id"
    }

    ${lib.concatMapStringsSep "\n" (app:
      if app ? ref then
        "install_flathub_if_missing ${lib.escapeShellArg app.ref}"
      else
        "install_bundle_if_missing ${lib.escapeShellArg app.appId} ${lib.escapeShellArg app.bundleUrl}"
    ) flatpakApps}

    ${lib.concatMapStringsSep "\n" (app:
      lib.optionalString (app ? permissions)
        "apply_permission_override ${lib.escapeShellArg (appIdOf app)} ${lib.escapeShellArgs app.permissions}"
    ) flatpakApps}
  '';
in
{
  environment.systemPackages = [ pkgs.warehouse ] ++ flatpakCommandWrappers;

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
      echo "flatpak-bootstrap: monitoring service..."
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
