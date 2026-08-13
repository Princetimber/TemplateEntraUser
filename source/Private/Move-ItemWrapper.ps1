# Wraps Move-Item for Pester mocking.
function Move-ItemWrapper {
    [CmdletBinding()]
    [OutputType([void])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Wrapper function; ShouldProcess handled by calling function.')]
    param(
        [Parameter(Mandatory)]
        [string]$LiteralPath,

        [Parameter(Mandatory)]
        [string]$Destination
    )

    Move-Item -LiteralPath $LiteralPath -Destination $Destination -Force -ErrorAction Stop
}
