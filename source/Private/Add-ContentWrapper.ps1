# Wraps Add-Content for Pester mocking.
function Add-ContentWrapper {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Wrapper function; ShouldProcess handled by calling function.')]
    param(
        [Parameter(Mandatory)]
        [string]$LiteralPath,

        [Parameter(Mandatory)]
        [string]$Value
    )

    Add-Content -LiteralPath $LiteralPath -Value $Value -ErrorAction Stop
}
