# Resolves the template user by UserPrincipalName or ObjectId.
function Resolve-EntraTemplateUser {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $UserId
    )

    try {
        return Invoke-EntraGraphRequestWithRetry -ScriptBlock {
            Get-MgUser -UserId $UserId -ErrorAction Stop
        }
    }
    catch {
        throw "Template user '$UserId' could not be resolved via Microsoft Graph: $($_.Exception.Message)"
    }
}
