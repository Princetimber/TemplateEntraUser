#Requires -Version 7.0
BeforeAll {
    $script:dscModuleName = 'Copy-EntraUser'
    Import-Module -Name $script:dscModuleName -Force
}

AfterAll {
    Get-Module -Name $script:dscModuleName -All | Remove-Module -Force
}

Describe 'New-EntraUserPassword' {
    It 'Returns a SecureString' {
        InModuleScope -ModuleName $script:dscModuleName {
            New-EntraUserPassword | Should -BeOfType [securestring]
        }
    }

    It 'Defaults to a 16-character password drawn only from the documented character set' {
        InModuleScope -ModuleName $script:dscModuleName {
            $securePassword = New-EntraUserPassword
            $plainText = [System.Net.NetworkCredential]::new('', $securePassword).Password

            $plainText.Length | Should -Be 16
            $plainText | Should -Match '^[0-9A-Za-z!#$%]+$'
        }
    }

    It 'Honors -Length' {
        InModuleScope -ModuleName $script:dscModuleName {
            $securePassword = New-EntraUserPassword -Length 24
            $plainText = [System.Net.NetworkCredential]::new('', $securePassword).Password

            $plainText.Length | Should -Be 24
        }
    }

    It 'Never generates the same password twice in a row (CSPRNG sanity check)' {
        InModuleScope -ModuleName $script:dscModuleName {
            $first = [System.Net.NetworkCredential]::new('', (New-EntraUserPassword)).Password
            $second = [System.Net.NetworkCredential]::new('', (New-EntraUserPassword)).Password

            $first | Should -Not -Be $second
        }
    }

    It 'Rejects a length below the minimum' {
        InModuleScope -ModuleName $script:dscModuleName {
            { New-EntraUserPassword -Length 4 } | Should -Throw
        }
    }
}
