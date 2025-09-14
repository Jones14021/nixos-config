{ pkgs, ... }:

{
    # wrapper will be at /run/wrappers/bin/nethogs;
    # this path is placed early in PATH on NixOS, so running nethogs will hit the
    # capability-enabled wrapper without modifying the Nix store file
    security.wrappers.nethogs = {
        source = "${pkgs.nethogs}/bin/nethogs";
        owner = "root";
        group = "root";
        # https://gitlab.com/mission-center-devs/mission-center/-/wikis/Home/Nethogs
        capabilities = "cap_net_admin,cap_net_raw,cap_dac_read_search,cap_sys_ptrace+pe";
        permissions = "u+rx,g+rx,o+rx";
    };
}