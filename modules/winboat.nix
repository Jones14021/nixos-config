{ config, pkgs, lib, ... }:

let
  version = "0.8.5";
  # URL of the AppImage asset.
  winboatUrl = "https://github.com/TibixDev/winboat/releases/download/v${version}/WinBoat-${version}-x86_64.AppImage";  
  # put fake sha256 to update: sha256-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX=
  winboatSha256 = "sha256-UdzRw3dpggI4aF9DTrrBo9J1dn2tYcY7cQMrMIf51gI=";
  # Desktop entry metadata
  desktopName = "WinBoat";
  desktopComment = "Run Windows apps on Linux with seamless integration";
  desktopCategories = "Utility;System;";
in
{
  # define service
  options.services.winboat-appimage = {
    enable = lib.mkEnableOption "WinBoat AppImage";
    packageName = lib.mkOption {
      type = lib.types.str;
      default = "winboat";
      description = "Name for the resulting package on PATH.";
    };
  };

  config = lib.mkIf config.services.winboat-appimage.enable {

    # AppImage runtime support system-wide.
    programs.appimage = {
      enable = true;
      binfmt = true; # allows executing AppImages directly
      # Optionally extend runtime libraries if needed for some AppImages.
      # package = pkgs.appimage-run.override { extraPkgs = pkgs: with pkgs; [ libepoxy brotli ]; };
    };

    # iptables/iptable_nat specifically called out by upstream docs
    networking.firewall.enable = lib.mkDefault true;

    # Package WinBoat AppImage as a normal Nix package with desktop integration.
    environment.systemPackages = let
      winboatAppImage = pkgs.fetchurl {
        url = winboatUrl;
        sha256 = winboatSha256;
      };

      # https://nixos.org/manual/nixpkgs/stable/#sec-pkgs-appimageTools
      winboatPkg = pkgs.appimageTools.wrapType2 {
        pname = config.services.winboat-appimage.packageName;
        src = winboatAppImage;
        version = version;

        extraPkgs = pkgs: [ ]; # add runtime libs if WinBoat AppImage demands extras

        extraInstallCommands = ''
          # Try to extract desktop entry and icon if they exist in the AppImage
          if [ -d "$out/share/applications" ]; then
            sed -i 's|^Exec=.*|Exec=${config.services.winboat-appimage.packageName} %U|' "$out/share/applications/"*.desktop || true
            sed -i 's|^TryExec=.*|TryExec=${config.services.winboat-appimage.packageName}|' "$out/share/applications/"*.desktop || true
            # Ensure Categories/Name/Comment are sensible fallbacks
            for f in "$out/share/applications/"*.desktop; do
              grep -q '^Name=' "$f" || echo "Name=${desktopName}" >> "$f"
              grep -q '^Comment=' "$f" || echo "Comment=${desktopComment}" >> "$f"
              grep -q '^Categories=' "$f" || echo "Categories=${desktopCategories}" >> "$f"
            done
          else
            mkdir -p "$out/share/applications"
            cat > "$out/share/applications/${config.services.winboat-appimage.packageName}.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=${desktopName}
Comment=${desktopComment}
Exec=${config.services.winboat-appimage.packageName} %U
Terminal=false
Categories=${desktopCategories}
StartupWMClass=WinBoat
EOF
          fi
        '';
      };
    in
      [
        winboatPkg
        pkgs.freerdp # prerequisite for winboat
      ];
  };
}
