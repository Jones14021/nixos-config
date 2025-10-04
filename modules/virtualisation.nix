# https://nixos.wiki/wiki/Docker

{ config, pkgs, lib, ... }:

{
    virtualisation.docker = {      
      enableOnBoot = true;
      daemon.settings = { };
    };

    virtualisation.docker.rootless = {
      enable = false; # not supported by WinBoat
    };

    environment.systemPackages = [
      pkgs.docker
      pkgs.docker-compose
    ];

    # KVM and kernel modules (common defaults for Intel/AMD; WinBoat requires KVM)
    boot.kernelModules = [
      "kvm"
      "kvm_intel"
      "kvm_amd"
      "tap"
      "tun"
      "br_netfilter"
      "iptable_nat"
      "ipt_REJECT"
      "nf_nat"
      "nf_conntrack"
    ];

}
