function Get-RequiredGraphPermission {
    <#
    .SYNOPSIS
        Returns the single, canonical set of least-privilege Microsoft Graph
        permission names Copy-EntraUser requires.
    .DESCRIPTION
        Used identically for both auth paths: as the -Scopes argument to the
        interactive Connect-MgGraph fallback, and documented verbatim in
        Copy-EntraUser's comment-based help .NOTES as the application
        permissions the CBA app registration must be pre-consented with.
        Keeping one source of truth prevents the two lists drifting apart.

        NOTE: PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup is the
        verified Microsoft Graph permission name for reading and creating
        PIM-for-Groups eligibility schedule requests/instances. It is NOT
        named PrivilegedAccessGroup.ReadWrite.AzureADGroup (that string does
        not exist in the Graph permissions reference).

        NOTE: RoleEligibilitySchedule.ReadWrite.Directory and
        RoleAssignmentSchedule.Read.Directory are the verified Microsoft
        Graph permission names for directory-role PIM (as opposed to
        PIM-for-Groups): reading/writing role eligibility schedule instances
        and requests, and read-only access to active role assignment
        schedule instances (used only to detect permanent, non-PIM role
        assignments so they can be skipped with a warning rather than
        cloned).
    .OUTPUTS
        System.String[]
    .EXAMPLE
        Get-RequiredGraphPermission
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    return @(
        'User.ReadWrite.All'
        'GroupMember.ReadWrite.All'
        'PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup'
        'RoleEligibilitySchedule.ReadWrite.Directory'
        'RoleAssignmentSchedule.Read.Directory'
    )
}
