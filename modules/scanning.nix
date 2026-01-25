# https://nixos.wiki/wiki/Scanners

# if nothing works, tip: https://github.com/NixOS/nixpkgs/issues/217996
# --> VueScan

# find a scanner:
# sudo sane-find-scanner

# scanimage -L # List available scanners
# scanimage -d "scanner_name" > scan.pnm # Perform a scan

# utsushi backend disabled because it does not offer an obvious advantage

# vuescan proprietary app added because it offers a fallback support for a wide variety of scanners

{ pkgs, lib, ... }:
let
  vuescan = pkgs.callPackage ./vuescan.nix { };
in
{
    hardware.sane.enable = true;
    hardware.sane.extraBackends = [
        pkgs.sane-airscan # network scanning
        #pkgs.utsushi # Epson ImageScanV3 (utsushi) backend    
    ];

    environment.systemPackages = [
        #vuescan
    ];

    services.udev.packages = [
        #pkgs.utsushi
        #vuescan
    ];
}
