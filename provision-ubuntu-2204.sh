#!/bin/bash

# Ubuntu 22.04 Runner Image Provisioning Script
# This script replicates the provisioning process from ubuntu-22.04.pkr.hcl
# Run with sudo privileges
# 
# Usage:
#   ./provision-ubuntu-2204.sh           # Normal execution
#   DRY_RUN=1 ./provision-ubuntu-2204.sh # Dry run mode (shows commands without executing)
#
# Feature flags (set to 0 to disable):
#   INSTALL_ANDROID=0 INSTALL_POWERSHELL=0 ./provision-ubuntu-2204.sh
#   
# Available feature flags:
#   INSTALL_CORE_TOOLS, INSTALL_CLOUD_TOOLS, INSTALL_DEVELOPMENT_TOOLS,
#   INSTALL_VERSION_CONTROL, INSTALL_BROWSERS, INSTALL_LANGUAGES,
#   INSTALL_DATABASES, INSTALL_WEB_SERVERS, INSTALL_BUILD_TOOLS,
#   INSTALL_CONTAINER_TOOLS, INSTALL_INFRASTRUCTURE, INSTALL_ANDROID,
#   INSTALL_POWERSHELL, INSTALL_DATA_SCIENCE, INSTALL_MISC_TOOLS

set -e

# Check if running in dry-run mode
DRY_RUN="${DRY_RUN:-0}"

# Feature flags - control which software groups to install
# Set to 0 to skip installation of that group
INSTALL_CORE_TOOLS="${INSTALL_CORE_TOOLS:-1}"                    # Actions cache, runner package, APT common, etc.
INSTALL_CLOUD_TOOLS="${INSTALL_CLOUD_TOOLS:-1}"                  # Azure CLI, AWS tools, Google Cloud CLI, etc.
INSTALL_DEVELOPMENT_TOOLS="${INSTALL_DEVELOPMENT_TOOLS:-1}"      # Clang, Swift, CMake, CodeQL, compilers, etc.
INSTALL_VERSION_CONTROL="${INSTALL_VERSION_CONTROL:-1}"          # Git, Git LFS, GitHub CLI
INSTALL_BROWSERS="${INSTALL_BROWSERS:-1}"                        # Firefox, Chrome, Microsoft Edge
INSTALL_LANGUAGES="${INSTALL_LANGUAGES:-1}"                      # Haskell, Java, Kotlin, Node.js, PHP, Ruby, Python, etc.
INSTALL_DATABASES="${INSTALL_DATABASES:-1}"                      # MySQL, PostgreSQL, MSSQL tools
INSTALL_WEB_SERVERS="${INSTALL_WEB_SERVERS:-1}"                  # Apache, Nginx
INSTALL_BUILD_TOOLS="${INSTALL_BUILD_TOOLS:-1}"                  # Bazel, vcpkg, yq, zstd, ninja
INSTALL_CONTAINER_TOOLS="${INSTALL_CONTAINER_TOOLS:-1}"          # Docker, container tools, Kubernetes tools
INSTALL_INFRASTRUCTURE="${INSTALL_INFRASTRUCTURE:-1}"            # Terraform, Packer, Pulumi
INSTALL_ANDROID="${INSTALL_ANDROID:-1}"                          # Android SDK
INSTALL_POWERSHELL="${INSTALL_POWERSHELL:-1}"                    # PowerShell and PowerShell modules
INSTALL_DATA_SCIENCE="${INSTALL_DATA_SCIENCE:-1}"                # Miniconda, R language
INSTALL_MISC_TOOLS="${INSTALL_MISC_TOOLS:-1}"                    # Selenium, pipx packages, Homebrew

# Function to log and optionally execute commands
run_command() {
    local cmd="$1"
    echo ">>> RUNNING: $cmd"
    if [[ "$DRY_RUN" == "1" ]]; then
        echo "    [DRY RUN] Would execute: $cmd"
        return 0
    else
        eval "$cmd"
    fi
}

# Function to log and optionally execute bash scripts
run_script() {
    local script="$1"
    echo ">>> RUNNING SCRIPT: $script"
    if [[ "$DRY_RUN" == "1" ]]; then
        echo "    [DRY RUN] Would execute: bash $script"
        return 0
    else
        bash "$script"
    fi
}

# Function to log and optionally execute PowerShell scripts
run_pwsh_script() {
    local script="$1"
    echo ">>> RUNNING POWERSHELL SCRIPT: $script"
    if [[ "$DRY_RUN" == "1" ]]; then
        echo "    [DRY RUN] Would execute: pwsh -f $script"
        return 0
    else
        pwsh -f "$script"
    fi
}

