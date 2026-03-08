#!/usr/bin/env bash
# Exit immediately if a command exits with a non-zero status
set -e

TMP_PORT="/tmp/ttyBLE_BMS"
# Using ttyS2000 as it matches pyserial's 'ttyS*' regex without conflicting 
# with actual hardware ttyS0-ttyS31 ports.
TARGET_TTY="/dev/ttyS2000"
BLE_PID=""
MAC=""
LOG_FILE=""

cleanup() {
    # Prevent trap from firing multiple times if wait gets interrupted
    trap - SIGINT SIGTERM
    echo -e "\n[+] Caught CTRL+C or exiting. Cleaning up..."
    
    if [ -n "$BLE_PID" ] && kill -0 "$BLE_PID" 2>/dev/null; then
        echo "[+] Stopping ble-serial background process (PID $BLE_PID)..."
        kill "$BLE_PID" 2>/dev/null || true
        wait "$BLE_PID" 2>/dev/null || true
    fi

    if [ -L "$TARGET_TTY" ]; then
        echo "[+] Removing GUI symlink $TARGET_TTY (requires sudo)..."
        sudo rm -f "$TARGET_TTY" 2>/dev/null || true
    fi

    if [ -n "$MAC" ]; then
        echo "[+] Removing $MAC from BlueZ cache to ensure a clean state next time..."
        bluetoothctl remove "$MAC" >/dev/null 2>&1 || true
    fi

    if [ -f "$LOG_FILE" ]; then
        rm -f "$LOG_FILE"
    fi

    echo "[+] Cleanup complete. Have a nice day!"
    exit 0
}

# Trap signals to run the cleanup function
trap cleanup SIGINT SIGTERM

echo "[+] Checking Bluetooth status..."
if ! command -v bluetoothctl &> /dev/null; then
    echo "[-] bluetoothctl not found. Please ensure bluez is installed."
    exit 1
fi

echo "[+] Powering on Bluetooth..."
bluetoothctl power on >/dev/null

echo "======================================================"
echo " Scanning for BLE devices (this takes a few seconds)..."
echo "======================================================"

# Run ble-scan and capture the output
SCAN_OUTPUT=$(ble-scan)

# Create arrays to hold MAC addresses and full display names
declare -a MAC_LIST
declare -a DISPLAY_LIST
INDEX=1
DEFAULT_INDEX=""

echo ""
echo "Available Devices:"

# Process the scan output line by line. We only care about lines starting with a MAC address.
while read -r line; do
    if [[ "$line" =~ ^([0-9A-Fa-f:]{17}) ]]; then
        mac="${BASH_REMATCH[1]}"
        # Store for array indexing
        MAC_LIST[$INDEX]=$mac
        DISPLAY_LIST[$INDEX]="$line"
        
        # Look for the target string "DP" to set as default (usually the ELF Hub battery)
        if [[ -z "$DEFAULT_INDEX" && "$line" == *"DP"* ]]; then
            DEFAULT_INDEX=$INDEX
            echo -e "  [$INDEX] $line  <-- (Suggested Default)"
        else
            echo "  [$INDEX] $line"
        fi
        ((INDEX++))
    fi
done <<< "$SCAN_OUTPUT"

# If no devices were found, exit early
if [ ${#MAC_LIST[@]} -eq 0 ]; then
    echo "[-] No BLE devices found. Is your Bluetooth working properly?"
    exit 1
fi

echo ""
# Prompt user with the default option if a "DP*" device was found
if [ -n "$DEFAULT_INDEX" ]; then
    read -p "Select a device number [leave empty for default: $DEFAULT_INDEX]: " USER_SELECTION
    if [ -z "$USER_SELECTION" ]; then
        USER_SELECTION=$DEFAULT_INDEX
    fi
else
    read -p "Select a device number: " USER_SELECTION
fi

# Validate user input
if ! [[ "$USER_SELECTION" =~ ^[0-9]+$ ]] || [ "$USER_SELECTION" -lt 1 ] || [ "$USER_SELECTION" -ge "$INDEX" ]; then
    echo "[-] Invalid selection. Exiting."
    exit 1
fi

MAC=${MAC_LIST[$USER_SELECTION]}
# Convert MAC to uppercase for bluetoothctl compatibility
MAC=$(echo "$MAC" | tr 'a-z' 'A-Z')

echo "[+] Selected: ${DISPLAY_LIST[$USER_SELECTION]}"
echo "[+] Removing $MAC from BlueZ cache to prevent stale connection errors..."
bluetoothctl remove "$MAC" >/dev/null 2>&1 || true

echo "[+] Waiting 5 seconds for Bluetooth cache to clear..."
sleep 5

echo "[+] Starting ble-serial bridge for $MAC..."

# Create a temporary file for our logs to avoid pipeline buffering issues
LOG_FILE=$(mktemp)

# Force Python to be unbuffered so logs appear in the temp file immediately
export PYTHONUNBUFFERED=1

# Start ble-serial in the background and redirect output to the temp file
ble-serial -d "$MAC" -p "$TMP_PORT" > "$LOG_FILE" 2>&1 &
# Get the exact PID of the Python process (no subshells involved)
BLE_PID=$!

# Use tail to read the log file in the foreground.
# --pid ensures tail exits automatically if ble-serial crashes or finishes.
tail --pid="$BLE_PID" -f "$LOG_FILE" | while read -r logline; do
    echo "BLE: $logline"
    
    # Check for the success message indicating the main loop has started
    if [[ "$logline" == *"Running main loop!"* ]]; then
        echo ""
        echo "[+] BLE connection established successfully!"
        echo "[+] Bridging to $TARGET_TTY so the GUI can see it (requires sudo)..."
        
        # Because tail | while is a pipe, stdin is the log file. 
        # We redirect < /dev/tty so sudo prompts the actual terminal for a password.
        set +e 
        sudo -S < /dev/tty ln -sf "$TMP_PORT" "$TARGET_TTY"
        set -e

        echo "======================================================"
        echo " SUCCESS: BLE to Serial Bridge is active!"
        echo " Virtual PTY:   $TMP_PORT"
        echo " GUI Port:      $TARGET_TTY"
        echo ""
        echo " -> 1. Open bms-tools-gui in another terminal."
        echo " -> 2. Select '$TARGET_TTY' from the dropdown menu."
        echo " -> 3. Click Connect."
        echo ""
        echo " -> Leave this window open! Press CTRL+C here to stop."
        echo "======================================================"
    fi

    # Check for common failure messages
    if [[ "$logline" == *"TimeoutError"* ]] || \
       [[ "$logline" == *"failed to discover services"* ]] || \
       [[ "$logline" == *"device disconnected"* ]]; then
        echo ""
        echo "[-] ERROR DETECTED: ble-serial failed to connect or dropped the connection."
        echo "[-] Please ensure your phone is disconnected from the battery and try again."
        # Kill ble-serial to trigger the cleanup sequence
        kill "$BLE_PID" 2>/dev/null || true
    fi
done

# If tail exits (either because ble-serial crashed or we killed it gracefully in the loop),
# we run cleanup to tidy up everything and exit correctly.
cleanup
