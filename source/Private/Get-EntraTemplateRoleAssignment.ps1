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
