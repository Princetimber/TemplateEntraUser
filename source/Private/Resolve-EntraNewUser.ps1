# Resolves the target ("new") user: an existing user by identifier, or a
# user to be created from a supplied property hashtable. When -NewUser is a
# hashtable, this checks for an existing user with the same
# UserPrincipalName first (idempotency: a previous, interrupted run may
# already have created it) before calling New-MgUser.
function Resolve-EntraNewUser {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [object] $NewUser
    )

    if ($NewUser -is [string]) {
        return Invoke-EntraGraphRequestWithRetry -ScriptBlock {
            Get-MgUser -UserId $NewUser -ErrorAction Stop
        }
    }

    $requiredKey = @('DisplayName', 'UserPrincipalName', 'MailNickname', 'PasswordProfile', 'AccountEnabled')
    foreach ($key in $requiredKey) {
        if (-not $NewUser.ContainsKey($key)) {
            throw "The -NewUser hashtable is missing required key '$key'."
        }
    }

    # Defense in depth: never let an empty/missing Password reach New-MgUser.
    # A caller-side bug (or a declined confirmation somewhere upstream) that
    # produces a blank password must fail loudly here, not create an account
    # nobody can sign in to.
    if ([string]::IsNullOrEmpty($NewUser.PasswordProfile.Password)) {
        throw "The -NewUser hashtable's PasswordProfile.Password is empty or missing."
    }

    if ($NewUser.UserPrincipalName -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
        throw "The -NewUser hashtable's UserPrincipalName '$($NewUser.UserPrincipalName)' is not a valid UPN."
    }

    # OData string literals delimit on a single quote; double any embedded
    # quote so a UPN containing one cannot break out of the filter literal
    # and redirect the lookup to a different principal.
    $escapedUpn = ConvertTo-EscapedODataString -Value $NewUser.UserPrincipalName
    $existing = Invoke-EntraGraphRequestWithRetry -ScriptBlock {
        Get-MgUser -Filter "userPrincipalName eq '$escapedUpn'" -ErrorAction Stop
    }
    if ($existing) {
        Write-Verbose "New user '$($NewUser.UserPrincipalName)' already exists (Id=$($existing.Id)); skipping creation."
        return $existing
    }

    if ($PSCmdlet.ShouldProcess($NewUser.UserPrincipalName, 'Create user')) {
        return Invoke-EntraGraphRequestWithRetry -ScriptBlock {
            New-MgUser -BodyParameter $NewUser -ErrorAction Stop
        }
    }
}
