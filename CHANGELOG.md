# Changelog for {{MODULE_NAME}}

The format is based on and uses the types of changes according to [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Removed the broken project-level `PostToolUse` ScriptAnalyzer hook from
  `.claude/settings.json`. The hook's `pwsh` script was wrapped in double
  quotes while the hook itself runs via `sh -c "<command>"`, which expanded
  `$files` and stripped the inner double quotes before `pwsh` ever parsed the
  script, corrupting `if ($files)` into `if ()` and throwing a `ParserError`
  on every `Edit`/`Write`. An equivalent, correctly single-quoted hook has
  been configured at the user level instead, so linting on `.ps1`/`.psm1`
  changes continues without the quoting bug or duplicate execution.

- Restored a passing `main` build: the checked-in `output/` build artifact used
  during local verification of the prior `Removed` change had gone stale before
  `Write-ToLog`'s Bearer-token and unquoted `key: value` redaction patterns were
  added, masking a real regression — removing the dead logging helpers' tests
  also dropped code coverage below the 85% threshold. Added targeted Pester
  coverage for previously-untested `Write-ToLog`/`Invoke-LogRotation` error
  paths (mutex-acquire timeout, log-write failure, rotation failure, directory-
  creation race, `ErrorRecord` invocation/inner-exception detail) and for
  `Get-Greeting`'s `ThrowTerminatingError` branch, bringing coverage to ~94.5%.

### Removed

- Removed `Write-ErrorLog`, `Get-LogFilePath`, `Get-LogFileSize`, `Set-LogFilePath`,
  and `Clear-LogFile` from `source/Private` along with their dedicated Pester
  tests. None of these functions were ever called by the module's public or
  private code — they existed only to be unit-tested, and `Write-ErrorLog`
  duplicated logic already handled by `Write-ToLog`'s own `ErrorRecord`
  parameter set. `Write-ToLog` (the module's standard logger) and
  `Invoke-LogRotation` (invoked from within `Write-ToLog`) are unchanged.

### Security

- Restricted the opencode GitHub Actions workflow to trusted commenters (repo
  owner, org members, invited collaborators). Previously any user could comment
  `/oc` on a public issue or PR to run the agent with `ANTHROPIC_API_KEY` and an
  OIDC token in scope. Also pinned the third-party opencode action to an immutable
  release commit (v1.18.9) instead of the mutable `@latest` branch.

### Fixed

- Enabled PSResourceGet so the NuGet version ranges in RequiredModules.psd1 resolve
  on a clean machine (the legacy PowerShellGet path could not parse them), and
  declared the transitive build dependencies (Configuration, Metadata, Plaster,
  PowerShellForGitHub) so ModuleBuilder and the Sampler tasks import cleanly.
- Shipped a valid module GUID in the source manifest so the un-initialized template
  builds in CI; Initialize-Template regenerates a unique GUID on init.
- Scoped the QA per-function help, unit-test, and ScriptAnalyzer checks to exported
  (public) functions, matching the convention that private functions carry no
  comment-based help. The QA ScriptAnalyzer check now honours PSScriptAnalyzerSettings.psd1.
- Hardened the ModuleFast dependency bootstrap to fetch over HTTPS with an
  HTML-interstitial and byte-decoding guard before executing the script.
- Corrected release pipelines to invoke the defined `publish_psgallery` workflow.
- Made template token replacement literal and escaped apostrophes in generated
  single-quoted secret assignments.
- Made source module imports fail fast when a private or public script cannot load.
- Corrected private script filenames to match their function names exactly.
- Replaced copied logging identifiers with template-specific file and mutex names.
- Made the Initialize-Template `.git`/`output` exclusions cross-platform; the previous
  backslash-only globs never matched on macOS/Linux, so those paths were not excluded.
- Extended Write-ToLog secret redaction to also cover Bearer tokens and unquoted
  `key: value` pairs (in addition to the existing key=value, JSON, and XML forms).

### Added

- Export-Greeting public function demonstrating correct ShouldProcess usage for
  state-changing operations (file writes with -WhatIf, -Confirm, -Force, -Append,
  -PassThru support).
- Clear-LogFile private function — clears the active log file with optional
  timestamped archive backup before clearing. ConfirmImpact=High always prompts
  unless -Force or -Confirm:$false is passed.
- Get-LogFilePath private function — returns the current module-scoped log file
  path ($script:LogFile) for inspection or use in external scripts.
- Get-LogFileSize private function — returns the current log file size in bytes;
  returns 0 if the log file does not yet exist.
- Invoke-LogRotation private function — rotates log files by shifting numbered
  backups up (log.5 removed, log.4 shifted to log.5, continuing through log to
  log.1). Called inside the
  Write-ToLog mutex; not intended for direct use.
- Set-LogFilePath private function — sets the module-scoped log file path with
  absolute-path validation; -Force creates the destination directory on demand.
  Also updates $Global:LogFile for backward compatibility.
- Write-ErrorLog private function — convenience wrapper around Write-ToLog for
  ErrorRecord objects. Logs the main message at ERROR level; exception type,
  category, location, and inner exception at DEBUG. -IncludeStackTrace appends
  the PowerShell script stack trace.

### Changed

- Updated `.claude/settings.json` PostToolUse hook to pass `-Settings PSScriptAnalyzerSettings.psd1`
  to `Invoke-ScriptAnalyzer`, ensuring the project-local ruleset is applied on every file edit
  inside Claude Code.
- Rebuilt Write-ToLog as a production-grade, thread-safe logging framework:
  - Named mutex (Global\TemplateModuleLog) prevents concurrent write
    corruption across threads and runspaces.
  - Auto-rotates at 10 MB, keeping up to 5 numbered backup files.
  - Redacts passwords, tokens, keys, and secrets in key=value, JSON, and XML/HTML
    formats before writing.
  - ANSI colour console output via PSStyle (7.2+) with escape-code fallback.
  - Dedicated ErrorRecord parameter set for structured exception logging.
  - Wrapper functions (Test-PathWrapper, Add-ContentWrapper, Get-ItemWrapper,
    New-ItemDirectoryWrapper) isolate I/O calls for Pester mockability.
  - Mutex is disposed on PowerShell exit via Register-EngineEvent.
- Removed ShouldProcess from Get-Greeting — read-only functions should not use
  SupportsShouldProcess. Removed Force parameter accordingly.
- Replaced string-throw error handling in Get-Greeting with proper ErrorRecord
  construction via ThrowTerminatingError.
- Replaced AllowEmptyString with ValidateNotNullOrEmpty and ValidatePattern on
  Format-GreetingMessage Name parameter.
- Pinned dependency versions in RequiredModules.psd1 using version ranges instead
  of 'latest'.
- Consolidated AI agent documentation: removed .github/instructions/ directory
  (5 files) and tests/tests.instructions.md, trimmed copilot-instructions.md.
- Updated README, CLAUDE.md, and help text to reflect all changes.

### Removed

- Windows PowerShell 5.1 test job from azure-pipelines.yml (contradicts PS 7.0
  requirement in #Requires).
- .github/instructions/ directory and tests/tests.instructions.md.
- Classes/ directory reference from documentation (directory did not exist).
