# Enumerates the template user's directory-role PIM eligibility schedule
# instances and current active role assignment schedule instances.
#
# Fetches PIM eligibility for directory roles via the
# RoleEligibilityScheduleInstance endpoint filtered on the template user's
# principal ID -- this is directory-role PIM, not PIM for Groups (which
# uses PrivilegedAccessGroupEligibilityScheduleInstance and must never be
# used here). Also fetches the template user's current active role
# assignment schedule instances via the RoleAssignmentScheduleInstance
# endpoint, purely so Split-EntraRoleAssignment can detect and flag
# permanent, non-PIM role assignments -- an eligible-but-not-yet-activated
# PIM directory role does NOT appear in this collection, mirroring how an
# eligible-but-not-yet-activated PIM-for-Groups assignment doesn't appear in
# direct group membership. Copy-EntraUser never clones an active assignment
# directly; only PIM-eligible roles are cloned (see Grant-EntraRoleEligibility).
#
# Also resolves each distinct RoleDefinitionId referenced by either
# collection to a display name via Get-MgRoleManagementDirectoryRoleDefinition,
# for use in warning messages -- the same purpose as group DisplayName
# resolution in Get-EntraTemplateGroupMembership.
#
# Returns a hashtable with keys EligibilitySchedule, ActiveAssignmentSchedule
# (both arrays), and RoleDefinitionById (a hashtable of RoleDefinitionId ->
# DisplayName).
function Get-EntraTemplateRoleAssignment {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $TemplateUserId
    )

    $escapedTemplateUserId = ConvertTo-EscapedODataString -Value $TemplateUserId

    try {
        $eligibilitySchedule = @(Invoke-EntraGraphRequestWithRetry -ScriptBlock {
                Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance `
                    -Filter "principalId eq '$escapedTemplateUserId'" -All -ErrorAction Stop
            })
        $activeAssignmentSchedule = @(Invoke-EntraGraphRequestWithRetry -ScriptBlock {
                Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance `
                    -Filter "principalId eq '$escapedTemplateUserId'" -All -ErrorAction Stop
            })
    }
    catch {
        throw "Failed to enumerate template user '$TemplateUserId' directory role eligibility/assignment: $($_.Exception.Message)"
    }

    $roleDefinitionId = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($instance in @($eligibilitySchedule) + @($activeAssignmentSchedule)) {
        [void]$roleDefinitionId.Add($instance.RoleDefinitionId)
    }

    $roleDefinitionById = @{}
    foreach ($id in $roleDefinitionId) {
        try {
            $roleDefinition = Invoke-EntraGraphRequestWithRetry -ScriptBlock {
                Get-MgRoleManagementDirectoryRoleDefinition -UnifiedRoleDefinitionId $id -ErrorAction Stop
            }
        }
        catch {
            Write-Warning "Could not resolve role definition '$id' (it may have been deleted or is inaccessible); its display name will be unavailable in warnings. $($_.Exception.Message)"
            continue
        }
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
