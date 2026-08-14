# Changelog for Copy-EntraUser

The format is based on and uses the types of changes according to [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Added `RoleManagement.Read.Directory` to `Get-RequiredGraphPermission` (now
  six permissions total), matching the Microsoft Graph requirement for
  `Get-MgRoleManagementDirectoryRoleDefinition` ("List roleDefinitions").
  Updated the `.NOTES` permission tables in `Copy-EntraUser.ps1` and
  `README.md` to match.
- Added a shared private retry helper, `Invoke-EntraGraphRequestWithRetry`,
  that honors the `Retry-After` header with exponential backoff for Graph
  429 (throttled) / 503 (unavailable) responses, and wired it around the
  Graph SDK calls in `Add-EntraGroupMembership`, `Grant-EntraGroupEligibility`,
  `Grant-EntraRoleEligibility`, `Get-EntraTemplateGroupMembership`,
  `Get-EntraTemplateRoleAssignment`, `Resolve-EntraNewUser`, and
  `Resolve-EntraTemplateUser`.
- Added a shared private helper, `ConvertTo-EscapedODataString`, and applied
  it consistently everywhere a variable is interpolated into a Graph
  `-Filter` string (previously only `Resolve-EntraNewUser` escaped).
- `Copy-EntraUser` now emits structured `Write-ToLog` entries (INFO/WARN/
  SUCCESS) around connect/disconnect and each clone action, alongside the
  existing `Write-Verbose`/`Write-Warning` streams.

### Changed

- `Copy-EntraUser` now connects to Microsoft Graph once in `begin {}` and
  disconnects once in `end {}` (or immediately on error), instead of
  reconnecting/disconnecting for every pipelined `-NewUser` object.
- `Connect-EntraGraphSession` no longer declares `SupportsShouldProcess`:
  `Connect-` is not a state-changing verb per this project's convention, so
  it now always attempts the connection it was called to make.
- `Add-EntraGroupMembership` now performs a targeted `Get-MgGroupMember
  -Filter "id eq '...'"` lookup instead of fetching the entire group
  membership with `-All`.
- `New-EntraUserPassword` now guarantees at least one uppercase, lowercase,
  digit, and symbol character, then Fisher-Yates shuffles the full
  character array (using the same CSPRNG) before building the
  `SecureString`.
- `Grant-EntraGroupEligibility` and `Grant-EntraRoleEligibility` now use
  `(Get-Date).ToUniversalTime()` for `startDateTime` instead of local time.
  PIM eligibility expiration remains intentionally normalized to
  `NoExpiration` rather than mirrored from the template user -- see the
  updated comment-based help in both files and in `Copy-EntraUser.ps1` for
  the rationale.
- Added `try`/`catch` with actionable error messages around the remaining
  unprotected Graph-mutating calls in `Add-EntraGroupMembership`,
  `Grant-EntraGroupEligibility`, `Grant-EntraRoleEligibility`,
  `Get-EntraTemplateGroupMembership`, and `Get-EntraTemplateRoleAssignment`.
- Added `[ValidateNotNullOrEmpty()]` to mandatory string ID parameters that
  were missing it across `source/Private/*.ps1`.

- `Copy-EntraUser` now also clones the template user's directly-assigned,
  PIM-eligible directory role assignments onto the new/target user, as an
  ELIGIBLE (never active/permanent) grant — mirroring the existing
  PIM-for-Groups eligibility cloning. Administrative Unit-scoped role
  eligibilities and permanent (non-PIM) role assignments are skipped with a
  named `Write-Warning` rather than cloned or silently dropped. Requires two
  additional Graph permissions: `RoleEligibilitySchedule.ReadWrite.Directory`
  and `RoleAssignmentSchedule.Read.Directory` (see
  `Get-RequiredGraphPermission`).

- `Copy-EntraUser` now accepts an opt-in `-PassThru` switch, returning a
  result object with `NewUserId` and `GeneratedPassword` properties.
  `GeneratedPassword` is populated only when a password was auto-generated
  (i.e. `-NewUserPassword` was omitted on the named-parameter create-user
  path) and is `$null` whenever the caller supplied their own password or
  used `-NewUser` instead. Without `-PassThru`, `Copy-EntraUser` continues
  to produce no pipeline output at all -- this remains the only supported
  way to retrieve an auto-generated password, since it is still never
  written to any other output stream.

- `Copy-EntraUser` now accepts named parameters (`-NewUserPrincipalName`,
  `-NewUserDisplayName`, `-NewUserMailNickname`, `-NewUserPassword`,
  `-NewUserAccountEnabled`) as an alternative to hand-building a `-NewUser`
  properties hashtable when creating a new user. `-NewUser` is unchanged and
  still works for both an existing-user identifier and the hashtable form;
  the two styles are mutually exclusive, with an actionable error if
  neither or both are supplied. If `-NewUserPassword` is omitted, a random
  password is generated via the new `New-EntraUserPassword` private helper
  (a CSPRNG, never `Get-Random`) and is never written to any output
  stream — the operator retrieves or resets it through a separate flow,
  since it cannot be recovered from the function's output. The generated
  password sets `ForceChangePasswordNextSignIn`, so it only needs to work
  for a single first sign-in.

### Changed

- `Copy-EntraUser`'s `-TenantId` and `-ClientId` parameters are no longer
  mandatory. When no certificate parameter (`-CertificateThumbprint` or
  `-CertificatePath`/`-CertificatePassword`) is supplied at all, the
  function now connects to Microsoft Graph interactively from the start —
  no certificate-based attempt is made and no fallback warning is emitted,
  since there is nothing to fall back from. `-TenantId`/`-ClientId` remain
  optional in this mode and are passed through to the interactive sign-in
  only when supplied. Certificate-based auth (either parameter set) still
  requires both `-TenantId` and `-ClientId`, now enforced with an explicit,
  actionable error at the start of `Connect-EntraGraphSession` rather than
  relying on mandatory-parameter prompting.

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

- Removed the opencode dev-tooling integration: `opencode.json` (agent config,
  MCP server wiring, permissions) and `.github/workflows/opencode.yml` (the
  `/oc`/`/opencode` comment-triggered GitHub Actions workflow). Neither file
  was referenced by the module, its tests, or the build/release pipelines —
  this only removes optional CI/dev tooling. If `ANTHROPIC_API_KEY` was added
  to repository or organization secrets solely for this workflow, it should be
  revoked there as well.

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
  - Named mutex (Global\Copy-EntraUserLog) prevents concurrent write
    corruption across threads and runspaces.
  - Auto-rotates at 10 MB, keeping up to 5 numbered backup files.
  - Redacts passwords, tokens, keys, and secrets in key=value, JSON, and XML/HTML
    formats before writing.
  - ANSI colour console output via PSStyle (7.2+) with escape-code fallback.
  - Dedicated ErrorRecord parameter set for structured exception logging.
  - Wrapper functions (Test-PathWrapper, Add-ContentWrapper, Get-ItemWrapper,
    New-ItemDirectoryWrapper) isolate I/O calls for Pester mockability.
  - Mutex is disposed on PowerShell exit via Register-EngineEvent.
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
