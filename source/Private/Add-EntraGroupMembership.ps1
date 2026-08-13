# Idempotently adds a user as a direct member of a group. Reads the group's
# current direct members first, filtered to the target user's Object ID
# rather than enumerating the whole group; if the target user is already
# present, skips with Write-Verbose rather than attempting the add and
# relying on Graph to reject the duplicate.
function Add-EntraGroupMembership {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $GroupId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $NewUserId
    )

    $escapedNewUserId = ConvertTo-EscapedODataString -Value $NewUserId
    try {
        $existingMember = @(Invoke-EntraGraphRequestWithRetry -ScriptBlock {
                Get-MgGroupMember -GroupId $GroupId -Filter "id eq '$escapedNewUserId'" `
                    -ConsistencyLevel eventual -CountVariable memberCount -All -ErrorAction Stop
            })
    }
    catch {
        throw "Failed to read existing membership of group '$GroupId' for user '$NewUserId': $($_.Exception.Message)"
    }

    if ($existingMember.Count -gt 0) {
        Write-Verbose "User '$NewUserId' is already a member of group '$GroupId'; skipping."
        return
    }

    if ($PSCmdlet.ShouldProcess($GroupId, "Add user '$NewUserId' as a direct member")) {
        try {
            Invoke-EntraGraphRequestWithRetry -ScriptBlock {
                New-MgGroupMemberByRef -GroupId $GroupId -BodyParameter @{
                    '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$NewUserId"
                } -ErrorAction Stop
            }
            Write-ToLog -Message "Added user '$NewUserId' as a direct member of group '$GroupId'." -Level 'SUCCESS' -WhatIf:$false -Confirm:$false
        }
        catch {
            throw "Failed to add user '$NewUserId' as a direct member of group '$GroupId': $($_.Exception.Message)"
        }
    }
}
