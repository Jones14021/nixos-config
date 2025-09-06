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
    home-manager.url = "github:nix-community/home-manager/release-25.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nixosConfEditor.url = "github:snowfallorg/nixos-conf-editor";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, nixosConfEditor, ... }: let

    allHosts = [
      {
        name = "nixoldie";
        system = "x86_64-linux";
        hardwareConfig = ./hosts/nixoldie/hardware-configuration.nix;
        config = ./hosts/nixoldie/configuration.nix;
        home = ./home/jonas.nix;
      }
      # , { name = "otherhost"; ... }
    ];

  in {
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
              home-manager.users.jonas = import host.home;
            }
          ];
          # Pass all flake package inputs as specialArgs
          specialArgs = {
            nixosConfEditor = nixosConfEditor;
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
