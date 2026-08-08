# this file returns a function to build a per-system packages attrset
# it can be imported and used in outputs
# supply the "system" as the only argument

{ nixpkgs, erosanix }:
system:
let
  pkgs = import nixpkgs {
    inherit system;
    config = {
      allowUnfree = true;
      # self.packages.latex-vscode uses pkgs.vscode-with-extensions, which
      # currently depends on the EOL Electron 40 runtime.
      permittedInsecurePackages = [ "electron-40.10.5" ];
    };
  };
in
with (pkgs // erosanix.packages.${system} // erosanix.lib.${system});
{
  fusion360 = pkgs.callPackage ./pkgs/fusion360 {
    inherit mkWindowsApp makeDesktopIcon copyDesktopIcons;
    wine = wineWowPackages.base;
  };
  png2svg = pkgs.callPackage ./pkgs/png2svg { };
  text2img = pkgs.callPackage ./pkgs/text2img { };
  upscaler = pkgs.callPackage ./pkgs/upscaler { };
  bms-tools = pkgs.callPackage ./pkgs/bms-tools { };
  md2pdf = pkgs.callPackage ./pkgs/md2pdf { };
  dns-leak-test = pkgs.callPackage ./pkgs/dns-leak-test { };
  wireguard-extract-secrets = pkgs.callPackage ./pkgs/wireguard-extract-secrets { };
  vpn-tray = pkgs.callPackage ./pkgs/vpn-tray {
    inherit (pkgs.qt6Packages) wrapQtAppsHook qtbase qtwayland;
    inherit python3 systemd;
  };
  latex-vscode = pkgs.callPackage ./pkgs/latex-vscode { };
  sm2uploader = pkgs.callPackage ./pkgs/sm2uploader { };
  vidname = pkgs.callPackage ./pkgs/vidname { };
  pdf2md = pkgs.callPackage ./pkgs/pdf2md {
    llamaCpp = pkgs.llama-cpp;
  };
  # other packages here e.g.
    #package_name = pkgs.callPackage ./pkgs/someflake {
    #  inherit (anotherneededflake.packages.${system}) mkWindowsApp;
    #};
}
