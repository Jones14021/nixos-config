#!/usr/bin/env python3
import urllib.request
import json
import subprocess
import os

def check_dns_leaks():
    print("🔍 Fetching IP and forcing DNS resolution (this takes a few seconds)...")
    
    try:
        # 1. Get a unique test ID
        with urllib.request.urlopen("https://bash.ws/id", timeout=5) as response:
            leak_id = response.read().decode("utf-8").strip()
        
        # 2. Ping 10 unique subdomains to force your computer's active DNS to resolve them
        with open(os.devnull, 'w') as devnull:
            for x in range(0, 10):
                host = f"{x}.{leak_id}.bash.ws"
                subprocess.call(['ping', '-c', '1', '-W', '1', host], stdout=devnull, stderr=devnull)

        # 3. Query the API to see who resolved those pings
        api_url = f"https://bash.ws/dnsleak/test/{leak_id}?json"
        with urllib.request.urlopen(api_url, timeout=5) as response:
            data = json.loads(response.read().decode("utf-8"))
            
    except Exception as e:
        print(f"❌ Failed to reach DNS leak API: {e}")
        print("   (Is the Kill Switch active without a VPN connection?)")
        return

    # Parse Results
    my_ip = "Unknown"
    dns_servers = []
    conclusion = "Unknown"
    
    for item in data:
        if item.get('type') == 'ip':
            my_ip = f"{item.get('ip')} [{item.get('country_name', 'Unknown')}, {item.get('asn', '')}]"
        elif item.get('type') == 'dns':
            dns_servers.append(f"{item.get('ip')} [{item.get('country_name', 'Unknown')}, {item.get('asn', '')}]")
        elif item.get('type') == 'conclusion':
            conclusion = item.get('ip', '')

    print("===========================================")
    print(f"🌍 Public IP:       {my_ip}")
    print("===========================================")
    print("🛡️  DNS Servers visible to the internet:")
    
    if not dns_servers:
        print("   ⚠️  No DNS servers detected.")
    else:
        for dns in dns_servers:
            print(f"   - {dns}")

    print("-------------------------------------------")
    # Highlight the API's conclusion (usually "DNS is leaking" or "DNS is not leaking")
    if "not" in conclusion.lower() or "good" in conclusion.lower() or "no leak" in conclusion.lower():
        print(f"   ✅ API Conclusion: {conclusion}")
    else:
        print(f"   ❌ API Conclusion: {conclusion}")
    print("===========================================")

def check_kill_switch():
    print("🧪 Initiating Kill Switch Probe...")
    
    # Needs sudo to read wireguard config
    try:
        wg_show = subprocess.check_output(['sudo', 'wg', 'show', 'interfaces'], stderr=subprocess.DEVNULL).decode().strip()
        wg_iface = wg_show.split('\n')[0] if wg_show else ""
    except Exception:
        print("❌ Please run this script with sudo privileges to test the Kill Switch.")
        return

    if not wg_iface:
        print("⚠️  No active WireGuard interface found. Skipping routing probe.")
        return

    try:
        endpoint_raw = subprocess.check_output(['sudo', 'wg', 'show', wg_iface, 'endpoints']).decode().strip()
        # Extract just the IP, stripping the port
        endpoint = endpoint_raw.split()[1].split(':')[0]
    except Exception:
        print("❌ Failed to extract Endpoint IP. Aborting probe.")
        return

    if not endpoint:
        print("❌ Failed to extract Endpoint IP. Aborting probe.")
        return

    print(f"   Active Interface: {wg_iface}")
    print(f"   Endpoint IP: {endpoint}")
    print("   -> Blackholing endpoint to simulate tunnel crash...")
    
    subprocess.call(['sudo', 'ip', 'route', 'add', 'blackhole', endpoint])
    
    # Try to reach Cloudflare DNS
    res = subprocess.call(['curl', '-s', '--max-time', '3', 'https://1.1.1.1'], stdout=subprocess.DEVNULL)
    
    if res == 0:
        print("   ❌ FAIL: Traffic successfully bypassed the VPN! Kill switch is inactive.")
    else:
        print("   ✅ PASS: Internet access blocked. Kill switch works.")
        
    subprocess.call(['sudo', 'ip', 'route', 'del', 'blackhole', endpoint])
    print("   -> Routing restored.")

if __name__ == '__main__':
    check_dns_leaks()
    check_kill_switch()
