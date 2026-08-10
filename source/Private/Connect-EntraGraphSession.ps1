function Connect-EntraGraphSession {
    <#
    .SYNOPSIS
        Connects to Microsoft Graph, defaulting to certificate-based app-only
        auth, falling back to interactive delegated sign-in automatically if
        CBA cannot be established.
    .DESCRIPTION
        The portable 'CertificateFile' parameter set (PFX path + SecureString
        password, loaded via X509Certificate2) works identically on Windows,
        macOS, and Linux and is the primary supported path. The 'Thumbprint'
        parameter set depends on a Windows certificate store and is provided
        only for environments where one already exists.

        If the chosen CBA path throws for any reason (module missing,
        certificate not found or expired, Connect-MgGraph itself throws),
        this function emits an explicit Write-Warning naming the fallback and
        connects interactively instead, requesting the exact scopes from
        Get-RequiredGraphPermission -- never relying on previously cached
        consent.
    .PARAMETER TenantId
        The Entra ID tenant ID (GUID or verified domain).
    .PARAMETER ClientId
        The app registration's application (client) ID.
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
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [string] $TenantId,

        [Parameter(Mandatory)]
        [string] $ClientId,

        [Parameter(Mandatory, ParameterSetName = 'Thumbprint')]
        [string] $CertificateThumbprint,

        [Parameter(Mandatory, ParameterSetName = 'CertificateFile')]
        [string] $CertificatePath,

        [Parameter(Mandatory, ParameterSetName = 'CertificateFile')]
        [securestring] $CertificatePassword
    )

    $cbaSucceeded = $false

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

    if (-not $cbaSucceeded) {
        Connect-MgGraph -TenantId $TenantId -Scopes (Get-RequiredGraphPermission) -ErrorAction Stop
        Write-Verbose "Connected via interactive delegated auth (TenantId=$TenantId)."
    }

    return Get-MgContext
}
