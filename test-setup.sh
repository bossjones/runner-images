#!/bin/bash

# Simple test script to verify the setup function works properly

set -e

# Set up basic variables (simulate the main script environment)
REPO_ROOT="$(pwd)"
UBUNTU_SCRIPTS_DIR="${REPO_ROOT}/images/ubuntu/scripts"
INSTALLER_SCRIPT_FOLDER="${REPO_ROOT}/images/ubuntu/toolsets"

# Source the echo functions from the main script
source <(grep -A 20 "^echo_info()" provision-ubuntu-2204-simple.sh)
source <(grep -A 20 "^echo_success()" provision-ubuntu-2204-simple.sh)
source <(grep -A 20 "^echo_error()" provision-ubuntu-2204-simple.sh)
source <(grep -A 20 "^echo_warning()" provision-ubuntu-2204-simple.sh)

# Source the cleanup and setup functions
source <(sed -n '/^cleanup_imagegeneration()/,/^}/p' provision-ubuntu-2204-simple.sh)
source <(sed -n '/^setup_directories_and_toolset()/,/^}/p' provision-ubuntu-2204-simple.sh)

echo "=== Testing setup function ==="

# Clean up any existing directory
if [[ -d "/imagegeneration" ]]; then
    echo "Removing existing /imagegeneration directory..."
    sudo rm -rf "/imagegeneration"
fi

# Test the setup function
echo "Running setup_directories_and_toolset..."
sudo bash -c "$(declare -f setup_directories_and_toolset echo_info echo_success echo_error echo_warning cleanup_imagegeneration); 
              REPO_ROOT='$REPO_ROOT'; 
              UBUNTU_SCRIPTS_DIR='$UBUNTU_SCRIPTS_DIR'; 
              INSTALLER_SCRIPT_FOLDER='$INSTALLER_SCRIPT_FOLDER';
              setup_directories_and_toolset"

# Verify the results
echo ""
echo "=== Verification ==="

if [[ -d "/imagegeneration" ]]; then
    echo "✅ /imagegeneration directory created"
else
    echo "❌ /imagegeneration directory missing"
    exit 1
fi

if [[ -f "/imagegeneration/toolset.json" ]]; then
    echo "✅ toolset.json found"
else
    echo "❌ toolset.json missing"
    exit 1
fi

if [[ -f "/imagegeneration/helpers/os.sh" ]]; then
    echo "✅ os.sh found"
else
    echo "❌ os.sh missing"
    exit 1
fi

if [[ -f "/imagegeneration/helpers/install.sh" ]]; then
    echo "✅ install.sh found"
else
    echo "❌ install.sh missing"
    exit 1
fi

echo ""
echo "=== Contents of /imagegeneration/helpers ==="
ls -la /imagegeneration/helpers/

echo ""
echo "✅ Setup test completed successfully!"