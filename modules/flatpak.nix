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

  External bundle entries are downloaded when their appId is missing or their
  bundleUrl differs from the one last installed (recorded in
  /var/lib/flatpak-bootstrap/<appId>.url); the temporary bundle is deleted
  after installation. Changing bundleUrl therefore upgrades or downgrades the
  app on the next rebuild; an unchanged bundleUrl never triggers a download.

  `permissions` are system overrides for flatpakApps and user overrides (for
  every Home Manager user) for unmanagedFlatpakApps. They are applied only when
  they changed since the last rebuild: without manual tweaks the overrides are
  reset to exactly the declared set; with Flatseal tweaks the declared options
  are added and the tweaks are kept. Each rebuild prints a diff in the
  flatpak-bootstrap output for every app whose overrides deviate from the config.

  Commands listed in `commands` (in flatpakApps or unmanagedFlatpakApps) get
  small wrapper scripts on the system PATH that call `flatpak run --command=...`,
  so CLIs packaged inside a Flatpak can be used and tab-completed in a terminal.
*/
{ config, lib, pkgs, ... }:
let
  systemctl = "${pkgs.systemd}/bin/systemctl";
  journalctl = "${pkgs.systemd}/bin/journalctl";
  flatpak = lib.getExe pkgs.flatpak;

  # Each item is either:
  # - { ref = "APPLICATION_ID//BRANCH"; } for an app from Flathub.
  # - { appId = "APPLICATION_ID"; bundleUrl = "https://.../app.flatpak"; }
  #   for an external Flatpak bundle. The app is (re)installed when that
  #   application ID is missing system-wide or bundleUrl has changed.
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
      bundleUrl = "https://github.com/tangency-labs/solidcraft/releases/download/v0.22.0/solidcraft-0.22.0-linux-x86_64.flatpak";
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
        # /app/bin first, or the host's command wrappers shadow the app's own binaries.
        "--env=PATH=/app/bin:/usr/bin:/run/current-system/sw/bin"
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
  # permissions = [ ... ] are `flatpak override --user` options. The
  # flatpak-bootstrap service writes them as each Home Manager user (via
  # runuser) into ~/.local/share/flatpak/overrides/<appId>, even before the app
  # is installed, so they are in place when the launcher installs it. Like the
  # system overrides, they are only rewritten when `permissions` changed, and
  # manual Flatseal tweaks are kept and reported as a deviation.
  # artcraftControlKey = { variable = "..."; commands = [ ... ]; } makes those
  # wrappers hand the running GUI's control key to the CLI (ArtCraft apps only,
  # needed for `mcp --connect`).
  #
  # ArtCraft control ports: the GUI opens its control channel on
  # <APP>_CONTROL_PORT, which must match the MCP entry in
  # modules/home-manager/opencode.nix. Network access is needed because the
  # control channel is loopback TCP.
  unmanagedFlatpakApps = [
    {
      appId = "ai.storyteller.wordcraft";
      commands = [ "wordcraft" "wordcraft-cli" ];
      permissions = [ "--share=network" "--env=WORDCRAFT_CONTROL_PORT=7981" ];
      artcraftControlKey = { variable = "WORDCRAFT_CONTROL_KEY"; commands = [ "wordcraft-cli" ]; };
    }
    {
      appId = "ai.storyteller.cadcraft";
      commands = [ "cadcraft" "cadcraft-cli" ];
      permissions = [ "--share=network" "--env=CADCRAFT_CONTROL_PORT=7982" ];
    }
    {
      appId = "ai.storyteller.deckcraft";
      commands = [ "deckcraft" "deckcraft-cli" ];
      permissions = [ "--share=network" "--env=DECKCRAFT_CONTROL_PORT=7983" ];
    }
    {
      appId = "ai.storyteller.gridcraft";
      commands = [ "gridcraft" "gridcraft-cli" ];
      permissions = [ "--share=network" "--env=GRIDCRAFT_CONTROL_PORT=7984" ];
    }
    # PDFCraft's control channel is a file, and its MCP server cannot attach to the GUI.
    { appId = "ai.storyteller.pdfcraft"; commands = [ "pdfcraft" "pdfcraft-cli" ]; }
    {
      appId = "ai.storyteller.photocraft";
      commands = [ "photocraft" "photocraft-cli" ];
      permissions = [
        "--share=network"
        "--env=PHOTOCRAFT_CONTROL_PORT=7985"
        # GUI and CLI share this token; the GUI creates it on first start.
        "--env=PHOTOCRAFT_CONTROL_TOKEN_FILE=/home/jonas/.var/app/ai.storyteller.photocraft/control-token"
      ];
    }
    {
      appId = "ai.storyteller.soundcraft";
      commands = [ "soundcraft" "soundcraft-cli" ];
      permissions = [ "--share=network" "--env=SOUNDCRAFT_CONTROL_PORT=7986" ];
    }
  ];

  appIdOf = app: app.appId or (builtins.head (lib.splitString "//" app.ref));

  # An ArtCraft GUI writes its key to control-key.<instance id>, but every
  # `flatpak run` gets a new instance id, so the CLI never finds that file on its
  # own. This picks the newest key file that belongs to a still running instance.
  artcraftControlKeyLookup = appId: variable: ''
    if [ -z "''${${variable}:-}" ]; then
      key_files=()
      while read -r instance app; do
        [ "$app" = ${lib.escapeShellArg appId} ] || continue
        for key_file in "$HOME"/.var/app/${lib.escapeShellArg appId}/config/*/control-key."$instance"; do
          [ -r "$key_file" ] && key_files+=("$key_file")
        done
      done < <(${flatpak} ps --columns=instance,application)
      if [ "''${#key_files[@]}" -gt 0 ]; then
        ${variable}="$(< "$(${pkgs.coreutils}/bin/ls -t "''${key_files[@]}" | ${pkgs.coreutils}/bin/head -n 1)")"
        export ${variable}
      fi
    fi
  '';

  # Without a scope flag, `flatpak run` finds the app in the user or system installation.
  mkFlatpakCommand = scopeArgs: app: command: let
    appId = appIdOf app;
  in
    pkgs.writeShellScriptBin command ''
      ${lib.optionalString (app ? artcraftControlKey && lib.elem command app.artcraftControlKey.commands)
        (artcraftControlKeyLookup appId app.artcraftControlKey.variable)}
      exec ${flatpak} run ${scopeArgs} --command=${lib.escapeShellArg command} ${lib.escapeShellArg appId} "$@"
    '';

  flatpakCommandWrappers =
    lib.concatMap (app: map (mkFlatpakCommand "--system" app) (app.commands or [ ])) flatpakApps
    ++ lib.concatMap (app: map (mkFlatpakCommand "" app) app.commands) unmanagedFlatpakApps;

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

    bundle_state_dir=/var/lib/flatpak-bootstrap
    mkdir --parents "$bundle_state_dir"

    install_bundle_if_missing_or_changed() {
      app_id="$1"
      bundle_url="$2"
      url_file="$bundle_state_dir/$app_id.url"

      if ${flatpak} info --system "$app_id" >/dev/null 2>&1 \
        && [ "$(cat "$url_file" 2>/dev/null)" = "$bundle_url" ]; then
        return 0
      fi

      bundle_path="$(mktemp --tmpdir=/var/lib/flatpak --suffix=.flatpak)"
      trap 'rm --force "$bundle_path"' EXIT
      ${curl} --fail --location --output "$bundle_path" "$bundle_url"
      ${flatpak} install --system --noninteractive --reinstall "$bundle_path"
      rm --force "$bundle_path"
      trap - EXIT
      printf '%s' "$bundle_url" > "$url_file"
    }

    # Usage: sync_permissions system|USER HOME APP_ID [OVERRIDE-OPTION...]
    sync_permissions() {
      owner="$1"
      home="$2"
      app_id="$3"
      shift 3

      if [ "$owner" = system ]; then
        override_file="/var/lib/flatpak/overrides/$app_id"
        run_override() { ${flatpak} override --system "$@" "$app_id"; }
      else
        override_file="$home/.local/share/flatpak/overrides/$app_id"
        run_override() {
          ${pkgs.util-linux}/bin/runuser -u "$owner" -- \
            ${pkgs.coreutils}/bin/env HOME="$home" ${flatpak} override --user "$@" "$app_id"
        }
      fi
      state_file="$bundle_state_dir/overrides/$owner/$app_id"
      mkdir --parents "$(dirname "$state_file")"

      # Let flatpak write the declared overrides into a scratch dir so they are comparable.
      render_dir="$(mktemp --directory)"
      if [ "$#" -gt 0 ]; then
        FLATPAK_USER_DIR="$render_dir" ${flatpak} override --user "$@" "$app_id"
      fi
      declared="$(cat "$render_dir/overrides/$app_id" 2>/dev/null || true)"
      rm --recursive --force "$render_dir"
      last="$(cat "$state_file" 2>/dev/null || true)"
      actual="$(cat "$override_file" 2>/dev/null || true)"

      if [ "$declared" != "$last" ] && [ "$actual" != "$declared" ]; then
        if [ "$actual" = "$last" ]; then
          run_override --reset
          [ "$#" -eq 0 ] || run_override "$@"
          echo "flatpak-bootstrap: applied changed permissions for $app_id ($owner)"
        else
          [ "$#" -eq 0 ] || run_override "$@"
          echo "flatpak-bootstrap: $app_id ($owner) has manual overrides; added the declared permissions without resetting, so permissions removed from the config may still be granted" >&2
        fi
        actual="$(cat "$override_file" 2>/dev/null || true)"
      fi
      printf '%s' "$declared" > "$state_file"

      if [ "$actual" != "$declared" ]; then
        echo "flatpak-bootstrap: $app_id ($owner) overrides deviate from config:" >&2
        ${pkgs.diffutils}/bin/diff --unified --label declared --label actual \
          <(printf '%s\n' "$declared") <(printf '%s\n' "$actual") >&2 || true
      fi
    }

    ${lib.concatMapStringsSep "\n" (app:
      if app ? ref then
        "install_flathub_if_missing ${lib.escapeShellArg app.ref}"
      else
        "install_bundle_if_missing_or_changed ${lib.escapeShellArg app.appId} ${lib.escapeShellArg app.bundleUrl}"
    ) flatpakApps}

    ${lib.concatMapStringsSep "\n" (app:
      "sync_permissions system '' ${lib.escapeShellArg (appIdOf app)} ${lib.escapeShellArgs (app.permissions or [ ])}"
    ) flatpakApps}

    ${lib.concatMapStringsSep "\n" (user:
      lib.concatMapStringsSep "\n" (app:
        "sync_permissions ${lib.escapeShellArg user} ${lib.escapeShellArg config.users.users.${user}.home} ${lib.escapeShellArg app.appId} ${lib.escapeShellArgs (app.permissions or [ ])}"
      ) unmanagedFlatpakApps
    ) (lib.attrNames config.home-manager.users)}
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
