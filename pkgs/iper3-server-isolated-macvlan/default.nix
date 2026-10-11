{ pkgs }:

let
  dhcpHook = pkgs.writeShellScript "iperf-isolated-dhcp-hook" (builtins.readFile ./dhcp-hook.sh);
in
pkgs.writeShellApplication {
  name = "iper3-server-isolated-macvlan";

  runtimeInputs = [
    pkgs.iproute2
    pkgs.iperf3
    pkgs.busybox
    pkgs.coreutils
    pkgs.gnugrep
    pkgs.gawk
  ];

  text = ''
    export DHCP_HOOK_PATH="${dhcpHook}"
    export IP_BIN="${pkgs.iproute2}/bin/ip"
    ${builtins.readFile ./iper3-server-isolated-macvlan.sh}
  '';

  meta = {
    description = "Interactive isolated IPv4 iperf3 server using macvlan";
    mainProgram = "iper3-server-isolated-macvlan";
    platforms = pkgs.lib.platforms.linux;
  };
}
