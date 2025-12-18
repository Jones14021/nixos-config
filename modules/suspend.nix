{ config, pkgs, ... }:

{
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "suspend" ''
      exec systemctl suspend
    '')
  ];
}
