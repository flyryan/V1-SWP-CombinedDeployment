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

# Parse S&W script with error checking
SW_URL=$(grep 'dsa_control" -a' "$sw_temp_file" | sed -E 's/.*-a ([^ ]+).*/\1/' || echo "")
TENANT_ID=$(grep 'tenantID:' "$sw_temp_file" | sed -E 's/.*tenantID:([^"]*).*/\1/' || echo "")
TOKEN=$(grep 'token:' "$sw_temp_file" | sed -E 's/.*token:([^"]*).*/\1/' || echo "")
POLICY_ID=$(grep 'policyid:' "$sw_temp_file" | sed -E 's/.*policyid:([^"]*).*/\1/' || echo "")
MANAGER_PROXY=$(grep 'manager_proxy=' "$sw_temp_file" | cut -d'"' -f2 || echo "")
MANAGER_PROXY_CRED=$(grep 'manager_proxy_credential=' "$sw_temp_file" | cut -d'"' -f2 || echo "")

# Validate S&W required variables
if [[ -z "$SW_URL" || -z "$TENANT_ID" || -z "$TOKEN" || -z "$POLICY_ID" ]]; then
    echo "Error: Failed to parse required Server & Workload Security variables"
    exit 1
fi

echo -e "\n=== Vision One Script ===\n"
echo "Paste the entire Vision One deployment script (Press Ctrl+D when finished):"
cat > "$v1_temp_file"

# Parse Vision One script with error checking
V1_ENV=$(grep 'XBC_ENV=' "$v1_temp_file" | cut -d'"' -f2 || echo "")
V1_TOKEN=$(grep 'XBC_AGENT_TOKEN=' "$v1_temp_file" | cut -d'"' -f2 || echo "")
V1_COMPANY_ID=$(grep 'company_id' "$v1_temp_file" | sed -E 's/.*"company_id":"([^"]*).*/\1/' || echo "")
V1_PROXY_ADDR=$(grep 'PROXY_ADDR_PORT=' "$v1_temp_file" | cut -d'"' -f2 || echo "")
V1_PROXY_USER=$(grep 'PROXY_USERNAME=' "$v1_temp_file" | cut -d'"' -f2 || echo "")
V1_PROXY_PASS=$(grep 'PROXY_PASSWORD=' "$v1_temp_file" | cut -d'"' -f2 || echo "")

# Validate V1 required variables
if [[ -z "$V1_ENV" || -z "$V1_TOKEN" || -z "$V1_COMPANY_ID" ]]; then
    echo "Error: Failed to parse required Vision One variables"
    exit 1
fi

# Show parsed information for verification
echo -e "\nParsed Information:"
echo -e "\nServer & Workload Security:"
echo "Manager URL: $SW_URL"
echo "Tenant ID: $TENANT_ID"
echo "Policy ID: $POLICY_ID"
echo "Manager Proxy: ${MANAGER_PROXY:-None}"
echo "Manager Proxy Credentials: ${MANAGER_PROXY_CRED:+Configured}"

echo -e "\nVision One:"
echo "Environment: $V1_ENV"
echo "Token: $V1_TOKEN"
echo "Company ID: $V1_COMPANY_ID"
echo "Proxy Address: ${V1_PROXY_ADDR:-None}"
echo "Proxy Username: ${V1_PROXY_USER:-None}"
echo "Proxy Password: ${V1_PROXY_PASS:+Configured}"

echo -e "\nIs this information correct? (y/n): "
read confirm
if [[ "$confirm" != "y" ]]; then
    echo "Please try again"
    exit 1
fi

# Generate the combined installation script
SCRIPT_NAME="trend_combined_install.sh"

cat << EOT > "$SCRIPT_NAME"
#!/bin/bash

# Combined Trend Micro Server & Workload + Vision One Endpoint Sensor Installer
# Generated: $(date)

set -e  # Exit on error

# Global Variables
INSTALL_LOG="/var/log/trend_install.log"
V1_INSTALL_LOG="/tmp/v1es_install.log"
TEMP_DIR=\$(mktemp -d)
trap 'rm -rf "\$TEMP_DIR"' EXIT

# Check root privileges
if [[ \$(whoami) != "root" ]]; then
    echo "[ERROR] This script must be run with root privileges"
    exit 1
fi

# Logging function
log() {
    local level="\$1"
    local message="\$2"
    echo "[\$level] \$message"
    echo "\$(date) [\$level] \$message" >> "\$INSTALL_LOG"
    echo "\$(date) [\$level] \$message" >> "\$V1_INSTALL_LOG"
}

# Platform check function
check_platform() {
    local osVersion=\$(sw_vers -productVersion)
    local buildVersion=\$(sw_vers -buildVersion)
    local major=\$(echo \$osVersion | cut -d "." -f1)
    local minor=\$(echo \$osVersion | cut -d "." -f2)
    
    log "INFO" "Detected macOS version: \$osVersion (Build \$buildVersion)"
    
    if [[ \$major -le 10 && \$minor -le 14 ]]; then
        log "ERROR" "Unsupported platform detected"
        exit 1
    fi
    
    echo "\$osVersion"
    echo "\$buildVersion"
}

