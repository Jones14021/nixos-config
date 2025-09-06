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
    home-manager.url = "github:nix-community/home-manager/release-25.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nixosConfEditor.url = "github:snowfallorg/nixos-conf-editor";
  };

  outputs = { self, nixpkgs, home-manager, nixosConfEditor, ... }: let

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
            # add more flake packages here if needed
          };
        };
      }) allHosts
    );
  };
}
