#Requires -Version 7.0
BeforeAll {
    . (Join-Path $PSScriptRoot '../../../source/Private/Add-EntraGroupMembership.ps1')
}

Describe 'Add-EntraGroupMembership' {
    Context 'User is not yet a member' {
        BeforeAll {
            Mock Get-MgGroupMember { @() }
            Mock New-MgGroupMemberByRef { }
        }

        It 'Adds the member' {
            Add-EntraGroupMembership -GroupId '11111111-1111-1111-1111-111111111111' `
                -NewUserId '00000000-0000-0000-0000-000000000004' -Confirm:$false
            Should -Invoke New-MgGroupMemberByRef -Times 1
        }
    }

    Context 'User is already a member (idempotent re-run)' {
        BeforeAll {
            Mock Get-MgGroupMember { @([pscustomobject]@{ Id = '00000000-0000-0000-0000-000000000004' }) }
            Mock New-MgGroupMemberByRef { }
        }

        It 'Does not call New-MgGroupMemberByRef again' {
            Add-EntraGroupMembership -GroupId '11111111-1111-1111-1111-111111111111' `
                -NewUserId '00000000-0000-0000-0000-000000000004' -Confirm:$false
            Should -Invoke New-MgGroupMemberByRef -Times 0
        }
    }

    Context '-WhatIf is passed' {
        BeforeAll {
            Mock Get-MgGroupMember { @() }
            Mock New-MgGroupMemberByRef { }
        }

        It 'Does not call New-MgGroupMemberByRef' {
            Add-EntraGroupMembership -GroupId '11111111-1111-1111-1111-111111111111' `
                -NewUserId '00000000-0000-0000-0000-000000000004' -WhatIf
            Should -Invoke New-MgGroupMemberByRef -Times 0
        }
    }
}