# Proxy configuration function
configure_proxy() {
    # S&W Proxy
    if [[ -n "$MANAGER_PROXY" ]]; then
        if [[ -n "$MANAGER_PROXY_CRED" ]]; then
            export all_proxy="http://$MANAGER_PROXY_CRED@$MANAGER_PROXY"
        else
            export all_proxy="http://$MANAGER_PROXY"
        fi
    fi
    
    # V1 Proxy
    if [[ -n "$V1_PROXY_ADDR" ]]; then
        local proxy_cred=""
        if [[ -n "$V1_PROXY_USER" ]]; then
            if [[ -n "$V1_PROXY_PASS" ]]; then
                proxy_cred="$V1_PROXY_USER:$V1_PROXY_PASS@"
            else
                proxy_cred="$V1_PROXY_USER@"
            fi
        fi
        export HTTP_PROXY="http://\${proxy_cred}$V1_PROXY_ADDR"
        export HTTPS_PROXY="http://\${proxy_cred}$V1_PROXY_ADDR"
    fi
}

log "INFO" "Starting combined Trend Micro installation..."

# Get platform information
read osVersion buildVersion < <(check_platform)

# Configure proxy settings
configure_proxy

# =====================
# Server & Workload Installation
# =====================
log "INFO" "Starting Server & Workload Protection installation..."

# Download S&W package
log "INFO" "Downloading S&W agent package..."
packageUrl="https://app.deepsecurity.trendmicro.com:443/software/agent/macOS/universal/agent.pkg?tenantID=$TENANT_ID&macOSVersion=\${osVersion}.\${buildVersion}"
curl -v --tlsv1.2 -L -o "\$TEMP_DIR/agent.pkg" "\$packageUrl"
if [[ \$? -eq 60 ]]; then
    log "ERROR" "TLS certificate validation failed for S&W package download"
    exit 1
elif [[ \$? -ne 0 ]]; then
    log "ERROR" "Failed to download S&W package"
    exit 1
fi

# Install S&W package
log "INFO" "Installing S&W agent..."
installer -pkg "\$TEMP_DIR/agent.pkg" -target /
if [[ \$? -ne 0 ]]; then
    log "ERROR" "Failed to install S&W package"
    exit 1
fi

# Wait for DSA service
log "INFO" "Waiting for DSA service to initialize..."
totalCount=360
count=0
while [[ \$count -lt \$totalCount ]]; do
    if launchctl list "com.trendmicro.dsa" &>/dev/null; then
        break
    fi
    sleep 10
    count=\$((count + 1))
done

if [[ \$count -ge \$totalCount ]]; then
    log "ERROR" "DSA service failed to initialize"
    exit 1
fi

# Activate S&W agent
log "INFO" "Activating S&W agent..."
dsa_control="/Library/Application Support/com.trendmicro.DSAgent/dsa_control"
"\$dsa_control" -r
if [[ -n "$MANAGER_PROXY" ]]; then
    "\$dsa_control" -x "dsm_proxy://$MANAGER_PROXY"
    if [[ -n "$MANAGER_PROXY_CRED" ]]; then
        "\$dsa_control" -u "$MANAGER_PROXY_CRED"
    fi
fi
"\$dsa_control" -a "$SW_URL" "tenantID:$TENANT_ID" "token:$TOKEN" "policyid:$POLICY_ID"
if [[ \$? -ne 0 ]]; then
    log "ERROR" "Failed to activate S&W agent"
    exit 1
fi

# Verify activation
if [[ ! -f "/Library/Application Support/com.trendmicro.DSAgent/certs/ds_agent_dsm.crt" ]]; then
    log "ERROR" "S&W agent activation verification failed"
    exit 1
fi

# =====================
# Vision One Installation
# =====================
log "INFO" "Starting Vision One Endpoint Sensor installation..."

# Prepare V1 variables
XBC_ENV="$V1_ENV"
XBC_AGENT_TOKEN="$V1_TOKEN"
HTTP_BODY='{\"company_id\":\"$V1_COMPANY_ID\",\"platform\":\"mac64\",\"scenario_ids\":[\"$V1_TOKEN\"]}'

# Download V1 package
log "INFO" "Downloading V1 Endpoint Sensor..."
CURL_OPTIONS="--tlsv1.2"
XBC_FQDN="api-\${XBC_ENV}.xdr.trendmicro.com"
GET_INSTALLER_URL="https://\${XBC_FQDN}/apk/installer"
INSTALLER_PATH="\$TEMP_DIR/v1es_installer.zip"

