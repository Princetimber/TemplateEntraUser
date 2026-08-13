# Idempotently grants a user an ELIGIBLE (never active/permanent) PIM
# directory role assignment.
#
# Reads existing eligibility schedule instances for this
# principal/role/scope first; if one already exists, skips with
# Write-Verbose rather than attempting the create and relying on Graph to
# reject a duplicate request. Uses the directory-role PIM
# UnifiedRoleEligibilityScheduleRequest endpoint -- never the PIM-for-Groups
# PrivilegedAccessGroupEligibilityScheduleRequest endpoint (see
# Grant-EntraGroupEligibility for that). The request action is always
# 'AdminAssign': an admin directly assigning eligibility, never a
# self-service or extend/renew action.
#
# Eligibility expiration is deliberately normalized to 'NoExpiration' rather
# than mirrored from the template user's own eligibility schedule: an
# eligibility end date is tied to the circumstances of the template
# principal (e.g. a fixed-term project or contract), and silently carrying
# that same absolute date onto an unrelated new principal would be
# semantically wrong, not merely an implementation shortcut. Operators who
# need a bounded eligibility window should apply one deliberately after
# cloning, via PIM itself.
#
# -DirectoryScopeId defaults to '/' (tenant-wide) -- Copy-EntraUser only
# ever clones tenant-wide role eligibility (see Split-EntraRoleAssignment).
function Grant-EntraRoleEligibility {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', 'Justification',
        Justification = 'Referenced inside the Invoke-EntraGraphRequestWithRetry -ScriptBlock closure below; the analyzer does not trace variable usage into nested scriptblocks.'
    )]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RoleDefinitionId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $NewUserId,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $DirectoryScopeId = '/',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Justification = 'Provisioned via Copy-EntraUser template clone.'
    )

    $escapedNewUserId = ConvertTo-EscapedODataString -Value $NewUserId
    $escapedRoleDefinitionId = ConvertTo-EscapedODataString -Value $RoleDefinitionId
    $escapedDirectoryScopeId = ConvertTo-EscapedODataString -Value $DirectoryScopeId

    try {
        $existingInstance = @(Invoke-EntraGraphRequestWithRetry -ScriptBlock {
                Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance `
                    -Filter "principalId eq '$escapedNewUserId' and roleDefinitionId eq '$escapedRoleDefinitionId' and directoryScopeId eq '$escapedDirectoryScopeId'" -All -ErrorAction Stop
            })
    }
    catch {
        throw "Failed to read existing PIM role eligibility for user '$NewUserId' on role '$RoleDefinitionId' at scope '$DirectoryScopeId': $($_.Exception.Message)"
    }

    if ($existingInstance.Count -gt 0) {
        Write-Verbose "User '$NewUserId' already has a PIM role eligibility instance for role '$RoleDefinitionId' at scope '$DirectoryScopeId'; skipping."
        return
    }

    if ($PSCmdlet.ShouldProcess($RoleDefinitionId, "Grant eligible PIM directory role assignment to user '$NewUserId'")) {
        try {
            Invoke-EntraGraphRequestWithRetry -ScriptBlock {
                New-MgRoleManagementDirectoryRoleEligibilityScheduleRequest -BodyParameter @{
                    action           = 'AdminAssign'
                    principalId      = $NewUserId
                    roleDefinitionId = $RoleDefinitionId
                    directoryScopeId = $DirectoryScopeId
                    scheduleInfo     = @{
                        startDateTime = (Get-Date).ToUniversalTime()
                        expiration    = @{ type = 'NoExpiration' }
                    }
                    justification    = $Justification
                } -ErrorAction Stop
            }
            Write-ToLog -Message "Granted PIM directory role eligibility to user '$NewUserId' for role '$RoleDefinitionId' at scope '$DirectoryScopeId'." -Level 'SUCCESS' -WhatIf:$false -Confirm:$false
        }
        catch {
            throw "Failed to grant PIM directory role eligibility to user '$NewUserId' for role '$RoleDefinitionId' at scope '$DirectoryScopeId': $($_.Exception.Message)"
        }
    }
}
