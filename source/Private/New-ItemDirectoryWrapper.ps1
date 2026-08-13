# Wraps New-Item -ItemType Directory for Pester mocking.
function New-ItemDirectoryWrapper {
    [CmdletBinding()]
    [OutputType([System.IO.DirectoryInfo])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Wrapper function; ShouldProcess handled by calling function.')]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    return New-Item -Path $Path -ItemType Directory -Force -ErrorAction Stop
}
