# Connects to Microsoft Graph, defaulting to certificate-based app-only auth
# when certificate parameters are supplied, falling back to (or starting
# directly with) interactive delegated sign-in otherwise.
#
# The portable 'CertificateFile' parameter set (PFX path + SecureString
# password, loaded via X509Certificate2) works identically on Windows,
# macOS, and Linux and is the primary supported certificate-based path. The
# 'Thumbprint' parameter set depends on a Windows certificate store and is
# provided only for environments where one already exists.
#
# If the chosen CBA path throws for any reason (module missing, certificate
# not found or expired, Connect-MgGraph itself throws), this function emits
# an explicit Write-Warning naming the fallback and connects interactively
# instead, requesting the exact scopes from Get-RequiredGraphPermission --
# never relying on previously cached consent.
#
# When neither -CertificateThumbprint nor -CertificatePath is supplied at
# all (the 'Interactive' parameter set), no certificate-based attempt is
# made and no fallback warning is emitted -- this function connects
# interactively from the start, since there is nothing to fall back from.
# TenantId and ClientId remain optional in this mode; Graph's own
# interactive sign-in prompts for a tenant/uses its default client
# registration when they are omitted.
function Connect-EntraGraphSession {
    [CmdletBinding(DefaultParameterSetName = 'Interactive')]
    [OutputType([object])]
    param(
        [Parameter()]
        [string] $TenantId,

        [Parameter()]
        [string] $ClientId,

        [Parameter(Mandatory, ParameterSetName = 'Thumbprint')]
        [ValidateNotNullOrEmpty()]
        [string] $CertificateThumbprint,

        [Parameter(Mandatory, ParameterSetName = 'CertificateFile')]
        [ValidateNotNullOrEmpty()]
        [string] $CertificatePath,

        [Parameter(Mandatory, ParameterSetName = 'CertificateFile')]
        [securestring] $CertificatePassword
    )

    $cbaSucceeded = $false
    $attemptsCba = $PSCmdlet.ParameterSetName -in @('Thumbprint', 'CertificateFile')

    if ($attemptsCba) {
        if ([string]::IsNullOrWhiteSpace($TenantId) -or [string]::IsNullOrWhiteSpace($ClientId)) {
            throw 'TenantId and ClientId are required for certificate-based authentication. Supply both, or omit every certificate parameter to connect interactively instead.'
        }

        try {
            if ($PSCmdlet.ParameterSetName -eq 'CertificateFile') {
                $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
                    $CertificatePath, $CertificatePassword
                )
                Connect-MgGraph -ClientId $ClientId -TenantId $TenantId -Certificate $certificate -ErrorAction Stop
            }
            else {
                Connect-MgGraph -ClientId $ClientId -TenantId $TenantId `
                    -CertificateThumbprint $CertificateThumbprint -ErrorAction Stop
            }
            $cbaSucceeded = $true
            Write-Verbose "Connected via certificate-based auth (ClientId=$ClientId, TenantId=$TenantId)."
            Write-ToLog -Message "Connected to Microsoft Graph via certificate-based auth (ClientId=$ClientId, TenantId=$TenantId)." -Level 'SUCCESS' -WhatIf:$false -Confirm:$false
        }
        catch {
            Write-Warning "Certificate-based authentication failed ($($_.Exception.Message)); falling back to interactive delegated sign-in."
            Write-ToLog -Message "Certificate-based authentication failed ($($_.Exception.Message)); falling back to interactive delegated sign-in." -Level 'WARN' -WhatIf:$false -Confirm:$false
        }
    }
    else {
        Write-Verbose 'No certificate parameters supplied; connecting interactively.'
    }

    if (-not $cbaSucceeded) {
        $interactiveParams = @{ Scopes = Get-RequiredGraphPermission }
        if ($TenantId) { $interactiveParams['TenantId'] = $TenantId }
        if ($ClientId) { $interactiveParams['ClientId'] = $ClientId }

        Connect-MgGraph @interactiveParams -ErrorAction Stop
        Write-Verbose "Connected via interactive delegated auth$(if ($TenantId) { " (TenantId=$TenantId)" })."
        Write-ToLog -Message "Connected to Microsoft Graph via interactive delegated auth$(if ($TenantId) { " (TenantId=$TenantId)" })." -Level 'SUCCESS' -WhatIf:$false -Confirm:$false
    }

    return Get-MgContext
}
