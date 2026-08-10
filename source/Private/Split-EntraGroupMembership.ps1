function Split-EntraGroupMembership {
    <#
    .SYNOPSIS
        Partitions a template user's direct group memberships into groups
        that can be cloned as a plain direct membership, groups that must be
        cloned as a PIM-for-Groups eligible assignment instead, and groups
        that cannot be safely cloned by this function at all.
    .DESCRIPTION
        Pure function: no Graph calls, no side effects. A group already
        covered by a PIM-for-Groups eligibility schedule instance is placed
        in PimGroup, never PlainGroup, so the new user never receives both a
        direct membership and an eligibility request for the same group.
        Dynamic-membership groups and role-assignable groups are routed to
        UnsupportedGroup: New-MgGroupMemberByRef cannot safely write to
        dynamic-membership groups (membership is computed, not settable),
        and role-assignable groups require elevated handling this function
        does not implement. Callers must Write-Warning for each entry in
        UnsupportedGroup rather than silently dropping them.
    .PARAMETER DirectGroup
        The template user's direct, non-transitive group memberships (from
        Get-MgUserMemberOfAsGroup).
    .PARAMETER EligibilitySchedule
        The template user's current PIM-for-Groups eligibility schedule
        instances (from Get-MgIdentityGovernancePrivilegedAccessGroupEligibilityScheduleInstance).
    .OUTPUTS
        System.Collections.Hashtable with keys PlainGroup, PimGroup,
        UnsupportedGroup (each System.Object[]).
    .EXAMPLE
        Split-EntraGroupMembership -DirectGroup $direct -EligibilitySchedule $eligibility
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $DirectGroup,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $EligibilitySchedule
    )

    $eligibilityByGroupId = @{}
    foreach ($instance in $EligibilitySchedule) {
        $eligibilityByGroupId[$instance.GroupId] = $instance
    }

    $plainGroup = [System.Collections.Generic.List[object]]::new()
    $pimGroup = [System.Collections.Generic.List[object]]::new()
    $unsupportedGroup = [System.Collections.Generic.List[object]]::new()

    foreach ($group in $DirectGroup) {
        if ($eligibilityByGroupId.ContainsKey($group.Id)) {
            $group | Add-Member -MemberType NoteProperty -Name 'AccessId' `
                -Value $eligibilityByGroupId[$group.Id].AccessId -Force
            $pimGroup.Add($group)
            continue
        }

        $isDynamic = $group.GroupTypes -contains 'DynamicMembership'
        $isRoleAssignable = [bool]$group.AdditionalProperties['isAssignableToRole']

        if ($isDynamic -or $isRoleAssignable) {
            $unsupportedGroup.Add($group)
            continue
        }

        $plainGroup.Add($group)
    }

    return @{
        PlainGroup       = $plainGroup.ToArray()
        PimGroup         = $pimGroup.ToArray()
        UnsupportedGroup = $unsupportedGroup.ToArray()
    }
}
