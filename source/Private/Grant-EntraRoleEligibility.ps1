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
