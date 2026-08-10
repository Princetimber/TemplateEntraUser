# {{MODULE_NAME}}

A production-ready PowerShell module template built with the [Sampler](https://github.com/gaelcolas/Sampler) framework. This template provides standardized patterns, comprehensive testing, and CI/CD integration to accelerate your PowerShell module development.

## Features

- **PowerShell 7+ Standards** - Advanced functions, proper ShouldProcess usage, comprehensive validation
- **Sampler Framework** - Industry-standard build system with GitVersion semantic versioning
- **Comprehensive Testing** - Pester v5+ with 85% code coverage threshold, QA tests for ScriptAnalyzer compliance
- **CI/CD Integration** - Pre-configured GitHub Actions and Azure Pipelines workflows
- **Example Functions** - Working examples demonstrating correct patterns (read-only vs state-changing)
- **Quick Setup** - Interactive `Initialize-Template.ps1` script for rapid customization

## Quick Start

### 1. Create Your Module from Template

```powershell
# Clone or download this repository
git clone <your-template-repo-url> MyNewModule
cd MyNewModule

# Run the initialization script
./Initialize-Template.ps1
```

The init script will prompt you for:
- **Module Name** (e.g., `Invoke-MyModule`) - validates approved Verb-Noun pattern
- **Description** - what your module does
- **Author** - your name
- **Company** - your organization
- **GUID** - auto-generated if not provided

### 2. Build Your Module

```powershell
# First build (resolves dependencies)
./build.ps1 -ResolveDependency -tasks build

# Subsequent builds
./build.ps1 -tasks build

# Run tests
./build.ps1 -tasks test

# Lint
Invoke-ScriptAnalyzer -Path source/ -Recurse
```

### 3. Add Your Functions

```powershell
# Add a public function
New-Item -Path source/Public/Get-MyData.ps1 -ItemType File

# Add corresponding test
New-Item -Path tests/Unit/Public/Get-MyData.tests.ps1 -ItemType File
```

Follow the patterns in `Get-Greeting.ps1` (read-only) and `Export-Greeting.ps1` (state-changing with ShouldProcess).

## Directory Structure

```
{{MODULE_NAME}}/
├── .github/
│   ├── copilot-instructions.md           # GitHub Copilot instructions
│   └── workflows/
│       ├── ci.yml                        # GitHub Actions CI (multi-platform)
│       └── release.yml                   # GitHub Actions release to PSGallery
├── .vscode/
│   └── tasks.json                        # VS Code build/test tasks
├── source/
│   ├── {{MODULE_NAME}}.psd1              # Module manifest
│   ├── {{MODULE_NAME}}.psm1              # Root module (dot-sources functions)
│   ├── en-US/
│   │   └── about_{{MODULE_NAME}}.help.txt # About help file
│   ├── Public/                           # Exported functions (one per file)
│   │   ├── Get-Greeting.ps1              # Example read-only function
│   │   └── Export-Greeting.ps1           # Example state-changing function
│   └── Private/                          # Internal helpers (one per file)
│       ├── Format-GreetingMessage.ps1    # Example private function
│       ├── Write-ToLog.ps1              # Thread-safe logger (core entry point)
│       ├── Clear-LogFile.ps1            # Clears the active log (archive option)
│       ├── Get-LogFilePath.ps1          # Returns current log file path
│       ├── Get-LogFileSize.ps1          # Returns log file size in bytes
│       ├── Invoke-LogRotation.ps1       # Rotates numbered log backups
│       ├── Set-LogFilePath.ps1          # Sets the module-scoped log path
│       └── Write-ErrorLog.ps1           # ErrorRecord convenience wrapper
├── tests/
│   ├── QA/
│   │   └── module.tests.ps1              # ScriptAnalyzer, changelog, help tests
│   └── Unit/
│       ├── Public/
│       │   ├── Get-Greeting.tests.ps1
│       │   └── Export-Greeting.tests.ps1
│       └── Private/
│           ├── Format-GreetingMessage.tests.ps1
│           ├── Write-ToLog.tests.ps1
│           ├── Clear-LogFile.tests.ps1
│           ├── Get-LogFilePath.tests.ps1
│           ├── Get-LogFileSize.tests.ps1
│           ├── Invoke-LogRotation.tests.ps1
│           ├── Set-LogFilePath.tests.ps1
│           └── Write-ErrorLog.tests.ps1
├── azure-pipelines.yml                   # Azure Pipelines (multi-platform, PSGallery deploy)
├── build.ps1                             # Sampler build bootstrap
├── build.yaml                            # Sampler build configuration
├── CHANGELOG.md                          # Keep a Changelog format
├── CLAUDE.md                             # Claude Code context and standards
├── Initialize-Template.ps1               # One-time setup script (removes itself)
├── LICENSE                               # MIT License
├── README.md                             # This file
├── RequiredModules.psd1                  # Build dependencies (pinned version ranges)
├── Resolve-Dependency.ps1                # Dependency resolver
└── Resolve-Dependency.psd1               # Resolver configuration
```

## Patterns Demonstrated

### Get-Greeting (Read-Only Function)

- `[CmdletBinding()]` without ShouldProcess (read-only operations don't need it)
- Pipeline input, `PassThru` for rich object output
- Input validation with `ValidateSet`, `ValidateNotNullOrEmpty`
- Proper `ErrorRecord` construction with `ThrowTerminatingError`

### Export-Greeting (State-Changing Function)

- `[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]` - correct use of ShouldProcess
- `-WhatIf` and `-Confirm` support for safe file operations
- `-Force` to overwrite, `-Append` to add to existing files
- `-PassThru` returning `[System.IO.FileInfo]`

### Logging Framework (Private)

Seven private functions form a production-grade, thread-safe logging system:

| Function | Purpose |
|----------|---------|
| `Write-ToLog` | Core entry point. Writes timestamped entries to `$script:LogFile` under a named mutex. Supports INFO, DEBUG, WARN, ERROR, SUCCESS levels. Redacts sensitive values. ANSI colour console output with PSStyle fallback. |
| `Clear-LogFile` | Clears the active log. `ConfirmImpact=High` — prompts unless `-Force`. `-Archive` copies a timestamped `.bak` before clearing. |
| `Get-LogFilePath` | Returns the current module-scoped log file path for inspection or external use. |
| `Get-LogFileSize` | Returns the log file size in bytes; returns `0` if the file does not yet exist. |
| `Invoke-LogRotation` | Shifts numbered backups up (`.5` removed, `.4→.5`, …, current→`.1`). Called inside the `Write-ToLog` mutex — not for direct use. |
| `Set-LogFilePath` | Sets `$script:LogFile` (and `$Global:LogFile` for backward compatibility) to an absolute path. `-Force` creates the directory. |
| `Write-ErrorLog` | Convenience wrapper for `[ErrorRecord]` objects. Logs the message at ERROR; exception type, category, location, and inner exception at DEBUG. `-IncludeStackTrace` appends the PowerShell script stack trace. |

**Key design choices:**
- All file I/O calls go through thin wrapper functions (`Add-ContentWrapper`, `Test-PathWrapper`, etc.) so Pester can mock them without touching the filesystem.
- Auto-rotation at 10 MB keeps up to 5 numbered backups.
- Sensitive data (passwords, tokens, keys, secrets) is redacted in key=value, JSON, and XML formats before any write.

## CI/CD Setup

### GitHub Actions

1. **CI Workflow** (`.github/workflows/ci.yml`)
   - Triggers on: push to `main`, pull requests
   - Platforms: Ubuntu, Windows, macOS
   - Steps: Build -> Test -> ScriptAnalyzer -> Code Coverage

2. **Release Workflow** (`.github/workflows/release.yml`)
   - Triggers on: tags matching `v*`
   - Steps: Build -> Test -> Publish to PSGallery -> Create GitHub Release

**Required Secrets:**
- `PSGALLERY_API_KEY` - Your PowerShell Gallery API key

### Azure Pipelines

The template includes `azure-pipelines.yml` with:
- Multi-platform testing: Linux, Windows (PS7), macOS
- Code coverage reporting
- Deploy stage: publishes to PSGallery and GitHub Releases on `main` branch

**Required Variables:**
- `GalleryApiToken` - Your PowerShell Gallery API key
- `GitHubToken` - GitHub PAT for releases

## Publishing

Two independent publish targets are available — run only the one you need:

| Target | Build task | Destination |
|--------|-----------|-------------|
| PSGallery | `./build.ps1 -tasks publish_psgallery` | [PowerShell Gallery](https://www.powershellgallery.com) |
| GitHub Release | `./build.ps1 -tasks publish_github` | GitHub Releases |

### Step 1 — Obtain your credential

**PSGallery:**
1. Sign in at [powershellgallery.com](https://www.powershellgallery.com)
2. Go to **Account → API Keys → Create**
3. Scope it to your package name (or leave unscoped)
4. Copy the key — it is shown only once

**GitHub Release:**
1. Go to [github.com/settings/tokens](https://github.com/settings/tokens)
2. Generate a new token with `repo` scope
3. Copy the token — it is shown only once

### Step 2 — Store the credential locally (never commit it)

The easiest way is to pass `-PublishTarget` to `Initialize-Template.ps1` — it creates `secrets.local.ps1` automatically with only the credential needed:

```powershell
# PSGallery only
./Initialize-Template.ps1 -PublishTarget PSGallery

# GitHub Release only
./Initialize-Template.ps1 -PublishTarget GitHub
```

Alternatively, copy the example file and populate it manually:

```powershell
Copy-Item secrets.local.ps1.example secrets.local.ps1
```

`secrets.local.ps1` is listed in `.gitignore` and will never be committed. `secrets.local.ps1.example` is the safe, committed template.

### Step 3 — Publish

```powershell
# Load your credential into the session
. ./secrets.local.ps1

# Build first to ensure output is up to date
./build.ps1 -tasks build

# Publish to PSGallery only
./build.ps1 -tasks publish_psgallery

# OR publish a GitHub Release only
./build.ps1 -tasks publish_github
```

### CI/CD publishing (automated)

For automated pipelines, store credentials as protected secrets/variables — never in code:

| Platform | Variable name | Target | Where to configure |
|---|---|---|---|
| GitHub Actions | `PSGALLERY_API_KEY` | PSGallery | Repo → Settings → Secrets and variables → Actions |
| GitHub Actions | `GITHUB_TOKEN` | GitHub Release | Auto-provided by Actions runtime |
| Azure Pipelines | `GalleryApiToken` | PSGallery | Pipeline → Edit → Variables (lock icon) |
| Azure Pipelines | `GitHubToken` | GitHub Release | Pipeline → Edit → Variables (lock icon) |

## Testing

```powershell
# Run all tests
./build.ps1 -tasks test

# Run tests directly with Pester
Invoke-Pester

# Run with coverage
Invoke-Pester -CodeCoverage source/**/*.ps1
```

### Test Structure
- **QA Tests** (`tests/QA/module.tests.ps1`) - ScriptAnalyzer compliance, changelog format, help documentation quality
- **Unit Tests** (`tests/Unit/`) - Mirrors source structure with mocked dependencies

## Placeholder Reference

| Placeholder | Description | Example |
|-------------|-------------|---------|
| `{{MODULE_NAME}}` | Module name | `Invoke-MyModule` |
| `{{MODULE_DESCRIPTION}}` | Module description | `Storage management for Windows Server` |
| `{{AUTHOR}}` | Author name | `John Doe` |
| `{{COMPANY}}` | Company/organization | `Contoso Ltd` |
| `{{MODULE_GUID}}` | Unique module GUID | `12345678-1234-1234-1234-123456789012` |

Files named `TemplateModule.*` will be renamed to your actual module name.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

Built with:
- [Sampler](https://github.com/gaelcolas/Sampler) - PowerShell module build framework
- [Pester](https://github.com/pester/Pester) - PowerShell testing framework
- [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer) - PowerShell linter
- [GitVersion](https://gitversion.net/) - Semantic versioning

## Contributing

1. Fork the template repository
2. Make your improvements
3. Submit a pull request with a clear description

---

**Ready to build your module?** Run `./Initialize-Template.ps1` to get started!
