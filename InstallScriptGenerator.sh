#!/bin/bash

set -e  # Exit on error

# Secure temporary file creation with cleanup trap
cleanup() {
    rm -f "$sw_temp_file" "$v1_temp_file" "$combined_temp"
}

sw_temp_file=$(mktemp)
v1_temp_file=$(mktemp)
combined_temp=$(mktemp)
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

# First, create the script header
cat > "$combined_temp" << 'EOT'
#!/bin/bash

# Combined Trend Micro Server & Workload + Vision One Endpoint Sensor Installer

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

# Parse command line arguments
SKIP_SWP=false
AUTO_CONTINUE=false

for arg in "$@"; do
    case "$arg" in
        --skip-swp)
            SKIP_SWP=true
            ;;
        --auto-continue)
            AUTO_CONTINUE=true
            ;;
    esac
done

log "INFO" "Starting combined Trend Micro installation..."

# =====================
# Server & Workload Installation
# =====================
if [[ "$SKIP_SWP" == "true" ]]; then
    log "INFO" "Skipping Server & Workload Protection installation (--skip-swp flag detected)"
else
    log "INFO" "Starting Server & Workload Protection installation..."

EOT

# Append S&W script content
sed '1{/^#!/d}' "$sw_temp_file" >> "$combined_temp"

# Add the middle section
cat >> "$combined_temp" << 'EOT'

    # Verify S&W installation
    if ! launchctl list "com.trendmicro.dsa" &>/dev/null; then
        log "ERROR" "Server & Workload agent is not running"
        exit 1
    fi

    log "INFO" "Server & Workload installation completed successfully"
fi

# =====================
# Vision One Installation
# =====================

# Check if auto-continue flag is set
if [[ "$AUTO_CONTINUE" != "true" && "$SKIP_SWP" != "true" ]]; then
    echo -n "Press Enter to continue with Vision One installation or Ctrl+C to cancel..."
    read
fi

log "INFO" "Starting Vision One Endpoint Sensor installation..." "v1"

EOT

# Append V1 script content
sed '1{/^#!/d}' "$v1_temp_file" >> "$combined_temp"

# Add the footer
cat >> "$combined_temp" << 'EOT'

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

# Create the final script
cp "$combined_temp" "$SCRIPT_NAME"
chmod +x "$SCRIPT_NAME"

echo -e "\nCombined installation script has been generated: $SCRIPT_NAME"
echo "Copy this script to target machines and run with sudo"
echo "Usage:"
echo "  Normal installation:              sudo ./$SCRIPT_NAME"
echo "  Skip confirmation prompt:         sudo ./$SCRIPT_NAME --auto-continue"
echo "  Skip S&W installation (debug):    sudo ./$SCRIPT_NAME --skip-swp"
echo "  Skip both:                        sudo ./$SCRIPT_NAME --skip-swp --auto-continue"
echo "Installation logs will be written to /var/log/trend_install.log and /tmp/v1es_install.log"
