# Partitions the template user's direct group memberships and
# eligibility-only groups into groups that can be cloned as a plain direct
# membership, groups that must be cloned as a PIM-for-Groups eligible
# assignment instead, and groups that cannot be safely cloned by this
# function at all.
#
# Pure function: no Graph calls, no side effects. The candidate group set
# is the UNION of -DirectGroup and -EligibilityOnlyGroup, because an
# ELIGIBLE (not yet activated) PIM-for-Groups assignment does not appear in
# the template user's direct membership results -- direct membership and
# PIM eligibility are separate planes in Graph. A group covered by a
# PIM-for-Groups eligibility schedule instance is placed in PimGroup, never
# PlainGroup, so the new user never receives both a direct membership and
# an eligibility request for the same group. Dynamic-membership groups and
# role-assignable groups are routed to UnsupportedGroup: New-MgGroupMemberByRef
# cannot safely write to dynamic-membership groups (membership is computed,
# not settable), and role-assignable groups require elevated handling this
# function does not implement. Eligibility is checked BEFORE the
# dynamic/role-assignable guard: a role-assignable group the template user
# is only eligible for (never a direct member of) is routed to PimGroup,
# not UnsupportedGroup, because PimGroup only ever produces an ELIGIBLE
# PIM-for-Groups grant (Grant-EntraGroupEligibility), never a
# direct-membership write -- so the unsafe write the role-assignable guard
# exists to prevent cannot occur via that path regardless of ordering. Only
# a role-assignable group with NO eligibility instance reaches the guard
# and is routed to UnsupportedGroup.
#
# IsAssignableToRole is read from the typed SDK property first, with a
# fallback to AdditionalProperties['isAssignableToRole'] for defensiveness
# (a caller-supplied hashtable-backed object, or a Graph response shape
# where the property is genuinely absent).
#
# Callers must Write-Warning for each entry in UnsupportedGroup rather than
# silently dropping them. Returns a hashtable with keys PlainGroup,
# PimGroup, UnsupportedGroup (each System.Object[]).
function Split-EntraGroupMembership {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $DirectGroup,

        [Parameter()]
        [AllowEmptyCollection()]
        [object[]] $EligibilityOnlyGroup = @(),

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

    $candidateGroup = [System.Collections.Generic.List[object]]::new()
    $seenGroupId = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($group in @($DirectGroup) + @($EligibilityOnlyGroup)) {
        if ($null -eq $group) {
            continue
        }
        if ($seenGroupId.Add($group.Id)) {
            $candidateGroup.Add($group)
        }
    }

    foreach ($group in $candidateGroup) {
        if ($eligibilityByGroupId.ContainsKey($group.Id)) {
            $pimGroupEntry = [pscustomobject]@{
                Id                    = $group.Id
                DisplayName           = $group.DisplayName
                GroupTypes            = $group.GroupTypes
                IsAssignableToRole    = $group.IsAssignableToRole
                AdditionalProperties  = $group.AdditionalProperties
                AccessId              = $eligibilityByGroupId[$group.Id].AccessId
            }
            $pimGroup.Add($pimGroupEntry)
            continue
        }

        $isDynamic = $group.GroupTypes -contains 'DynamicMembership'
        $isRoleAssignable = if ($null -ne $group.IsAssignableToRole) {
            [bool]$group.IsAssignableToRole
        }
        elseif ($null -ne $group.AdditionalProperties) {
            [bool]$group.AdditionalProperties['isAssignableToRole']
        }
        else {
            $false
        }

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
