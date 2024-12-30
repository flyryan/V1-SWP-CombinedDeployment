# Trend Micro Combined Deployment Script Generator

This tool generates a unified installation script for Trend Micro's Server & Workload Security (Deep Security Agent) and Vision One Endpoint Sensor on macOS systems. It combines the deployment scripts from both platforms into a single, streamlined installation process.

## Overview

The script generator takes deployment scripts from both the Server & Workload Security console and Vision One console, extracts the necessary configuration parameters, and generates a combined installation script that can deploy both agents efficiently.

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
     * Navigate to Support > Deployment Scripts
     * Configure deployment options
     * Copy the generated script
   
   - From Vision One console:
     * Navigate to Endpoint Inventory > Deployment
     * Configure deployment options
     * Copy the generated script

2. Run the script generator:
   ```bash
   chmod +x InstallScriptGenerator.sh
   ./InstallScriptGenerator.sh
   ```

3. When prompted:
   - Paste the Server & Workload Security script (press Ctrl+D when finished)
   - Paste the Vision One script (press Ctrl+D when finished)
   - Review the parsed information
   - Confirm if the information is correct

4. The generator will create a combined installation script named `trend_combined_install.sh`

5. Deploy the generated script:
   ```bash
   sudo ./trend_combined_install.sh
   ```

## Features

- **Unified Installation**: Installs both agents in a single operation
- **Proxy Support**: Handles proxy configuration for both agents
- **Platform Validation**: Checks OS version compatibility
- **Robust Error Handling**: Comprehensive error checking and reporting
- **Detailed Logging**: Maintains separate logs for troubleshooting
- **Service Verification**: Ensures services are properly initialized
- **Secure Operations**: Proper handling of credentials and temporary files

## Logging

The combined installation script writes logs to two locations:
- `/var/log/trend_install.log`: Main installation log
- `/tmp/v1es_install.log`: Vision One specific installation log

Log entries include:
- Timestamp
- Severity level (INFO/ERROR)
- Detailed status messages
- Error information when applicable

## Troubleshooting

Common issues and solutions:

1. **TLS Certificate Validation Failure**
   - Ensure the system's certificate store is up to date
   - Check network security appliances aren't intercepting HTTPS traffic

2. **Proxy Issues**
   - Verify proxy settings in both original deployment scripts
   - Ensure proxy credentials are correctly formatted

3. **Installation Timeout**
   - Check system resources
   - Verify network connectivity to Trend Micro servers
   - Review logs for specific error messages

4. **Service Initialization Failure**
   - Check system requirements are met
   - Verify no conflicts with other security software
   - Review logs for specific error messages

## Support

For issues with:
- Server & Workload Security: Contact Trend Micro Deep Security support
- Vision One: Contact Trend Micro Vision One support
- Script Generator: Open an issue in this repository

## License

This project is licensed under the MIT License - see the LICENSE file for details.
