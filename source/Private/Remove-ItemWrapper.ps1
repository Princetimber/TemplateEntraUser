# Wraps Remove-Item for Pester mocking.
function Remove-ItemWrapper {
    [CmdletBinding()]
    [OutputType([void])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Wrapper function; ShouldProcess handled by calling function.')]
    param(
        [Parameter(Mandatory)]
        [string]$LiteralPath
    )

    Remove-Item -LiteralPath $LiteralPath -Force -ErrorAction Stop
}
