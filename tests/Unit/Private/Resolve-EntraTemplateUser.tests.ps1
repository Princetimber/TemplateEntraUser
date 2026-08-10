#Requires -Version 7.0
BeforeAll {
    . (Join-Path $PSScriptRoot '../../../source/Private/Resolve-EntraTemplateUser.ps1')
}

Describe 'Resolve-EntraTemplateUser' {
    Context 'User exists' {
        BeforeAll {
            Mock Get-MgUser {
                [pscustomobject]@{ Id = '00000000-0000-0000-0000-000000000002'; UserPrincipalName = 'template.user@contoso.onmicrosoft.com' }
            }
        }

        It 'Returns the resolved user object' {
            $result = Resolve-EntraTemplateUser -UserId 'template.user@contoso.onmicrosoft.com'
            $result.UserPrincipalName | Should -Be 'template.user@contoso.onmicrosoft.com'
        }
    }

    Context 'User does not exist' {
        BeforeAll {
            Mock Get-MgUser { throw [Microsoft.Graph.PowerShell.Runtime.RestException]::new() } -ErrorAction Ignore
            Mock Get-MgUser { throw 'Request_ResourceNotFound' }
        }

        It 'Throws an actionable, named error' {
            { Resolve-EntraTemplateUser -UserId 'missing.user@contoso.onmicrosoft.com' } |
                Should -Throw '*missing.user@contoso.onmicrosoft.com*'
        }
    }
}
