{ pkgs, ... }:
let 
    version = "4.15.0";
in
{
    # Optional: pin version
    #nixpkgs.overlays = [
    #    (final: prev: {
    #        snapmaker-luban = prev.snapmaker-luban.overrideAttrs (old: rec {               
    #            src = prev.fetchurl {
    #            url = "https://github.com/Snapmaker/Luban/releases/download/v${version}/snapmaker-luban-${version}-linux-x64.tar.gz";
    #            # put fake sha256 to update: sha256-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX=
    #            hash = "sha256-VNIuOsRTS5qsq4IK1G6NSidNNEgziHGTNGvDKwjPO70=";
    #            };
    #        });
    #    })
    #];

    #nixpkgs.config.permittedInsecurePackages = [
    #    "snapmaker-luban-${version}"
    #];
}
