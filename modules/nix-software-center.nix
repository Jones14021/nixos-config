{ pkgs, ... }:

let
  nixSoftwareCenterOverlay = self: super: {
    nix-software-center = super.callPackage (pkgs.fetchFromGitHub {
      owner = "ljubitje"; # for fixing the the ‘gnome.adwaita-icon-theme’ was moved to top-level error
      repo = "nix-software-center";
      rev = "0.1.3";
      sha256 = "HVnDccOT6pNOXjtNMvT9T3Op4JbJm2yMBNWMUajn3vk=";
    }) {};
  };
in
{
  nixpkgs.overlays = [ nixSoftwareCenterOverlay ];
}
