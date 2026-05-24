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
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    declarative-flatpak.url = "github:Jones14021/declarative-flatpak/modif_v4.1.6";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
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
            # Import unstable explicitly instead of reusing legacyPackages, because this host
            # needs custom nixpkgs config at evaluation time (for example allowUnfree for vscode).
            # legacyPackages is a convenient pre-instantiated package set and is fine when you
            # just want the default package set and good backwards compatibility, but it cannot be customized with config here.
            # The extra import is a small efficiency tradeoff that is worth it for the license policy.
            unstablePkgs = import nixpkgs-unstable {
              system = host.system;
              config.allowUnfree = true;
            };
            # add more flake packages here if needed
          };
        };
      }) allHosts
    );
  };
}
