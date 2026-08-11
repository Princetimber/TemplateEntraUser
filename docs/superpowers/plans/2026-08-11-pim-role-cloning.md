# PIM-Enabled Directory Role Cloning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Copy-EntraUser clones a template user's directly-assigned, PIM-eligible directory role assignments onto the new/target user, as an ELIGIBLE (never active/permanent) grant, alongside the existing group/PIM-for-Groups cloning.

**Architecture:** Three new `Private/` functions mirror the existing group-cloning pipeline (`Get-EntraTemplateGroupMembership` → `Split-EntraGroupMembership` → `Grant-EntraGroupEligibility`) for directory roles instead of groups: `Get-EntraTemplateRoleAssignment` (fetch), `Split-EntraRoleAssignment` (pure classify), `Grant-EntraRoleEligibility` (idempotent grant). `Copy-EntraUser.ps1` wires the three together inside its existing `ShouldProcess` gate. `Get-RequiredGraphPermission` gains the two new Graph scopes this requires.

**Tech Stack:** PowerShell 7+, Microsoft.Graph.Identity.Governance SDK cmdlets (`Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance`, `Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance`, `Get-MgRoleManagementDirectoryRoleDefinition`, `New-MgRoleManagementDirectoryRoleEligibilityScheduleRequest`), Pester v5.

## Global Constraints

