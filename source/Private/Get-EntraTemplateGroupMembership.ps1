# Enumerates the template user's direct group memberships, current
# PIM-for-Groups eligibility schedule instances, and the resolved group
# objects for any eligibility-only groups.
#
# Direct memberships are read via Get-MgUserMemberOfAsGroup, which is
# explicitly non-transitive -- dynamic and nested/transitive memberships are
# intentionally excluded, since those cannot be assigned to directly.
# PIM-for-Groups eligibility uses the
# PrivilegedAccessGroupEligibilityScheduleInstance endpoint filtered on the
# template user's principal ID -- this is PIM for Groups, not directory-role
# PIM (which uses UnifiedRoleEligibilitySchedule*/RoleEligibilitySchedule*
# cmdlets and must never be used here).
#
# An eligible-but-not-yet-activated PIM-for-Groups assignment does NOT
# appear in the direct membership results -- eligibility and direct
# membership are separate planes in Graph. For every eligibility instance
# whose GroupId is not already present in the direct membership set, the
# actual group object is resolved via Get-MgGroup so downstream
# partitioning (Split-EntraGroupMembership) has a usable
# DisplayName/GroupTypes/IsAssignableToRole for warnings and routing --
# eligibility instances themselves only carry GroupId/PrincipalId/AccessId.
#
# Returns a hashtable with keys DirectGroup, EligibilitySchedule, and
# EligibilityOnlyGroup (all arrays).
function Get-EntraTemplateGroupMembership {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $TemplateUserId
    )

    $escapedTemplateUserId = ConvertTo-EscapedODataString -Value $TemplateUserId

    try {
        $directGroup = @(Invoke-EntraGraphRequestWithRetry -ScriptBlock {
                Get-MgUserMemberOfAsGroup -UserId $TemplateUserId -All -ErrorAction Stop
            })
        $eligibilitySchedule = @(Invoke-EntraGraphRequestWithRetry -ScriptBlock {
                Get-MgIdentityGovernancePrivilegedAccessGroupEligibilityScheduleInstance `
                    -Filter "principalId eq '$escapedTemplateUserId'" -All -ErrorAction Stop
            })
    }
    catch {
        throw "Failed to enumerate template user '$TemplateUserId' group membership/eligibility: $($_.Exception.Message)"
    }

    $directGroupId = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($group in $directGroup) {
        [void]$directGroupId.Add($group.Id)
    }

    $eligibilityOnlyGroupId = [System.Collections.Generic.List[string]]::new()
    $seenEligibilityOnlyGroupId = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($instance in $eligibilitySchedule) {
        if (-not $directGroupId.Contains($instance.GroupId) -and $seenEligibilityOnlyGroupId.Add($instance.GroupId)) {
            $eligibilityOnlyGroupId.Add($instance.GroupId)
        }
    }

    $eligibilityOnlyGroup = [System.Collections.Generic.List[object]]::new()
    foreach ($groupId in $eligibilityOnlyGroupId) {
        try {
            $resolvedGroup = Invoke-EntraGraphRequestWithRetry -ScriptBlock {
                Get-MgGroup -GroupId $groupId -ErrorAction Stop
            }
        }
        catch {
            Write-Warning "Could not resolve eligibility-only group '$groupId' (it may have been deleted or is inaccessible); its PIM-for-Groups eligibility will not be cloned. $($_.Exception.Message)"
            continue
        }
        if ($null -eq $resolvedGroup) {
            Write-Warning "Could not resolve eligibility-only group '$groupId' (it may have been deleted or is inaccessible); its PIM-for-Groups eligibility will not be cloned."
            continue
        }
        $eligibilityOnlyGroup.Add($resolvedGroup)
    }

    return @{
        DirectGroup          = $directGroup
        EligibilitySchedule  = $eligibilitySchedule
        EligibilityOnlyGroup = $eligibilityOnlyGroup.ToArray()
    }
}
