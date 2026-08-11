function New-EntraUserPassword {
    <#
    .SYNOPSIS
        Generates a cryptographically random password for a new Entra ID user.
    .DESCRIPTION
        Draws from a digits/upper/lower/symbol character set using
        [System.Security.Cryptography.RandomNumberGenerator]::GetInt32, a
        CSPRNG available cross-platform on .NET 6+/PowerShell 7+ -- never
        Get-Random, which is not cryptographically secure. Each character is
        appended directly to the SecureString via .AppendChar() so the full
        plaintext password is never materialized as a managed string --
        avoiding ConvertTo-SecureString -AsPlainText entirely. Returns the
        password as a SecureString; the caller is responsible for unwrapping
        it only where a Graph API call requires a plain string, and for
        never writing it to a Write-Verbose/Warning/Error stream.
    .PARAMETER Length
        The number of characters to generate. Defaults to 16.
    .OUTPUTS
        System.Security.SecureString
    .EXAMPLE
        New-EntraUserPassword
    .EXAMPLE
        New-EntraUserPassword -Length 24
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([securestring])]
    param(
        [Parameter()]
        [ValidateRange(8, 256)]
        [int] $Length = 16
    )

    if ($PSCmdlet.ShouldProcess('random password', 'Generate')) {
        $charSet = [char[]](48..57 + 65..90 + 97..122 + 33 + 35 + 36 + 37)
        $securePassword = [securestring]::new()
        1..$Length | ForEach-Object {
            $securePassword.AppendChar($charSet[[System.Security.Cryptography.RandomNumberGenerator]::GetInt32(0, $charSet.Length)])
        }
        $securePassword.MakeReadOnly()
        return $securePassword
    }
}
