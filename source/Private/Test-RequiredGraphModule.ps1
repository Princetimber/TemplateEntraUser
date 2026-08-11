function Test-RequiredGraphModule {
    <#
    .SYNOPSIS
        Verifies the specific Microsoft.Graph.* sub-modules Copy-EntraUser
        depends on are installed at a compatible version, before any Graph
        call is attempted.
    .DESCRIPTION
        Fails fast with an actionable error naming exactly which module and
        minimum version is missing. Never installs a module automatically —
        installing modules is itself a side effect requiring operator consent.
    .OUTPUTS
        None. Throws a terminating error on the first missing/under-versioned
        module.
    .EXAMPLE
        Test-RequiredGraphModule
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    $requiredModule = [ordered]@{
        'Microsoft.Graph.Authentication'      = [version]'2.25.0'
        'Microsoft.Graph.Users'                = [version]'2.25.0'
        'Microsoft.Graph.Groups'                = [version]'2.25.0'
        'Microsoft.Graph.Identity.Governance'   = [version]'2.25.0'
    }

    foreach ($moduleName in $requiredModule.Keys) {
        $installed = Get-Module -Name $moduleName -ListAvailable |
            Sort-Object Version -Descending |
            Select-Object -First 1

        if (-not $installed -or $installed.Version -lt $requiredModule[$moduleName]) {
            throw "Required module '$moduleName' (minimum version $($requiredModule[$moduleName])) is not installed. Install it with: Install-Module -Name $moduleName -MinimumVersion $($requiredModule[$moduleName]) -Scope CurrentUser"
        }
    }
}