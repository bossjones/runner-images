#!/bin/bash

# Simplified Ubuntu 22.04 Runner Image Provisioning Script
# Run from the runner-images repo root directory with sudo privileges
#
# Prerequisites:
#   1. SSH to server
#   2. git clone https://github.com/actions/runner-images.git
#   3. cd runner-images
#   4. sudo ./provision-ubuntu-2204-simple.sh
#
# Basic Usage:
#   sudo ./provision-ubuntu-2204-simple.sh                           # Normal execution (includes prerequisites)
#   sudo DRY_RUN=1 ./provision-ubuntu-2204-simple.sh                 # Dry run mode (shows commands without executing)
#   sudo ENABLE_DOCTOR=1 ./provision-ubuntu-2204-simple.sh           # Doctor mode (check environment and auto-install missing packages)
#   sudo DISABLE_COLORS=1 ./provision-ubuntu-2204-simple.sh          # Disable colored output
#
# State management (resumption support):
#   sudo ./provision-ubuntu-2204-simple.sh                           # Resume from last failed step (if any)
#   sudo STATE_FILE=/custom/path.state ./provision-ubuntu-2204-simple.sh  # Custom state file location
#   sudo FORCE_RESTART=1 ./provision-ubuntu-2204-simple.sh           # Start fresh, ignore previous state
#
# Feature flags (set to 0 to disable specific software groups):
#   sudo INSTALL_ANDROID=0 INSTALL_POWERSHELL=0 ./provision-ubuntu-2204-simple.sh
#   sudo INSTALL_BROWSERS=0 INSTALL_DATA_SCIENCE=0 ./provision-ubuntu-2204-simple.sh
#
# Available feature flags:
#   INSTALL_CORE_TOOLS, INSTALL_CLOUD_TOOLS, INSTALL_DEVELOPMENT_TOOLS,
#   INSTALL_VERSION_CONTROL, INSTALL_BROWSERS, INSTALL_LANGUAGES,
#   INSTALL_DATABASES, INSTALL_WEB_SERVERS, INSTALL_BUILD_TOOLS,
#   INSTALL_CONTAINER_TOOLS, INSTALL_INFRASTRUCTURE, INSTALL_ANDROID,
#   INSTALL_POWERSHELL, INSTALL_DATA_SCIENCE, INSTALL_MISC_TOOLS
#
# Examples:
#   # Check environment and auto-install missing packages before running
#   sudo ENABLE_DOCTOR=1 ./provision-ubuntu-2204-simple.sh
#
#   # Install only core tools and languages, skip everything else
#   sudo INSTALL_CLOUD_TOOLS=0 INSTALL_BROWSERS=0 INSTALL_ANDROID=0 ./provision-ubuntu-2204-simple.sh
#
#   # Dry run to see what would be installed
#   sudo DRY_RUN=1 ./provision-ubuntu-2204-simple.sh
#
#   # Resume after fixing a failed step
#   sudo ./provision-ubuntu-2204-simple.sh
#
#   # Start completely fresh
#   sudo FORCE_RESTART=1 ./provision-ubuntu-2204-simple.sh
#
#   # Provide Docker Hub credentials to avoid rate limits
#   sudo DOCKERHUB_LOGIN=myuser DOCKERHUB_PASSWORD=mypass ./provision-ubuntu-2204-simple.sh
#
#   # Disable colors for logging to files
#   sudo DISABLE_COLORS=1 ./provision-ubuntu-2204-simple.sh > provision.log 2>&1

set -e

# Check if running in dry-run mode
DRY_RUN="${DRY_RUN:-0}"

# Doctor mode - check environment and requirements
ENABLE_DOCTOR="${ENABLE_DOCTOR:-0}"

# Color settings
DISABLE_COLORS="${DISABLE_COLORS:-0}"

# Export critical environment variables early
export DEBIAN_FRONTEND=noninteractive

# Define invoke_tests function that installation scripts expect
invoke_tests() {
    local test_name="$1"
    local test_file="$2"

    # Determine the correct test directory path
    local test_dir="$HELPER_SCRIPTS/../tests"
    local helpers_file="$test_dir/Helpers.psm1"
    local test_file_path="$test_dir/${test_name}.Tests.ps1"

    # Only run tests if PowerShell is available and tests directory exists
    if command -v pwsh >/dev/null 2>&1 && [[ -f "$helpers_file" ]] && [[ -f "$test_file_path" ]]; then
        echo_info "Running tests for $test_name..."
        if [[ "$DRY_RUN" == "1" ]]; then
            echo_dry_run "Would run tests for $test_name using $test_file_path"
            return 0
        fi

        # Run the PowerShell tests with correct paths
        # We need to override the hardcoded path in the PowerShell function
        pwsh -Command "
            Import-Module '$helpers_file' -DisableNameChecking

            # Override the Invoke-PesterTests function to use our correct path
            function global:Invoke-PesterTests {
                param([string]\$TestFile, [string]\$TestName)
                \$testPath = '$test_dir/\${TestFile}.Tests.ps1'
                if (-not (Test-Path \$testPath)) {
                    throw \"Unable to find test file '\$TestFile' on '\$testPath'.\"
                }
                if (-not (Get-Module 'Pester')) {
                    Import-Module Pester
                }
                \$configuration = [PesterConfiguration] @{
                    Run    = @{ Path = \$testPath; PassThru = \$true }
                    Output = @{ Verbosity = 'Detailed'; RenderMode = 'Plaintext' }
                }
                if (\$TestName) {
                    \$configuration.Filter.FullName = \$TestName
                }
                Invoke-Pester -Configuration \$configuration
            }

            Invoke-PesterTests -TestFile '$test_name' -TestName '$test_file'
        "
    else
        echo_info "Skipping tests for $test_name (PowerShell, test framework, or test file not available)"
        if [[ ! -f "$helpers_file" ]]; then
            echo_info "  Missing: $helpers_file"
        fi
        if [[ ! -f "$test_file_path" ]]; then
            echo_info "  Missing: $test_file_path"
        fi
    fi
}

