/*
  Jonas's Snapmaker 2.0 A350T has a Quick Swap Kit, dual-extrusion printhead,
  and 10 W laser. Cura is for 3D printing with the dual extruder; laser jobs
  still use a laser-capable application such as Snapmaker Luban.

  Install Snapmaker's official Cura plugin and its printer, extruder, material,
  quality, and G-code support for the version of Cura installed by cura.nix.
  The A350 machine definition uses the published Quick Swap work area, assuming
  no Bracing Kit. Cura's printer instances and print settings remain writable.

  On first use, add the non-networked "Snapmaker 2 A350 Dual Extruder" whose
  profile author is "Snapmaker". Cura also bundles an identically named profile
  with an unknown author. Prefer the plugin's profile for this setup: it uses
  Snapmaker's dual-extruder profiles and Snapmaker-flavor G-code, and the work
  area below applies to it, not to the bundled profile. This is not a claim of
  better print quality; the plugin has open reports involving temperatures and
  tool changes, so verify settings and supervise initial prints.
  Check X/Y/Z in Cura's Machine Settings before printing: existing printer
  settings can override these defaults, and an oversized job can hit travel
  limits with the Quick Swap Kit installed.
  https://wiki.snapmaker.com/en/Snapmaker_Luban/cura_plugin
  https://forum.snapmaker.com/t/snapmaker-provided-machine-configurations-in-cura/36871
  https://github.com/Snapmaker/SnapmakerCuraPlugin/issues

  The plugin uses UDP broadcast discovery, which does not cross Tailscale.
  Export "Snapmaker Flavor G-code" and upload it with sm2uploader using the
  printer's reachable address. Pass -knownhosts a writable path outside the
  Nix store to persist its token.
*/
{ lib, pkgs, ... }:

let
  # A350 dual extruder with Quick Swap, without a Bracing Kit, in millimeters.
  # Adjust these values if the physical setup changes:
  # https://support.snapmaker.com/hc/en-us/articles/20786910972311
  workArea = {
    width = 320;  # X
    depth = 315;  # Y
    height = 270; # Z
  };

  # Cura stores plugins and definitions under its major.minor version.
  curaVersion = lib.versions.majorMinor pkgs.cura-appimage.version;

  # Pin Snapmaker's latest official release (0.9.4), including its resources.
  snapmakerPluginSource = pkgs.fetchFromGitHub {
    owner = "Snapmaker";
    repo = "SnapmakerCuraPlugin";
    rev = "717cd07ec4a18d6d4fb345e1f328a091f1dac4e3";
    hash = "sha256-ym02WiVLzCJ0N9CcXNZx9K7vFgO+x7GdCuS6xtDduqw=";
  };

  # Cura's plugin normally copies its resources from the plugin directory.
  # Nix store files are read-only, so use copyfile instead of copy2 to create
  # writable user copies. The A350 definition is deployed separately by Home
  # Manager and must not be overwritten when the plugin installs resources.
  snapmakerPlugin = pkgs.runCommand "snapmaker-cura-plugin-0.9.4-quickswap" {
    nativeBuildInputs = [ pkgs.jq ];
  } ''
    cp -R ${snapmakerPluginSource} "$out"
    chmod -R u+w "$out"

    substituteInPlace "$out/settings_plugin/SnapmakerSettingsPlugin.py" \
      --replace-fail 'if filename.endswith(".def.json"):' \
        'if filename.endswith(".def.json") and filename != "snapmaker_2_a350_dual_extruder.def.json":' \
      --replace-fail 'shutil.copy2(file_path, definition_dir)' 'shutil.copyfile(file_path, os.path.join(definition_dir, filename))' \
      --replace-fail 'shutil.copy2(file_path, extruder_dir)' 'shutil.copyfile(file_path, os.path.join(extruder_dir, filename))' \
      --replace-fail 'shutil.copy2(file_path, material_dir)' 'shutil.copyfile(file_path, os.path.join(material_dir, filename))' \
      --replace-fail 'dirs_exist_ok=True)' 'dirs_exist_ok=True, copy_function=shutil.copyfile)'

    definition="$out/resources/snapmaker_2_dual_extruder/definitions/snapmaker_2_a350_dual_extruder.def.json"
    jq --argjson width ${toString workArea.width} \
       --argjson depth ${toString workArea.depth} \
       --argjson height ${toString workArea.height} \
       '.overrides.machine_width.default_value = $width |
      .overrides.machine_depth.default_value = $depth |
      .overrides.machine_height.default_value = $height' "$definition" > "$definition.tmp"
    mv "$definition.tmp" "$definition"
  '';
in
{
  # Cura discovers this plugin at startup; it installs the remaining resources.
  xdg.dataFile."cura/${curaVersion}/plugins/SnapmakerJ1CuraPlugin".source = snapmakerPlugin;

  # Keep the adjusted machine definition declarative, including on plugin updates.
  xdg.dataFile."cura/${curaVersion}/definitions/snapmaker_2_a350_dual_extruder.def.json".source =
    "${snapmakerPlugin}/resources/snapmaker_2_dual_extruder/definitions/snapmaker_2_a350_dual_extruder.def.json";
}