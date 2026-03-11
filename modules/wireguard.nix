{ config, pkgs, lib, ... }:

# ==============================================================================
# WireGuard VPN Configuration & Kill Switch Implementation
# ==============================================================================
# 
# THE SECURITY MODEL: KERNEL-LEVEL KILL SWITCH
# This configuration bypasses user-space managers (like NetworkManager) and 
# interacts directly with the Linux kernel via `wg-quick` and `iptables`.
# WireGuard tags its encrypted UDP packets with a  cryptographic `fwmark`.
# When `killswitch = true`, the injected iptables rules instruct the kernel to 
# violently REJECT any outbound packet that lacks this mark, unless it is 
# traveling locally (localhost).
#
# If `killswitch = true` and `allowedIPs = [ "0.0.0.0/0" "::/0" ]`, traditional 
# leaks of your public ISP IP address are virtually impossible. 
# - DNS Leaks: If systemd-resolved tries to bypass the VPN, the kernel drops the 
#   packet. Your DNS simply breaks instead of leaking.
# - IPv6 Leaks: If your VPN is IPv4-only, IPv6 traffic is dropped by ip6tables.
#   It will not leak to your ISP.
#
# CAVEATS & RISKS TO CONSIDER:
# 1. Split Tunneling Danger: If you set `killswitch = false` and define specific 
#    `allowedIPs` (e.g., just routing a corporate subnet), all other traffic 
#    falls back to your ISP. This exposes you to normal DNS and WebRTC leaks.
# 2. Captive Portals: Public Wi-Fi login pages (hotels, airports) will NOT work 
#    while the kill switch is active. The portal's HTTP intercept traffic will 
#    be blocked. You must disable the VPN to log in, exposing your traffic 
#    temporarily.
# 3. LAN Isolation: The strict iptables rules block access to your local network 
#    (e.g., 192.168.1.x) to prevent gateway bypass attacks. If you need to print 
#    or SSH into local machines, you must add explicit iptables ACCEPT rules 
#    for your local subnet, which introduces a slight risk if a malicious app 
#    binds to your local gateway.
# 4. WebRTC Local IP Leaks: While WebRTC cannot leak your public ISP IP with 
#    this kill switch, browsers can still discover your machine's local IP 
#    (e.g., 192.168.1.45) and transmit it as text inside the encrypted tunnel to 
#    the destination website.
#
# ==============================================================================

# To start, stop, or restart the VPN, you must use systemd:
#
# Start: sudo systemctl start wg-quick-Dallas-BBQ-WG
#
# Stop: sudo systemctl stop wg-quick-Dallas-BBQ-WG
#
# Status: systemctl status wg-quick-Dallas-BBQ-WG