# Feature flags - control which software groups to install
# Set to 0 to skip installation of that group
INSTALL_CORE_TOOLS="${INSTALL_CORE_TOOLS:-1}"                    # Actions cache, runner package, APT common, etc.
INSTALL_CLOUD_TOOLS="${INSTALL_CLOUD_TOOLS:-0}"                  # Azure CLI, AWS tools, Google Cloud CLI, etc.
INSTALL_DEVELOPMENT_TOOLS="${INSTALL_DEVELOPMENT_TOOLS:-1}"      # Clang, Swift, CMake, CodeQL, compilers, etc.
INSTALL_VERSION_CONTROL="${INSTALL_VERSION_CONTROL:-1}"          # Git, Git LFS, GitHub CLI
INSTALL_BROWSERS="${INSTALL_BROWSERS:-1}"                        # Firefox, Chrome, Microsoft Edge
INSTALL_LANGUAGES="${INSTALL_LANGUAGES:-1}"                      # Haskell, Java, Kotlin, Node.js, PHP, Ruby, Python, etc.
INSTALL_DATABASES="${INSTALL_DATABASES:-0}"                      # MySQL, PostgreSQL, MSSQL tools
INSTALL_WEB_SERVERS="${INSTALL_WEB_SERVERS:-0}"                  # Apache, Nginx
INSTALL_BUILD_TOOLS="${INSTALL_BUILD_TOOLS:-1}"                  # Bazel, vcpkg, yq, zstd, ninja
INSTALL_CONTAINER_TOOLS="${INSTALL_CONTAINER_TOOLS:-1}"          # Docker, container tools, Kubernetes tools
INSTALL_INFRASTRUCTURE="${INSTALL_INFRASTRUCTURE:-0}"            # Terraform, Packer, Pulumi
INSTALL_ANDROID="${INSTALL_ANDROID:-0}"                          # Android SDK
INSTALL_POWERSHELL="${INSTALL_POWERSHELL:-1}"                    # PowerShell and PowerShell modules
INSTALL_DATA_SCIENCE="${INSTALL_DATA_SCIENCE:-0}"                # Miniconda, R language
INSTALL_MISC_TOOLS="${INSTALL_MISC_TOOLS:-1}"                    # Selenium, pipx packages, Homebrew

# Color definitions (will be set based on DISABLE_COLORS)
RED=""
GREEN=""
YELLOW=""
BLUE=""
PURPLE=""
CYAN=""
WHITE=""
BOLD=""
RESET=""

# Initialize colors based on DISABLE_COLORS setting
init_colors() {
    if [[ "$DISABLE_COLORS" != "1" ]] && [[ -t 1 ]]; then
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[1;33m'
        BLUE='\033[0;34m'
        PURPLE='\033[0;35m'
        CYAN='\033[0;36m'
        WHITE='\033[1;37m'
        BOLD='\033[1m'
        RESET='\033[0m'
    fi
}

# Colored echo functions
echo_error() {
    echo -e "${RED}❌ ERROR:${RESET} $*"
}

echo_success() {
    echo -e "${GREEN}✅${RESET} $*"
}

echo_warning() {
    echo -e "${YELLOW}⚠️  WARNING:${RESET} $*"
}

echo_info() {
    echo -e "${BLUE}ℹ️${RESET}  $*"
}

echo_step() {
    echo -e "${CYAN}>>>${RESET} $*"
}

echo_header() {
    echo -e "${BOLD}${PURPLE}=== $* ===${RESET}"
}

echo_running() {
    echo -e "${CYAN}>>> RUNNING:${RESET} $*"
}

echo_running_script() {
    echo -e "${CYAN}>>> RUNNING SCRIPT:${RESET} $*"
}

echo_running_pwsh() {
    echo -e "${CYAN}>>> RUNNING POWERSHELL SCRIPT:${RESET} $*"
}

echo_skipping() {
    echo -e "${YELLOW}>>> SKIPPING:${RESET} $*"
}

echo_completed() {
    echo -e "${GREEN}>>> COMPLETED:${RESET} $*"
}

echo_failed() {
    echo -e "${RED}>>> FAILED:${RESET} $*"
}

echo_dry_run() {
    echo -e "${BLUE}    [DRY RUN]${RESET} $*"
}

# Function to check and install missing packages
check_and_install_package() {
    local command="$1"
    local package="$2"
    local is_required="${3:-true}"

    if command -v "$command" >/dev/null 2>&1; then
        echo_success "Found required command: $command"
        return 0
    fi

    # Package is missing, try to install it
    if [[ "$is_required" == "true" ]]; then
        echo_warning "Missing required command: $command"
    else
        echo_warning "Missing optional command: $command"
    fi

    if [[ "$EUID" -ne 0 ]]; then
        echo "   Cannot install - not running as root"
        return 1
    fi

    if [[ "$DRY_RUN" == "1" ]]; then
        echo_dry_run "Would run: apt-get update && apt-get install -y $package"
        return 0
    fi

    echo_step "INSTALLING: $package (provides $command)"

    # Update package list if not done recently
    if [[ ! -f /var/lib/apt/periodic/update-success-stamp ]] || [[ $(find /var/lib/apt/periodic/update-success-stamp -mmin +60) ]]; then
        echo_info "Updating package lists..."
        DEBIAN_FRONTEND=noninteractive apt-get update -qq
    fi

    # Install the package
    if DEBIAN_FRONTEND=noninteractive apt-get install -y "$package"; then
        echo_success "Successfully installed $package"

        # Verify the command is now available
        if command -v "$command" >/dev/null 2>&1; then
            echo_success "Command $command is now available"
            return 0
        else
            echo_error "Package $package installed but $command still not available"
            return 1
        fi
    else
        echo_error "Failed to install package $package"
        return 1
    fi
}

# Function to run a step with state tracking
run_step() {
    local step_name="$1"
    local step_type="$2"
    local step_command="$3"

    if grep -q "^$step_name$" "$STATE_FILE" 2>/dev/null; then
        echo_skipping "$step_name (already completed)"
        return 0
    fi

    echo_step "RUNNING STEP: $step_name"

    if [[ "$DRY_RUN" == "1" ]]; then
        echo_dry_run "Would execute $step_type: $step_command"
        echo_dry_run "Would mark step as completed"
        return 0
    fi

    # Pre-step setup: ensure required directories exist for specific steps
    if [[ "$step_name" == "configure-apt-sources" ]]; then
        echo_info "Ensuring cloud templates directory exists..."
        mkdir -p /etc/cloud/templates
    fi

    case "$step_type" in
        "command")
            eval "$step_command"
            ;;
        "script")
            bash "$step_command"
            ;;
        "pwsh")
            pwsh -f "$step_command"
            ;;
        *)
            echo_error "Unknown step type: $step_type"
            return 1
            ;;
    esac

    if [ $? -eq 0 ]; then
        echo "$step_name" >> "$STATE_FILE"
        echo_completed "$step_name"
    else
        echo_failed "$step_name"
        echo_error "Fix the issue and rerun the script to resume from this step"
        exit 1
    fi
}

