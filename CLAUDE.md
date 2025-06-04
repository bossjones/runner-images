# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains the source code for GitHub Actions Runner Images - the VM images used by GitHub-hosted runners (`ubuntu-latest`, `windows-latest`, `macos-latest`) and Azure DevOps Microsoft-hosted agents. Images are built using HashiCorp Packer and deployed weekly with updated software.

## Key Commands

### Building Images

**Complete image generation (PowerShell):**
```powershell
Import-Module .\helpers\GenerateResourcesAndImage.ps1
GenerateResourcesAndImage -SubscriptionId "sub-id" -ResourceGroupName "imagegen-rg" -AzureLocation "East US" -ImageType "Ubuntu2204"
```

**Direct Packer build:**
```bash
packer plugins install github.com/hashicorp/azure 2.2.1
packer build -var "subscription_id=$SubscriptionId" -var "client_id=$ClientId" -var "location=$Location" images/ubuntu/templates/ubuntu-22.04.pkr.hcl
```

### Testing

**Run all tests:**
```powershell
pwsh -File images/{os}/scripts/tests/RunAll-Tests.ps1
```

**Individual component tests:**
```powershell
Invoke-Pester images/ubuntu/scripts/tests/Git.Tests.ps1
```

### Validation

**JSON schema validation:**
```powershell
.\helpers\CheckJsonSchema.ps1
```

**Check outdated version pinning:**
```powershell
.\helpers\CheckOutdatedVersionPinning.ps1
```

## Architecture

### Core Structure
- **Packer Templates**: `images/{os}/templates/*.pkr.hcl` - Define VM builds using HCL2
- **Toolsets**: `images/{os}/toolsets/toolset-*.json` - Software version specifications (validated against `schemas/toolset-schema.json`)
- **Installation Scripts**: `images/{os}/scripts/build/` - Software installation automation
- **Tests**: `images/{os}/scripts/tests/*.Tests.ps1` - Pester-based validation

### OS Support
- **Ubuntu**: 22.04, 24.04 (`ubuntu-latest` points to 24.04)
- **Windows**: Server 2019, 2022, 2025 (`windows-latest` points to 2022)
- **macOS**: 13, 14, 15 (Intel x64 and ARM64) (`macos-latest` points to 14 ARM64)

### Image Generation Flow
1. Packer creates temporary Azure VM from base image
2. Connects via SSH/WinRM and runs installation scripts
3. Tests validate software installation
4. Creates managed image from VM disk
5. Auto-generates documentation (README files)

### Testing Framework
- **Technology**: Pester (PowerShell testing framework)
- **Pattern**: Each component has dedicated `*.Tests.ps1` file
- **Execution**: `RunAll-Tests.ps1` orchestrates all tests
- **Integration**: Tests run during Packer build process

### Software Management
- **Toolsets**: JSON files define versions for Python, Node.js, Go, etc.
- **Installation**: Dedicated scripts per tool (`install-*.sh`, `Install-*.ps1`)
- **Validation**: Each tool has corresponding test file
- **Documentation**: Auto-generated software reports

## Development Workflow

### Prerequisites
- Packer 1.8.2+
- PowerShell 5.0+
- Azure CLI
- Git
- Azure subscription with proper permissions

### Adding New Software
1. Update relevant `toolset-*.json` file
2. Create installation script in `scripts/build/`
3. Add validation tests in `scripts/tests/`
4. Update documentation generation if needed
5. Run schema validation and tests

### CI/CD Integration
- **Triggers**: PR labels (`CI ubuntu-all`, `CI ubuntu-2204`, etc.)
- **Build System**: Private repository handles actual builds
- **Testing**: Automated validation on PR submission

### Helper Modules
- **Common.Helpers.psm1**: Shared PowerShell functions
- **SoftwareReport.*.psm1**: Documentation generation
- **GenerateResourcesAndImage.ps1**: Complete build automation

## Key Files and Patterns

### Toolset Configuration
```json
{
  "toolcache": [
    {
      "name": "Python",
      "versions": ["3.9.*", "3.10.*", "3.11.*", "3.12.*", "3.13.*"]
    }
  ]
}
```

### Packer Template Structure
- Uses Azure ARM builder
- Environment variables for authentication
- Provisioners for installation and testing
- Post-processors for cleanup

### PowerShell Testing Pattern
```powershell
Describe "ToolName" {
    It "Should be installed" {
        Get-Command tool-name | Should -Not -BeNullOrEmpty
    }
}
```

## Network and Security
- Service Principal authentication for Azure
- IP restrictions for build agent access
- Network security groups for temporary VMs
- Credential scanning exclusions for build logs

## Post-Generation Scripts
Located in `images/{os}/assets/post-gen/` - these scripts run on deployed VMs to configure user-specific settings and permissions after image deployment.

## Simplified Provisioning Script

### Custom Local Provisioning
- **File**: `provision-ubuntu-2204-simple.sh` - Simplified provisioning script for local Ubuntu 22.04 setup
- **Purpose**: Replicate GitHub Actions runner environment on any Ubuntu 22.04 system without Packer
- **Cross-platform development**: Developed on macOS, executed on Ubuntu

### Usage
```bash
# Basic usage
sudo ./provision-ubuntu-2204-simple.sh

# Check environment and auto-install missing packages
sudo ENABLE_DOCTOR=1 ./provision-ubuntu-2204-simple.sh

# Dry run to see what would be installed
sudo DRY_RUN=1 ./provision-ubuntu-2204-simple.sh

# Resume from failed step (automatic state management)
sudo ./provision-ubuntu-2204-simple.sh

# Start completely fresh
sudo FORCE_RESTART=1 ./provision-ubuntu-2204-simple.sh

# Disable colors for logging
sudo DISABLE_COLORS=1 ./provision-ubuntu-2204-simple.sh > provision.log 2>&1
```

### Key Features
- **State Management**: Automatic resumption from failed steps using state files
- **Feature Flags**: Granular control over software installation groups
- **Doctor Mode**: Environment validation and automatic package installation
- **Color Output**: Enhanced readability with optional color disable
- **Cross-platform**: Handles macOS development → Ubuntu execution workflow

### Environment Requirements
- **Critical packages**: curl, wget, jq, gpg, unzip, tar (auto-installed if missing)
- **System directories**: `/etc/cloud/templates`, `/usr/local/bin`, `/etc/environment`
- **Network access**: GitHub, package repositories, language-specific download sites
- **Permissions**: sudo access for package installation and system configuration

### Architecture Differences from Packer
- **No IMAGE_FOLDER**: Runs directly from repo directory instead of `/imagegeneration`
- **Temporary toolset**: Creates `/tmp/runner-images-installer/toolset.json` from `toolset-2204.json`
- **Helper functions**: Includes `invoke_tests()` function for PowerShell test integration
- **Auto-recovery**: Creates missing system directories (e.g., `/etc/cloud/templates`)

### Development Notes
- **Environment variables**: `DEBIAN_FRONTEND=noninteractive` set early to prevent interactive prompts
- **Toolset mapping**: Ubuntu 22.04 uses `toolset-2204.json` → `toolset.json` at runtime
- **Package installation**: Robust error handling with automatic retry and validation
- **Testing integration**: Graceful fallback when PowerShell/tests unavailable
