#Requires -Version 7.0
BeforeAll {
    . (Join-Path $PSScriptRoot '../../../source/Private/Test-RequiredGraphModule.ps1')
}

Describe 'Test-RequiredGraphModule' {
    Context 'All required modules present' {
        BeforeAll {
            Mock Get-Module {
                [pscustomobject]@{ Name = $Name; Version = [version]'2.25.0' }
            } -ParameterFilter { $ListAvailable }
        }

        It 'Does not throw' {
            { Test-RequiredGraphModule } | Should -Not -Throw
        }
    }

    Context 'A required module is missing' {
        BeforeAll {
            Mock Get-Module {
                if ($Name -eq 'Microsoft.Graph.Identity.Governance') { return $null }
                [pscustomobject]@{ Name = $Name; Version = [version]'2.25.0' }
            } -ParameterFilter { $ListAvailable }
        }

        It 'Throws naming the exact missing module' {
            { Test-RequiredGraphModule } | Should -Throw '*Microsoft.Graph.Identity.Governance*'
        }
    }
}
