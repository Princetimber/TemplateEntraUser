function Get-EntraTemplateGroupMembership {
    <#
    .SYNOPSIS
        Enumerates the template user's direct group memberships and current
        PIM-for-Groups eligibility schedule instances.
    .DESCRIPTION
        Direct memberships are read via Get-MgUserMemberOfAsGroup, which is
        explicitly non-transitive -- dynamic and nested/transitive memberships
        are intentionally excluded, since those cannot be assigned to
        directly. PIM-for-Groups eligibility uses the
        PrivilegedAccessGroupEligibilityScheduleInstance endpoint filtered on
        the template user's principal ID -- this is PIM for Groups, not
        directory-role PIM (which uses UnifiedRoleEligibilitySchedule* /
        RoleEligibilitySchedule* cmdlets and must never be used here).
    .PARAMETER TemplateUserId
        The template user's Object ID.
    .OUTPUTS
        Hashtable with keys DirectGroup and EligibilitySchedule (both arrays).
    .EXAMPLE
        Get-EntraTemplateGroupMembership -TemplateUserId $templateUser.Id
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $TemplateUserId
    )

    return @{
        DirectGroup         = @(Get-MgUserMemberOfAsGroup -UserId $TemplateUserId -All)
        EligibilitySchedule = @(Get-MgIdentityGovernancePrivilegedAccessGroupEligibilityScheduleInstance `
                -Filter "principalId eq '$TemplateUserId'" -All)
    }
}
