#Requires -Version 7.0
BeforeAll {
    $script:dscModuleName = 'Copy-EntraUser'
    Import-Module -Name $script:dscModuleName -Force
}

AfterAll {
    Get-Module -Name $script:dscModuleName -All | Remove-Module -Force
}

Describe 'Test-RequiredGraphModule' {
    Context 'All required modules present' {
        It 'Does not throw' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-Module {
                    [pscustomobject]@{ Name = $Name; Version = [version]'2.25.0' }
                } -ParameterFilter { $ListAvailable }

                { Test-RequiredGraphModule } | Should -Not -Throw
            }
        }
    }

    Context 'A required module is missing' {
        It 'Throws naming the exact missing module' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-Module {
                    if ($Name -eq 'Microsoft.Graph.Identity.Governance') { return $null }
                    [pscustomobject]@{ Name = $Name; Version = [version]'2.25.0' }
                } -ParameterFilter { $ListAvailable }

                { Test-RequiredGraphModule } | Should -Throw '*Microsoft.Graph.Identity.Governance*'
            }
        }
    }
}
