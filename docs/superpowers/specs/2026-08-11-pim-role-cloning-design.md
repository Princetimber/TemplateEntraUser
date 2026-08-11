# Design: PIM-Enabled Directory Role Cloning for Copy-EntraUser

Date: 2026-08-11
Status: Approved

## Problem

`Copy-EntraUser` currently clones a template user's direct group memberships
and PIM-for-Groups eligibility. It does not touch directory role assignments
at all. If the template user directly holds a PIM-eligible directory role
(e.g. Helpdesk Administrator, User Administrator), the clone gets none of
that access model — an operator has to notice and replicate it by hand.

## Goal

When the template user has a directly-assigned, PIM-governed directory role,
replicate it onto the new/target user as part of the same clone operation
that already handles groups.

## Decisions

These were confirmed with the user before design:

1. **Grant type: ELIGIBLE, never active/permanent.** The new user receives
   an eligible PIM role assignment (`UnifiedRoleEligibilityScheduleRequest`),
   mirroring the existing group-eligibility behavior. This matches the
   module's least-privilege stance — cloning access never grants standing
   privileged access automatically.
2. **Non-PIM permanent role assignments are out of scope.** If the template
   user holds a directory role as a plain, permanent assignment with no PIM
   eligibility behind it at all, `Copy-EntraUser` skips it with a
   `Write-Warning`, consistent with how dynamic-membership and
   role-assignable groups are already skipped rather than cloned or
   silently dropped.
3. **Tenant-wide scope only.** Only role eligibilities scoped to the whole
   directory (`directoryScopeId` = `/`) are cloned. Administrative-Unit
   (AU) scoped role eligibilities are skipped with a warning in this first
   version.
