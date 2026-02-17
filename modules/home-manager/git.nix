{ config, pkgs, lib, ... }:

{
  programs.git = {
    enable = true;
    settings = {
        user = {
            name = "HOERMANN Jonas";
            email = "jonashoermann12@gmail.com";
        };
        init = {
            defaultBranch = "main";
        };
        core = {
            editor = "code --wait";
        };
        credential = {
            helper = "store";
        };
    };
  };
}