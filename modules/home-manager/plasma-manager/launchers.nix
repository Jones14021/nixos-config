# Plasma desktop icons and taskbar pins for every host.
#
# Add a system application's desktop file name to desktopApplications to place
# an editable copy on the desktop. Find names under
# /run/current-system/sw/share/applications. To add icons only on one host,
# extend the existing lib.optionals host check or add another one.
#
# Add "applications:<desktop-file-name>" to taskbarApplications to pin an app;
# host-specific additions can use the same lib.optionals pattern. Plasma also
# accepts special URLs such as "preferred://browser". Existing custom pins and
# desktop files are kept. Deleting a baseline item works until the next rebuild;
# edits to an existing desktop file are not overwritten.
#
# Rebuilds repair recognized old Nix store references in desktop links, writable
# desktop Exec commands, and taskbar pins where a stable replacement is known.
# Other custom commands and unresolved links are left alone. Taskbar changes are
# applied to a running Plasma session, or at the next login if none is running.
{ config, lib, pkgs, osConfig, ... }:

let
  # Desktop baselines use system-profile applications; per-user and Flatpak
  # applications can still be added manually and their existing links repaired.
  desktopApplications = [
    "org.kde.dolphin.desktop"
    "org.kde.konsole.desktop"
  ] ++ lib.optionals (osConfig.networking.hostName == "werkstatt") [
    "virt-manager.desktop"
  ];
  taskbarApplications = [
    "applications:org.kde.dolphin.desktop"
    "applications:org.kde.konsole.desktop"
    "applications:google-chrome.desktop"
  ];
  taskbarScript = ''
    const baseline = ${builtins.toJSON taskbarApplications};
    function isTaskManager(widget) {
      return widget.type === "org.kde.plasma.taskmanager" || widget.type === "org.kde.plasma.icontasks";
    }
    const allPanels = panels();
    const taskPanels = allPanels.filter(function(panel) { return panel.widgets().some(isTaskManager); });
    const baselinePanel = taskPanels.filter(function(panel) { return panel.screen >= 0; })[0] || taskPanels[0];
    let baselineApplied = false;
    allPanels.forEach(function(panel) {
      panel.widgets().forEach(function(widget) {
        if (!isTaskManager(widget)) return;
        widget.currentConfigGroup = ["General"];
        const existing = widget.readConfig("launchers", []);
        const launchers = [];
        // Keep the existing order and custom pins, but replace generation-specific URLs.
        existing.forEach(function(launcher) {
          const match = launcher.match(/^file:\/\/\/(?:nix\/store\/[^/]+|run\/current-system\/sw)\/share\/applications\/([^/]+\.desktop)$/);
          const stable = match ? "applications:" + match[1] : launcher;
          launchers.push(stable);
        });
        // Add the baseline to one taskbar without replacing any panel or widget.
        if (!baselineApplied && panel === baselinePanel) {
          baseline.forEach(function(launcher) {
            if (launchers.indexOf(launcher) === -1 &&
                !(launcher === "applications:org.kde.dolphin.desktop" && launchers.indexOf("preferred://filemanager") !== -1)) {
              launchers.push(launcher);
            }
          });
          baselineApplied = true;
        }
        if (JSON.stringify(launchers) !== JSON.stringify(existing)) {
          widget.writeConfig("launchers", launchers);
          widget.reloadConfig();
        }
      });
    });
  '';
  taskbarScriptFile = pkgs.writeText "plasma-launchers.js" taskbarScript;
in
{
  # The copied desktop entries use gio via the stable per-user profile path.
  home.packages = [ (lib.getBin pkgs.glib) ];

  # Plasma Manager runs this when a session starts, including after offline rebuilds.
  programs.plasma.startup.desktopScript.launchers = {
    text = taskbarScript;
    runAlways = true;
  };

  # Also update a running session during rebuild; the login hook is the fallback.
  home.activation.plasmaTaskbarLaunchers = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    user_bus="/run/user/$(id -u)/bus"
    if [ -S "$user_bus" ]; then
      ${pkgs.systemd}/bin/busctl --address="unix:path=$user_bus" call \
        org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell evaluateScript s \
        "$(< ${taskbarScriptFile})" >/dev/null 2>&1 || true
    fi
  '';

  home.activation.plasmaDesktopLaunchers = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    desktop_dir="$(${pkgs.xdg-user-dirs}/bin/xdg-user-dir DESKTOP)"
    mkdir -p "$desktop_dir"

    # Repair existing store-backed links and simple absolute Exec commands only
    # when the corresponding application is available through a stable profile.
    for target in "$desktop_dir"/*.desktop; do
      if [ -L "$target" ]; then
        old_target="$(readlink "$target")"
        case "$old_target" in
          /nix/store/*/share/applications/*.desktop)
            application="''${old_target##*/}"
            for source in \
              "$HOME/.local/share/flatpak/exports/share/applications/$application" \
              "/etc/profiles/per-user/${config.home.username}/share/applications/$application" \
              "$HOME/.nix-profile/share/applications/$application" \
              "/run/current-system/sw/share/applications/$application" \
              "/var/lib/flatpak/exports/share/applications/$application"; do
              if [ -f "$source" ]; then
                ln -sfn "$source" "$target"
                break
              fi
            done
            ;;
        esac
      elif [ -f "$target" ] && [ -w "$target" ]; then
        command_line="$(${pkgs.kdePackages.kconfig}/bin/kreadconfig6 --file "$target" --group 'Desktop Entry' --key Exec)"
        if [[ "$command_line" =~ ^/nix/store/[^/]+/bin/([^/[:space:]]+)(.*)$ ]]; then
          executable="''${BASH_REMATCH[1]}"
          arguments="''${BASH_REMATCH[2]}"
          for executable_dir in "/etc/profiles/per-user/${config.home.username}/bin" "$HOME/.nix-profile/bin" /run/current-system/sw/bin; do
            if [ -x "$executable_dir/$executable" ]; then
              ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 --file "$target" --group 'Desktop Entry' --key Exec \
                "$executable_dir/$executable$arguments"
              break
            fi
          done
        fi
      fi
    done

    # Create writable baseline entries, replacing only recognized application
    # symlinks; custom files and other symlinks are left alone.
    for application in ${lib.escapeShellArgs desktopApplications}; do
      source="/run/current-system/sw/share/applications/$application"
      target="$desktop_dir/$application"
      replace_link=false
      if [ -L "$target" ]; then
        link_target="$(readlink "$target")"
        case "$link_target" in
          "$HOME/.local/share/flatpak/exports/share/applications/$application"|\
          "/etc/profiles/per-user/${config.home.username}/share/applications/$application"|\
          "$HOME/.nix-profile/share/applications/$application"|\
          "/run/current-system/sw/share/applications/$application"|\
          "/var/lib/flatpak/exports/share/applications/$application")
            source="$link_target"
            replace_link=true
            ;;
        esac
      fi
      if [ -f "$source" ] && { [ "$replace_link" = true ] || { [ ! -e "$target" ] && [ ! -L "$target" ]; }; }; then
        cp --remove-destination --no-preserve=mode "$source" "$target"
        chmod u+wx "$target"
        ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 --file "$target" --group 'Desktop Entry' --key Exec \
          "/etc/profiles/per-user/${config.home.username}/bin/gio launch $source %U"
      fi
    done
  '';
}