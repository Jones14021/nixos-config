# this file returns a function to build a per-system packages attrset
# it can be imported and used in outputs
# supply the "system" as the only argument

{ nixpkgs, erosanix }:
system:
let
  pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };
in
with (pkgs // erosanix.packages.${system} // erosanix.lib.${system});
{
  # other packages here e.g.
    #package_name = pkgs.callPackage ./pkgs/someflake {
    #  inherit (anotherneededflake.packages.${system}) mkWindowsApp;
    #};
}
