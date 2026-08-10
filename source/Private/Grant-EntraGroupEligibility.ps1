function Grant-EntraGroupEligibility {
    <#
    .SYNOPSIS
        Idempotently grants a user an ELIGIBLE (never active/permanent)
        PIM-for-Groups assignment, mirroring the access tier (member/owner)
        the template user held.
    .DESCRIPTION
        Reads existing eligibility schedule instances for this principal/group
        pair first; if one already exists, skips with Write-Verbose rather
        than attempting the create and relying on Graph to reject a duplicate
        request. Uses the PIM-for-Groups
        PrivilegedAccessGroupEligibilityScheduleRequest endpoint -- never the
        directory-role PIM (UnifiedRoleEligibilitySchedule*) endpoints. The
        request action is always 'AdminAssign': an admin directly assigning
        eligibility, never a self-service or extend/renew action.
    .PARAMETER GroupId
        The Object ID of the PIM-for-Groups-onboarded group.
    .PARAMETER NewUserId
        The Object ID of the user to grant eligibility to.
    .PARAMETER AccessId
        The access tier to grant: 'member' or 'owner', mirrored from the
        template user's own eligibility.
    .PARAMETER Justification
        Text justification recorded on the eligibility request.
    .EXAMPLE
        Grant-EntraGroupEligibility -GroupId $groupId -NewUserId $newUser.Id -AccessId 'member'
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string] $GroupId,

        [Parameter(Mandatory)]
        [string] $NewUserId,

        [Parameter(Mandatory)]
        [ValidateSet('member', 'owner')]
        [string] $AccessId,

        [Parameter()]
        [string] $Justification = 'Provisioned via Copy-EntraUser template clone.'
    )

    $existingInstance = @(Get-MgIdentityGovernancePrivilegedAccessGroupEligibilityScheduleInstance `
            -Filter "principalId eq '$NewUserId' and groupId eq '$GroupId'" -All)

    if ($existingInstance.Count -gt 0) {
        Write-Verbose "User '$NewUserId' already has a PIM-for-Groups eligibility instance for group '$GroupId'; skipping."
        return
    }

    if ($PSCmdlet.ShouldProcess($GroupId, "Grant eligible '$AccessId' PIM-for-Groups assignment to user '$NewUserId'")) {
        New-MgIdentityGovernancePrivilegedAccessGroupEligibilityScheduleRequest -BodyParameter @{
            accessId      = $AccessId
            principalId   = $NewUserId
            groupId       = $GroupId
            action        = 'AdminAssign'
            scheduleInfo  = @{
                startDateTime = (Get-Date)
                expiration    = @{ type = 'NoExpiration' }
            }
            justification = $Justification
        }
    }
}
