{ pkgs, ... }:

{
  services.xserver.enable = true;
  services.displayManager.plasma-login-manager.enable = true;
  services.desktopManager.plasma6.enable = true;
  services.xserver.xkb = { layout = "de"; variant = ""; };
  console.keyMap = "de";

  environment.systemPackages = with pkgs;
  [
    kdePackages.kate
    kdePackages.isoimagewriter
    kdePackages.partitionmanager
    kdePackages.kcalc
  ];
}
