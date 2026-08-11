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
