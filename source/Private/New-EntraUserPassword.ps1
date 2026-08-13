# Generates a cryptographically random password for a new Entra ID user.
# Draws from a digits/upper/lower/symbol character set using
# [System.Security.Cryptography.RandomNumberGenerator]::GetInt32, a CSPRNG
# available cross-platform on .NET 6+/PowerShell 7+ -- never Get-Random,
# which is not cryptographically secure. Guarantees at least one character
# from each of the four classes (uppercase, lowercase, digit, symbol) by
# drawing one character from each class first, then fills the remaining
# length randomly from the combined character set, then Fisher-Yates
# shuffles the resulting array (using the same CSPRNG) so the guaranteed
# class characters are not always in the same leading positions. Each
# character is appended directly to the SecureString via .AppendChar() so
# the full plaintext password is never materialized as a managed string --
# avoiding ConvertTo-SecureString -AsPlainText entirely. Returns the
# password as a SecureString; the caller is responsible for unwrapping it
# only where a Graph API call requires a plain string, and for never
# writing it to a Write-Verbose/Warning/Error stream.
#
# Deliberately does NOT declare SupportsShouldProcess. This function has no
# external state to gate -- it only builds an in-memory value -- and gating
# it behind ShouldProcess previously let an operator running Copy-EntraUser
# with -Confirm decline a confusing "Generate random password?" prompt,
# causing this function to return $null and an empty-string password to
# silently reach the mutating New-MgUser call. A pure generator must always
# return a real value; the PSUseShouldProcessForStateChangingFunctions
# analyzer rule (which flags any New- verb regardless of whether it
# mutates external state) is suppressed below with that justification.
function New-EntraUserPassword {
    [CmdletBinding()]
    [OutputType([securestring])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure in-memory generator with no external state to gate; see .NOTES.'
    )]
    param(
        [Parameter()]
        [ValidateRange(8, 256)]
        [int] $Length = 16
    )

    $digitSet = [char[]](48..57)
    $upperSet = [char[]](65..90)
    $lowerSet = [char[]](97..122)
    $symbolSet = [char[]](33, 35, 36, 37)
    $charSet = $digitSet + $upperSet + $lowerSet + $symbolSet

    $passwordChar = [System.Collections.Generic.List[char]]::new()

    # Guarantee at least one character from each required class first.
    foreach ($classSet in @($upperSet, $lowerSet, $digitSet, $symbolSet)) {
        $passwordChar.Add($classSet[[System.Security.Cryptography.RandomNumberGenerator]::GetInt32(0, $classSet.Length)])
    }

    # Fill the remaining length randomly from the combined character set.
    for ($i = $passwordChar.Count; $i -lt $Length; $i++) {
        $passwordChar.Add($charSet[[System.Security.Cryptography.RandomNumberGenerator]::GetInt32(0, $charSet.Length)])
    }

    # Fisher-Yates shuffle (using the same CSPRNG) so the guaranteed
    # class characters are not always in the same leading positions.
    for ($i = $passwordChar.Count - 1; $i -gt 0; $i--) {
        $j = [System.Security.Cryptography.RandomNumberGenerator]::GetInt32(0, $i + 1)
        $temp = $passwordChar[$i]
        $passwordChar[$i] = $passwordChar[$j]
        $passwordChar[$j] = $temp
    }

    $securePassword = [securestring]::new()
    foreach ($char in $passwordChar) {
        $securePassword.AppendChar($char)
    }
    $securePassword.MakeReadOnly()
    return $securePassword
}
