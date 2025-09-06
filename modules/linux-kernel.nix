{ pkgs, ... }:

let
  pinnedKernel = pkgs.linux_6_12.override {
    argsOverride = rec {
      # pin kernel to 6.12.41 while tailscale networking is impacted
      # https://github.com/nixos/nixpkgs/issues/438765
      version = "6.12.41";
      src = pkgs.fetchurl {
        url = "mirror://kernel/linux/kernel/v6.x/linux-${version}.tar.xz";
        sha256 = "axmjrplCPeJBaWTWclHXRZECd68li0xMY+iP2H2/Dic=";
      };
      modDirVersion = version;
    };
  };
in
{
  boot.kernelPackages = pkgs.linuxPackagesFor pinnedKernel;
  #boot.kernelPackages = pkgs.linuxPackages_latest;
}
