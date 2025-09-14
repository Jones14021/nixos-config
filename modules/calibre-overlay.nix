{ pkgs, lib, ... }:

let
  calibreOverlay = self: super: {
    calibre = super.calibre.overrideAttrs (old: {
      propagatedBuildInputs =
        (old.propagatedBuildInputs or [ ])
        ++ [ super.python3Packages.pycryptodome ]; # required for DeDRM plugin
    });
  };
in
{
  nixpkgs.overlays = [ calibreOverlay ];
}