CURL_OUT=\$(curl -w "%{http_code}" -L -H "Content-Type: application/json" -d "\$HTTP_BODY" -o "\$INSTALLER_PATH" \$CURL_OPTIONS "\$GET_INSTALLER_URL")
if [[ \$? -eq 60 ]]; then
    log "ERROR" "TLS certificate validation failed for V1 package download"
    exit 1
elif [[ \$CURL_OUT -ge 400 || \$? -ne 0 ]]; then
    log "ERROR" "Failed to download V1 package (HTTP \$CURL_OUT)"
    exit 1
fi

# Extract and install V1 package
EXTRACTED_DIR="\$TEMP_DIR/v1es"
mkdir -p "\$EXTRACTED_DIR" && tar -zxf "\$INSTALLER_PATH" -C "\$EXTRACTED_DIR"
if [[ \$? -ne 0 ]]; then
    log "ERROR" "Failed to extract V1 package"
    exit 1
fi

PKG_PATH=\$(find "\$EXTRACTED_DIR" -type f -name "endpoint_basecamp.pkg")
if [[ ! -f "\$PKG_PATH" ]]; then
    log "ERROR" "Could not find V1 installer package"
    exit 1
fi

# Configure V1 installation
PROPERTY="{\\"xbc_env\\": \\"\$XBC_ENV\\", \\"xbc_agent_token\\": \\"\$XBC_AGENT_TOKEN\\", \\"full_package\\": true}"
echo "\$PROPERTY" | plutil -convert xml1 -o "\$TEMP_DIR/endpoint_basecamp.conf.plist" -

# Configure connection methods
if [[ -n "$V1_PROXY_ADDR" ]]; then
    PROXY_CONFIG=\$(printf "http://$V1_PROXY_ADDR" | base64)
    if [[ -n "$V1_PROXY_USER" ]]; then
        if [[ -n "$V1_PROXY_PASS" ]]; then
            PROXY_CONFIG=\$(printf "http://$V1_PROXY_USER:$V1_PROXY_PASS@$V1_PROXY_ADDR" | base64)
        else
            PROXY_CONFIG=\$(printf "http://$V1_PROXY_USER:@$V1_PROXY_ADDR" | base64)
        fi
    fi
    CONNECT_CONFIG=\$(printf '{"fps":[{"connections": [{"type": "USER_INPUT"}]}]}' | base64)
    defaults write com.trendmicro.endpointbasecamp user_proxy_config -string "\$PROXY_CONFIG"
else
    CONNECT_CONFIG=\$(printf '{"fps":[{"connections": [{"type": "DIRECT_CONNECT"}]}]}' | base64)
fi
defaults write com.trendmicro.endpointbasecamp user_connect_config -string "\$CONNECT_CONFIG"

# Install V1 package
log "INFO" "Installing V1 Endpoint Sensor..."
INSTALL_RESULT=\$(installer -pkg "\$PKG_PATH" -target / 2>&1)
if [[ \$? -ne 0 ]]; then
    log "ERROR" "Failed to install V1 package: \$INSTALL_RESULT"
    exit 1
fi

# Wait for V1 registration
log "INFO" "Waiting for V1 agent registration..."
RETRY_COUNT=0
MAX_RETRY_COUNT=30
REGISTERED=\$(defaults read com.trendmicro.endpointbasecamp kRegisterCompany 2>/dev/null)
while [[ -z "\$REGISTERED" && \$RETRY_COUNT -lt \$MAX_RETRY_COUNT ]]; do
    sleep 10
    REGISTERED=\$(defaults read com.trendmicro.endpointbasecamp kRegisterCompany 2>/dev/null)
    RETRY_COUNT=\$((RETRY_COUNT + 1))
done

if [[ \$RETRY_COUNT -ge \$MAX_RETRY_COUNT ]]; then
    log "ERROR" "V1 registration timed out"
    exit 1
fi

# Check if XES is launched
log "INFO" "Waiting for endpoint sensor to start..."
RETRY_COUNT=0
MAX_RETRY_COUNT=60
while [[ \$RETRY_COUNT -lt \$MAX_RETRY_COUNT ]]; do
    if launchctl list "com.trendmicro.EDRAgent" &>/dev/null; then
        break
    fi
    sleep 10
    RETRY_COUNT=\$((RETRY_COUNT + 1))
done

if [[ \$RETRY_COUNT -ge \$MAX_RETRY_COUNT ]]; then
    log "ERROR" "Endpoint sensor failed to start"
    exit 1
fi

log "INFO" "Installation completed successfully!"
log "INFO" "Check \$INSTALL_LOG and \$V1_INSTALL_LOG for detailed logs"

exit 0
EOT

# Make the generated script executable
chmod +x "$SCRIPT_NAME"

echo -e "\nCombined installation script has been generated: $SCRIPT_NAME"
echo "Copy this script to target machines and run with sudo"
echo "Installation logs will be written to /var/log/trend_install.log and /tmp/v1es_install.log"
