# If you want the same core package set across all machines,
# you should move your shared environment.systemPackages list into a separate NixOS module
# (e.g. modules/common-packages.nix) and import that module in every host-specific configuration.
# Do not put systemPackages directly in flake.nix. Modules and host configs should always
# own package and service configuration.

# rebuild via:
# sudo nixos-rebuild switch --flake ~/nixos-config#hostname

{
  description = "Scheisch dr nix bassiert dr nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    declarative-flatpak.url = "github:in-a-dil-emma/declarative-flatpak/v4.1.0";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    erosanix = {
      url = "github:emmanuelrosa/erosanix";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, plasma-manager, erosanix, declarative-flatpak, ... }: let

    allHosts = [
      {
        name = "nixoldie";
        system = "x86_64-linux";
        hardwareConfig = ./hosts/nixoldie/hardware-configuration.nix;
        config = ./hosts/nixoldie/configuration.nix;
        home = ./home/jonas.nix;
      }
      {
        name = "spectre";
        system = "x86_64-linux";
        hardwareConfig = ./hosts/spectre/hardware-configuration.nix;
        config = ./hosts/spectre/configuration.nix;
        home = ./home/jonas.nix;
      }
      # , { name = "otherhost"; ... }
    ];

    # get the function to get the per-system attrset for the contained packages
    mkPackages = import ./flake-packages.nix { inherit nixpkgs erosanix; };

  in {

    # add the packages returned by mkPackages to self.packages for different systems
    packages.x86_64-linux = mkPackages "x86_64-linux";
    # could for example do that for other systems/architectures here as well

    # Dynamically define all hosts using list above
    nixosConfigurations = builtins.listToAttrs (
      map (host: {
        name = host.name;
        value = nixpkgs.lib.nixosSystem {
          system = host.system;
          modules = [
            host.hardwareConfig
            host.config
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.sharedModules = [
                plasma-manager.homeModules.plasma-manager
              ];
              home-manager.users.jonas = import host.home;
            }
            declarative-flatpak.nixosModules.default
          ];
          # Pass all flake package inputs as specialArgs
          specialArgs = {
            inherit self;
            # ----- Why use legacyPackages? -----
            # * Most existing NixOS and Home Manager configurations expect pkgs to be a set of packages
            #   indexed by their names (pkgs.vim, pkgs.firefox, etc.).
            # * legacyPackages exposes this compatible package set from newer nixpkgs sources (like unstable or overlays).
            # * Without explicitly using legacyPackages, you might work with the newer packageOverrides
            #   or other evolving interfaces that can break backwards compatibility.
            unstablePkgs = nixpkgs-unstable.legacyPackages.x86_64-linux;
            # add more flake packages here if needed
          };
        };
      }) allHosts
    );
  };
}
