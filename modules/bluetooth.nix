# https://wiki.nixos.org/wiki/Bluetooth
{ pkgs, lib, ... }:

{
    # Bluetooth support
    hardware.bluetooth.enable = true;
    services.blueman.enable = true; # depends on hardware.bluetooth.enable = true
}
