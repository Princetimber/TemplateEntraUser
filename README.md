# Copy-EntraUser

A production-ready PowerShell module, built with the [Sampler](https://github.com/gaelcolas/Sampler) framework, that clones an Entra ID user's direct group memberships and PIM-for-Groups eligible assignments onto a new or existing user — mirroring the template user's access tier without ever granting a permanent membership where the template only held PIM eligibility.

## Features

- **PowerShell 7+ Standards** - Advanced functions, proper ShouldProcess usage, comprehensive validation
- **Sampler Framework** - Industry-standard build system with GitVersion semantic versioning
- **Comprehensive Testing** - Pester v5+ with 85% code coverage threshold, QA tests for ScriptAnalyzer compliance
- **CI/CD Integration** - Pre-configured GitHub Actions and Azure Pipelines workflows
- **Example Functions** - Working examples demonstrating correct patterns (read-only vs state-changing)

## Quick Start

The `Copy-EntraUser` module is already instantiated. To build and import it:

```powershell
# First build (resolves dependencies)
./build.ps1 -ResolveDependency -tasks build

# Subsequent builds
./build.ps1 -tasks build

# Run tests
./build.ps1 -tasks test

# Import the module
Import-Module ./output/module/Copy-EntraUser

# Lint
Invoke-ScriptAnalyzer -Path source/ -Recurse
```

## Authentication

The `Copy-EntraUser` function authenticates via **certificate-based app-only authentication (CBA)** by default, falling back automatically to **interactive delegated sign-in** if certificate-based auth cannot be established.

### Authentication Parameters

Two parameter sets are available via `Connect-EntraGraphSession`:

1. **Portable PFX File** (recommended, default)
   - `-CertificatePath` — Path to a PFX certificate file
   - `-CertificatePassword` — SecureString password protecting the PFX file
   - Works identically on **Windows, macOS, and Linux**

2. **Certificate Thumbprint** (Windows-only convenience)
   - `-CertificateThumbprint` — Thumbprint of a certificate already in the Windows certificate store
   - Not portable to macOS or Linux

### Fallback Behavior

If certificate-based authentication fails for any reason (missing certificate, expired certificate, module not installed, or API errors), the function automatically falls back to interactive delegated sign-in with an **explicit warning**:

```
Certificate-based authentication failed (...); falling back to interactive delegated sign-in.
```

Interactive sign-in requests explicit scopes from `Get-RequiredGraphPermission` — never relying on previously cached consent.

## Required Graph Permissions

The `Copy-EntraUser` function requires three Microsoft Graph permissions. Both application permissions (CBA) and delegated scopes (interactive fallback) use the same set:

### Application Permissions (Certificate-Based Auth)

| Permission | Description |
|-----------|-------------|
| `User.ReadWrite.All` | Read and write all user properties and group memberships |
| `GroupMember.ReadWrite.All` | Read and write group membership for all groups |
| `PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup` | Read and write PIM-for-Groups eligibility schedule assignments |

### Delegated Scopes (Interactive Auth)

| Scope | Description |
|-------|-------------|
| `User.ReadWrite.All` | Read and write all user properties and group memberships |
| `GroupMember.ReadWrite.All` | Read and write group membership for all groups |
| `PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup` | Read and write PIM-for-Groups eligibility schedule assignments |

> **Note:** Both tables list the exact same three permissions. The source of truth is the `Get-RequiredGraphPermission` function, which ensures both CBA and interactive auth paths remain in sync and cannot drift.

## Directory Structure

```
Copy-EntraUser/
├── .github/
│   ├── copilot-instructions.md           # GitHub Copilot instructions
│   └── workflows/
│       ├── ci.yml                        # GitHub Actions CI (multi-platform)
│       └── release.yml                   # GitHub Actions release to PSGallery
├── .vscode/
│   └── tasks.json                        # VS Code build/test tasks
├── source/
│   ├── Copy-EntraUser.psd1              # Module manifest
│   ├── Copy-EntraUser.psm1              # Root module (dot-sources functions)
│   ├── en-US/
│   │   └── about_Copy-EntraUser.help.txt # About help file
│   ├── Public/
│   │   └── Copy-EntraUser.ps1           # The exported cmdlet: orchestrates the whole clone
│   └── Private/                          # Internal helpers (one per file)
│       ├── Connect-EntraGraphSession.ps1        # CBA connect, auto-falls back to interactive
│       ├── Resolve-EntraTemplateUser.ps1        # Resolves the template user by UPN/ObjectId
│       ├── Resolve-EntraNewUser.ps1             # Resolves/creates the target user (idempotent)
│       ├── Get-EntraTemplateGroupMembership.ps1 # Reads direct memberships + PIM eligibility
│       ├── Split-EntraGroupMembership.ps1       # Pure partition: Plain / Pim / Unsupported
│       ├── Add-EntraGroupMembership.ps1         # Idempotent direct membership write
│       ├── Grant-EntraGroupEligibility.ps1      # Idempotent PIM-for-Groups eligibility grant
│       ├── Get-RequiredGraphPermission.ps1      # Single source of truth for required scopes
│       ├── Test-RequiredGraphModule.ps1         # Verifies Microsoft.Graph sub-modules are present
│       └── Write-ToLog.ps1                      # Thread-safe logger used across the module
├── tests/
│   ├── QA/
│   │   ├── module.tests.ps1              # ScriptAnalyzer, changelog, help tests
│   │   └── repository.tests.ps1          # Repository-level hygiene checks
│   ├── Unit/
│   │   ├── Public/
│   │   │   └── Copy-EntraUser.tests.ps1
│   │   └── Private/                      # One test file per helper above
│   └── Integration/
│       └── Copy-EntraUser.Idempotency.tests.ps1  # Full-chain, zero-mutation-on-rerun proof
├── ASSUMPTIONS.md                        # Decisions register for this instantiation
├── azure-pipelines.yml                   # Azure Pipelines (multi-platform, PSGallery deploy)
├── build.ps1                             # Sampler build bootstrap
├── build.yaml                            # Sampler build configuration
├── CHANGELOG.md                          # Keep a Changelog format
├── CLAUDE.md                             # Claude Code context and standards
├── LICENSE                               # MIT License
├── README.md                             # This file
├── RequiredModules.psd1                  # Build dependencies (pinned version ranges)
├── Resolve-Dependency.ps1                # Dependency resolver
└── Resolve-Dependency.psd1               # Resolver configuration
```

## Usage

### Example 1: Certificate-Based Auth with Portable PFX File

This example uses certificate-based app-only authentication with a portable PFX file:

```powershell
# Copy template user's group memberships and PIM eligibility to a new hire
Copy-EntraUser `
    -TemplateUserId 'template.user@contoso.onmicrosoft.com' `
    -NewUser 'new.hire@contoso.onmicrosoft.com' `
    -TenantId '00000000-0000-0000-0000-000000000000' `
    -ClientId '00000000-0000-0000-0000-000000000001' `
    -CertificatePath ./copy-entrauser.pfx `
    -CertificatePassword (Read-Host -AsSecureString 'Certificate password')
```

**What happens:**
- The function connects to Microsoft Graph using the certificate and client ID
- Resolves both the template user (existing employee) and target user (new hire)
- Enumerates the template user's direct group memberships
- Identifies which groups are plain security groups and which are PIM-for-Groups groups
- Adds the new hire as a direct member to all plain groups
- Grants ELIGIBLE (not active) PIM-for-Groups assignments matching the template user's access tier (member vs owner)
- Skips dynamic-membership and role-assignable groups with a warning

### Example 2: Interactive Fallback with User Creation

This example demonstrates the interactive fallback scenario when certificate authentication fails (e.g., certificate expired or missing):

```powershell
# Create a new user and clone template user's permissions (certificate path specified
# but unavailable; falls back to interactive auth automatically)
Copy-EntraUser `
    -TemplateUserId 'template.user@contoso.onmicrosoft.com' `
    -NewUser @{
        DisplayName = 'New Hire'
        UserPrincipalName = 'new.hire@contoso.onmicrosoft.com'
        MailNickname = 'new.hire'
        PasswordProfile = @{ Password = -join (1..16 | ForEach-Object { $c = [char[]](48..57 + 65..90 + 97..122 + 33 + 35 + 36 + 37); $c[[System.Security.Cryptography.RandomNumberGenerator]::GetInt32(0, $c.Length)] }) }
        AccountEnabled = $true
    } `
    -TenantId '00000000-0000-0000-0000-000000000000' `
    -ClientId '00000000-0000-0000-0000-000000000001' `
    -CertificatePath ./missing-or-expired.pfx `
    -CertificatePassword (Read-Host -AsSecureString 'Certificate password')
```

**What happens:**
- The function attempts to load the PFX certificate; if the file doesn't exist or is expired, it emits a warning:
  ```
  Certificate-based authentication failed (...); falling back to interactive delegated sign-in.
  ```
- The function then connects interactively, prompting you to sign in with your Microsoft account
- Interactive sign-in explicitly requests the three required scopes (not relying on cached consent)
- Creates the new user with the properties specified in the hashtable
- Clones the template user's group memberships and PIM eligibility to the newly created account

## How Copy-EntraUser Works

`Copy-EntraUser` is composed of small, single-responsibility private helpers, each independently unit-tested and orchestrated by the public `Copy-EntraUser` cmdlet:

| Function | Purpose |
|----------|---------|
| `Connect-EntraGraphSession` | Certificate-based app-only auth by default; falls back to interactive delegated sign-in (with an explicit warning) if the certificate cannot be loaded. |
| `Resolve-EntraTemplateUser` | Resolves the template user by UPN or ObjectId. |
| `Resolve-EntraNewUser` | Resolves an existing target user, or idempotently creates one from a supplied property hashtable (checks for an existing UPN match first). |
| `Get-EntraTemplateGroupMembership` | Reads the template user's direct (non-transitive) group memberships and current PIM-for-Groups eligibility schedule instances; resolves the group object for any eligibility-only group not already covered by a direct membership. |
| `Split-EntraGroupMembership` | Pure function: partitions the combined group set into `PlainGroup` (direct membership), `PimGroup` (PIM-for-Groups eligible), and `UnsupportedGroup` (dynamic-membership or role-assignable groups, skipped with a warning). |
| `Add-EntraGroupMembership` | Idempotently adds the target user as a direct member (reads current members first, skips if already present). |
| `Grant-EntraGroupEligibility` | Idempotently grants an ELIGIBLE (never active/permanent) PIM-for-Groups assignment mirroring the template user's access tier. |
| `Get-RequiredGraphPermission` | Single source of truth for the required application/delegated Graph permissions, keeping both auth paths in sync. |
| `Test-RequiredGraphModule` | Verifies the required Microsoft.Graph sub-modules are installed before connecting. |

**Key design choices:**
- Every mutating helper (`Add-EntraGroupMembership`, `Grant-EntraGroupEligibility`, `Resolve-EntraNewUser`) reads current state before writing, so re-running `Copy-EntraUser` against an already-provisioned user makes zero mutating Graph calls (see `tests/Integration/Copy-EntraUser.Idempotency.tests.ps1`).
- `Split-EntraGroupMembership` is a pure function with no Graph calls or side effects, making the routing logic (plain vs. PIM vs. unsupported) exhaustively unit-testable in isolation.
- A template user's PIM-for-Groups eligibility never becomes a permanent direct membership on the new user — the module always mirrors the access *tier*, never escalates it.
- `Write-ToLog` (and its supporting private helpers) provide thread-safe, mutex-protected logging with automatic rotation and secret redaction, used across the module for diagnostics.

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

Copy the example file and populate it with your credentials:

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