4. **Inherited/group-sourced roles are out of scope by definition.** Only
   `memberType = 'Direct'` role eligibility/assignment instances are
   considered — inherited (via a role-assignable group, or via an AU-scoped
   admin's implicit scope) is not "directly assigned" and is silently
   ignored, the same way transitive group membership is never even fetched
   today.

## Architecture

Three new `Private/` functions, mirroring the existing
`Get-EntraTemplateGroupMembership` → `Split-EntraGroupMembership` →
`Grant-EntraGroupEligibility` pipeline.

### 1. `Get-EntraTemplateRoleAssignment -TemplateUserId <id>`

Fetches the template user's directory-role PIM data:

- `Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance -Filter "principalId eq '<id>'" -All`
  → the template user's current PIM role eligibility schedule instances.
- `Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance -Filter "principalId eq '<id>'" -All`
  → the template user's current *active* role assignment schedule instances.
  This is fetched only to detect permanent, non-PIM assignments (decision 2)
  — an eligible-but-inactive role does not appear here, mirroring how an
  eligible-but-inactive PIM-for-Groups assignment doesn't appear in direct
  group membership.
- Resolves each distinct `RoleDefinitionId` referenced by either collection
  to a display name via `Get-MgRoleManagementDirectoryRoleDefinition`, for
  use in warning messages (same purpose as group `DisplayName` resolution
  in `Get-EntraTemplateGroupMembership`).

Returns a hashtable: `@{ EligibilitySchedule; ActiveAssignmentSchedule; RoleDefinitionById }`.

### 2. `Split-EntraRoleAssignment`

Pure function, no Graph calls — mirrors `Split-EntraGroupMembership`.

Parameters: `-EligibilitySchedule`, `-ActiveAssignmentSchedule`, `-RoleDefinitionById`.

Logic:

- Any instance with `MemberType -ne 'Direct'` (`Inherited` or `Group`) is
  dropped silently — out of scope by decision 4.
- Eligibility instance, `MemberType -eq 'Direct'`, `DirectoryScopeId -eq '/'`
  → **PimRole** (`RoleDefinitionId`, `DisplayName`, `DirectoryScopeId`).
- Eligibility instance, `MemberType -eq 'Direct'`, `DirectoryScopeId -ne '/'`
  → **UnsupportedRole** (reason: AU-scoped, not cloned — decision 3).
- Active assignment instance, `MemberType -eq 'Direct'`,
  `AssignmentType -eq 'Assigned'` (permanent, not from an activation), and
  no eligibility instance already claimed the same
  `RoleDefinitionId`+`DirectoryScopeId` → **UnsupportedRole** (reason:
  non-PIM permanent assignment, not cloned — decision 2).
- Active assignment instance with `AssignmentType -eq 'Activated'` is
  ignored: it is just the currently-active form of an eligibility instance
  already captured in the `PimRole`/`UnsupportedRole` pass above, so
  counting it again would double-report the same role.

Returns: `@{ PimRole; UnsupportedRole }` (each `System.Object[]`).

### 3. `Grant-EntraRoleEligibility -RoleDefinitionId -NewUserId -DirectoryScopeId -Justification`

Idempotent — mirrors `Grant-EntraGroupEligibility`:

- Reads existing eligibility schedule instances for this
  principal/role/scope first (`Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance
  -Filter "principalId eq '<NewUserId>' and roleDefinitionId eq '<RoleDefinitionId>' and directoryScopeId eq '<DirectoryScopeId>'"`);
  skips with `Write-Verbose` if one already exists.
- Otherwise calls `New-MgRoleManagementDirectoryRoleEligibilityScheduleRequest`
  with `action = 'AdminAssign'`, `scheduleInfo.expiration.type = 'NoExpiration'`
  (eligible, never active/permanent — decision 1).
- `SupportsShouldProcess`, same as `Grant-EntraGroupEligibility`.

## Wiring into `Copy-EntraUser.ps1`

Inside the existing `process` block, after resolving template/new user and
before/alongside the existing group-membership clone, inside the same
`ShouldProcess` gate:

```powershell
$roleAssignment = Get-EntraTemplateRoleAssignment -TemplateUserId $templateUser.Id
$roleSplit = Split-EntraRoleAssignment -EligibilitySchedule $roleAssignment.EligibilitySchedule `
    -ActiveAssignmentSchedule $roleAssignment.ActiveAssignmentSchedule `
    -RoleDefinitionById $roleAssignment.RoleDefinitionById

foreach ($role in $roleSplit.UnsupportedRole) {
    Write-Warning "Skipped role '$($role.DisplayName)' ($($role.RoleDefinitionId)): $($role.Reason)"
}

if ($PSCmdlet.ShouldProcess($newUserObject.Id, "Clone group memberships, PIM-for-Groups eligibility, and PIM directory role eligibility from '$TemplateUserId'")) {
    # ... existing group code ...
    foreach ($role in $roleSplit.PimRole) {
        Grant-EntraRoleEligibility -RoleDefinitionId $role.RoleDefinitionId -NewUserId $newUserObject.Id -DirectoryScopeId $role.DirectoryScopeId
    }
}
```

Comment-based help (`.SYNOPSIS`, `.DESCRIPTION`, `.NOTES`) is updated to
describe directory-role cloning alongside group cloning.

## Permissions

Add to `Get-RequiredGraphPermission` (the single source of truth used both
in `Connect-MgGraph -Scopes` and documented in `Copy-EntraUser`'s `.NOTES`):

- `RoleEligibilitySchedule.ReadWrite.Directory` — read the template user's
  eligibility instances, check the new user's existing eligibility
  instances, and create the eligibility schedule request.
- `RoleAssignmentSchedule.Read.Directory` — read-only; needed solely to
  detect and warn about non-PIM permanent role assignments (decision 2).

Both permission names were verified against Microsoft Graph documentation
(`unifiedRoleEligibilityScheduleInstance`, `unifiedRoleAssignmentScheduleInstance`,
`roleEligibilityScheduleRequests` reference pages) during design, not
assumed from training data.

## Testing

Pester unit tests (mirroring the existing group tests):

- `Get-EntraTemplateRoleAssignment.tests.ps1` — mocks the two Graph list
  calls and the role-definition resolution call; asserts the returned
  hashtable shape.
- `Split-EntraRoleAssignment.tests.ps1` — pure-function table tests: direct
  tenant-wide eligibility → PimRole; AU-scoped eligibility → UnsupportedRole;
  permanent non-PIM `Assigned` active instance → UnsupportedRole; `Activated`
  active instance with a matching eligibility → ignored (not double
  reported); `Inherited`/`Group` memberType → dropped silently.
- `Grant-EntraRoleEligibility.tests.ps1` — idempotency (existing instance
  found → no write call), and the create path with `-WhatIf` /
  `ShouldProcess` mocked.
- `Copy-EntraUser.tests.ps1` — updated to assert the new role-cloning calls
  happen alongside the existing group-cloning calls, and that
  `UnsupportedRole` entries produce `Write-Warning`.
- `Get-RequiredGraphPermission.tests.ps1` — updated to assert the two new
  scopes are present.

Target: maintain the project's 85% coverage threshold.

## Out of scope (this iteration)

- AU-scoped role eligibility cloning.
- Cloning non-PIM permanent role assignments (even as a flagged/opt-in
  behavior) — skipped with a warning only.
- Custom directory roles vs built-in roles: no distinction is made:
  `RoleDefinitionId` is treated opaquely, so custom roles are cloned the
  same as built-in ones as long as they're PIM-eligible, direct, and
  tenant-wide.
