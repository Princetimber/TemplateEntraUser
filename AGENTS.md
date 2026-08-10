# AGENTS.md

Universal context for AI agents (Cursor, Copilot, Claude, etc.) working in this repository.

## Project

**{{MODULE_NAME}}** — a PowerShell module built with the [Sampler](https://github.com/gaelcolas/Sampler) framework.
Target runtime: **PowerShell 7.0+**.

## Build / Test / Lint

```powershell
# First build (resolves dependencies)
./build.ps1 -ResolveDependency -tasks build

# Subsequent builds
./build.ps1 -tasks build

# Run tests
./build.ps1 -tasks test
# or directly:
Invoke-Pester

# Lint
Invoke-ScriptAnalyzer -Path source/ -Recurse

# Package
./build.ps1 -tasks pack
```

Always run `Invoke-ScriptAnalyzer` after modifying `.ps1`/`.psm1` files and fix all warnings
before committing. Always run the full test suite after code changes, not just tests for
modified files.

## Directory Structure

```
source/
  Public/           # Exported functions (one per file)
  Private/          # Internal helpers (one per file)
  en-US/            # Help files
  TemplateModule.psm1   # Root module (dot-sources Public/ and Private/)
  TemplateModule.psd1   # Module manifest
tests/
  QA/               # ScriptAnalyzer compliance, changelog, help quality
    module.tests.ps1
  Unit/
    Public/          # Tests mirror source/Public/
    Private/         # Tests mirror source/Private/
```

## Code Style

### Functions

- **One function per file**; filename matches function name exactly (e.g. `Get-Greeting.ps1`).
- Always use `[CmdletBinding()]` on advanced functions.
- `SupportsShouldProcess` **only** on state-changing operations (`Set-`, `New-`, `Remove-`, `Export-`).
  Read-only functions (`Get-`, `Test-`, `Find-`) must **never** use `ShouldProcess`.
- Every public function requires comment-based help: `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`.
- Input validation is mandatory: `ValidateNotNullOrEmpty`, `ValidateSet`, `ValidatePattern`.

### Naming

- **Functions**: PascalCase with approved Verb-Noun (e.g. `Get-Greeting`, `Export-Greeting`).
- **Parameters**: PascalCase (e.g. `$FilePath`, `$Style`).
- **Local variables**: camelCase (e.g. `$resolvedPath`, `$trimmedName`).

### Error Handling

- Use structured `try/catch/finally`. Never swallow exceptions.
- Construct proper `ErrorRecord` objects with `ThrowTerminatingError` for critical failures.
- Non-terminating errors: `Write-Error -ErrorAction Continue`.

### Logging

- Use `Write-ToLog` (not `Write-Log`) as the standard logging function.
- `Write-ToLog` maps levels to native PowerShell streams:
  - `INFO` / `DEBUG` -> `Write-Verbose`
  - `WARN` -> `Write-Warning`
  - `ERROR` -> `Write-Error`
  - `SUCCESS` -> `Write-Information`

### Prohibited

- Never use `Invoke-Expression`.
- Never hardcode secrets, tokens, or credentials.
- Never suppress exceptions with empty `catch {}` blocks.
- Never add telemetry or background network calls without explicit documentation.

## Testing

- **Framework**: Pester v5+ with `BeforeDiscovery`/`BeforeAll`/`Describe`/`It` structure.
- **Coverage threshold**: 85% (configured in `build.yaml`).
- **Cross-platform**: all tests must run on macOS, Linux, and Windows. Mock Windows-only
  cmdlets (`Get-Service`, `Get-EventLog`, etc.) when needed.
- Test files mirror the source layout: `tests/Unit/Public/Get-Greeting.tests.ps1` tests
  `source/Public/Get-Greeting.ps1`.
- Mock all external dependencies including `Write-ToLog` in unit tests.

### Test Template

```powershell
#Requires -Version 7.0

BeforeAll {
    $script:dscModuleName = 'TemplateModule'
    Import-Module -Name $script:dscModuleName
}

AfterAll {
    Get-Module -Name $script:dscModuleName -All | Remove-Module -Force
}

Describe 'FunctionName' -Tag 'Unit' {
    BeforeAll {
        Mock -ModuleName $script:dscModuleName -CommandName Write-ToLog -MockWith {}
    }

    Context 'When <scenario>' {
        It 'Should <expected behavior>' {
            # Arrange, Act, Assert
        }
    }
}
```

## Dependencies

Defined in `RequiredModules.psd1` (pinned version ranges):

| Module               | Version Range  |
|----------------------|--------------- |
| InvokeBuild          | `[5.0, 6.0)`   |
| PSScriptAnalyzer     | `[1.22, 2.0)`  |
| Pester               | `[5.6, 6.0)`   |
| ModuleBuilder        | `[3.0, 4.0)`   |
| ChangelogManagement  | `[3.0, 4.0)`   |
| Sampler              | `[0.118, 1.0)` |
| Sampler.GitHubTasks  | `[0.6, 1.0)`   |

## CI/CD

- **GitHub Actions**: `.github/workflows/ci.yml` (push to main + PRs, matrix: Linux/Windows/macOS)
  and `.github/workflows/release.yml` (tags `v*`, publishes to PSGallery + GitHub Releases).
- **Azure Pipelines**: `azure-pipelines.yml` (Build -> Test multi-platform -> Coverage -> Deploy).

## Git Workflow

- Make fixes -> run all tests -> run ScriptAnalyzer -> commit to feature branch -> create PR -> merge -> clean up branch.
- Before deleting a branch, switch HEAD away from it first.
- Perform file writes sequentially to avoid cascade failures.

## Agent Principles

- Make the smallest safe change that achieves the goal.
- Follow existing patterns before introducing new architecture.
- Never assume access to live systems or production environments.
- If requirements are unclear, ask rather than guess.
- See `CLAUDE.md` for Claude Code-specific conventions and `.github/copilot-instructions.md`
  for GitHub Copilot instructions.
