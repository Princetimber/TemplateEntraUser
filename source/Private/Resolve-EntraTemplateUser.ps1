function Resolve-EntraTemplateUser {
    <#
    .SYNOPSIS
        Resolves the template user by UserPrincipalName or ObjectId.
    .PARAMETER UserId
        The template user's UserPrincipalName or ObjectId.
    .OUTPUTS
        The Microsoft Graph user object.
    .EXAMPLE
        Resolve-EntraTemplateUser -UserId 'template.user@contoso.onmicrosoft.com'
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [string] $UserId
    )

    try {
        return Get-MgUser -UserId $UserId -ErrorAction Stop
    }
    catch {
        throw "Template user '$UserId' could not be resolved via Microsoft Graph: $($_.Exception.Message)"
    }
}
