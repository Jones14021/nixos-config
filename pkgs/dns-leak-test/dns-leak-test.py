#!/usr/bin/env python3
import urllib.request
import json
import subprocess
import time
import os
import random
import string

def check_browser_doh():
    print("===========================================")
    print("🌐 Testing Browser DoH (DNS over HTTPS)")
    
    try:
        wg_iface = subprocess.check_output(['sudo', 'wg', 'show', 'interfaces'], stderr=subprocess.DEVNULL).decode().strip().split('\n')[0]
    except Exception as e:
        print(f"❌ Sudo required to read interfaces: {e}")
        return

    if not wg_iface:
        print("⚠️  VPN is not active. Please start the VPN first.")
        return

    # Check if tcpdump is available
    subprocess.check_output(['tcpdump', '--version'], stderr=subprocess.DEVNULL).decode().strip().split('\n')[0]

    # Generate a unique test domain
    random_str = ''.join(random.choices(string.ascii_lowercase + string.digits, k=12))
    test_domain = f"{random_str}.bash.ws"
    pcap_file = "/tmp/doh_test.pcap"

    print(f"   [Starting packet capture on {wg_iface} for Port 53...]")

    # Start tcpdump in the background writing to a file
    # -s 0: Capture full packet payload
    # -U: Write immediately to file without buffering
    tcpdump = subprocess.Popen(
        ['sudo', 'tcpdump', '-i', wg_iface, '-n', '-s', '0', '-U', 'udp', 'port', '53', '-w', pcap_file],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    time.sleep(1)

    print("\n   👉 ACTION REQUIRED: Open your web browser and navigate to:")
    print(f"   http://{test_domain}")
    print("   (It is normal if the browser says 'Site not found')")
    
    # Wait for the user to click the link
    input("\n   Press [ENTER] here *after* you have tried to load the page...")

    # Stop the capture
    subprocess.call(['sudo', 'kill', str(tcpdump.pid)])
    time.sleep(0.5)

    print("\n   🔍 Analyzing packet capture...")
    found = False
    
    # Read the pcap file, force ASCII output (-A), and search for our domain
    check_cmd = f"sudo tcpdump -A -r {pcap_file} 2>/dev/null | grep -i '{random_str}'"
    
    try:
        # Use subprocess.run to safely capture stdout and stderr without throwing an exception immediately
        result = subprocess.run(check_cmd, shell=True, text=True, capture_output=True)
        
        # grep returns 0 if match found, 1 if no match, 2 if error
        if result.returncode == 0:
            found = True
            print(f"      [Debug] grep found match:\n      {result.stdout.strip()}")
        elif result.returncode == 1:
            found = False
            print("      [Debug] grep finished successfully but found no matching packets.")
            
            # Since grep didn't find it, let's peek at what tcpdump ACTUALLY captured to see if it's empty
            debug_dump = subprocess.run(f"sudo tcpdump -r {pcap_file} 2>/dev/null | head -n 5", shell=True, text=True, capture_output=True)
            print(f"      [Debug] First 5 lines of pcap file:\n{debug_dump.stdout}")
        else:
            found = False
            print(f"      [Debug] Command failed with exit code {result.returncode}")
            print(f"      [Debug] STDOUT: {result.stdout}")
            print(f"      [Debug] STDERR: {result.stderr}")
            
    except Exception as e:
        found = False
        print(f"      [Debug] Python exception during analysis: {str(e)}")

    # Cleanup
    subprocess.call(['sudo', 'rm', '-f', pcap_file])

    print("\n   -------------------------------------------")
    if found:
        print("   ✅ PASS: DoH is OFF.")
        print("      Your browser successfully sent a standard UDP Port 53 query.")
        print("      It is safely routed through the VPN tunnel.")
    else:
        print("   ❌ FAIL: DoH is ON (or traffic bypassed the VPN).")
        print("      Your browser hid the DNS query using HTTPS.")
        print("      Please disable 'Secure DNS' in your browser settings!")
    
    print("===========================================")

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
    check_browser_doh()
