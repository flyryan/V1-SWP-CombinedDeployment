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

cat << 'EOT' > "$SCRIPT_NAME"
#!/bin/bash

# Combined Trend Micro Server & Workload + Vision One Endpoint Sensor Installer
# Generated: $(date)

set -e  # Exit on error

# Global Variables
INSTALL_LOG="/var/log/trend_install.log"
V1_INSTALL_LOG="/tmp/v1es_install.log"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

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

# Platform check function
check_platform() {
    local osVersion=$(sw_vers -productVersion)
    local major=$(echo $osVersion | cut -d "." -f1)
    local minor=$(echo $osVersion | cut -d "." -f2)
    
    log "INFO" "Detected macOS version: $osVersion"
    
    if [[ $major -le 10 && $minor -le 14 ]]; then
        log "ERROR" "Unsupported platform detected"
        exit 1
    fi
}

log "INFO" "Starting combined Trend Micro installation..."

# Check platform compatibility
check_platform

# =====================
# Server & Workload Installation
# =====================
log "INFO" "Starting Server & Workload Protection installation..."

# Create a temporary script for S&W installation
SW_SCRIPT="$TEMP_DIR/sw_install.sh"
cat > "$SW_SCRIPT" << 'SWEOF'
EOT

# Append the S&W script content
cat "$sw_temp_file" >> "$SCRIPT_NAME"

# Continue with the combined script
cat << 'EOT' >> "$SCRIPT_NAME"
SWEOF

chmod +x "$SW_SCRIPT"
log "INFO" "Executing Server & Workload installation..."

# Execute S&W script with preserved environment
(
    cd "$TEMP_DIR"
    if ! bash "$SW_SCRIPT" 2>&1 | tee -a "$INSTALL_LOG"; then
        log "ERROR" "Server & Workload installation failed"
        exit 1
    fi
)

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

# Create a temporary script for V1 installation
V1_SCRIPT="$TEMP_DIR/v1_install.sh"
cat > "$V1_SCRIPT" << 'V1EOF'
EOT

# Append the V1 script content
cat "$v1_temp_file" >> "$SCRIPT_NAME"

# Finish the combined script
cat << 'EOT' >> "$SCRIPT_NAME"
V1EOF

chmod +x "$V1_SCRIPT"
log "INFO" "Executing Vision One installation..." "v1"

# Execute V1 script with preserved environment
(
    cd "$TEMP_DIR"
    if ! bash "$V1_SCRIPT" 2>&1 | tee -a "$V1_INSTALL_LOG"; then
        log "ERROR" "Vision One installation failed" "v1"
        exit 1
    fi
)

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
