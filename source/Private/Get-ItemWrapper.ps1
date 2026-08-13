# Wraps Get-Item for Pester mocking.
function Get-ItemWrapper {
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [string]$LiteralPath
    )

    return Get-Item -LiteralPath $LiteralPath
}