# Function to check if a feature flag is enabled
is_enabled() {
    local flag="$1"
    [[ "${flag}" == "1" ]]
}

# Function to skip a section if feature flag is disabled
skip_if_disabled() {
    local flag="$1"
    local section_name="$2"
    if ! is_enabled "$flag"; then
        echo ">>> SKIPPING: $section_name (feature flag disabled)"
        return 0
    fi
    return 1
}

# Configuration variables - adjust these paths as needed
# Main directory where all image generation files will be stored
IMAGE_FOLDER="/imagegeneration"
# Directory containing helper PowerShell modules and utility scripts
HELPER_SCRIPT_FOLDER="/imagegeneration/helpers"
# Directory where installation scripts will be copied for execution
INSTALLER_SCRIPT_FOLDER="/imagegeneration/installers"
# JSON file that stores metadata about the image being built
IMAGEDATA_FILE="/imagegeneration/imagedata.json"
# Version identifier for the image, defaults to "dev" if not set via environment
IMAGE_VERSION="${IMAGE_VERSION:-dev}"
# Operating system identifier used in scripts, defaults to "ubuntu22"
IMAGE_OS="${IMAGE_OS:-ubuntu22}"

# Script directory - assumes repo is installed at ~/dev/github-action/runner-images
# Get the absolute path of the directory containing this script, or use expected location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# If script is not in the expected location, use the standard installation path
if [[ ! -d "$SCRIPT_DIR/images/ubuntu/scripts" ]]; then
    SCRIPT_DIR="$HOME/dev/github-action/runner-images"
    echo "Script not found in current directory, using expected location: $SCRIPT_DIR"
fi
# Path to Ubuntu-specific build and test scripts within the repository
UBUNTU_SCRIPTS_DIR="${SCRIPT_DIR}/images/ubuntu/scripts"
# Path to Ubuntu assets like configuration files and post-generation scripts
ASSETS_DIR="${SCRIPT_DIR}/images/ubuntu/assets"
# Path to repository-wide helper scripts and PowerShell modules
HELPERS_DIR="${SCRIPT_DIR}/helpers"

echo "=== Ubuntu 22.04 Runner Image Provisioning Started ==="

# Create base directories
echo "Creating base directories..."
run_command "mkdir -p $IMAGE_FOLDER"
run_command "chmod 777 $IMAGE_FOLDER"

# Copy helper scripts
echo "Copying helper scripts..."
run_command "cp -r $UBUNTU_SCRIPTS_DIR/helpers $HELPER_SCRIPT_FOLDER"

# Configure APT mock
echo "Configuring APT mock..."
run_command "export DEBIAN_FRONTEND=noninteractive"
run_script "$UBUNTU_SCRIPTS_DIR/build/configure-apt-mock.sh"

# Configure repositories and APT
echo "Configuring repositories and APT..."
run_command "export HELPER_SCRIPTS=$HELPER_SCRIPT_FOLDER"
run_script "$UBUNTU_SCRIPTS_DIR/build/install-ms-repos.sh"
run_script "$UBUNTU_SCRIPTS_DIR/build/configure-apt-sources.sh"
run_script "$UBUNTU_SCRIPTS_DIR/build/configure-apt.sh"

# Configure system limits
echo "Configuring system limits..."
run_script "$UBUNTU_SCRIPTS_DIR/build/configure-limits.sh"

# Copy installer scripts and other files
echo "Copying installer scripts and assets..."
run_command "cp -r $UBUNTU_SCRIPTS_DIR/build $INSTALLER_SCRIPT_FOLDER"
run_command "cp -r $ASSETS_DIR/post-gen $IMAGE_FOLDER/"
run_command "cp -r $UBUNTU_SCRIPTS_DIR/tests $IMAGE_FOLDER/"
run_command "cp -r $UBUNTU_SCRIPTS_DIR/docs-gen $IMAGE_FOLDER/"
run_command "cp -r $HELPERS_DIR/software-report-base $IMAGE_FOLDER/docs-gen/"
run_command "cp $SCRIPT_DIR/images/ubuntu/toolsets/toolset-2204.json $INSTALLER_SCRIPT_FOLDER/toolset.json"

# Reorganize directories
echo "Reorganizing directories..."
run_command "mv $IMAGE_FOLDER/docs-gen $IMAGE_FOLDER/SoftwareReport"
run_command "mv $IMAGE_FOLDER/post-gen $IMAGE_FOLDER/post-generation"

