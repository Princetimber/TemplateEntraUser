# GitHub Copilot Repository Instructions

## Overview

**{{MODULE_NAME}}** — a PowerShell module built with [Sampler](https://github.com/gaelcolas/Sampler).
Target: PowerShell 7.0+. See `CLAUDE.md` for full project context and coding conventions.

## Environment

- PowerShell 7.x required
- Pester v5+ for testing
- PSScriptAnalyzer for linting
- Sampler framework for builds

## Build / Test / Lint

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

## Project Layout

```
source/
  Public/       # Exported functions (one per file)
  Private/      # Internal helpers (one per file)
  *.psm1        # Root module (dot-sources functions)
  *.psd1        # Module manifest
tests/
  QA/           # ScriptAnalyzer, changelog, help quality
  Unit/
    Public/     # Tests mirror source/Public/
    Private/    # Tests mirror source/Private/
```

## Key Conventions

- One function per file, filename matches function name
- `[CmdletBinding()]` on all advanced functions
- `SupportsShouldProcess` only on state-changing operations (Set-, New-, Remove-, Export-)
- Read-only functions (Get-, Test-, Find-) must NOT use ShouldProcess
- `ValidateNotNullOrEmpty`, `ValidateSet`, `ValidatePattern` for input validation
- Comment-based help: `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`
- Structured `try/catch/finally`, never swallow exceptions
- Use native PowerShell streams for logging (Write-Verbose, Write-Warning, etc.)
- Never use `Invoke-Expression` or hardcode secrets

## Copilot Behavior

- Follow existing patterns before creating new ones
- Prioritize security and clarity over cleverness
- Ask for clarification if requirements are ambiguous
- Never assume production access or generate insecure defaults
- See `CLAUDE.md` for detailed standards
