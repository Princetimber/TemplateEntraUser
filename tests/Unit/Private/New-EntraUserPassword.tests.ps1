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

    It 'Always includes at least one character from each required class (uppercase, lowercase, digit, symbol)' {
        InModuleScope -ModuleName $script:dscModuleName {
            1..25 | ForEach-Object {
                $plainText = [System.Net.NetworkCredential]::new('', (New-EntraUserPassword)).Password
                $plainText | Should -Match '[A-Z]'
                $plainText | Should -Match '[a-z]'
                $plainText | Should -Match '[0-9]'
                $plainText | Should -Match '[!#$%]'
            }
        }
    }

    It 'Rejects a length below the minimum' {
        InModuleScope -ModuleName $script:dscModuleName {
            { New-EntraUserPassword -Length 4 } | Should -Throw
        }
    }

    It 'Is not gated behind ShouldProcess -- always generates a real password unconditionally' {
        # A pure, side-effect-free generator must never be able to return $null
        # via a declined confirmation prompt. Regression test for a bug where
        # SupportsShouldProcess on this function let an operator answering "No"
        # to a confusing "Generate random password?" prompt cause Copy-EntraUser
        # to silently build an empty-string password and pass it to New-MgUser.
        InModuleScope -ModuleName $script:dscModuleName {
            (Get-Command New-EntraUserPassword).Parameters.Keys | Should -Not -Contain 'WhatIf'
            (Get-Command New-EntraUserPassword).Parameters.Keys | Should -Not -Contain 'Confirm'
            New-EntraUserPassword | Should -Not -BeNullOrEmpty
        }
    }
}
