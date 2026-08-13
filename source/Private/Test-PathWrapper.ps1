# Wraps Test-Path for Pester mocking.
function Test-PathWrapper {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [string]
        $Path,

        [Parameter(Mandatory, ParameterSetName = 'LiteralPath')]
        [string]
        $LiteralPath,

        [Parameter(ParameterSetName = 'Path')]
        [ValidateSet('Any', 'Container', 'Leaf')]
        [string]
        $PathType
    )

    if ($PSCmdlet.ParameterSetName -eq 'LiteralPath') {
        return Test-Path -LiteralPath $LiteralPath
    }

    if ($PathType) {
        return Test-Path -Path $Path -PathType $PathType
    }

    return Test-Path -Path $Path
}