# Configure image data
echo "Configuring image data..."
run_command "export IMAGE_VERSION IMAGEDATA_FILE"
run_script "$UBUNTU_SCRIPTS_DIR/build/configure-image-data.sh"

# Configure environment
echo "Configuring environment..."
run_command "export IMAGE_VERSION IMAGE_OS HELPER_SCRIPTS=$HELPER_SCRIPT_FOLDER"
run_script "$UBUNTU_SCRIPTS_DIR/build/configure-environment.sh"

# Install vital APT packages
echo "Installing vital APT packages..."
run_command "export DEBIAN_FRONTEND=noninteractive HELPER_SCRIPTS=$HELPER_SCRIPT_FOLDER INSTALLER_SCRIPT_FOLDER"
run_script "$UBUNTU_SCRIPTS_DIR/build/install-apt-vital.sh"

# Install PowerShell
if ! skip_if_disabled "$INSTALL_POWERSHELL" "PowerShell installation"; then
    echo "Installing PowerShell..."
    run_command "export HELPER_SCRIPTS=$HELPER_SCRIPT_FOLDER INSTALLER_SCRIPT_FOLDER"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-powershell.sh"

    # Install PowerShell modules
    echo "Installing PowerShell modules..."
    run_command "export HELPER_SCRIPTS=$HELPER_SCRIPT_FOLDER INSTALLER_SCRIPT_FOLDER"
    run_pwsh_script "$UBUNTU_SCRIPTS_DIR/build/Install-PowerShellModules.ps1"
    run_pwsh_script "$UBUNTU_SCRIPTS_DIR/build/Install-PowerShellAzModules.ps1"
fi

# Install main software packages
echo "Installing main software packages..."
run_command "export HELPER_SCRIPTS=$HELPER_SCRIPT_FOLDER INSTALLER_SCRIPT_FOLDER DEBIAN_FRONTEND=noninteractive"

# Core tools and infrastructure
if ! skip_if_disabled "$INSTALL_CORE_TOOLS" "Core tools and infrastructure"; then
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-actions-cache.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-runner-package.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-apt-common.sh"
fi

# Cloud tools
if ! skip_if_disabled "$INSTALL_CLOUD_TOOLS" "Cloud tools"; then
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-azcopy.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-azure-cli.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-azure-devops-cli.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-bicep.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-aliyun-cli.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-aws-tools.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-google-cloud-cli.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-heroku.sh"
fi

# Web servers
if ! skip_if_disabled "$INSTALL_WEB_SERVERS" "Web servers"; then
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-apache.sh"
fi

# Development tools and compilers
if ! skip_if_disabled "$INSTALL_DEVELOPMENT_TOOLS" "Development tools and compilers"; then
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-clang.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-swift.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-cmake.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-codeql-bundle.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-dotnetcore-sdk.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-gcc-compilers.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-gfortran.sh"
fi

# Container tools
if ! skip_if_disabled "$INSTALL_CONTAINER_TOOLS" "Container tools"; then
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-container-tools.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-kubernetes-tools.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-oc-cli.sh"
fi

# Version control
if ! skip_if_disabled "$INSTALL_VERSION_CONTROL" "Version control tools"; then
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-git.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-git-lfs.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-github-cli.sh"
fi

# Browsers
if ! skip_if_disabled "$INSTALL_BROWSERS" "Web browsers"; then
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-firefox.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-microsoft-edge.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-google-chrome.sh"
fi

# Infrastructure tools
if ! skip_if_disabled "$INSTALL_INFRASTRUCTURE" "Infrastructure tools"; then
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-terraform.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-packer.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-pulumi.sh"
fi

# Programming languages and runtimes
if ! skip_if_disabled "$INSTALL_LANGUAGES" "Programming languages and runtimes"; then
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-haskell.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-java-tools.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-leiningen.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-kotlin.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-mono.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-nvm.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-nodejs.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-php.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-ruby.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-rust.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-julia.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-sbt.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-python.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-pypy.sh"
fi

# Data science and analysis
if ! skip_if_disabled "$INSTALL_DATA_SCIENCE" "Data science tools"; then
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-miniconda.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-rlang.sh"
fi

# Databases
if ! skip_if_disabled "$INSTALL_DATABASES" "Database tools"; then
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-mysql.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-mssql-tools.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-sqlpackage.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-postgresql.sh"
fi

# Web servers and tools (additional)
if ! skip_if_disabled "$INSTALL_WEB_SERVERS" "Additional web servers"; then
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-nginx.sh"
fi

