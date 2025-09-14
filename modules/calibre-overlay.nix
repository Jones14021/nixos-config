{ pkgs, lib, ... }:

let

  # known working versions with dedrm - calibre
  #
  # calibre 8.4.0  <->  dedrm v10.0.3

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
