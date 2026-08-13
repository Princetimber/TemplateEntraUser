#Requires -Version 7.0
BeforeAll {
    $script:dscModuleName = 'Copy-EntraUser'
    Import-Module -Name $script:dscModuleName -Force
}

AfterAll {
    Get-Module -Name $script:dscModuleName -All | Remove-Module -Force
}

Describe 'Add-EntraGroupMembership' {
    BeforeAll {
        Mock Write-ToLog { } -ModuleName $script:dscModuleName
    }

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

        It 'Queries members with a targeted id filter rather than enumerating the whole group' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-MgGroupMember { @() }
                Mock New-MgGroupMemberByRef { }

                Add-EntraGroupMembership -GroupId '11111111-1111-1111-1111-111111111111' `
                    -NewUserId '00000000-0000-0000-0000-000000000004' -Confirm:$false

                Should -Invoke Get-MgGroupMember -Times 1 -ParameterFilter {
                    $Filter -eq "id eq '00000000-0000-0000-0000-000000000004'" -and $ConsistencyLevel -eq 'eventual'
                }
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

    Context 'Get-MgGroupMember throws' {
        It 'Rethrows an actionable error' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-MgGroupMember { throw 'Simulated Graph failure' }

                { Add-EntraGroupMembership -GroupId '11111111-1111-1111-1111-111111111111' `
                        -NewUserId '00000000-0000-0000-0000-000000000004' -Confirm:$false } |
                    Should -Throw '*11111111-1111-1111-1111-111111111111*'
            }
        }
    }
}
