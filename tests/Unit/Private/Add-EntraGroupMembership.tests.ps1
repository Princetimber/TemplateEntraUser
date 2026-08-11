#Requires -Version 7.0
BeforeAll {
    $script:dscModuleName = 'Copy-EntraUser'
    Import-Module -Name $script:dscModuleName -Force
}

AfterAll {
    Get-Module -Name $script:dscModuleName -All | Remove-Module -Force
}

Describe 'Add-EntraGroupMembership' {
    Context 'User is not yet a member' {
        It 'Adds the member' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-MgGroupMember { @() }
                Mock New-MgGroupMemberByRef { }

                Add-EntraGroupMembership -GroupId '11111111-1111-1111-1111-111111111111' `
                    -NewUserId '00000000-0000-0000-0000-000000000004' -Confirm:$false
                Should -Invoke New-MgGroupMemberByRef -Times 1
            }
        }
    }

    Context 'User is already a member (idempotent re-run)' {
        It 'Does not call New-MgGroupMemberByRef again' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-MgGroupMember { @([pscustomobject]@{ Id = '00000000-0000-0000-0000-000000000004' }) }
                Mock New-MgGroupMemberByRef { }

                Add-EntraGroupMembership -GroupId '11111111-1111-1111-1111-111111111111' `
                    -NewUserId '00000000-0000-0000-0000-000000000004' -Confirm:$false
                Should -Invoke New-MgGroupMemberByRef -Times 0
            }
        }
    }

    Context '-WhatIf is passed' {
        It 'Does not call New-MgGroupMemberByRef' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-MgGroupMember { @() }
                Mock New-MgGroupMemberByRef { }

                Add-EntraGroupMembership -GroupId '11111111-1111-1111-1111-111111111111' `
                    -NewUserId '00000000-0000-0000-0000-000000000004' -WhatIf
                Should -Invoke New-MgGroupMemberByRef -Times 0
            }
        }
    }
}