let
  # Define your VPN configurations here.
  # Set `killswitch = true` to enable the strict iptables lock.
  vpns = [
# Example WireGuard VPN configuration for Windscribe's Dallas server.
#    {
#      name = "wg-dallas";
#      address = [ "10.255.255.2/32" ];
#      dns = [ "10.255.255.3" ];
#      privateKeyFile = "/var/lib/wireguard/keys/wg-dallas.key";
#      publicKey = "<windscribe_server_public_key>";
#      endpoint = "<windscribe_endpoint_ip>:51820";
#      
#      # For a full tunnel, use 0.0.0.0/0 and ::/0.
#      # For a split tunnel, define specific subnets here AND set killswitch = false.
#      allowedIPs = [ "0.0.0.0/0" "::/0" ]; 
#      killswitch = true; 
#    }
    {
        name = "Dallas-BBQ-WG";
        description = "Windscribe-Dallas-BBQ-WG";
        address = [ "100.126.215.198/32" ];
        dns = [ "10.255.255.2" ];
        privateKeyFile = "/var/lib/wireguard/keys/Windscribe-Dallas-BBQ-WG.key";
        presharedKeyFile = "/var/lib/wireguard/keys/Windscribe-Dallas-BBQ-WG.psk";
        publicKey = "47tLjymDPpTIBerb+wn02/XNFABF4YDAGwOnijSoZmQ=";
        endpoint = "dfw-192-wg.whiskergalaxy.com:443";
        allowedIPs = [ "0.0.0.0/0" "::/0" ];
        killswitch = true;
    }
  ];

  mkInterface = vpn: {
    name = vpn.name;
    value = {
      # Do not start automatically on boot or rebuild
      autostart = false;

      address = vpn.address;
      dns = vpn.dns;
      privateKeyFile = vpn.privateKeyFile;
      
      peers = [{
        publicKey = vpn.publicKey;
        presharedKeyFile = if vpn ? presharedKeyFile then vpn.presharedKeyFile else null;
        allowedIPs = vpn.allowedIPs;
        endpoint = vpn.endpoint;
        persistentKeepalive = 25;
      }];

      postUp = lib.optionalString vpn.killswitch ''
        ENDPOINT_IP=$(${pkgs.coreutils}/bin/echo "${vpn.endpoint}" | ${pkgs.coreutils}/bin/cut -d: -f1)

        # Tell Tailscale to stop hijacking DNS so Windscribe's DNS can take over
        ${pkgs.tailscale}/bin/tailscale set --accept-dns=false

        # 1. Allow WireGuard encrypted traffic out to Windscribe
        ${pkgs.iptables}/bin/iptables -I OUTPUT -d $ENDPOINT_IP -j ACCEPT
        ${pkgs.iptables}/bin/ip6tables -I OUTPUT -d $ENDPOINT_IP -j ACCEPT 2>/dev/null || true

        # 2. Allow Tailscale heartbeat/control traffic to bypass the kill switch
        ${pkgs.iptables}/bin/iptables -I OUTPUT -o tailscale0 -j ACCEPT
        ${pkgs.iptables}/bin/ip6tables -I OUTPUT -o tailscale0 -j ACCEPT 2>/dev/null || true

        # 3. Apply the strict kill switch to the bottom of the chain
        ${pkgs.iptables}/bin/iptables -A OUTPUT ! -o ${vpn.name} -m mark ! --mark $(${pkgs.wireguard-tools}/bin/wg show ${vpn.name} fwmark) -m addrtype ! --dst-type LOCAL -j REJECT
        ${pkgs.iptables}/bin/ip6tables -A OUTPUT ! -o ${vpn.name} -m mark ! --mark $(${pkgs.wireguard-tools}/bin/wg show ${vpn.name} fwmark) -m addrtype ! --dst-type LOCAL -j REJECT
      '';

      preDown = lib.optionalString vpn.killswitch ''
        ENDPOINT_IP=$(${pkgs.coreutils}/bin/echo "${vpn.endpoint}" | ${pkgs.coreutils}/bin/cut -d: -f1)

        # Clean up the allow rules
        ${pkgs.iptables}/bin/iptables -D OUTPUT -d $ENDPOINT_IP -j ACCEPT
        ${pkgs.iptables}/bin/ip6tables -D OUTPUT -d $ENDPOINT_IP -j ACCEPT 2>/dev/null || true

        ${pkgs.iptables}/bin/iptables -D OUTPUT -o tailscale0 -j ACCEPT
        ${pkgs.iptables}/bin/ip6tables -D OUTPUT -o tailscale0 -j ACCEPT 2>/dev/null || true

        # Clean up the kill switch
        ${pkgs.iptables}/bin/iptables -D OUTPUT ! -o ${vpn.name} -m mark ! --mark $(${pkgs.wireguard-tools}/bin/wg show ${vpn.name} fwmark) -m addrtype ! --dst-type LOCAL -j REJECT
        ${pkgs.iptables}/bin/ip6tables -D OUTPUT ! -o ${vpn.name} -m mark ! --mark $(${pkgs.wireguard-tools}/bin/wg show ${vpn.name} fwmark) -m addrtype ! --dst-type LOCAL -j REJECT
        
        # Restore Tailscale MagicDNS now that the VPN tunnel is closed
        ${pkgs.tailscale}/bin/tailscale set --accept-dns=true
      '';
    };
  };
in
{
  networking.wg-quick.interfaces = builtins.listToAttrs (map mkInterface vpns);
  # Tell NetworkManager to completely ignore these specific VPN interfaces 
  # so it doesn't break the DNS or the iptables kill switch for
  # interfaces that it doesn't manage. You must control these interfaces manually via systemd.
  networking.networkmanager.unmanaged = map (vpn: vpn.name) vpns;

  # Allow wheel users to start/stop wg-quick interfaces without sudo
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          action.lookup("unit").startsWith("wg-quick-") &&
          subject.isInGroup("wheel")) {
          return polkit.Result.YES;
      }
    });
  '';
}
