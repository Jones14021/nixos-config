{ config, pkgs, lib, ... }:

{
  programs.git = {
    enable = true;
    userName = "HOERMANN Jonas";
    userEmail = "jonashoermann12@gmail.com";
    extraConfig = {
        init.defaultBranch = "main";
        core.editor = "code --wait";
        credential.helper = "store";
    };
  };
}