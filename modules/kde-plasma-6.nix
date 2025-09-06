{ pkgs, ... }:

{
  services.xserver.enable = true;
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;
  services.displayManager.sddm.autoNumlock = true;
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
