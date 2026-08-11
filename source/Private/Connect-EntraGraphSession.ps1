function Connect-EntraGraphSession {
    <#
    .SYNOPSIS
        Connects to Microsoft Graph, defaulting to certificate-based app-only
        auth when certificate parameters are supplied, falling back to (or
        starting directly with) interactive delegated sign-in otherwise.
    .DESCRIPTION
        The portable 'CertificateFile' parameter set (PFX path + SecureString
        password, loaded via X509Certificate2) works identically on Windows,
        macOS, and Linux and is the primary supported certificate-based path.
        The 'Thumbprint' parameter set depends on a Windows certificate store
        and is provided only for environments where one already exists.

        If the chosen CBA path throws for any reason (module missing,
        certificate not found or expired, Connect-MgGraph itself throws),
        this function emits an explicit Write-Warning naming the fallback and
        connects interactively instead, requesting the exact scopes from
        Get-RequiredGraphPermission -- never relying on previously cached
        consent.

        When neither -CertificateThumbprint nor -CertificatePath is supplied
        at all (the 'Interactive' parameter set), no certificate-based attempt
        is made and no fallback warning is emitted -- this function connects
        interactively from the start, since there is nothing to fall back
        from. TenantId and ClientId remain optional in this mode; Graph's own
        interactive sign-in prompts for a tenant/uses its default client
        registration when they are omitted.
    .PARAMETER TenantId
        The Entra ID tenant ID (GUID or verified domain). Required when a
        certificate parameter is supplied (certificate-based auth always
        needs an explicit tenant and app registration); optional for
        interactive-only sign-in.
    .PARAMETER ClientId
        The app registration's application (client) ID. Required when a
        certificate parameter is supplied; optional for interactive-only
        sign-in.
    .PARAMETER CertificateThumbprint
        Thumbprint of a certificate already present in a local certificate
        store. Windows-only; not portable to macOS or Linux.
    .PARAMETER CertificatePath
        Path to a PFX certificate file. Portable across all platforms.
    .PARAMETER CertificatePassword
        SecureString password protecting the PFX file at CertificatePath.
    .OUTPUTS
        The object returned by Get-MgContext.
    .EXAMPLE
        Connect-EntraGraphSession -TenantId $tenantId -ClientId $clientId `
            -CertificatePath ./copy-entrauser.pfx -CertificatePassword $securePassword
    .EXAMPLE
        # No app registration/certificate available yet: connect interactively.
        Connect-EntraGraphSession
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Interactive')]
    [OutputType([object])]
    param(
        [Parameter()]
        [string] $TenantId,

        [Parameter()]
        [string] $ClientId,

        [Parameter(Mandatory, ParameterSetName = 'Thumbprint')]
        [string] $CertificateThumbprint,

        [Parameter(Mandatory, ParameterSetName = 'CertificateFile')]
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

        if ($PSCmdlet.ShouldProcess($TenantId, 'Connect to Microsoft Graph (certificate-based, app-only)')) {
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
            }
            catch {
                Write-Warning "Certificate-based authentication failed ($($_.Exception.Message)); falling back to interactive delegated sign-in."
            }
        }
    }
    else {
        Write-Verbose 'No certificate parameters supplied; connecting interactively.'
    }

    if (-not $cbaSucceeded) {
        $target = if ($TenantId) { $TenantId } else { 'interactive sign-in' }
        if ($PSCmdlet.ShouldProcess($target, 'Connect to Microsoft Graph (interactive delegated sign-in)')) {
            $interactiveParams = @{ Scopes = Get-RequiredGraphPermission }
            if ($TenantId) { $interactiveParams['TenantId'] = $TenantId }
            if ($ClientId) { $interactiveParams['ClientId'] = $ClientId }

            Connect-MgGraph @interactiveParams -ErrorAction Stop
            Write-Verbose "Connected via interactive delegated auth$(if ($TenantId) { " (TenantId=$TenantId)" })."
        }
    }

    return Get-MgContext
}
