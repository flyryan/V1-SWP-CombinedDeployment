#!/bin/bash

set -e  # Exit on error

# Secure temporary file creation with cleanup trap
cleanup() {
    rm -f "$sw_temp_file" "$v1_temp_file"
}

sw_temp_file=$(mktemp)
v1_temp_file=$(mktemp)
trap cleanup EXIT

cat << "EOF"
========================================================
Trend Micro Combined Deployment Script Generator
========================================================

Prerequisites:

1. From Server & Workload Security console:
   - Navigate to Updates > Software > Local
   - Click "Generate Deployment Scripts..."
   - Configure the following options:
     * Platform: macOS Agent Deployment
     * Activate Agent automatically after installation (checked)
     * Security Policy: Select as needed
     * Computer Group: Select as needed
     * Relay Group: Select as needed
     * Configure proxy settings if required
     * Validate Workload Security Manager TLS certificate (recommended)
   - Click "Copy to Clipboard" to get the script

2. From Vision One console:
   - Navigate to Endpoint Security > Endpoint Inventory
   - Click "Agent Installer" button in the top-right corner
   - Select the "Deployment Script" tab
   - Configure the following options:
     * Protection type: Endpoint Sensor
     * Operating system: macOS
     * Proxy for deployment: Direct connect (or configure proxy if needed)
     * Validate Trend Vision One server TLS certificate (recommended)
   - Copy the generated script

3. System Requirements:
   - macOS 10.15 (Catalina) or later
   - Root/sudo privileges
   - Internet connectivity to Trend Micro servers
   - Curl with TLS support

Please paste each script when prompted.
EOF

echo -e "\n=== Server & Workload Security Script ===\n"
echo "Paste the entire S&W deployment script (Press Ctrl+D when finished):"
cat > "$sw_temp_file"

echo -e "\n=== Vision One Script ===\n"
echo "Paste the entire Vision One deployment script (Press Ctrl+D when finished - Note: You may have to press twice.):"
cat > "$v1_temp_file"

# Basic validation of input scripts
if ! grep -q "dsa_control" "$sw_temp_file"; then
    echo "Error: Invalid Server & Workload Security script (missing dsa_control)"
    exit 1
fi

if ! grep -q "endpoint_basecamp" "$v1_temp_file"; then
    echo "Error: Invalid Vision One script (missing endpoint_basecamp)"
    exit 1
fi

# Generate the combined installation script
SCRIPT_NAME="trend_combined_install.sh"

cat > "$SCRIPT_NAME" << 'EOT'
#!/bin/bash

# Combined Trend Micro Server & Workload + Vision One Endpoint Sensor Installer
# Generated: $(date)

# Global Variables
INSTALL_LOG="/var/log/trend_install.log"
V1_INSTALL_LOG="/tmp/v1es_install.log"

# Check root privileges
if [[ $(whoami) != "root" ]]; then
    echo "[ERROR] This script must be run with root privileges"
    exit 1
fi

# Logging function
log() {
    local level="$1"
    local message="$2"
    echo "[$level] $message"
    echo "$(date) [$level] $message" >> "$INSTALL_LOG"
    if [[ "$3" == "v1" ]]; then
        echo "$(date) [$level] $message" >> "$V1_INSTALL_LOG"
    fi
}

log "INFO" "Starting combined Trend Micro installation..."

# =====================
# Server & Workload Installation
# =====================
log "INFO" "Starting Server & Workload Protection installation..."

# Execute S&W installation in a subshell to isolate variables
(
EOT

# Append S&W script content, removing the shebang line if present
sed '1{/^#!/d}' "$sw_temp_file" >> "$SCRIPT_NAME"

# Continue the combined script
cat >> "$SCRIPT_NAME" << 'EOT'
) 2>&1 | tee -a "$INSTALL_LOG"

# Verify S&W installation
if ! launchctl list "com.trendmicro.dsa" &>/dev/null; then
    log "ERROR" "Server & Workload agent is not running"
    exit 1
fi

log "INFO" "Server & Workload installation completed successfully"

# =====================
# Vision One Installation
# =====================

# Check if auto-continue flag is set
if [[ "$1" != "--auto-continue" ]]; then
    echo -n "Press Enter to continue with Vision One installation or Ctrl+C to cancel..."
    read
fi

log "INFO" "Starting Vision One Endpoint Sensor installation..." "v1"

# Execute Vision One installation in a subshell to isolate variables
(
EOT

# Append V1 script content, removing the shebang line if present
sed '1{/^#!/d}' "$v1_temp_file" >> "$SCRIPT_NAME"

# Finish the combined script
cat >> "$SCRIPT_NAME" << 'EOT'
) 2>&1 | tee -a "$V1_INSTALL_LOG"

# Verify V1 installation
if ! launchctl list "com.trendmicro.EDRAgent" &>/dev/null; then
    log "ERROR" "Vision One Endpoint Sensor is not running" "v1"
    exit 1
fi

log "INFO" "Vision One installation completed successfully" "v1"
log "INFO" "Combined installation completed successfully!"
log "INFO" "Check $INSTALL_LOG and $V1_INSTALL_LOG for detailed logs"

exit 0
EOT

# Make the generated script executable
chmod +x "$SCRIPT_NAME"

echo -e "\nCombined installation script has been generated: $SCRIPT_NAME"
echo "Copy this script to target machines and run with sudo"
echo "To skip the Vision One installation confirmation prompt, use: sudo ./$SCRIPT_NAME --auto-continue"
echo "Installation logs will be written to /var/log/trend_install.log and /tmp/v1es_install.log"
