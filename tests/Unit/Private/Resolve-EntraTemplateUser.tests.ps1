#Requires -Version 7.0
BeforeAll {
    $script:dscModuleName = 'Copy-EntraUser'
    Import-Module -Name $script:dscModuleName -Force
}

AfterAll {
    Get-Module -Name $script:dscModuleName -All | Remove-Module -Force
}

Describe 'Resolve-EntraTemplateUser' {
    Context 'User exists' {
        It 'Returns the resolved user object' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-MgUser {
                    [pscustomobject]@{ Id = '00000000-0000-0000-0000-000000000002'; UserPrincipalName = 'template.user@contoso.onmicrosoft.com' }
                }

                $result = Resolve-EntraTemplateUser -UserId 'template.user@contoso.onmicrosoft.com'
                $result.UserPrincipalName | Should -Be 'template.user@contoso.onmicrosoft.com'
            }
        }
    }

    Context 'User does not exist' {
        It 'Throws an actionable, named error' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-MgUser { throw [Microsoft.Graph.PowerShell.Runtime.RestException]::new() } -ErrorAction Ignore
                Mock Get-MgUser { throw 'Request_ResourceNotFound' }

                { Resolve-EntraTemplateUser -UserId 'missing.user@contoso.onmicrosoft.com' } |
                    Should -Throw '*missing.user@contoso.onmicrosoft.com*'
            }
        }
    }
}
