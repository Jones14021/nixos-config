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
# 5. DoH (DNS over HTTPS):
#    Modern browsers like Chrome, Firefox, and Brave have DoH enabled by default.
#    DoH was designed to hide your DNS queries from your ISP by wrapping them inside
#    normal HTTPS traffic (TCP Port 443) and sending them to a third-party provider
#    like Cloudflare (1.1.1.1) or Google (8.8.8.8).
#    
#    The Result: You have effectively given your browsing history to a third-party
#    data broker (like Google or Cloudflare) instead of keeping it strictly within 
#    Windscribe's no-log ecosystem. When you run a DNS leak test, it will show Cloudflare's
#    servers instead of Windscribe's, which is often (mis)diagnosed as a leak.
#
#    The Fix: This configuration disables DoH in both Chromium-based browsers and Firefox,
#    forcing them to use the system's DNS resolver (systemd-resolved) which is
#    configured to route through the VPN tunnel to Windscribe's DNS servers. This way,
#    your DNS queries remain private and consistent with the VPN's no-log policy.
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

        # 1. Save current Tailscale DNS state, then disable it safely
        # We query the local tailscaled API for the raw preference boolean.
        TS_STATE_FILE="/run/wg-quick-${vpn.name}-ts-dns.state"
        
        # Check if tailscale is running and extract the CorpDNS (accept-dns) preference
        if ${pkgs.tailscale}/bin/tailscale status &>/dev/null; then
          TS_DNS_STATUS=$(${pkgs.tailscale}/bin/tailscale debug prefs | ${pkgs.jq}/bin/jq -r '.CorpDNS')
          ${pkgs.coreutils}/bin/echo "$TS_DNS_STATUS" > "$TS_STATE_FILE"
          
          # Tell Tailscale to stop hijacking DNS so Windscribe's DNS can take over
          if [ "$TS_DNS_STATUS" = "true" ]; then
            ${pkgs.tailscale}/bin/tailscale set --accept-dns=false
          fi
        else
          # Tailscale isn't running, write a dummy state
          ${pkgs.coreutils}/bin/echo "false" > "$TS_STATE_FILE"
        fi

        # 2. Allow WireGuard encrypted traffic out to Windscribe
        ${pkgs.iptables}/bin/iptables -I OUTPUT -d $ENDPOINT_IP -j ACCEPT
        ${pkgs.iptables}/bin/ip6tables -I OUTPUT -d $ENDPOINT_IP -j ACCEPT 2>/dev/null || true

        # 3. Apply the strict kill switch to the bottom of the chain
        ${pkgs.iptables}/bin/iptables -A OUTPUT ! -o ${vpn.name} -m mark ! --mark $(${pkgs.wireguard-tools}/bin/wg show ${vpn.name} fwmark) -m addrtype ! --dst-type LOCAL -j REJECT
        ${pkgs.iptables}/bin/ip6tables -A OUTPUT ! -o ${vpn.name} -m mark ! --mark $(${pkgs.wireguard-tools}/bin/wg show ${vpn.name} fwmark) -m addrtype ! --dst-type LOCAL -j REJECT
      '';

      preDown = lib.optionalString vpn.killswitch ''
        ENDPOINT_IP=$(${pkgs.coreutils}/bin/echo "${vpn.endpoint}" | ${pkgs.coreutils}/bin/cut -d: -f1)

        # Clean up the allow rules
        ${pkgs.iptables}/bin/iptables -D OUTPUT -d $ENDPOINT_IP -j ACCEPT
        ${pkgs.iptables}/bin/ip6tables -D OUTPUT -d $ENDPOINT_IP -j ACCEPT 2>/dev/null || true

        # Clean up the kill switch
        ${pkgs.iptables}/bin/iptables -D OUTPUT ! -o ${vpn.name} -m mark ! --mark $(${pkgs.wireguard-tools}/bin/wg show ${vpn.name} fwmark) -m addrtype ! --dst-type LOCAL -j REJECT
        ${pkgs.iptables}/bin/ip6tables -D OUTPUT ! -o ${vpn.name} -m mark ! --mark $(${pkgs.wireguard-tools}/bin/wg show ${vpn.name} fwmark) -m addrtype ! --dst-type LOCAL -j REJECT
        
        # Restore Tailscale MagicDNS ONLY if it was previously enabled
        TS_STATE_FILE="/run/wg-quick-${vpn.name}-ts-dns.state"
        if [ -f "$TS_STATE_FILE" ]; then
          WAS_ENABLED=$(${pkgs.coreutils}/bin/cat "$TS_STATE_FILE")
          if [ "$WAS_ENABLED" = "true" ]; then
            ${pkgs.tailscale}/bin/tailscale set --accept-dns=true
          fi
          ${pkgs.coreutils}/bin/rm -f "$TS_STATE_FILE"
        fi
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

  # Note: This setting applies to Google Chrome and Brave as well if they are
  # installed via Nixpkgs, as they inherit the Chromium enterprise policies.
  programs.chromium = {
    enable = true;
    extraOpts = {
      # This completely disables the "Use secure DNS" (DNS over HTTPS, DoH) setting in the browser,
      # forcing Chromium to use systemd-resolved (and therefore the VPN's DNS).
      "DnsOverHttpsMode" = "off";
    };
  };

  programs.firefox = {
    enable = true;
    policies = {
      # This locks the Firefox DoH setting to "Off" and prevents 
      # the user from accidentally toggling it back on in the GUI.
      "DNSOverHTTPS" = {
        "Enabled" = false;
        "Locked" = true;
      };
    };
  };
}
