function Resolve-EntraNewUser {
    <#
    .SYNOPSIS
        Resolves the target ("new") user: an existing user by identifier, or
        a user to be created from a supplied property hashtable.
    .DESCRIPTION
        When -NewUser is a hashtable, this checks for an existing user with
        the same UserPrincipalName first (idempotency: a previous, interrupted
        run may already have created it) before calling New-MgUser.
    .PARAMETER NewUser
        Either the UPN/ObjectId of a pre-existing target user, or a hashtable
        of properties (must include DisplayName, UserPrincipalName,
        MailNickname, PasswordProfile, AccountEnabled) for a user to create.
    .OUTPUTS
        The Microsoft Graph user object.
    .EXAMPLE
        Resolve-EntraNewUser -NewUser 'new.user@contoso.onmicrosoft.com'
    .EXAMPLE
        Resolve-EntraNewUser -NewUser @{
            DisplayName = 'New Hire'; UserPrincipalName = 'new.hire@contoso.onmicrosoft.com'
            MailNickname = 'new.hire'; PasswordProfile = @{ Password = (New-Guid) }
            AccountEnabled = $true
        }
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [object] $NewUser
    )

    if ($NewUser -is [string]) {
        return Get-MgUser -UserId $NewUser -ErrorAction Stop
    }

    $requiredKey = @('DisplayName', 'UserPrincipalName', 'MailNickname', 'PasswordProfile', 'AccountEnabled')
    foreach ($key in $requiredKey) {
        if (-not $NewUser.ContainsKey($key)) {
            throw "The -NewUser hashtable is missing required key '$key'."
        }
    }

    if ($NewUser.UserPrincipalName -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
        throw "The -NewUser hashtable's UserPrincipalName '$($NewUser.UserPrincipalName)' is not a valid UPN."
    }

    # OData string literals delimit on a single quote; double any embedded
    # quote so a UPN containing one cannot break out of the filter literal
    # and redirect the lookup to a different principal.
    $escapedUpn = $NewUser.UserPrincipalName.Replace("'", "''")
    $existing = Get-MgUser -Filter "userPrincipalName eq '$escapedUpn'" -ErrorAction Stop
    if ($existing) {
        Write-Verbose "New user '$($NewUser.UserPrincipalName)' already exists (Id=$($existing.Id)); skipping creation."
        return $existing
    }

    if ($PSCmdlet.ShouldProcess($NewUser.UserPrincipalName, 'Create user')) {
        return New-MgUser -BodyParameter $NewUser -ErrorAction Stop
    }
}
