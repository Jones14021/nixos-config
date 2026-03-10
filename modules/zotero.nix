{ config, lib, pkgs, ... }:

let
  # 1. Fetch the Better BibTeX plugin (.xpi file)
  betterBibtex = pkgs.fetchurl {
    url = "https://github.com/retorquere/zotero-better-bibtex/releases/download/v9.0.7/zotero-better-bibtex-9.0.7.xpi";
    sha256 = "sha256-adrEhUdOw5V+Ln+ua02mJIyZo4CcY48/9kAMjxpD9HA=";
  };

  # 2. Override the default Zotero package
  zoteroWithPlugins = pkgs.zotero.overrideAttrs (oldAttrs: {
    # Append to the postInstall phase to inject the plugin
    postInstall = (oldAttrs.postInstall or "") + ''
      # The UUID must match exactly what the plugin author defines
      PLUGIN_DIR="$out/lib/zotero/distribution/extensions/better-bibtex@retorquere.zotero.org"
      
      mkdir -p "$PLUGIN_DIR"
      
      # Extract the plugin directly into Zotero's system-wide extension folder
      ${pkgs.unzip}/bin/unzip -q ${betterBibtex} -d "$PLUGIN_DIR"
    '';
  });

in
{
  # Add our custom Zotero derivation to the system packages
  environment.systemPackages = [
    zoteroWithPlugins
  ];
}