# Legacy functions for backward compatibility and simple commands
run_command() {
    local cmd="$1"
    echo_running "$cmd"
    if [[ "$DRY_RUN" == "1" ]]; then
        echo_dry_run "Would execute: $cmd"
        return 0
    else
        eval "$cmd"
    fi
}

# Function to log and optionally execute bash scripts
run_script() {
    local script="$1"
    echo_running_script "$script"
    if [[ "$DRY_RUN" == "1" ]]; then
        echo_dry_run "Would execute: bash $script"
        return 0
    else
        bash "$script"
    fi
}

# Function to log and optionally execute PowerShell scripts
run_pwsh_script() {
    local script="$1"
    echo_running_pwsh "$script"
    if [[ "$DRY_RUN" == "1" ]]; then
        echo_dry_run "Would execute: pwsh -f $script"
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
        echo_skipping "$section_name (feature flag disabled)"
        return 0
    fi
    return 1
}

# Doctor function to check environment and requirements
run_doctor() {
    echo_header "DOCTOR MODE: Checking Environment and Requirements"

    local warnings=0
    local errors=0

    # Check if running as root
    if [[ "$EUID" -ne 0 ]]; then
        echo_error "Script must be run with sudo privileges"
        ((errors++))
    else
        echo_success "Running with sudo privileges"
    fi

    # Check if in correct directory
    if [[ ! -f "images/ubuntu/scripts/build/install-actions-cache.sh" ]]; then
        echo_error "Must run from runner-images repo root directory"
        echo "   Expected to find: images/ubuntu/scripts/build/install-actions-cache.sh"
        ((errors++))
    else
        echo_success "Running from correct directory (runner-images repo root)"
    fi

    # Check disk space (recommend at least 20GB free)
    available_space=$(df . -BG | awk 'NR==2{print $4}' | sed 's/G//')
    if [[ $available_space -lt 20 ]]; then
        echo_warning "Only ${available_space}GB free space available"
        echo "   Recommend at least 20GB for full installation"
        ((warnings++))
    else
        echo_success "Sufficient disk space: ${available_space}GB available"
    fi

    # Check internet connectivity to critical services
    echo ""
    echo_header "Network Connectivity"
    local critical_urls=("https://github.com" "https://api.github.com")
    local optional_urls=()

    # Add URLs based on enabled features
    if is_enabled "$INSTALL_LANGUAGES"; then
        optional_urls+=("https://downloads.python.org" "https://sh.rustup.rs" "https://getcomposer.org")
    fi

    if is_enabled "$INSTALL_DEVELOPMENT_TOOLS"; then
        optional_urls+=("https://packages.microsoft.com" "https://swift.org")
    fi

    if is_enabled "$INSTALL_BROWSERS"; then
        optional_urls+=("https://dl.google.com" "https://packages.microsoft.com")
    fi

    # Test critical URLs
    for url in "${critical_urls[@]}"; do
        if curl -s --connect-timeout 5 "$url" >/dev/null; then
            echo_success "Connected to $url"
        else
            echo_error "Cannot connect to $url"
            echo "   This is required for basic functionality"
            ((errors++))
        fi
    done

    # Test optional URLs
    if [[ ${#optional_urls[@]} -gt 0 ]]; then
        for url in "${optional_urls[@]}"; do
            if curl -s --connect-timeout 5 "$url" >/dev/null; then
                echo "✅ Connected to $url"
            else
                echo "⚠️  WARNING: Cannot connect to $url"
                echo "   Some installations may fail"
                ((warnings++))
            fi
        done
    fi

    # Check required commands for basic functionality
    echo ""
    echo_header "Basic System Commands"

    # Define command to package mappings
    local package_map=(
        "curl:curl"
        "wget:wget"
        "gpg:gnupg"
        "jq:jq"
        "unzip:unzip"
        "tar:tar"
    )

    for mapping in "${package_map[@]}"; do
        local cmd="${mapping%%:*}"
        local pkg="${mapping##*:}"

        if ! check_and_install_package "$cmd" "$pkg" "true"; then
            ((errors++))
        fi
    done

    # apt-get should always be available on Ubuntu, check separately
    if command -v "apt-get" >/dev/null 2>&1; then
        echo_success "Found required command: apt-get"
    else
        echo_error "Missing critical command: apt-get (cannot install packages)"
        ((errors++))
    fi

    # Check additional tools needed for enabled features
    echo ""
    echo_header "Feature-specific Commands"

    local optional_packages=()

    # Development tools requirements
    if is_enabled "$INSTALL_DEVELOPMENT_TOOLS"; then
        optional_packages+=("make:make" "rsync:rsync" "parallel:parallel" "lsb_release:lsb-release")
    fi

    # Language-specific requirements
    if is_enabled "$INSTALL_LANGUAGES"; then
        optional_packages+=("python3:python3" "pip3:python3-pip")
        # shasum is typically provided by perl package but is often already available
        if ! command -v shasum >/dev/null 2>&1; then
            optional_packages+=("shasum:perl")
        else
            echo_success "Found optional command: shasum"
        fi
    fi

    if [[ ${#optional_packages[@]} -gt 0 ]]; then
        for mapping in "${optional_packages[@]}"; do
            local cmd="${mapping%%:*}"
            local pkg="${mapping##*:}"

            if ! check_and_install_package "$cmd" "$pkg" "false"; then
                echo "   Some installations may fail without this command"
                ((warnings++))
            fi
        done
    else
        echo_info "No optional packages needed for current feature selection"
    fi

    # Docker-specific checks if container tools will be installed
    if is_enabled "$INSTALL_CONTAINER_TOOLS"; then
        echo ""
        echo "=== Docker Installation Checks ==="

        # Check if Docker credentials are provided
        if [[ -n "${DOCKERHUB_LOGIN:-}" ]] && [[ -n "${DOCKERHUB_PASSWORD:-}" ]]; then
            echo "✅ Docker Hub credentials provided (will avoid rate limits)"
            echo "   Login: ${DOCKERHUB_LOGIN}"
        else
            echo "⚠️  WARNING: No Docker Hub credentials provided"
            echo "   Docker installation will work but may hit rate limits"
            echo "   To provide credentials, set DOCKERHUB_LOGIN and DOCKERHUB_PASSWORD"
            ((warnings++))
        fi

        # Check if we want to pull images
        if [[ "${DOCKERHUB_PULL_IMAGES:-yes}" == "yes" ]]; then
            echo "✅ Docker images will be pulled during installation"
        else
            echo "ℹ️  Docker images will not be pulled (DOCKERHUB_PULL_IMAGES=no)"
        fi
    fi

    # PowerShell-specific checks
    if is_enabled "$INSTALL_POWERSHELL"; then
        echo ""
        echo "=== PowerShell Installation Checks ==="
        echo "✅ PowerShell will be installed and configured"
        echo "   This enables toolset configuration and software reporting"
    else
        echo ""
        echo "=== PowerShell Installation Checks ==="
        echo "⚠️  WARNING: PowerShell installation disabled"
        echo "   Some features like toolset configuration will be skipped"
        ((warnings++))
    fi

    # Homebrew-specific checks
    if is_enabled "$INSTALL_MISC_TOOLS"; then
        echo ""
        echo "=== Homebrew Installation Checks ==="
        if [[ "$EUID" -eq 0 ]]; then
            echo "⚠️  WARNING: Running as root - Homebrew installation will be skipped"
            echo "   Homebrew should be installed manually as regular user after provisioning"
            ((warnings++))
        else
            echo "✅ Running as regular user - Homebrew can be installed"
        fi
    fi

    # Environment variable checks
    echo ""
    echo "=== Environment Variables ==="

    # Check critical environment variables
    local env_vars=("HOME" "USER" "PATH")
    for var in "${env_vars[@]}"; do
        if [[ -n "${!var}" ]]; then
            echo "✅ $var is set: ${!var}"
        else
            echo "❌ ERROR: $var is not set"
            ((errors++))
        fi
    done

    # Check directory permissions for key system paths
    echo ""
    echo "=== Directory Permissions ==="

    local check_dirs=(
        "/usr/local/bin:Write access for binary installations"
        "/etc/environment:Write access for environment variables"
        "/tmp:Write access for temporary files"
    )

    if is_enabled "$INSTALL_DEVELOPMENT_TOOLS"; then
        check_dirs+=("/usr/share:Write access for .NET installation")
    fi

    for dir_info in "${check_dirs[@]}"; do
        local dir="${dir_info%%:*}"
        local desc="${dir_info##*:}"

        if [[ -d "$dir" ]] && [[ -w "$dir" ]]; then
            echo "✅ $dir is writable ($desc)"
        elif [[ -d "$dir" ]]; then
            echo "⚠️  WARNING: $dir exists but not writable ($desc)"
            echo "   May need sudo privileges during installation"
            ((warnings++))
        else
            echo "❌ ERROR: $dir does not exist ($desc)"
            ((errors++))
        fi
    done

    # Ubuntu version and architecture checks
    echo ""
    echo "=== System Information ==="

    if command -v lsb_release >/dev/null 2>&1; then
        local ubuntu_version=$(lsb_release -rs 2>/dev/null)
        echo "✅ Ubuntu version: $ubuntu_version"

        # Warn about version-specific requirements
        if [[ "$ubuntu_version" == "24.04" ]]; then
            echo "ℹ️  Ubuntu 24.04 detected - will configure pip with break-system-packages"
        fi
    else
        echo "⚠️  WARNING: Cannot determine Ubuntu version"
        ((warnings++))
    fi

    local arch=$(uname -m)
    echo "ℹ️  System architecture: $arch"
    if [[ "$arch" != "x86_64" ]]; then
        echo "⚠️  WARNING: Non-x86_64 architecture detected"
        echo "   Some packages may not be available for this architecture"
        ((warnings++))
    fi

    # State file checks
    echo ""
    echo "=== State Management Checks ==="
    if [[ -f "$STATE_FILE" ]]; then
        completed_steps=$(wc -l < "$STATE_FILE" 2>/dev/null || echo "0")
        echo "ℹ️  Found existing state file with $completed_steps completed steps"
        echo "   Location: $STATE_FILE"
        echo "   Script will resume from last incomplete step"
    else
        echo "ℹ️  No existing state file found"
        echo "   Will start fresh installation"
    fi

    if [[ -w "$(dirname "$STATE_FILE")" ]]; then
        echo "✅ State file location is writable"
    else
        echo "❌ ERROR: Cannot write to state file location: $(dirname "$STATE_FILE")"
        ((errors++))
    fi

    # Feature flag summary
    echo ""
    echo "=== Installation Plan Summary ==="
    local enabled_features=()
    local disabled_features=()

    local feature_flags=(
        "INSTALL_CORE_TOOLS:Core Tools"
        "INSTALL_CLOUD_TOOLS:Cloud Tools"
        "INSTALL_DEVELOPMENT_TOOLS:Development Tools"
        "INSTALL_VERSION_CONTROL:Version Control"
        "INSTALL_BROWSERS:Browsers"
        "INSTALL_LANGUAGES:Programming Languages"
        "INSTALL_DATABASES:Databases"
        "INSTALL_WEB_SERVERS:Web Servers"
        "INSTALL_BUILD_TOOLS:Build Tools"
        "INSTALL_CONTAINER_TOOLS:Container Tools"
        "INSTALL_INFRASTRUCTURE:Infrastructure Tools"
        "INSTALL_ANDROID:Android SDK"
        "INSTALL_POWERSHELL:PowerShell"
        "INSTALL_DATA_SCIENCE:Data Science Tools"
        "INSTALL_MISC_TOOLS:Miscellaneous Tools"
    )

    for flag_info in "${feature_flags[@]}"; do
        local flag_name="${flag_info%%:*}"
        local flag_desc="${flag_info##*:}"
        local flag_value="${!flag_name}"

        if [[ "$flag_value" == "1" ]]; then
            enabled_features+=("$flag_desc")
        else
            disabled_features+=("$flag_desc")
        fi
    done

    echo "📦 ENABLED features (${#enabled_features[@]}):"
    for feature in "${enabled_features[@]}"; do
        echo "   ✅ $feature"
    done

    if [[ ${#disabled_features[@]} -gt 0 ]]; then
        echo ""
        echo "⏭️  DISABLED features (${#disabled_features[@]}):"
        for feature in "${disabled_features[@]}"; do
            echo "   ❌ $feature"
        done
    fi

    # Final summary
    echo ""
    echo "=== Doctor Summary ==="
    if [[ $errors -gt 0 ]]; then
        echo "❌ ERRORS: $errors (must be fixed before running)"
        echo "🔧 Please address the errors above before proceeding"
        exit 1
    elif [[ $warnings -gt 0 ]]; then
        echo "⚠️  WARNINGS: $warnings (script will run but review recommended)"
        echo "✅ No critical errors found"
        echo "🚀 Ready to proceed (warnings can be ignored if acceptable)"
    else
        echo "✅ No errors or warnings found"
        echo "🚀 Environment is ready for provisioning"
    fi

    echo ""
    echo "To proceed with installation:"
    echo "  sudo ./provision-ubuntu-2204-simple.sh"
    echo ""
    echo "To run with different options:"
    echo "  sudo INSTALL_BROWSERS=0 ./provision-ubuntu-2204-simple.sh"
    echo "  sudo DRY_RUN=1 ./provision-ubuntu-2204-simple.sh"
}

# Initialize colors
init_colors

# Ensure essential packages are available (auto-install if missing)
ensure_essential_packages() {
    local essential_commands=("curl" "wget" "jq")
    local missing_packages=()

    for cmd in "${essential_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            case "$cmd" in
                "curl") missing_packages+=("curl") ;;
                "wget") missing_packages+=("wget") ;;
                "jq") missing_packages+=("jq") ;;
            esac
        fi
    done

    if [[ ${#missing_packages[@]} -gt 0 ]]; then
        echo_warning "Missing essential packages: ${missing_packages[*]}"

        if [[ "$EUID" -eq 0 ]]; then
            echo_step "AUTO-INSTALLING missing packages..."

            if [[ "$DRY_RUN" != "1" ]]; then
                DEBIAN_FRONTEND=noninteractive apt-get update -qq
                for pkg in "${missing_packages[@]}"; do
                    echo_info "Installing $pkg..."
                    DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg"
                done
                echo_success "Essential packages installed"
            else
                echo_dry_run "Would install: ${missing_packages[*]}"
            fi
        else
            echo_error "Cannot auto-install packages - not running as root"
            echo "Please run: sudo apt-get install ${missing_packages[*]}"
            exit 1
        fi
    fi
}

# Check essential packages before proceeding
ensure_essential_packages

# Install comprehensive prerequisites
install_prerequisites() {
    echo_header "Installing Prerequisites"

    if [[ "$DRY_RUN" == "1" ]]; then
        echo_dry_run "Would install comprehensive prerequisites package list"
        echo_dry_run "Would configure locales (en_US.UTF-8)"
        return 0
    fi

    echo_info "Updating package lists..."
    DEBIAN_FRONTEND=noninteractive apt-get update -qq

    echo_info "Installing comprehensive prerequisites (this may take a few minutes)..."

    # Install prerequisites in groups for better error handling and progress visibility
    local basic_packages=(
        "sudo" "curl" "wget" "git" "ca-certificates" "gnupg" "lsb-release"
        "apt-transport-https" "build-essential" "procps" "locales" "bash-completion"
    )

    local dev_packages=(
        "g++" "gcc" "gzip" "make" "openssl" "pkg-config" "unzip" "vim" "tree" "xz-utils"
    )

    local library_packages=(
        "libbz2-dev" "libcairo2-dev" "libffi-dev" "liblzma-dev" "libncurses5-dev"
        "libncursesw5-dev" "libpq-dev" "libreadline-dev" "libsqlite3-dev" "libssl-dev"
        "libyaml-dev" "zlib1g-dev"
    )

    local python_packages=(
        "python3-dev" "python3-openssl"
    )

    local other_packages=(
        "llvm" "sqlite3" "tk-dev"
    )

    # Install each group with progress reporting
    for package_group in "basic_packages" "dev_packages" "library_packages" "python_packages" "other_packages"; do
        local -n packages=$package_group
        local group_name=${package_group//_/ }
        group_name=${group_name^}  # Capitalize first letter

        echo_info "Installing $group_name..."
        if ! DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"; then
            echo_error "Failed to install $group_name"
            echo "Packages: ${packages[*]}"
            exit 1
        fi
    done

    echo_success "All prerequisites installed successfully"

    # Configure locales
    echo_info "Configuring locales (en_US.UTF-8)..."

    # Enable en_US.UTF-8 locale in /etc/locale.gen
    if ! grep -q "^en_US.UTF-8 UTF-8" /etc/locale.gen; then
        echo_info "Enabling en_US.UTF-8 in /etc/locale.gen..."
        # Remove any commented version first
        sed -i '/^# en_US.UTF-8 UTF-8/d' /etc/locale.gen
        # Add the uncommented version
        echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
    else
        echo_info "en_US.UTF-8 already enabled in /etc/locale.gen"
    fi

    # Generate locales manually for better control
    echo_info "Generating locales..."
    locale-gen en_US.UTF-8

    # Update system locale settings
    echo_info "Updating system locale settings..."

    # Create/update /etc/default/locale
    cat > /etc/default/locale << 'EOF'
LANG="en_US.UTF-8"
LANGUAGE="en_US:en"
LC_ALL="en_US.UTF-8"
EOF

    # Update current session environment
    export LANG="en_US.UTF-8"
    export LANGUAGE="en_US:en"
    export LC_ALL="en_US.UTF-8"

    # Verify the locale is available
    if locale -a | grep -q "en_US.utf8"; then
        echo_success "Locales configured successfully"
    else
        echo_warning "Locale generation completed but en_US.utf8 not found in available locales"
        echo_info "Available locales:"
        locale -a | head -10
    fi

    # Clean up package cache
    echo_info "Cleaning up package cache..."
    # apt-get clean
    # rm -rf /var/lib/apt/lists/*

    echo_success "Prerequisites installation completed"
}

# Install prerequisites before proceeding
install_prerequisites

# Wrapper function for tracked step
install_prerequisites_step() {
    install_prerequisites
}

# Check if running from repo root
if [[ ! -f "images/ubuntu/scripts/build/install-actions-cache.sh" ]]; then
    echo_error "Must run from runner-images repo root directory"
    exit 1
fi

# Configuration
REPO_ROOT="$(pwd)"
HELPER_SCRIPTS="${REPO_ROOT}/images/ubuntu/scripts/helpers"
INSTALLER_SCRIPT_FOLDER="${REPO_ROOT}/images/ubuntu/toolsets"
UBUNTU_SCRIPTS_DIR="${REPO_ROOT}/images/ubuntu/scripts"
IMAGE_VERSION="${IMAGE_VERSION:-dev}"
IMAGE_OS="${IMAGE_OS:-ubuntu22}"

# Create a temporary directory for installer scripts and copy the toolset file
TEMP_INSTALLER_DIR="/tmp/runner-images-installer"
mkdir -p "$TEMP_INSTALLER_DIR"

# Copy the appropriate toolset file to the expected location
if [[ -f "$INSTALLER_SCRIPT_FOLDER/toolset-2204.json" ]]; then
    echo_info "Setting up toolset configuration for Ubuntu 22.04"
    cp "$INSTALLER_SCRIPT_FOLDER/toolset-2204.json" "$TEMP_INSTALLER_DIR/toolset.json"
    # Update INSTALLER_SCRIPT_FOLDER to point to our temp directory
    INSTALLER_SCRIPT_FOLDER="$TEMP_INSTALLER_DIR"
else
    echo_error "Cannot find toolset-2204.json file at $INSTALLER_SCRIPT_FOLDER/toolset-2204.json"
    exit 1
fi

# State file for tracking completion
STATE_FILE="${STATE_FILE:-/tmp/provision-ubuntu-2204.state}"
FORCE_RESTART="${FORCE_RESTART:-0}"

echo_header "Simplified Ubuntu 22.04 Runner Image Provisioning Started"
echo_info "Repo root: $REPO_ROOT"
echo_info "Helper scripts: $HELPER_SCRIPTS"
echo_info "Installer scripts: $INSTALLER_SCRIPT_FOLDER"
echo_info "State file: $STATE_FILE"

if [[ "$DRY_RUN" == "1" ]]; then
    echo_warning "DRY RUN MODE ENABLED - No commands will be executed"
fi

# Initialize state file or show resumption status
if [[ "$FORCE_RESTART" == "1" ]]; then
    echo_step "FORCE RESTART - Removing existing state file"
    if [[ -f "$STATE_FILE" ]]; then
        rm -f "$STATE_FILE"
        echo_success "Removed existing state file: $STATE_FILE"
    else
        echo_info "No existing state file to remove"
    fi
elif [[ -f "$STATE_FILE" ]]; then
    completed_steps=$(wc -l < "$STATE_FILE" 2>/dev/null || echo "0")
    echo_step "RESUMING - Found state file with $completed_steps completed steps"
    echo_info "To start fresh, run with FORCE_RESTART=1"
else
    echo_step "STARTING FRESH - No previous state found"
fi

# Create state file directory if needed
mkdir -p "$(dirname "$STATE_FILE")"

# Run doctor mode if enabled
if [[ "$ENABLE_DOCTOR" == "1" ]]; then
    run_doctor
    exit 0
fi

# Export environment variables that scripts expect
run_command "export HELPER_SCRIPTS=$HELPER_SCRIPTS"
run_command "export INSTALLER_SCRIPT_FOLDER=$INSTALLER_SCRIPT_FOLDER"
run_command "export DEBIAN_FRONTEND=noninteractive"
run_command "export IMAGE_VERSION=$IMAGE_VERSION"
run_command "export IMAGE_OS=$IMAGE_OS"

# Install comprehensive prerequisites as a tracked step
run_step "install-prerequisites" "command" "install_prerequisites_step"

# Basic APT configuration
echo_info "Configuring APT..."
run_step "configure-apt-mock" "script" "$UBUNTU_SCRIPTS_DIR/build/configure-apt-mock.sh"
run_step "install-ms-repos" "script" "$UBUNTU_SCRIPTS_DIR/build/install-ms-repos.sh"
run_step "configure-apt-sources" "script" "$UBUNTU_SCRIPTS_DIR/build/configure-apt-sources.sh"
run_step "configure-apt" "script" "$UBUNTU_SCRIPTS_DIR/build/configure-apt.sh"

# System configuration
echo_info "Configuring system..."
run_step "configure-limits" "script" "$UBUNTU_SCRIPTS_DIR/build/configure-limits.sh"

# Install vital packages
if ! skip_if_disabled "$INSTALL_CORE_TOOLS" "Vital packages installation"; then
    echo_info "Installing vital packages..."
    run_step "install-apt-vital" "script" "$UBUNTU_SCRIPTS_DIR/build/install-apt-vital.sh"
fi

# Install PowerShell (needed for many other installations)
if ! skip_if_disabled "$INSTALL_POWERSHELL" "PowerShell installation"; then
    echo_info "Installing PowerShell..."
    run_step "install-powershell" "script" "$UBUNTU_SCRIPTS_DIR/build/install-powershell.sh"
    run_step "install-powershell-modules" "pwsh" "$UBUNTU_SCRIPTS_DIR/build/Install-PowerShellModules.ps1"
    run_step "install-powershell-az-modules" "pwsh" "$UBUNTU_SCRIPTS_DIR/build/Install-PowerShellAzModules.ps1"
fi

# Install core tools
if ! skip_if_disabled "$INSTALL_CORE_TOOLS" "Core tools installation"; then
    echo "Installing core tools..."
    run_step "install-actions-cache" "script" "$UBUNTU_SCRIPTS_DIR/build/install-actions-cache.sh"
    run_step "install-runner-package" "script" "$UBUNTU_SCRIPTS_DIR/build/install-runner-package.sh"
    run_step "install-apt-common" "script" "$UBUNTU_SCRIPTS_DIR/build/install-apt-common.sh"
fi

# Cloud tools
if ! skip_if_disabled "$INSTALL_CLOUD_TOOLS" "Cloud tools"; then
    echo "Installing cloud tools..."
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-azcopy.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-azure-cli.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-azure-devops-cli.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-bicep.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-aliyun-cli.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-aws-tools.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-google-cloud-cli.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-heroku.sh"
fi

# Version control
if ! skip_if_disabled "$INSTALL_VERSION_CONTROL" "Version control tools"; then
    echo "Installing version control tools..."
    run_step "install-git" "script" "$UBUNTU_SCRIPTS_DIR/build/install-git.sh"
    run_step "install-git-lfs" "script" "$UBUNTU_SCRIPTS_DIR/build/install-git-lfs.sh"
    run_step "install-github-cli" "script" "$UBUNTU_SCRIPTS_DIR/build/install-github-cli.sh"
fi

# Development tools and compilers
if ! skip_if_disabled "$INSTALL_DEVELOPMENT_TOOLS" "Development tools and compilers"; then
    echo "Installing development tools..."
    run_step "install-clang" "script" "$UBUNTU_SCRIPTS_DIR/build/install-clang.sh"
    run_step "install-swift" "script" "$UBUNTU_SCRIPTS_DIR/build/install-swift.sh"
    run_step "install-cmake" "script" "$UBUNTU_SCRIPTS_DIR/build/install-cmake.sh"
    run_step "install-codeql-bundle" "script" "$UBUNTU_SCRIPTS_DIR/build/install-codeql-bundle.sh"
    run_step "install-dotnetcore-sdk" "script" "$UBUNTU_SCRIPTS_DIR/build/install-dotnetcore-sdk.sh"
    run_step "install-gcc-compilers" "script" "$UBUNTU_SCRIPTS_DIR/build/install-gcc-compilers.sh"
    run_step "install-gfortran" "script" "$UBUNTU_SCRIPTS_DIR/build/install-gfortran.sh"
fi

# Programming languages and runtimes
if ! skip_if_disabled "$INSTALL_LANGUAGES" "Programming languages and runtimes"; then
    echo "Installing programming languages..."
    # run_script "$UBUNTU_SCRIPTS_DIR/build/install-haskell.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-java-tools.sh"
    # run_script "$UBUNTU_SCRIPTS_DIR/build/install-leiningen.sh"
    # run_script "$UBUNTU_SCRIPTS_DIR/build/install-kotlin.sh"
    # run_script "$UBUNTU_SCRIPTS_DIR/build/install-mono.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-nvm.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-nodejs.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-php.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-ruby.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-rust.sh"
    # run_script "$UBUNTU_SCRIPTS_DIR/build/install-julia.sh"
    # run_script "$UBUNTU_SCRIPTS_DIR/build/install-sbt.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-python.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-pypy.sh"
fi

# Container tools
if ! skip_if_disabled "$INSTALL_CONTAINER_TOOLS" "Container tools"; then
    echo "Installing container tools..."
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-container-tools.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-kubernetes-tools.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-oc-cli.sh"
    run_command "export DOCKERHUB_LOGIN=\"${DOCKERHUB_LOGIN:-}\" DOCKERHUB_PASSWORD=\"${DOCKERHUB_PASSWORD:-}\""
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-docker.sh"
fi

# Browsers
if ! skip_if_disabled "$INSTALL_BROWSERS" "Web browsers"; then
    echo "Installing web browsers..."
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-firefox.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-microsoft-edge.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-google-chrome.sh"
fi

# Web servers
if ! skip_if_disabled "$INSTALL_WEB_SERVERS" "Web servers"; then
    echo "Installing web servers..."
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-apache.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-nginx.sh"
fi

# Databases
if ! skip_if_disabled "$INSTALL_DATABASES" "Database tools"; then
    echo "Installing database tools..."
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-mysql.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-mssql-tools.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-sqlpackage.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-postgresql.sh"
fi

# Infrastructure tools
if ! skip_if_disabled "$INSTALL_INFRASTRUCTURE" "Infrastructure tools"; then
    echo "Installing infrastructure tools..."
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-terraform.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-packer.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-pulumi.sh"
fi

# Build tools and utilities
if ! skip_if_disabled "$INSTALL_BUILD_TOOLS" "Build tools and utilities"; then
    echo "Installing build tools..."
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-bazel.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-oras-cli.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-vcpkg.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-yq.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-zstd.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-ninja.sh"
fi

# Data science and analysis
if ! skip_if_disabled "$INSTALL_DATA_SCIENCE" "Data science tools"; then
    echo "Installing data science tools..."
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-miniconda.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-rlang.sh"
fi

# Android SDK
if ! skip_if_disabled "$INSTALL_ANDROID" "Android SDK"; then
    echo "Installing Android SDK..."
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-android-sdk.sh"
fi

# Miscellaneous tools
if ! skip_if_disabled "$INSTALL_MISC_TOOLS" "Miscellaneous tools"; then
    echo "Installing miscellaneous tools..."
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-pipx-packages.sh"
    run_script "$UBUNTU_SCRIPTS_DIR/build/install-selenium.sh"

    # Install Homebrew (run as regular user, not sudo)
    if [ "$EUID" -eq 0 ]; then
        echo "Warning: Homebrew installation should be run as regular user, not root"
        echo "Skipping Homebrew installation - run install-homebrew.sh manually as regular user"
    else
        run_script "$UBUNTU_SCRIPTS_DIR/build/install-homebrew.sh"
    fi
fi

# Configure DPKG (always run this as it's system configuration)
echo_info "Configuring DPKG..."
run_script "$UBUNTU_SCRIPTS_DIR/build/configure-dpkg.sh"

# Configure snap
echo_info "Configuring snap..."
run_script "$UBUNTU_SCRIPTS_DIR/build/configure-snap.sh"

# Configure toolset (requires PowerShell)
if ! skip_if_disabled "$INSTALL_POWERSHELL" "PowerShell toolset configuration"; then
    echo_info "Configuring toolset..."
    run_pwsh_script "$UBUNTU_SCRIPTS_DIR/build/Install-Toolset.ps1"
    run_pwsh_script "$UBUNTU_SCRIPTS_DIR/build/Configure-Toolset.ps1"
fi

# Cleanup
echo_info "Running cleanup..."
run_step "cleanup" "script" "$UBUNTU_SCRIPTS_DIR/build/cleanup.sh"

# Final completion summary
if [[ "$DRY_RUN" != "1" ]]; then
    completed_steps=$(wc -l < "$STATE_FILE" 2>/dev/null || echo "0")
    echo_header "Simplified Ubuntu 22.04 Runner Image Provisioning Completed"
    echo_success "Total completed steps: $completed_steps"
    echo_info "State file: $STATE_FILE"
    echo_info "To start fresh next time: FORCE_RESTART=1 $0"
else
    echo_header "Dry Run Completed"
fi
