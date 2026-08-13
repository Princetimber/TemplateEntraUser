# Idempotently grants a user an ELIGIBLE (never active/permanent)
# PIM-for-Groups assignment, mirroring the access tier (member/owner) the
# template user held.
#
# Reads existing eligibility schedule instances for this principal/group
# pair first; if one already exists, skips with Write-Verbose rather than
# attempting the create and relying on Graph to reject a duplicate request.
# Uses the PIM-for-Groups PrivilegedAccessGroupEligibilityScheduleRequest
# endpoint -- never the directory-role PIM (UnifiedRoleEligibilitySchedule*)
# endpoints. The request action is always 'AdminAssign': an admin directly
# assigning eligibility, never a self-service or extend/renew action.
#
# Eligibility expiration is deliberately normalized to 'NoExpiration' rather
# than mirrored from the template user's own eligibility schedule: an
# eligibility end date is tied to the circumstances of the template
# principal (e.g. a fixed-term project or contract), and silently carrying
# that same absolute date onto an unrelated new principal would be
# semantically wrong, not merely an implementation shortcut. Operators who
# need a bounded eligibility window should apply one deliberately after
# cloning, via PIM itself.
function Grant-EntraGroupEligibility {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', 'Justification',
        Justification = 'Referenced inside the Invoke-EntraGraphRequestWithRetry -ScriptBlock closure below; the analyzer does not trace variable usage into nested scriptblocks.'
    )]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $GroupId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $NewUserId,

        [Parameter(Mandatory)]
        [ValidateSet('member', 'owner')]
        [string] $AccessId,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Justification = 'Provisioned via Copy-EntraUser template clone.'
    )

    $escapedNewUserId = ConvertTo-EscapedODataString -Value $NewUserId
    $escapedGroupId = ConvertTo-EscapedODataString -Value $GroupId

    try {
        $existingInstance = @(Invoke-EntraGraphRequestWithRetry -ScriptBlock {
                Get-MgIdentityGovernancePrivilegedAccessGroupEligibilityScheduleInstance `
                    -Filter "principalId eq '$escapedNewUserId' and groupId eq '$escapedGroupId'" -All -ErrorAction Stop
            })
    }
    catch {
        throw "Failed to read existing PIM-for-Groups eligibility for user '$NewUserId' on group '$GroupId': $($_.Exception.Message)"
    }

    if ($existingInstance.Count -gt 0) {
        Write-Verbose "User '$NewUserId' already has a PIM-for-Groups eligibility instance for group '$GroupId'; skipping."
        return
    }

    if ($PSCmdlet.ShouldProcess($GroupId, "Grant eligible '$AccessId' PIM-for-Groups assignment to user '$NewUserId'")) {
        try {
            Invoke-EntraGraphRequestWithRetry -ScriptBlock {
                New-MgIdentityGovernancePrivilegedAccessGroupEligibilityScheduleRequest -BodyParameter @{
                    accessId      = $AccessId
                    principalId   = $NewUserId
                    groupId       = $GroupId
                    action        = 'AdminAssign'
                    scheduleInfo  = @{
                        startDateTime = (Get-Date).ToUniversalTime()
                        expiration    = @{ type = 'NoExpiration' }
                    }
                    justification = $Justification
                } -ErrorAction Stop
            }
            Write-ToLog -Message "Granted PIM-for-Groups '$AccessId' eligibility to user '$NewUserId' for group '$GroupId'." -Level 'SUCCESS' -WhatIf:$false -Confirm:$false
        }
        catch {
            throw "Failed to grant PIM-for-Groups '$AccessId' eligibility to user '$NewUserId' for group '$GroupId': $($_.Exception.Message)"
        }
    }
}
