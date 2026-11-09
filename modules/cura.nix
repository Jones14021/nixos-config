{ pkgs, ... }:

{
  # SolidCraft's Send to Slicer discovers `cura` on PATH and starts it with
  # the exported 3MF/STL file. SolidCraft runs in a Flatpak, where Cura's
  # AppImage wrapper cannot create the nested bubblewrap sandbox it needs.
  # This wrapper uses the Flatpak host portal to start Cura outside the
  # sandbox with the same arguments; normal host launches remain unchanged.
  environment.systemPackages = [
    (pkgs.symlinkJoin {
      name = "cura-appimage-with-flatpak-bridge";
      paths = [
        (pkgs.writeShellScriptBin "cura" ''
          if [ -n "''${FLATPAK_ID:-}" ]; then
            exec /usr/bin/flatpak-spawn --host ${pkgs.cura-appimage}/bin/cura "$@"
          fi
          exec ${pkgs.cura-appimage}/bin/cura "$@"
        '')
        pkgs.cura-appimage
      ];
    })
  ];
}