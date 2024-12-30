# Trend Micro Combined Deployment Script Generator

This tool generates a unified installation script for Trend Micro's Server & Workload Security (Deep Security Agent) and Vision One Endpoint Sensor on macOS systems. It combines the deployment scripts from both platforms into a single, streamlined installation process.

## Overview

The script generator takes deployment scripts from both the Server & Workload Security console and Vision One console and combines them into a single installation script that deploys both agents in sequence. The original scripts are preserved exactly as they are, ensuring compatibility and reliability.

Note: All .sh files except InstallScriptGenerator.sh are git-ignored to prevent committing sensitive deployment scripts or generated files.

## Prerequisites

Before using this script generator, you need:

1. Access to Trend Micro Server & Workload Security console
   - Ability to generate a deployment script
   - Valid tenant ID, token, and policy ID

2. Access to Trend Micro Vision One console
   - Ability to generate a deployment script
   - Valid company ID and agent token

3. macOS system requirements:
   - macOS 10.15 (Catalina) or later
   - Root/sudo privileges
   - Internet connectivity to Trend Micro servers
   - Curl with TLS support

## Usage

1. Generate deployment scripts from both consoles:
   - From Server & Workload Security console:
     * Navigate to Updates > Software > Local
     * Click "Generate Deployment Scripts..." button
     * Configure the following options:
       - Platform: macOS Agent Deployment
       - Activate Agent automatically after installation (checked)
       - Security Policy: Select as needed
       - Computer Group: Select as needed
       - Relay Group: Select as needed
       - Configure proxy settings if required
       - Validate Workload Security Manager TLS certificate (recommended)
     * Click "Copy to Clipboard" to get the script
   
   - From Vision One console:
     * Navigate to Endpoint Security > Endpoint Inventory
     * Click "Agent Installer" button in the top-right corner
     * Select the "Deployment Script" tab
     * Configure the following options:
       - Protection type: Endpoint Sensor
       - Operating system: macOS
       - Proxy for deployment: Direct connect (or configure proxy if needed)
       - Validate Trend Vision One server TLS certificate (recommended)
     * Copy the generated script

2. Run the script generator:
   ```bash
   chmod +x InstallScriptGenerator.sh
   ./InstallScriptGenerator.sh
   ```

3. When prompted:
   - Paste the Server & Workload Security script (press Ctrl+D when finished)
   - Paste the Vision One script (press Ctrl+D when finished)

4. The generator will create a combined installation script named `trend_combined_install.sh`

5. Deploy the generated script:
   ```bash
   sudo ./trend_combined_install.sh
   ```

## Features

- **Sequential Installation**: Installs both agents one after the other, preserving their original installation logic
- **Proxy Support**: Maintains original proxy handling from each script
- **Platform Validation**: Checks OS version compatibility before installation
- **Robust Error Handling**: Verifies each installation step
- **Detailed Logging**: Maintains separate and combined logs for troubleshooting
- **Service Verification**: Ensures each agent's services are properly running
- **Secure Operations**: Proper handling of temporary files and cleanup
- **Version Control**: Ignores sensitive scripts while tracking only the generator

## Logging

The combined installation script writes logs to two locations:
- `/var/log/trend_install.log`: Main installation log
- `/tmp/v1es_install.log`: Vision One specific installation log

Log entries include:
- Timestamp
- Severity level (INFO/ERROR)
- Detailed status messages
- Error information when applicable