# Build tools and utilities
if ! skip_if_disabled "$INSTALL_BUILD_TOOLS" "Build tools and utilities"; then
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-bazel.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-oras-cli.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-vcpkg.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-yq.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-zstd.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-ninja.sh"
fi

# Configure DPKG (always run this as it's system configuration)
run_script "$UBUNTU_SCRIPTS_DIR/build/configure-dpkg.sh"

# Android SDK
if ! skip_if_disabled "$INSTALL_ANDROID" "Android SDK"; then
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-android-sdk.sh"
fi

# Install Docker (requires special environment variables)
if ! skip_if_disabled "$INSTALL_CONTAINER_TOOLS" "Docker installation"; then
    echo "Installing Docker..."
    run_command "export DOCKERHUB_LOGIN=\"${DOCKERHUB_LOGIN:-}\" DOCKERHUB_PASSWORD=\"${DOCKERHUB_PASSWORD:-}\""
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-docker.sh"
fi

# Configure toolset (requires PowerShell)
if ! skip_if_disabled "$INSTALL_POWERSHELL" "PowerShell toolset configuration"; then
    echo "Configuring toolset..."
    run_command "export HELPER_SCRIPTS=$HELPER_SCRIPT_FOLDER INSTALLER_SCRIPT_FOLDER"
    run_pwsh_script "$UBUNTU_SCRIPTS_DIR/build/Install-Toolset.ps1"
    run_pwsh_script "$UBUNTU_SCRIPTS_DIR/build/Configure-Toolset.ps1"
fi

# Miscellaneous tools
if ! skip_if_disabled "$INSTALL_MISC_TOOLS" "Miscellaneous tools"; then
    # Install pipx packages
    echo "Installing pipx packages..."
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-pipx-packages.sh"

    # Install Homebrew (run as regular user, not sudo)
    echo "Installing Homebrew..."
    run_command "export HELPER_SCRIPTS=$HELPER_SCRIPT_FOLDER DEBIAN_FRONTEND=noninteractive INSTALLER_SCRIPT_FOLDER"
    # Note: Homebrew installation should be run as regular user
    if [ "$EUID" -eq 0 ]; then
        echo "Warning: Homebrew installation should be run as regular user, not root"
        echo "Skipping Homebrew installation - run install-homebrew.sh manually as regular user"
    else
        run_script "$UBUNTU_SCRIPTS_DIR/build/install-homebrew.sh"
    fi

    # Selenium
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-selenium.sh"
fi

# Configure snap
echo "Configuring snap..."
run_command "export HELPER_SCRIPTS=$HELPER_SCRIPT_FOLDER"
run_script "$UBUNTU_SCRIPTS_DIR/build/configure-snap.sh"

echo "=== Reboot required at this point in Packer template ==="
echo "You may want to reboot and continue with the cleanup steps"

# Cleanup
echo "Running cleanup..."
run_script "$UBUNTU_SCRIPTS_DIR/build/cleanup.sh"

# Generate software report and run tests (requires PowerShell)
if ! skip_if_disabled "$INSTALL_POWERSHELL" "Software report generation and testing"; then
    echo "Generating software report and running tests..."
    run_command "export IMAGE_VERSION INSTALLER_SCRIPT_FOLDER"
    run_pwsh_script "$IMAGE_FOLDER/SoftwareReport/Generate-SoftwareReport.ps1 -OutputDirectory $IMAGE_FOLDER"
    run_pwsh_script "$IMAGE_FOLDER/tests/RunAll-Tests.ps1 -OutputDirectory $IMAGE_FOLDER"
else
    echo ">>> SKIPPING: Software report generation and testing (PowerShell disabled)"
fi

# Configure system
echo "Configuring system..."
run_command "export HELPER_SCRIPT_FOLDER INSTALLER_SCRIPT_FOLDER IMAGE_FOLDER"
run_script "$UBUNTU_SCRIPTS_DIR/build/configure-system.sh"

# Copy machine instance configuration
echo "Copying machine instance configuration..."
run_command "cp $ASSETS_DIR/ubuntu2204.conf /tmp/"
run_command "mkdir -p /etc/vsts"
run_command "cp /tmp/ubuntu2204.conf /etc/vsts/machine_instance.conf"

echo "=== Ubuntu 22.04 Runner Image Provisioning Completed ==="
echo "Software report generated at: $IMAGE_FOLDER/software-report.md"
echo "Test results available at: $IMAGE_FOLDER/tests/"