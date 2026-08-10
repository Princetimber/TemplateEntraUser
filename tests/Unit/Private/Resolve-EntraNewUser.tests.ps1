#Requires -Version 7.0
BeforeAll {
    Import-Module Microsoft.Graph.Users -Force
    . (Join-Path $PSScriptRoot '../../../source/Private/Resolve-EntraNewUser.ps1')
}

Describe 'Resolve-EntraNewUser' {
    Context 'Existing user supplied as a string identifier' {
        BeforeAll {
            Mock Get-MgUser { [pscustomobject]@{ Id = '00000000-0000-0000-0000-000000000003' } }
        }

        It 'Resolves via Get-MgUser and never calls New-MgUser' {
            Mock New-MgUser { }
            $result = Resolve-EntraNewUser -NewUser 'new.user@contoso.onmicrosoft.com'
            $result.Id | Should -Be '00000000-0000-0000-0000-000000000003'
            Should -Invoke New-MgUser -Times 0
        }
    }

    Context 'Hashtable supplied, missing a required key' {
        It 'Throws naming the missing key' {
            $incomplete = @{ DisplayName = 'New Hire'; UserPrincipalName = 'new.hire@contoso.onmicrosoft.com' }
            { Resolve-EntraNewUser -NewUser $incomplete } | Should -Throw '*MailNickname*'
        }
    }

    Context 'Hashtable supplied, user does not already exist (first run)' {
        BeforeAll {
            Mock Get-MgUser { $null } -ParameterFilter { $Filter }
            Mock New-MgUser { [pscustomobject]@{ Id = '00000000-0000-0000-0000-000000000004' } }
        }

        It 'Creates the user via New-MgUser' {
            $newUser = @{
                DisplayName = 'New Hire'; UserPrincipalName = 'new.hire@contoso.onmicrosoft.com'
                MailNickname = 'new.hire'; PasswordProfile = @{ Password = 'placeholder' }
                AccountEnabled = $true
            }
            $result = Resolve-EntraNewUser -NewUser $newUser -Confirm:$false
            $result.Id | Should -Be '00000000-0000-0000-0000-000000000004'
            Should -Invoke New-MgUser -Times 1
        }
    }

    Context 'Hashtable supplied, user already exists (idempotent re-run)' {
        BeforeAll {
            Mock Get-MgUser { [pscustomobject]@{ Id = '00000000-0000-0000-0000-000000000004' } } -ParameterFilter { $Filter }
            Mock New-MgUser { }
        }

        It 'Does not call New-MgUser again' {
            $newUser = @{
                DisplayName = 'New Hire'; UserPrincipalName = 'new.hire@contoso.onmicrosoft.com'
                MailNickname = 'new.hire'; PasswordProfile = @{ Password = 'placeholder' }
                AccountEnabled = $true
            }
            Resolve-EntraNewUser -NewUser $newUser -Confirm:$false
            Should -Invoke New-MgUser -Times 0
        }
    }
}
