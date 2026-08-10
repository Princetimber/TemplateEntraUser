function Add-EntraGroupMembership {
    <#
    .SYNOPSIS
        Idempotently adds a user as a direct member of a group.
    .DESCRIPTION
        Reads the group's current direct members first; if the target user
        is already present, skips with Write-Verbose rather than attempting
        the add and relying on Graph to reject the duplicate.
    .PARAMETER GroupId
        The Object ID of the group to add the member to.
    .PARAMETER NewUserId
        The Object ID of the user to add.
    .EXAMPLE
        Add-EntraGroupMembership -GroupId $groupId -NewUserId $newUser.Id
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string] $GroupId,

        [Parameter(Mandatory)]
        [string] $NewUserId
    )

    $existingMember = @(Get-MgGroupMember -GroupId $GroupId -All)
    if ($existingMember.Id -contains $NewUserId) {
        Write-Verbose "User '$NewUserId' is already a member of group '$GroupId'; skipping."
        return
    }

    if ($PSCmdlet.ShouldProcess($GroupId, "Add user '$NewUserId' as a direct member")) {
        New-MgGroupMemberByRef -GroupId $GroupId -BodyParameter @{
            '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$NewUserId"
        }
    }
}