- One function per file; filename matches the function name exactly (e.g. `Get-EntraTemplateRoleAssignment.ps1`).
- Private functions (`source/Private/`) — match the actual repo convention, not the aspirational style-rule doc: every existing `Private/` function (`Split-EntraGroupMembership`, `Grant-EntraGroupEligibility`, `Get-EntraTemplateGroupMembership`, `Get-RequiredGraphPermission`) ships full comment-based help (`.SYNOPSIS`/`.DESCRIPTION`/`.PARAMETER`/`.OUTPUTS`/`.EXAMPLE`). New Private functions in this plan follow that same pattern.
- Public functions (`source/Public/`) — comment-based help (`.SYNOPSIS`/`.DESCRIPTION`/`.PARAMETER`/`.EXAMPLE`) is **mandatory**.
- `[CmdletBinding()]` on every advanced function. `SupportsShouldProcess` only on state-changing functions (`Grant-EntraRoleEligibility`), never on read-only ones (`Get-EntraTemplateRoleAssignment`, `Split-EntraRoleAssignment`).
- Parameters: PascalCase. Local variables: camelCase. Splatting hashtable keys match the target cmdlet's PascalCase parameter names exactly.
- No aliases, no positional parameters in new code. Backtick line continuation is the existing repo's actual pattern for a two-parameter Graph cmdlet call that doesn't fit one line (see `Grant-EntraGroupEligibility.ps1`, `Get-EntraTemplateGroupMembership.ps1`) — match that exact pattern for the Graph calls in Tasks 1 and 3; don't introduce splatting there or backticks elsewhere.
- Follow the existing repo convention: no `#Requires -Version 7.0` line in `Private/` function files (none of the existing ones have it, despite the general PowerShell style rule — match what's actually in this file, not the aspirational rule).
- `85%` code coverage threshold (`build.yaml`).
- Cross-platform: all tests must run on macOS, Linux, and Windows (no live Graph calls — everything is mocked).
- `Invoke-ScriptAnalyzer -Path source/ -Recurse -Settings PSScriptAnalyzerSettings.psd1` must be zero-violation before the final commit.
- Test files mirror source structure: `tests/Unit/Private/<Name>.tests.ps1`.

---

## Task 1: `Get-EntraTemplateRoleAssignment`

**Files:**
- Create: `source/Private/Get-EntraTemplateRoleAssignment.ps1`
- Test: `tests/Unit/Private/Get-EntraTemplateRoleAssignment.tests.ps1`

**Interfaces:**
- Consumes: `Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance`, `Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance`, `Get-MgRoleManagementDirectoryRoleDefinition` (all from `Microsoft.Graph.Identity.Governance`, already a required module for this project via the existing PIM-for-Groups cmdlets).
- Produces: `Get-EntraTemplateRoleAssignment -TemplateUserId <string>` returns `[hashtable]` with keys `EligibilitySchedule` (`object[]`), `ActiveAssignmentSchedule` (`object[]`), `RoleDefinitionById` (`hashtable`, `RoleDefinitionId` string → `DisplayName` string). Consumed by Task 2's `Split-EntraRoleAssignment` and wired in Task 5.

- [ ] **Step 1: Write the failing tests**

Create `tests/Unit/Private/Get-EntraTemplateRoleAssignment.tests.ps1`:

```powershell
BeforeAll {
    $script:dscModuleName = 'Copy-EntraUser'
    Import-Module -Name $script:dscModuleName -Force
}

AfterAll {
    Get-Module -Name $script:dscModuleName -All | Remove-Module -Force
}

Describe 'Get-EntraTemplateRoleAssignment' {
    It 'Returns eligibility schedule instances, active assignment instances, and a role definition lookup' {
        InModuleScope -ModuleName $script:dscModuleName {
            Mock Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance {
                @([pscustomobject]@{
                        RoleDefinitionId = '66666666-6666-6666-6666-666666666666'
                        DirectoryScopeId = '/'
                        MemberType       = 'Direct'
                    })
            }
            Mock Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance {
                @([pscustomobject]@{
                        RoleDefinitionId = '99999999-9999-9999-9999-999999999999'
                        DirectoryScopeId = '/'
                        MemberType       = 'Direct'
                        AssignmentType   = 'Assigned'
                    })
            }
            Mock Get-MgRoleManagementDirectoryRoleDefinition {
                param($UnifiedRoleDefinitionId)
                [pscustomobject]@{ Id = $UnifiedRoleDefinitionId; DisplayName = "Role-$UnifiedRoleDefinitionId" }
            }

            $result = Get-EntraTemplateRoleAssignment -TemplateUserId '00000000-0000-0000-0000-000000000002'

            $result.EligibilitySchedule[0].RoleDefinitionId | Should -Be '66666666-6666-6666-6666-666666666666'
            $result.ActiveAssignmentSchedule[0].RoleDefinitionId | Should -Be '99999999-9999-9999-9999-999999999999'
            $result.RoleDefinitionById['66666666-6666-6666-6666-666666666666'] | Should -Be 'Role-66666666-6666-6666-6666-666666666666'
            $result.RoleDefinitionById['99999999-9999-9999-9999-999999999999'] | Should -Be 'Role-99999999-9999-9999-9999-999999999999'
        }
    }

    It 'Filters both list queries by the template user principal ID' {
        InModuleScope -ModuleName $script:dscModuleName {
            Mock Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance { @() }
            Mock Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance { @() }
            Mock Get-MgRoleManagementDirectoryRoleDefinition { $null }

            Get-EntraTemplateRoleAssignment -TemplateUserId '00000000-0000-0000-0000-000000000002' | Out-Null

            Should -Invoke Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance -Times 1 -ParameterFilter {
                $Filter -eq "principalId eq '00000000-0000-0000-0000-000000000002'"
            }
            Should -Invoke Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance -Times 1 -ParameterFilter {
                $Filter -eq "principalId eq '00000000-0000-0000-0000-000000000002'"
            }
        }
    }

    It 'Resolves each distinct RoleDefinitionId only once across both collections' {
        InModuleScope -ModuleName $script:dscModuleName {
            Mock Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance {
                @([pscustomobject]@{ RoleDefinitionId = '66666666-6666-6666-6666-666666666666'; DirectoryScopeId = '/'; MemberType = 'Direct' })
            }
            Mock Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance {
                @([pscustomobject]@{ RoleDefinitionId = '66666666-6666-6666-6666-666666666666'; DirectoryScopeId = '/'; MemberType = 'Direct'; AssignmentType = 'Activated' })
            }
            Mock Get-MgRoleManagementDirectoryRoleDefinition {
                [pscustomobject]@{ Id = '66666666-6666-6666-6666-666666666666'; DisplayName = 'Helpdesk Administrator' }
            }

            Get-EntraTemplateRoleAssignment -TemplateUserId '00000000-0000-0000-0000-000000000002' | Out-Null

            Should -Invoke Get-MgRoleManagementDirectoryRoleDefinition -Times 1
        }
    }

    It 'Warns and omits the entry when a role definition cannot be resolved' {
        InModuleScope -ModuleName $script:dscModuleName {
            Mock Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance {
                @([pscustomobject]@{ RoleDefinitionId = '66666666-6666-6666-6666-666666666666'; DirectoryScopeId = '/'; MemberType = 'Direct' })
            }
            Mock Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance { @() }
            Mock Get-MgRoleManagementDirectoryRoleDefinition { $null }

            $result = Get-EntraTemplateRoleAssignment -TemplateUserId '00000000-0000-0000-0000-000000000002' `
                -WarningVariable warnings -WarningAction SilentlyContinue

            $result.RoleDefinitionById.ContainsKey('66666666-6666-6666-6666-666666666666') | Should -BeFalse
            $warnings | Should -Not -BeNullOrEmpty
        }
    }

    It 'Returns empty arrays and an empty lookup when the template user has no role data at all' {
        InModuleScope -ModuleName $script:dscModuleName {
            Mock Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance { @() }
            Mock Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance { @() }
            Mock Get-MgRoleManagementDirectoryRoleDefinition { throw 'Should not be called when there is no role data.' }

            $result = Get-EntraTemplateRoleAssignment -TemplateUserId '00000000-0000-0000-0000-000000000002'

            $result.EligibilitySchedule | Should -BeNullOrEmpty
            $result.ActiveAssignmentSchedule | Should -BeNullOrEmpty
            $result.RoleDefinitionById.Count | Should -Be 0
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Invoke-Pester -Path tests/Unit/Private/Get-EntraTemplateRoleAssignment.tests.ps1 -Output Detailed`
Expected: FAIL — `Get-EntraTemplateRoleAssignment` is not recognized (the function doesn't exist yet).

- [ ] **Step 3: Write the implementation**

Create `source/Private/Get-EntraTemplateRoleAssignment.ps1`:

```powershell
function Get-EntraTemplateRoleAssignment {
    <#
    .SYNOPSIS
        Enumerates the template user's directory-role PIM eligibility
        schedule instances and current active role assignment schedule
        instances.
    .DESCRIPTION
        Fetches PIM eligibility for directory roles via the
        RoleEligibilityScheduleInstance endpoint filtered on the template
        user's principal ID -- this is directory-role PIM, not PIM for
        Groups (which uses PrivilegedAccessGroupEligibilityScheduleInstance
        and must never be used here). Also fetches the template user's
        current active role assignment schedule instances via the
        RoleAssignmentScheduleInstance endpoint, purely so
        Split-EntraRoleAssignment can detect and flag permanent, non-PIM
        role assignments -- an eligible-but-not-yet-activated PIM directory
        role does NOT appear in this collection, mirroring how an
        eligible-but-not-yet-activated PIM-for-Groups assignment doesn't
        appear in direct group membership. Copy-EntraUser never clones an
        active assignment directly; only PIM-eligible roles are cloned (see
        Grant-EntraRoleEligibility).

        Also resolves each distinct RoleDefinitionId referenced by either
        collection to a display name via
        Get-MgRoleManagementDirectoryRoleDefinition, for use in warning
        messages -- the same purpose as group DisplayName resolution in
        Get-EntraTemplateGroupMembership.
    .PARAMETER TemplateUserId
        The template user's Object ID.
    .OUTPUTS
        Hashtable with keys EligibilitySchedule, ActiveAssignmentSchedule
        (both arrays), and RoleDefinitionById (a hashtable of
        RoleDefinitionId -> DisplayName).
    .EXAMPLE
        Get-EntraTemplateRoleAssignment -TemplateUserId $templateUser.Id
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $TemplateUserId
    )

    $eligibilitySchedule = @(Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance `
            -Filter "principalId eq '$TemplateUserId'" -All)
    $activeAssignmentSchedule = @(Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance `
            -Filter "principalId eq '$TemplateUserId'" -All)

    $roleDefinitionId = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($instance in @($eligibilitySchedule) + @($activeAssignmentSchedule)) {
        [void]$roleDefinitionId.Add($instance.RoleDefinitionId)
    }

    $roleDefinitionById = @{}
    foreach ($id in $roleDefinitionId) {
        $roleDefinition = Get-MgRoleManagementDirectoryRoleDefinition -UnifiedRoleDefinitionId $id
        if ($null -eq $roleDefinition) {
            Write-Warning "Could not resolve role definition '$id' (it may have been deleted or is inaccessible); its display name will be unavailable in warnings."
            continue
        }
        $roleDefinitionById[$id] = $roleDefinition.DisplayName
    }

    return @{
        EligibilitySchedule      = $eligibilitySchedule
        ActiveAssignmentSchedule = $activeAssignmentSchedule
        RoleDefinitionById       = $roleDefinitionById
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Invoke-Pester -Path tests/Unit/Private/Get-EntraTemplateRoleAssignment.tests.ps1 -Output Detailed`
Expected: PASS (all 5 tests).

- [ ] **Step 5: Lint**

Run: `Invoke-ScriptAnalyzer -Path source/Private/Get-EntraTemplateRoleAssignment.ps1 -Settings PSScriptAnalyzerSettings.psd1 -Severity Error,Warning`
Expected: no output (zero violations).

- [ ] **Step 6: Commit**

```bash
git add source/Private/Get-EntraTemplateRoleAssignment.ps1 tests/Unit/Private/Get-EntraTemplateRoleAssignment.tests.ps1
git commit -m "feat: add Get-EntraTemplateRoleAssignment to fetch template user PIM role data"
```

---

## Task 2: `Split-EntraRoleAssignment`

**Files:**
- Create: `source/Private/Split-EntraRoleAssignment.ps1`
- Test: `tests/Unit/Private/Split-EntraRoleAssignment.tests.ps1`

**Interfaces:**
- Consumes: `EligibilitySchedule`/`ActiveAssignmentSchedule` shaped objects with `RoleDefinitionId`, `DirectoryScopeId`, `MemberType` (all three), and `AssignmentType` (active-assignment only) properties — the shape returned by Task 1's `Get-EntraTemplateRoleAssignment`. `RoleDefinitionById` hashtable from the same source.
- Produces: `Split-EntraRoleAssignment -EligibilitySchedule <object[]> -ActiveAssignmentSchedule <object[]> [-RoleDefinitionById <hashtable>]` returns `[hashtable]` with keys `PimRole` and `UnsupportedRole` (each `object[]`). `PimRole` entries have properties `RoleDefinitionId`, `DisplayName`, `DirectoryScopeId`. `UnsupportedRole` entries have `RoleDefinitionId`, `DisplayName`, `DirectoryScopeId`, `Reason`. Consumed by Task 5's wiring into `Copy-EntraUser.ps1`.

- [ ] **Step 1: Write the failing tests**

Create `tests/Unit/Private/Split-EntraRoleAssignment.tests.ps1`:

```powershell
BeforeAll {
    $script:dscModuleName = 'Copy-EntraUser'
    Import-Module -Name $script:dscModuleName -Force

    InModuleScope -ModuleName $script:dscModuleName {
        $script:tenantWideEligibility = [pscustomobject]@{
            RoleDefinitionId = '66666666-6666-6666-6666-666666666666'
            DirectoryScopeId = '/'
            MemberType       = 'Direct'
        }
        $script:auScopedEligibility = [pscustomobject]@{
            RoleDefinitionId = '77777777-7777-7777-7777-777777777777'
            DirectoryScopeId = '/administrativeUnits/88888888-8888-8888-8888-888888888888'
            MemberType       = 'Direct'
        }
        $script:groupInheritedEligibility = [pscustomobject]@{
            RoleDefinitionId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
            DirectoryScopeId = '/'
            MemberType       = 'Group'
        }
        $script:permanentAssignment = [pscustomobject]@{
            RoleDefinitionId = '99999999-9999-9999-9999-999999999999'
            DirectoryScopeId = '/'
            MemberType       = 'Direct'
            AssignmentType   = 'Assigned'
        }
        $script:activatedAssignment = [pscustomobject]@{
            RoleDefinitionId = '66666666-6666-6666-6666-666666666666'
            DirectoryScopeId = '/'
            MemberType       = 'Direct'
            AssignmentType   = 'Activated'
        }
        $script:inheritedAssignment = [pscustomobject]@{
            RoleDefinitionId = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
            DirectoryScopeId = '/'
            MemberType       = 'Inherited'
            AssignmentType   = 'Assigned'
        }
        $script:roleDefinitionById = @{
            '66666666-6666-6666-6666-666666666666' = 'Helpdesk Administrator'
            '77777777-7777-7777-7777-777777777777' = 'User Administrator'
            '99999999-9999-9999-9999-999999999999' = 'Global Reader'
        }
    }
}

AfterAll {
    Get-Module -Name $script:dscModuleName -All | Remove-Module -Force
}

Describe 'Split-EntraRoleAssignment' {
    It 'Routes a Direct, tenant-wide eligibility instance to PimRole' {
        InModuleScope -ModuleName $script:dscModuleName {
            $result = Split-EntraRoleAssignment -EligibilitySchedule @($script:tenantWideEligibility) `
                -ActiveAssignmentSchedule @() -RoleDefinitionById $script:roleDefinitionById

            $result.PimRole.RoleDefinitionId | Should -Contain $script:tenantWideEligibility.RoleDefinitionId
            $result.UnsupportedRole | Should -BeNullOrEmpty
        }
    }

    It 'Carries the resolved DisplayName onto the PimRole entry' {
        InModuleScope -ModuleName $script:dscModuleName {
            $result = Split-EntraRoleAssignment -EligibilitySchedule @($script:tenantWideEligibility) `
                -ActiveAssignmentSchedule @() -RoleDefinitionById $script:roleDefinitionById

            ($result.PimRole | Where-Object RoleDefinitionId -eq $script:tenantWideEligibility.RoleDefinitionId).DisplayName |
                Should -Be 'Helpdesk Administrator'
        }
    }

    It 'Routes an Administrative Unit-scoped eligibility instance to UnsupportedRole, not PimRole' {
        InModuleScope -ModuleName $script:dscModuleName {
            $result = Split-EntraRoleAssignment -EligibilitySchedule @($script:auScopedEligibility) `
                -ActiveAssignmentSchedule @() -RoleDefinitionById $script:roleDefinitionById

            $result.UnsupportedRole.RoleDefinitionId | Should -Contain $script:auScopedEligibility.RoleDefinitionId
            $result.PimRole | Should -BeNullOrEmpty
            ($result.UnsupportedRole | Where-Object RoleDefinitionId -eq $script:auScopedEligibility.RoleDefinitionId).Reason |
                Should -Match 'Administrative Unit'
        }
    }

    It 'Drops a Group-memberType eligibility instance silently (not PimRole, not UnsupportedRole)' {
        InModuleScope -ModuleName $script:dscModuleName {
            $result = Split-EntraRoleAssignment -EligibilitySchedule @($script:groupInheritedEligibility) `
                -ActiveAssignmentSchedule @() -RoleDefinitionById $script:roleDefinitionById

            $result.PimRole | Should -BeNullOrEmpty
            $result.UnsupportedRole | Should -BeNullOrEmpty
        }
    }

    It 'Routes a permanent (Assigned) active assignment with no matching eligibility to UnsupportedRole' {
        InModuleScope -ModuleName $script:dscModuleName {
            $result = Split-EntraRoleAssignment -EligibilitySchedule @() `
                -ActiveAssignmentSchedule @($script:permanentAssignment) -RoleDefinitionById $script:roleDefinitionById

            $result.UnsupportedRole.RoleDefinitionId | Should -Contain $script:permanentAssignment.RoleDefinitionId
            ($result.UnsupportedRole | Where-Object RoleDefinitionId -eq $script:permanentAssignment.RoleDefinitionId).Reason |
                Should -Match 'non-PIM'
        }
    }

    It 'Ignores an Activated active assignment that is already covered by its eligibility instance (no double-report)' {
        InModuleScope -ModuleName $script:dscModuleName {
            $result = Split-EntraRoleAssignment -EligibilitySchedule @($script:tenantWideEligibility) `
                -ActiveAssignmentSchedule @($script:activatedAssignment) -RoleDefinitionById $script:roleDefinitionById

            @($result.PimRole | Where-Object RoleDefinitionId -eq $script:tenantWideEligibility.RoleDefinitionId).Count | Should -Be 1
            $result.UnsupportedRole | Should -BeNullOrEmpty
        }
    }

    It 'Drops an Inherited-memberType active assignment silently' {
        InModuleScope -ModuleName $script:dscModuleName {
            $result = Split-EntraRoleAssignment -EligibilitySchedule @() `
                -ActiveAssignmentSchedule @($script:inheritedAssignment) -RoleDefinitionById $script:roleDefinitionById

            $result.PimRole | Should -BeNullOrEmpty
            $result.UnsupportedRole | Should -BeNullOrEmpty
        }
    }

    It 'Handles empty input without error and defaults RoleDefinitionById' {
        InModuleScope -ModuleName $script:dscModuleName {
            $result = Split-EntraRoleAssignment -EligibilitySchedule @() -ActiveAssignmentSchedule @()

            $result.PimRole | Should -BeNullOrEmpty
            $result.UnsupportedRole | Should -BeNullOrEmpty
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Invoke-Pester -Path tests/Unit/Private/Split-EntraRoleAssignment.tests.ps1 -Output Detailed`
Expected: FAIL — `Split-EntraRoleAssignment` is not recognized.

- [ ] **Step 3: Write the implementation**

Create `source/Private/Split-EntraRoleAssignment.ps1`:

```powershell
function Split-EntraRoleAssignment {
    <#
    .SYNOPSIS
        Partitions the template user's directory-role PIM data into roles
        that can be cloned as an ELIGIBLE PIM role assignment and roles
        that cannot be safely cloned by this function at all.
    .DESCRIPTION
        Pure function: no Graph calls, no side effects. Mirrors
        Split-EntraGroupMembership's shape for directory roles instead of
        groups.

        MemberType 'Inherited' or 'Group' (not directly assigned to the
        principal) is dropped silently on both inputs -- out of scope by
        definition, the same way transitive group membership is never even
        fetched.

        A Direct eligibility instance scoped tenant-wide (DirectoryScopeId
        '/') is routed to PimRole. A Direct eligibility instance scoped to
        an Administrative Unit is routed to UnsupportedRole.

        A Direct active assignment instance with AssignmentType 'Assigned'
        (a permanent assignment never backed by any PIM eligibility) and no
        matching eligibility instance is routed to UnsupportedRole. An
        active assignment instance with AssignmentType 'Activated' is
        ignored entirely: it is just the currently-active form of an
        eligibility instance already accounted for in the
        PimRole/UnsupportedRole pass above, so counting it again would
        double-report the same role.

        Callers must Write-Warning for each entry in UnsupportedRole rather
        than silently dropping them.
    .PARAMETER EligibilitySchedule
        The template user's current PIM directory role eligibility
        schedule instances (from
        Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance).
    .PARAMETER ActiveAssignmentSchedule
        The template user's current active directory role assignment
        schedule instances (from
        Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance).
    .PARAMETER RoleDefinitionById
        Lookup of RoleDefinitionId -> DisplayName, used to annotate PimRole
        and UnsupportedRole entries for readable warning messages.
    .OUTPUTS
        System.Collections.Hashtable with keys PimRole and UnsupportedRole
        (each System.Object[]).
    .EXAMPLE
        Split-EntraRoleAssignment -EligibilitySchedule $eligibility -ActiveAssignmentSchedule $active -RoleDefinitionById $lookup
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $EligibilitySchedule,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $ActiveAssignmentSchedule,

        [Parameter()]
        [hashtable] $RoleDefinitionById = @{}
    )

    $pimRole = [System.Collections.Generic.List[object]]::new()
    $unsupportedRole = [System.Collections.Generic.List[object]]::new()
    $eligibleKey = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($instance in $EligibilitySchedule) {
        if ($instance.MemberType -ne 'Direct') {
            continue
        }

        $displayName = $RoleDefinitionById[$instance.RoleDefinitionId]

        if ($instance.DirectoryScopeId -ne '/') {
            $unsupportedRole.Add([pscustomobject]@{
                    RoleDefinitionId = $instance.RoleDefinitionId
                    DisplayName      = $displayName
                    DirectoryScopeId = $instance.DirectoryScopeId
                    Reason           = 'Administrative Unit-scoped role eligibility is not cloned by Copy-EntraUser.'
                })
            continue
        }

        [void]$eligibleKey.Add(('{0}|{1}' -f $instance.RoleDefinitionId, $instance.DirectoryScopeId))
        $pimRole.Add([pscustomobject]@{
                RoleDefinitionId = $instance.RoleDefinitionId
                DisplayName      = $displayName
                DirectoryScopeId = $instance.DirectoryScopeId
            })
    }

    foreach ($instance in $ActiveAssignmentSchedule) {
        if ($instance.MemberType -ne 'Direct') {
            continue
        }
        if ($instance.AssignmentType -eq 'Activated') {
            continue
        }

        $key = '{0}|{1}' -f $instance.RoleDefinitionId, $instance.DirectoryScopeId
        if ($eligibleKey.Contains($key)) {
            continue
        }

        $unsupportedRole.Add([pscustomobject]@{
                RoleDefinitionId = $instance.RoleDefinitionId
                DisplayName      = $RoleDefinitionById[$instance.RoleDefinitionId]
                DirectoryScopeId = $instance.DirectoryScopeId
                Reason           = 'Permanent (non-PIM) role assignments are not cloned by Copy-EntraUser.'
            })
    }

    return @{
        PimRole         = $pimRole.ToArray()
        UnsupportedRole = $unsupportedRole.ToArray()
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Invoke-Pester -Path tests/Unit/Private/Split-EntraRoleAssignment.tests.ps1 -Output Detailed`
Expected: PASS (all 8 tests).

- [ ] **Step 5: Lint**

Run: `Invoke-ScriptAnalyzer -Path source/Private/Split-EntraRoleAssignment.ps1 -Settings PSScriptAnalyzerSettings.psd1 -Severity Error,Warning`
Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add source/Private/Split-EntraRoleAssignment.ps1 tests/Unit/Private/Split-EntraRoleAssignment.tests.ps1
git commit -m "feat: add Split-EntraRoleAssignment to classify PIM role eligibility for cloning"
```

---

## Task 3: `Grant-EntraRoleEligibility`

**Files:**
- Create: `source/Private/Grant-EntraRoleEligibility.ps1`
- Test: `tests/Unit/Private/Grant-EntraRoleEligibility.tests.ps1`

**Interfaces:**
- Consumes: `Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance`, `New-MgRoleManagementDirectoryRoleEligibilityScheduleRequest`.
- Produces: `Grant-EntraRoleEligibility -RoleDefinitionId <string> -NewUserId <string> [-DirectoryScopeId <string> = '/'] [-Justification <string>]`, `[OutputType([void])]`, `SupportsShouldProcess`. Called from Task 5's wiring with `-DirectoryScopeId $role.DirectoryScopeId` (a `PimRole` entry from Task 2).

- [ ] **Step 1: Write the failing tests**

Create `tests/Unit/Private/Grant-EntraRoleEligibility.tests.ps1`:

```powershell
BeforeAll {
    $script:dscModuleName = 'Copy-EntraUser'
    Import-Module -Name $script:dscModuleName -Force
}

AfterAll {
    Get-Module -Name $script:dscModuleName -All | Remove-Module -Force
}

Describe 'Grant-EntraRoleEligibility' {
    Context 'No existing eligibility schedule instance' {
        It 'Creates a new eligibility request with action AdminAssign and no expiration' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance { @() }
                Mock New-MgRoleManagementDirectoryRoleEligibilityScheduleRequest { }

                Grant-EntraRoleEligibility -RoleDefinitionId '66666666-6666-6666-6666-666666666666' `
                    -NewUserId '00000000-0000-0000-0000-000000000004' -Confirm:$false

                Should -Invoke New-MgRoleManagementDirectoryRoleEligibilityScheduleRequest -Times 1 -ParameterFilter {
                    $BodyParameter.action -eq 'AdminAssign' -and
                    $BodyParameter.roleDefinitionId -eq '66666666-6666-6666-6666-666666666666' -and
                    $BodyParameter.principalId -eq '00000000-0000-0000-0000-000000000004' -and
                    $BodyParameter.directoryScopeId -eq '/' -and
                    $BodyParameter.scheduleInfo.expiration.type -eq 'NoExpiration'
                }
            }
        }

        It 'Passes a non-tenant-wide DirectoryScopeId through unchanged' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance { @() }
                Mock New-MgRoleManagementDirectoryRoleEligibilityScheduleRequest { }

                Grant-EntraRoleEligibility -RoleDefinitionId '66666666-6666-6666-6666-666666666666' `
                    -NewUserId '00000000-0000-0000-0000-000000000004' -DirectoryScopeId '/' -Confirm:$false

                Should -Invoke New-MgRoleManagementDirectoryRoleEligibilityScheduleRequest -Times 1 -ParameterFilter {
                    $BodyParameter.directoryScopeId -eq '/'
                }
            }
        }
    }

    Context 'An eligibility schedule instance already exists (idempotent re-run)' {
        It 'Does not create a duplicate request' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance {
                    @([pscustomobject]@{
                            RoleDefinitionId = '66666666-6666-6666-6666-666666666666'
                            PrincipalId      = '00000000-0000-0000-0000-000000000004'
                            DirectoryScopeId = '/'
                        })
                }
                Mock New-MgRoleManagementDirectoryRoleEligibilityScheduleRequest { }

                Grant-EntraRoleEligibility -RoleDefinitionId '66666666-6666-6666-6666-666666666666' `
                    -NewUserId '00000000-0000-0000-0000-000000000004' -Confirm:$false

                Should -Invoke New-MgRoleManagementDirectoryRoleEligibilityScheduleRequest -Times 0
            }
        }
    }

    Context '-WhatIf support' {
        It 'Does not call New-MgRoleManagementDirectoryRoleEligibilityScheduleRequest under -WhatIf' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance { @() }
                Mock New-MgRoleManagementDirectoryRoleEligibilityScheduleRequest { }

                Grant-EntraRoleEligibility -RoleDefinitionId '66666666-6666-6666-6666-666666666666' `
                    -NewUserId '00000000-0000-0000-0000-000000000004' -WhatIf

                Should -Invoke New-MgRoleManagementDirectoryRoleEligibilityScheduleRequest -Times 0
            }
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Invoke-Pester -Path tests/Unit/Private/Grant-EntraRoleEligibility.tests.ps1 -Output Detailed`
Expected: FAIL — `Grant-EntraRoleEligibility` is not recognized.

- [ ] **Step 3: Write the implementation**

Create `source/Private/Grant-EntraRoleEligibility.ps1`:

```powershell
function Grant-EntraRoleEligibility {
    <#
    .SYNOPSIS
        Idempotently grants a user an ELIGIBLE (never active/permanent)
        PIM directory role assignment.
    .DESCRIPTION
        Reads existing eligibility schedule instances for this
        principal/role/scope first; if one already exists, skips with
        Write-Verbose rather than attempting the create and relying on
        Graph to reject a duplicate request. Uses the directory-role PIM
        UnifiedRoleEligibilityScheduleRequest endpoint -- never the
        PIM-for-Groups PrivilegedAccessGroupEligibilityScheduleRequest
        endpoint (see Grant-EntraGroupEligibility for that). The request
        action is always 'AdminAssign': an admin directly assigning
        eligibility, never a self-service or extend/renew action.
    .PARAMETER RoleDefinitionId
        The Object ID of the unifiedRoleDefinition to grant eligibility
        for.
    .PARAMETER NewUserId
        The Object ID of the user to grant eligibility to.
    .PARAMETER DirectoryScopeId
        The directory scope of the eligibility. Defaults to '/' (tenant-
        wide) -- Copy-EntraUser only ever clones tenant-wide role
        eligibility (see Split-EntraRoleAssignment).
    .PARAMETER Justification
        Text justification recorded on the eligibility request.
    .EXAMPLE
        Grant-EntraRoleEligibility -RoleDefinitionId $roleId -NewUserId $newUser.Id -DirectoryScopeId '/'
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string] $RoleDefinitionId,

        [Parameter(Mandatory)]
        [string] $NewUserId,

        [Parameter()]
        [string] $DirectoryScopeId = '/',

        [Parameter()]
        [string] $Justification = 'Provisioned via Copy-EntraUser template clone.'
    )

    $existingInstance = @(Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance `
            -Filter "principalId eq '$NewUserId' and roleDefinitionId eq '$RoleDefinitionId' and directoryScopeId eq '$DirectoryScopeId'" -All)

    if ($existingInstance.Count -gt 0) {
        Write-Verbose "User '$NewUserId' already has a PIM role eligibility instance for role '$RoleDefinitionId' at scope '$DirectoryScopeId'; skipping."
        return
    }

    if ($PSCmdlet.ShouldProcess($RoleDefinitionId, "Grant eligible PIM directory role assignment to user '$NewUserId'")) {
        New-MgRoleManagementDirectoryRoleEligibilityScheduleRequest -BodyParameter @{
            action           = 'AdminAssign'
            principalId      = $NewUserId
            roleDefinitionId = $RoleDefinitionId
            directoryScopeId = $DirectoryScopeId
            scheduleInfo     = @{
                startDateTime = (Get-Date)
                expiration    = @{ type = 'NoExpiration' }
            }
            justification    = $Justification
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Invoke-Pester -Path tests/Unit/Private/Grant-EntraRoleEligibility.tests.ps1 -Output Detailed`
Expected: PASS (all 4 tests).

- [ ] **Step 5: Lint**

Run: `Invoke-ScriptAnalyzer -Path source/Private/Grant-EntraRoleEligibility.ps1 -Settings PSScriptAnalyzerSettings.psd1 -Severity Error,Warning`
Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add source/Private/Grant-EntraRoleEligibility.ps1 tests/Unit/Private/Grant-EntraRoleEligibility.tests.ps1
git commit -m "feat: add Grant-EntraRoleEligibility for idempotent PIM role eligibility grants"
```

---

## Task 4: Update `Get-RequiredGraphPermission`

**Files:**
- Modify: `source/Private/Get-RequiredGraphPermission.ps1`
- Modify: `tests/Unit/Private/Get-RequiredGraphPermission.tests.ps1`

**Interfaces:**
- Produces: `Get-RequiredGraphPermission` now returns 5 permission strings instead of 3. Consumed by `Connect-EntraGraphSession` (unchanged call site) and documented in Task 5's `Copy-EntraUser.ps1` `.NOTES` update.

- [ ] **Step 1: Update the failing test first**

Edit `tests/Unit/Private/Get-RequiredGraphPermission.tests.ps1` — replace the whole `Describe` block:

```powershell
Describe 'Get-RequiredGraphPermission' {
    It 'Returns the exact five least-privilege permission strings, once each' {
        InModuleScope -ModuleName $script:dscModuleName {
            $result = Get-RequiredGraphPermission
            $result | Should -HaveCount 5
            $result | Should -Contain 'User.ReadWrite.All'
            $result | Should -Contain 'GroupMember.ReadWrite.All'
            $result | Should -Contain 'PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup'
            $result | Should -Contain 'RoleEligibilitySchedule.ReadWrite.Directory'
            $result | Should -Contain 'RoleAssignmentSchedule.Read.Directory'
        }
    }

    It 'Returns a [string[]] typed result' {
        InModuleScope -ModuleName $script:dscModuleName {
            (Get-RequiredGraphPermission) -is [array] | Should -BeTrue
            (Get-RequiredGraphPermission)[0] | Should -BeOfType [string]
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Invoke-Pester -Path tests/Unit/Private/Get-RequiredGraphPermission.tests.ps1 -Output Detailed`
Expected: FAIL — count is 3, not 5.

- [ ] **Step 3: Update the implementation**

Edit `source/Private/Get-RequiredGraphPermission.ps1` — keep the existing comment-based help block (this file already follows the repo's actual Private-function convention of full CBH; do not strip it), only extending `.DESCRIPTION`'s `NOTE:` paragraph and the `return` array:

```powershell
function Get-RequiredGraphPermission {
    <#
    .SYNOPSIS
        Returns the single, canonical set of least-privilege Microsoft Graph
        permission names Copy-EntraUser requires.
    .DESCRIPTION
        Used identically for both auth paths: as the -Scopes argument to the
        interactive Connect-MgGraph fallback, and documented verbatim in
        Copy-EntraUser's comment-based help .NOTES as the application
        permissions the CBA app registration must be pre-consented with.
        Keeping one source of truth prevents the two lists drifting apart.

        NOTE: PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup is the
        verified Microsoft Graph permission name for reading and creating
        PIM-for-Groups eligibility schedule requests/instances. It is NOT
        named PrivilegedAccessGroup.ReadWrite.AzureADGroup (that string does
        not exist in the Graph permissions reference).

        NOTE: RoleEligibilitySchedule.ReadWrite.Directory and
        RoleAssignmentSchedule.Read.Directory are the verified Microsoft
        Graph permission names for directory-role PIM (as opposed to
        PIM-for-Groups): reading/writing role eligibility schedule instances
        and requests, and read-only access to active role assignment
        schedule instances (used only to detect permanent, non-PIM role
        assignments so they can be skipped with a warning rather than
        cloned).
    .OUTPUTS
        System.String[]
    .EXAMPLE
        Get-RequiredGraphPermission
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    return @(
        'User.ReadWrite.All'
        'GroupMember.ReadWrite.All'
        'PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup'
        'RoleEligibilitySchedule.ReadWrite.Directory'
        'RoleAssignmentSchedule.Read.Directory'
    )
}
```

Verify the existing file's CBH block is preserved (not deleted) and only the `.DESCRIPTION` and `return` array change as shown.

- [ ] **Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path tests/Unit/Private/Get-RequiredGraphPermission.tests.ps1 -Output Detailed`
Expected: PASS (both tests).

- [ ] **Step 5: Lint**

Run: `Invoke-ScriptAnalyzer -Path source/Private/Get-RequiredGraphPermission.ps1 -Settings PSScriptAnalyzerSettings.psd1 -Severity Error,Warning`
Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add source/Private/Get-RequiredGraphPermission.ps1 tests/Unit/Private/Get-RequiredGraphPermission.tests.ps1
git commit -m "feat: add PIM directory role permissions to Get-RequiredGraphPermission"
```

---

## Task 5: Wire role cloning into `Copy-EntraUser.ps1`

**Files:**
- Modify: `source/Public/Copy-EntraUser.ps1`
- Modify: `tests/Unit/Public/Copy-EntraUser.tests.ps1`

**Interfaces:**
- Consumes: `Get-EntraTemplateRoleAssignment` (Task 1), `Split-EntraRoleAssignment` (Task 2), `Grant-EntraRoleEligibility` (Task 3).
- Produces: no new public interface — `Copy-EntraUser`'s existing signature and `-PassThru` output are unchanged; this task only adds internal orchestration and updates comment-based help.

- [ ] **Step 1: Update existing test mocks so current tests keep passing**

`Copy-EntraUser.ps1` will unconditionally call `Get-EntraTemplateRoleAssignment` and (conditionally) `Grant-EntraRoleEligibility` once Step 3 lands — every existing test in `Copy-EntraUser.tests.ps1` needs these mocked in the top-level `BeforeAll`, or they'll fail with "command not found" against the real (unmocked) Graph cmdlet names inside `Get-EntraTemplateRoleAssignment`.

Edit `tests/Unit/Public/Copy-EntraUser.tests.ps1` — in the top-level `BeforeAll` block (the one already containing `Mock Get-EntraTemplateGroupMembership { ... }`), add two more mocks immediately after the existing `Mock Grant-EntraGroupEligibility { } -ModuleName $script:dscModuleName` line:

```powershell
        Mock Get-EntraTemplateRoleAssignment {
            @{
                EligibilitySchedule      = @()
                ActiveAssignmentSchedule = @()
                RoleDefinitionById       = @{}
            }
        } -ModuleName $script:dscModuleName
        Mock Grant-EntraRoleEligibility { } -ModuleName $script:dscModuleName
```

- [ ] **Step 2: Run the full existing Copy-EntraUser test file to verify it still fails for the right reason**

Run: `Invoke-Pester -Path tests/Unit/Public/Copy-EntraUser.tests.ps1 -Output Detailed`
Expected: FAIL — `Get-EntraTemplateRoleAssignment`/`Grant-EntraRoleEligibility` mocks exist but `Copy-EntraUser.ps1` doesn't call them yet, so this step alone should still PASS every existing test (the mocks are inert until Step 3 wires the calls in). Confirm output shows all existing tests green before proceeding — this proves the mock addition itself is non-breaking.

- [ ] **Step 3: Add the new end-to-end role-cloning tests (still failing — the orchestration code doesn't exist yet)**

Edit `tests/Unit/Public/Copy-EntraUser.tests.ps1` — add these two new `Context` blocks immediately after the existing `Context 'C1: eligibility-only groups are still cloned end-to-end'` block (before `Context 'No credentials supplied at all: connects interactively from the start'`):

```powershell
    Context 'C2: PIM directory role eligibility is cloned end-to-end' {
        BeforeAll {
            Mock Get-EntraTemplateRoleAssignment {
                @{
                    EligibilitySchedule      = @([pscustomobject]@{
                            RoleDefinitionId = '66666666-6666-6666-6666-666666666666'
                            DirectoryScopeId = '/'
                            MemberType       = 'Direct'
                        })
                    ActiveAssignmentSchedule = @()
                    RoleDefinitionById       = @{ '66666666-6666-6666-6666-666666666666' = 'Helpdesk Administrator' }
                }
            } -ModuleName $script:dscModuleName
        }

        It 'Grants PIM role eligibility for a directly-assigned, tenant-wide eligible role' {
            Copy-EntraUser -TemplateUserId 'a@contoso.onmicrosoft.com' -NewUser 'b@contoso.onmicrosoft.com' `
                -TenantId '00000000-0000-0000-0000-000000000000' -ClientId '00000000-0000-0000-0000-000000000001' `
                -CertificatePath 'x.pfx' -CertificatePassword (ConvertTo-SecureString 'x' -AsPlainText -Force) -Confirm:$false
            Should -Invoke Grant-EntraRoleEligibility -Times 1 -ModuleName $script:dscModuleName -ParameterFilter {
                $RoleDefinitionId -eq '66666666-6666-6666-6666-666666666666' -and $DirectoryScopeId -eq '/'
            }
        }

        It 'Does not grant role eligibility under -WhatIf' {
            Copy-EntraUser -TemplateUserId 'a@contoso.onmicrosoft.com' -NewUser 'b@contoso.onmicrosoft.com' `
                -TenantId '00000000-0000-0000-0000-000000000000' -ClientId '00000000-0000-0000-0000-000000000001' `
                -CertificatePath 'x.pfx' -CertificatePassword (ConvertTo-SecureString 'x' -AsPlainText -Force) -WhatIf
            Should -Invoke Grant-EntraRoleEligibility -Times 0 -ModuleName $script:dscModuleName
        }
    }

    Context 'C3: unsupported role assignments are skipped with a warning, never granted' {
        It 'Skips an Administrative Unit-scoped role eligibility with a warning' {
            Mock Get-EntraTemplateRoleAssignment {
                @{
                    EligibilitySchedule      = @([pscustomobject]@{
                            RoleDefinitionId = '77777777-7777-7777-7777-777777777777'
                            DirectoryScopeId = '/administrativeUnits/88888888-8888-8888-8888-888888888888'
                            MemberType       = 'Direct'
                        })
                    ActiveAssignmentSchedule = @()
                    RoleDefinitionById       = @{ '77777777-7777-7777-7777-777777777777' = 'User Administrator' }
                }
            } -ModuleName $script:dscModuleName

            $null = Copy-EntraUser -TemplateUserId 'a@contoso.onmicrosoft.com' -NewUser 'b@contoso.onmicrosoft.com' `
                -TenantId '00000000-0000-0000-0000-000000000000' -ClientId '00000000-0000-0000-0000-000000000001' `
                -CertificatePath 'x.pfx' -CertificatePassword (ConvertTo-SecureString 'x' -AsPlainText -Force) `
                -Confirm:$false -WarningVariable capturedWarnings -WarningAction SilentlyContinue

            $capturedWarnings | Should -Not -BeNullOrEmpty
            Should -Invoke Grant-EntraRoleEligibility -Times 0 -ModuleName $script:dscModuleName
        }

        It 'Skips a permanent (non-PIM) role assignment with a warning' {
            Mock Get-EntraTemplateRoleAssignment {
                @{
                    EligibilitySchedule      = @()
                    ActiveAssignmentSchedule = @([pscustomobject]@{
                            RoleDefinitionId = '99999999-9999-9999-9999-999999999999'
                            DirectoryScopeId = '/'
                            MemberType       = 'Direct'
                            AssignmentType   = 'Assigned'
                        })
                    RoleDefinitionById       = @{ '99999999-9999-9999-9999-999999999999' = 'Global Reader' }
                }
            } -ModuleName $script:dscModuleName

            $null = Copy-EntraUser -TemplateUserId 'a@contoso.onmicrosoft.com' -NewUser 'b@contoso.onmicrosoft.com' `
                -TenantId '00000000-0000-0000-0000-000000000000' -ClientId '00000000-0000-0000-0000-000000000001' `
                -CertificatePath 'x.pfx' -CertificatePassword (ConvertTo-SecureString 'x' -AsPlainText -Force) `
                -Confirm:$false -WarningVariable capturedWarnings -WarningAction SilentlyContinue

            $capturedWarnings | Should -Not -BeNullOrEmpty
            Should -Invoke Grant-EntraRoleEligibility -Times 0 -ModuleName $script:dscModuleName
        }
    }
```

- [ ] **Step 4: Run tests to verify the new Context blocks fail**

Run: `Invoke-Pester -Path tests/Unit/Public/Copy-EntraUser.tests.ps1 -Output Detailed`
Expected: FAIL on the 4 new tests in `C2`/`C3` (`Grant-EntraRoleEligibility` is never invoked, no warnings are emitted) — all pre-existing tests still PASS.

- [ ] **Step 5: Update the comment-based help**

Edit `source/Public/Copy-EntraUser.ps1` — replace the `.SYNOPSIS`/`.DESCRIPTION` block:

```powershell
    .SYNOPSIS
        Clones an Entra ID user's direct group memberships, PIM-for-Groups
        eligible assignments, and PIM directory role eligible assignments
        from a template user onto a new or existing target user.
    .DESCRIPTION
        Resolves the template user and the target user, enumerates the
        template user's direct (non-transitive) group memberships and
        current PIM-for-Groups eligibility schedule instances, partitions
        those memberships into plain groups and PIM-for-Groups groups, then
        idempotently adds the target user as a direct member of each plain
        group and grants an ELIGIBLE (never active/permanent) PIM-for-Groups
        assignment for each PIM group, mirroring the template user's access
        tier (member vs owner). Dynamic-membership and role-assignable
        groups found in the template user's direct memberships are skipped
        with a named Write-Warning rather than cloned or silently dropped.

        Separately, enumerates the template user's directly-assigned (never
        inherited via a group or an Administrative Unit) PIM directory role
        eligibility schedule instances scoped tenant-wide, and grants an
        ELIGIBLE (never active/permanent) PIM directory role assignment for
        each one. Administrative Unit-scoped role eligibilities and
        permanent (non-PIM) role assignments are skipped with a named
        Write-Warning rather than cloned or silently dropped.

        Authenticates via certificate-based app-only auth when a certificate
        is supplied, falling back automatically to interactive delegated
        sign-in (with an explicit warning) if certificate-based auth cannot
        be established. When no certificate parameter is supplied at all --
        e.g. no app registration/certificate exists yet -- this connects
        interactively from the start, with no CBA attempt and no fallback
        warning (there is nothing to fall back from).
```

Replace the `.NOTES` block:

```powershell
    .NOTES
        Application permissions required (CBA app registration must be
        pre-consented with these; see Get-RequiredGraphPermission):
            - User.ReadWrite.All
            - GroupMember.ReadWrite.All
            - PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup
            - RoleEligibilitySchedule.ReadWrite.Directory
            - RoleAssignmentSchedule.Read.Directory

        Delegated scopes required (interactive fallback path; passed
        explicitly to Connect-MgGraph -Scopes, never relying on cached
        consent):
            - User.ReadWrite.All
            - GroupMember.ReadWrite.All
            - PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup
            - RoleEligibilitySchedule.ReadWrite.Directory
            - RoleAssignmentSchedule.Read.Directory

        RoleAssignmentSchedule.Read.Directory is read-only and used solely
        to detect permanent (non-PIM) directory role assignments so they
        can be skipped with a warning instead of silently cloned as
        standing access.

        Verb choice: Copy- (approved verb) was chosen over New- because this
        function's defining behaviour is replicating an existing principal's
        access model onto another principal, not creating a novel resource
        from a caller-authored specification.
```

- [ ] **Step 6: Wire the orchestration calls**

Edit `source/Public/Copy-EntraUser.ps1` — replace the `try { ... }` block inside `process`:

```powershell
        try {
            $templateUser = Resolve-EntraTemplateUser -UserId $TemplateUserId
            $newUserObject = Resolve-EntraNewUser -NewUser $NewUser

            $membership = Get-EntraTemplateGroupMembership -TemplateUserId $templateUser.Id
            $split = Split-EntraGroupMembership -DirectGroup $membership.DirectGroup `
                -EligibilityOnlyGroup $membership.EligibilityOnlyGroup `
                -EligibilitySchedule $membership.EligibilitySchedule

            foreach ($group in $split.UnsupportedGroup) {
                Write-Warning "Skipped group '$($group.DisplayName)' ($($group.Id)): dynamic-membership or role-assignable groups are not cloned by Copy-EntraUser."
            }

            $roleAssignment = Get-EntraTemplateRoleAssignment -TemplateUserId $templateUser.Id
            $roleSplit = Split-EntraRoleAssignment -EligibilitySchedule $roleAssignment.EligibilitySchedule `
                -ActiveAssignmentSchedule $roleAssignment.ActiveAssignmentSchedule `
                -RoleDefinitionById $roleAssignment.RoleDefinitionById

            foreach ($role in $roleSplit.UnsupportedRole) {
                Write-Warning "Skipped role '$($role.DisplayName)' ($($role.RoleDefinitionId)): $($role.Reason)"
            }

            if ($PSCmdlet.ShouldProcess($newUserObject.Id, "Clone group memberships, PIM-for-Groups eligibility, and PIM directory role eligibility from '$TemplateUserId'")) {
                foreach ($group in $split.PlainGroup) {
                    Add-EntraGroupMembership -GroupId $group.Id -NewUserId $newUserObject.Id
                }

                foreach ($group in $split.PimGroup) {
                    Grant-EntraGroupEligibility -GroupId $group.Id -NewUserId $newUserObject.Id -AccessId $group.AccessId
                }

                foreach ($role in $roleSplit.PimRole) {
                    Grant-EntraRoleEligibility -RoleDefinitionId $role.RoleDefinitionId -NewUserId $newUserObject.Id -DirectoryScopeId $role.DirectoryScopeId
                }
            }
        }
```

- [ ] **Step 7: Run the full Copy-EntraUser test file to verify everything passes**

Run: `Invoke-Pester -Path tests/Unit/Public/Copy-EntraUser.tests.ps1 -Output Detailed`
Expected: PASS — every pre-existing test plus the 4 new `C2`/`C3` tests.

- [ ] **Step 8: Lint**

Run: `Invoke-ScriptAnalyzer -Path source/Public/Copy-EntraUser.ps1 -Settings PSScriptAnalyzerSettings.psd1 -Severity Error,Warning`
Expected: no output.

- [ ] **Step 9: Commit**

```bash
git add source/Public/Copy-EntraUser.ps1 tests/Unit/Public/Copy-EntraUser.tests.ps1
git commit -m "feat: clone directly-assigned PIM directory role eligibility in Copy-EntraUser"
```

---

## Task 6: Changelog, full validation, final commit

**Files:**
- Modify: `CHANGELOG.md`

**Interfaces:** None — documentation and validation only.

- [ ] **Step 1: Add a CHANGELOG entry**

Edit `CHANGELOG.md` — add a new bullet under the existing `## [Unreleased]` → `### Added` section (above the existing `-PassThru` bullet, newest-first):

```markdown
- `Copy-EntraUser` now also clones the template user's directly-assigned,
  PIM-eligible directory role assignments onto the new/target user, as an
  ELIGIBLE (never active/permanent) grant — mirroring the existing
  PIM-for-Groups eligibility cloning. Administrative Unit-scoped role
  eligibilities and permanent (non-PIM) role assignments are skipped with a
  named `Write-Warning` rather than cloned or silently dropped. Requires two
  additional Graph permissions: `RoleEligibilitySchedule.ReadWrite.Directory`
  and `RoleAssignmentSchedule.Read.Directory` (see
  `Get-RequiredGraphPermission`).

```

- [ ] **Step 2: Run the full unit test suite**

Run: `Invoke-Pester -Path tests/Unit -Output Detailed`
Expected: PASS, all files including the 4 new/modified ones from Tasks 1-5.

- [ ] **Step 3: Run the full test suite with coverage**

Run:
```powershell
Invoke-Pester -Path tests -CodeCoverage source/**/*.ps1 -Output Detailed
```
Expected: PASS, coverage stays at or above the 85% threshold declared in `build.yaml`. If coverage drops below 85%, identify the uncovered lines in the new files and add a targeted test before proceeding — do not lower the threshold.

- [ ] **Step 4: Run ScriptAnalyzer across the whole source tree**

Run: `Invoke-ScriptAnalyzer -Path source/ -Recurse -Settings PSScriptAnalyzerSettings.psd1 -Severity Error,Warning`
Expected: no output (zero violations across the whole tree, not just the new files).

- [ ] **Step 5: Run the QA test suite**

Run: `Invoke-Pester -Path tests/QA -Output Detailed`
Expected: PASS — this validates ScriptAnalyzer compliance, changelog format, and manifest/help quality as part of the automated QA checks.

- [ ] **Step 6: Commit the changelog**

```bash
git add CHANGELOG.md
git commit -m "docs: add changelog entry for PIM directory role cloning"
```

---

## Post-plan: branch, PR, merge

This plan's tasks assume work happens on a feature branch (create it before Task 1 if not already done: `git checkout -b feature/pim-role-cloning` from `main`, per the project's git workflow — never commit new feature work directly to `main`). Once all six tasks are committed and green, push the branch and open a PR (`git push -u origin feature/pim-role-cloning`, `gh pr create`) — confirm with the user before merging, per the "commit or push only when asked" default; this plan covers implementation, not the merge decision.
