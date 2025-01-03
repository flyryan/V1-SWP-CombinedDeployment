#!/bin/bash

# Don't use set -e as we want to control error handling manually

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
    
    # Create and execute SWP installation script
    SWP_SCRIPT="/tmp/swp_install_$$.sh"
    trap 'rm -f "$SWP_SCRIPT"' EXIT
    cat > "$SWP_SCRIPT" << 'SWPEOF'
EOT

# Append SWP script content, preserving original script but removing shebang
sed '1d' "$sw_temp_file" >> "$combined_temp"

cat >> "$combined_temp" << 'EOT'
SWPEOF
    chmod +x "$SWP_SCRIPT"
    # Execute SWP script with proper environment
    (
        # Create a clean environment
        cd /tmp
        export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        export LANG=en_US.UTF-8
        export LC_ALL=en_US.UTF-8
        
        # Run the script with debug output
        env -i PATH="$PATH" LANG="$LANG" LC_ALL="$LC_ALL" HOME="$HOME" USER="$USER" LOGNAME="$USER" SHELL="/bin/bash" /bin/bash "$SWP_SCRIPT" 2>&1 | tee -a "$INSTALL_LOG"
    )
    SWP_RESULT=$?
    
    # Verify S&W installation
    if ! launchctl list "com.trendmicro.dsa" &>/dev/null; then
        log "ERROR" "Server & Workload agent is not running"
        if [[ "$AUTO_CONTINUE" != "true" ]]; then
            log "INFO" "Installation failed. Please check logs and try again."
            exit 1
        else
            log "WARNING" "Server & Workload agent installation failed, but continuing due to --auto-continue flag"
        fi
    else
        log "INFO" "Server & Workload installation completed successfully"
    fi
    
    # If SWP failed and we're not auto-continuing, exit
    if [[ $SWP_RESULT -ne 0 && "$AUTO_CONTINUE" != "true" ]]; then
        log "ERROR" "Server & Workload Protection installation failed with status $SWP_RESULT"
        exit $SWP_RESULT
    fi
fi

# =====================
# Vision One Installation
# =====================

# Only prompt for continuation if SWP was installed and auto-continue is not set
if [[ "$AUTO_CONTINUE" != "true" && "$SKIP_SWP" != "true" ]]; then
    echo -n "Press Enter to continue with Vision One installation or Ctrl+C to cancel..."
    read
fi

log "INFO" "Starting Vision One Endpoint Sensor installation..." "v1"

# Create and execute V1 installation script
V1_SCRIPT="/tmp/v1_install_$$.sh"
trap 'rm -f "$V1_SCRIPT"' EXIT
cat > "$V1_SCRIPT" << 'V1EOF'
EOT

# Append V1 script content
cat "$v1_temp_file" >> "$combined_temp"

cat >> "$combined_temp" << 'EOT'

V1EOF
chmod +x "$V1_SCRIPT"
# Execute V1 script with proper environment
(
    cd /tmp
    export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    export LANG=en_US.UTF-8
    export LC_ALL=en_US.UTF-8
    /bin/bash "$V1_SCRIPT" 2>&1 | tee -a "$V1_INSTALL_LOG"
)
V1_RESULT=$?
EOT

# Add the footer
cat >> "$combined_temp" << 'EOT'

# Verify V1 installation and check result
V1_SUCCESS=false
if [[ $V1_RESULT -ne 0 ]]; then
    log "ERROR" "Vision One installation returned error code $V1_RESULT" "v1"
    if [[ "$AUTO_CONTINUE" != "true" ]]; then
        exit $V1_RESULT
    fi
elif ! launchctl list "com.trendmicro.EDRAgent" &>/dev/null; then
    log "ERROR" "Vision One Endpoint Sensor is not running" "v1"
    if [[ "$AUTO_CONTINUE" != "true" ]]; then
        log "INFO" "Installation failed. Please check logs and try again."
        exit 1
    fi
else
    V1_SUCCESS=true
    log "INFO" "Vision One installation completed successfully" "v1"
fi

# Final status check
if [[ "$SKIP_SWP" == "true" && "$V1_SUCCESS" == "true" ]] || \
   [[ "$V1_SUCCESS" == "true" && $(launchctl list "com.trendmicro.dsa" &>/dev/null; echo $?) -eq 0 ]]; then
    log "INFO" "Combined installation completed successfully!"
else
    log "WARNING" "Installation completed with some components potentially not running"
fi

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