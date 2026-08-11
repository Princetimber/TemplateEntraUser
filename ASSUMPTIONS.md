# ASSUMPTIONS.md

This document registers the confirmed design decisions and architectural assumptions underlying the `Copy-EntraUser` module. Each entry represents a resolved requirement — not an open question.

## Deliverable Shape

The module is delivered as a **PowerShell Sampler-based module**, not a script, CLI tool, or other format. This provides standardized structure, build automation, testing infrastructure, and CI/CD pipelines out of the box.

## Module and Function Name

The primary exported function is named **`Copy-EntraUser`**, using the approved PowerShell verb `Copy-` (copying is a safe, non-state-changing operation on the template user; state-changing operations occur only on the target user and are guarded by `-WhatIf`/`-Confirm`). The rationale is documented in the function's own `.NOTES` section and copied here for visibility: `Copy-` correctly describes the semantic operation (clone permissions from an existing user), and the module name matches the primary function for discovery and clarity.

## Clone Scope

The function clones **group memberships and PIM-for-Groups eligibility assignments only**. It does NOT clone:

- User property assignments (department, manager, office location, etc.)
- Microsoft 365 license assignments
- Role-based access control (RBAC) role assignments
- Any attributes other than group membership and PIM eligibility

The scope is intentionally narrow to minimize side effects and allow operators to customize non-membership properties independently.

## `-NewUser` Parameter Flexibility

The `-NewUser` parameter accepts two input types:

1. **Existing User Identifier** (string) — an object ID (GUID), user principal name (UPN), or mail address of an already-provisioned Entra ID user
2. **New User Specification** (hashtable) — creates a new user with required keys:
   - `DisplayName` (string) — human-readable name
   - `UserPrincipalName` (string) — UPN (must be unique in the tenant)
   - `MailNickname` (string) — mail alias
   - `PasswordProfile` (hashtable) — `@{ Password = '...' }`; see Microsoft Graph docs for format
   - `AccountEnabled` (boolean) — `$true` or `$false` at creation time

The function validates the hashtable structure at runtime and fails fast with a clear error if required keys are missing.

## Microsoft Graph Permissions

### Permission Name Correction

The correct Microsoft Graph permission name is **`PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup`** (not `PrivilegedAccessGroup.ReadWrite.AzureADGroup`, as guessed in an earlier draft of the requirements). This permission is required for reading and writing PIM-for-Groups eligibility assignments.

### Full Permission Set

The function requires **three permissions** for both certificate-based app-only authentication and interactive delegated sign-in:

| Permission | Description |
|-----------|-------------|
| `User.ReadWrite.All` | Read and write all user properties |
| `GroupMember.ReadWrite.All` | Read and write group membership |
| `PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup` | Read and write PIM-for-Groups eligibility |

These are already listed in the module's `README.md` and implemented in the `Get-RequiredGraphPermission` function. Both CBA and interactive auth use the same set.

## Certificate Authentication

### Primary Path: Portable PFX + SecureString Password

Certificate-based app-only authentication uses a **portable PFX file** + `SecureString` password as the primary and required authentication path. This approach:

- Works identically on **Windows, macOS, and Linux**
- Requires no local certificate store
- Allows easy distribution to CI/CD pipelines and remote agents
- Is specified via `-CertificatePath` and `-CertificatePassword` parameters

### Secondary Path: Windows-Only Certificate Thumbprint

A convenience parameter `-CertificateThumbprint` is provided for **Windows-only** scenarios where a certificate is already installed in the local Windows certificate store. This is:

- Not portable to macOS or Linux
- Provided only for Windows developer convenience
- Not recommended for production or multi-platform automation
- Documented as Windows-only in help text

## Unsupported Group Handling

Groups that cannot be cloned (dynamic membership groups, role-assignable groups) are:

- **Skipped** with a named `Write-Warning` message identifying the group and reason
- **Never silently dropped** — operators see all skipped groups in the output
- **Not fatal to the overall operation** — the function continues processing remaining groups and completes successfully even if some groups are unsupported

This approach balances safety (visibility) and resilience (no whole-run failure).

## App Registration and Certificate Prerequisites

The module **assumes the following are already configured and do NOT create them**:

1. An Entra ID app registration exists
2. A certificate (PFX file or Windows certificate store) already bound to the app registration
3. Admin consent has already been granted for the three declared permissions

The module's responsibility is **only** to authenticate and invoke the cloning operation; setup and credential management remain the operator's responsibility.

## Missing Module Handling

If a required module (e.g., `Microsoft.Graph.Users`, `Microsoft.Graph.Groups`) cannot be imported:

- The function **fails immediately** with an actionable error message
- The error message includes the exact PowerShell Gallery install command
- Example: `"Install-Module Microsoft.Graph.Users -Repository PSGallery -Scope AllUsers -Force"`
- The function **never auto-installs** modules; operators retain full control over their environment

This conservative approach prevents surprise installations and keeps automation auditable.

## Microsoft.Graph Module Version Floor

The `RequiredModules.psd1` file specifies `Microsoft.Graph` sub-module version **`2.25.0`** as the confirmed minimum version floor. Microsoft Graph PowerShell SDK evolves rapidly, so this floor should be periodically re-verified against the current PowerShell Gallery release rather than treated as fixed forever. When re-verifying, confirm that:

- Version `2.25.0` (or higher) is still available on the target PowerShell Gallery
- The deployment environment's automation can resolve and install the version in use
- Breaking changes between your current production version and any newer floor do not affect your organization's scripts

## Repository Ownership and Visibility

The `Copy-EntraUser` module is scaffolded **in-place within the existing TemplateEntraUser repository**. As a result:

- The module inherits the existing repository's owner, visibility (public/private), and team permissions
- No new repository is created
- The existing `.github/workflows`, Azure Pipelines configuration, and branch protection rules apply
- The module is discoverable at the current repository URL

If the module must be split into a separate repository in the future, that is a separate administrative decision outside the module's configuration.

---

## Summary

These assumptions collectively define the module's authentication strategy (portable PFX primary, Windows thumbprint secondary), scope (group membership + PIM only), error handling (fail-fast with actionable messages, warn on unsupported groups), and prerequisites (app registration and cert already exist). The result is a secure, auditable, cross-platform module that respects operator choice and ownership.
