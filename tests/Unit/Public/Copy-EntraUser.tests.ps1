#Requires -Version 7.0
BeforeAll {
    $script:dscModuleName = 'Copy-EntraUser'
    Import-Module -Name $script:dscModuleName -Force
}

AfterAll {
    Get-Module -Name $script:dscModuleName -All | Remove-Module -Force
}

Describe 'Copy-EntraUser' {
    BeforeAll {
        Mock Test-RequiredGraphModule { } -ModuleName $script:dscModuleName
        Mock Connect-EntraGraphSession { [pscustomobject]@{ AuthType = 'AppOnly' } } -ModuleName $script:dscModuleName
        Mock Resolve-EntraTemplateUser { [pscustomobject]@{ Id = '00000000-0000-0000-0000-000000000002' } } -ModuleName $script:dscModuleName
        Mock Resolve-EntraNewUser { [pscustomobject]@{ Id = '00000000-0000-0000-0000-000000000004' } } -ModuleName $script:dscModuleName
        Mock Get-EntraTemplateGroupMembership {
            @{
                DirectGroup = @([pscustomobject]@{
                        Id = '11111111-1111-1111-1111-111111111111'; GroupTypes = @()
                        IsAssignableToRole = $false
                    })
                EligibilityOnlyGroup = @()
                EligibilitySchedule = @()
            }
        } -ModuleName $script:dscModuleName
        Mock Add-EntraGroupMembership { } -ModuleName $script:dscModuleName
        Mock Grant-EntraGroupEligibility { } -ModuleName $script:dscModuleName
        Mock Disconnect-MgGraph { } -ModuleName $script:dscModuleName
    }

    It 'Requires -TemplateUserId and -NewUser; TenantId/ClientId are optional (interactive mode needs neither)' {
        (Get-Command Copy-EntraUser).Parameters['TemplateUserId'].Attributes.Mandatory | Should -Contain $true
        (Get-Command Copy-EntraUser).Parameters['NewUser'].Attributes.Mandatory | Should -Contain $true
        (Get-Command Copy-EntraUser).Parameters['TenantId'].Attributes.Mandatory | Should -Not -Contain $true
        (Get-Command Copy-EntraUser).Parameters['ClientId'].Attributes.Mandatory | Should -Not -Contain $true
    }

    It 'CertificateThumbprint and CertificatePath are mutually exclusive parameter sets' {
        { Copy-EntraUser -TemplateUserId 'a@contoso.onmicrosoft.com' -NewUser 'b@contoso.onmicrosoft.com' `
                -TenantId '00000000-0000-0000-0000-000000000000' -ClientId '00000000-0000-0000-0000-000000000001' `
                -CertificateThumbprint 'AAAA' -CertificatePath 'x.pfx' `
                -CertificatePassword (ConvertTo-SecureString 'x' -AsPlainText -Force) -Confirm:$false
        } | Should -Throw
    }

    It 'Adds the new user to the plain group' {
        Copy-EntraUser -TemplateUserId 'a@contoso.onmicrosoft.com' -NewUser 'b@contoso.onmicrosoft.com' `
            -TenantId '00000000-0000-0000-0000-000000000000' -ClientId '00000000-0000-0000-0000-000000000001' `
            -CertificatePath 'x.pfx' -CertificatePassword (ConvertTo-SecureString 'x' -AsPlainText -Force) -Confirm:$false
        Should -Invoke Add-EntraGroupMembership -Times 1 -ModuleName $script:dscModuleName
        Should -Invoke Grant-EntraGroupEligibility -Times 0 -ModuleName $script:dscModuleName
    }

    It 'Running twice performs the same read-then-skip mutation pattern (no unconditional double-create)' {
        1..2 | ForEach-Object {
            Copy-EntraUser -TemplateUserId 'a@contoso.onmicrosoft.com' -NewUser 'b@contoso.onmicrosoft.com' `
                -TenantId '00000000-0000-0000-0000-000000000000' -ClientId '00000000-0000-0000-0000-000000000001' `
                -CertificatePath 'x.pfx' -CertificatePassword (ConvertTo-SecureString 'x' -AsPlainText -Force) -Confirm:$false
        }
        # Add-EntraGroupMembership itself owns the read-before-write idempotency check (Task 9's own
        # tests already prove that); here we assert the orchestrator calls it once per run either way,
        # i.e. it never skips calling the (idempotent) helper.
        Should -Invoke Add-EntraGroupMembership -Times 2 -ModuleName $script:dscModuleName
    }

    It 'Supports -WhatIf without connecting or mutating' {
        Copy-EntraUser -TemplateUserId 'a@contoso.onmicrosoft.com' -NewUser 'b@contoso.onmicrosoft.com' `
            -TenantId '00000000-0000-0000-0000-000000000000' -ClientId '00000000-0000-0000-0000-000000000001' `
            -CertificatePath 'x.pfx' -CertificatePassword (ConvertTo-SecureString 'x' -AsPlainText -Force) -WhatIf
        Should -Invoke Add-EntraGroupMembership -Times 0 -ModuleName $script:dscModuleName
    }

    Context 'C1: eligibility-only groups are still cloned end-to-end' {
        BeforeAll {
            # This group is ONLY reachable via EligibilityOnlyGroup -- it is
            # deliberately absent from DirectGroup -- exercising the union
            # logic across the real Get-EntraTemplateGroupMembership/
            # Split-EntraGroupMembership call sites in Copy-EntraUser itself.
            Mock Get-EntraTemplateGroupMembership {
                @{
                    DirectGroup = @()
                    EligibilityOnlyGroup = @([pscustomobject]@{
                            Id = '55555555-5555-5555-5555-555555555555'; DisplayName = 'Eligible-Only Group'
                            GroupTypes = @(); IsAssignableToRole = $false
                        })
                    EligibilitySchedule = @([pscustomobject]@{
                            GroupId = '55555555-5555-5555-5555-555555555555'; AccessId = 'owner'
                        })
                }
            } -ModuleName $script:dscModuleName
        }

        It 'Grants PIM-for-Groups eligibility for a group the template user is only eligible for, never a direct member of' {
            Copy-EntraUser -TemplateUserId 'a@contoso.onmicrosoft.com' -NewUser 'b@contoso.onmicrosoft.com' `
                -TenantId '00000000-0000-0000-0000-000000000000' -ClientId '00000000-0000-0000-0000-000000000001' `
                -CertificatePath 'x.pfx' -CertificatePassword (ConvertTo-SecureString 'x' -AsPlainText -Force) -Confirm:$false
            Should -Invoke Grant-EntraGroupEligibility -Times 1 -ModuleName $script:dscModuleName -ParameterFilter {
                $GroupId -eq '55555555-5555-5555-5555-555555555555' -and $AccessId -eq 'owner'
            }
            Should -Invoke Add-EntraGroupMembership -Times 0 -ModuleName $script:dscModuleName
        }
    }

    Context 'No credentials supplied at all: connects interactively from the start' {
        It 'Calls Connect-EntraGraphSession with no certificate/tenant/client parameters' {
            Copy-EntraUser -TemplateUserId 'a@contoso.onmicrosoft.com' -NewUser 'b@contoso.onmicrosoft.com' -Confirm:$false

            Should -Invoke Connect-EntraGraphSession -Times 1 -ModuleName $script:dscModuleName -ParameterFilter {
                $null -eq $TenantId -and $null -eq $ClientId -and
                $null -eq $CertificateThumbprint -and $null -eq $CertificatePath
            }
        }

        It 'Still clones the plain group membership end-to-end with zero credentials supplied' {
            Copy-EntraUser -TemplateUserId 'a@contoso.onmicrosoft.com' -NewUser 'b@contoso.onmicrosoft.com' -Confirm:$false
            Should -Invoke Add-EntraGroupMembership -Times 1 -ModuleName $script:dscModuleName
        }
    }

    It 'Passes only the supplied TenantId through when no certificate/ClientId is given' {
        Copy-EntraUser -TemplateUserId 'a@contoso.onmicrosoft.com' -NewUser 'b@contoso.onmicrosoft.com' `
            -TenantId '00000000-0000-0000-0000-000000000000' -Confirm:$false

        Should -Invoke Connect-EntraGraphSession -Times 1 -ModuleName $script:dscModuleName -ParameterFilter {
            $TenantId -eq '00000000-0000-0000-0000-000000000000' -and $null -eq $ClientId
        }
    }

    It 'Forwards -CertificateThumbprint (and only the thumbprint, never a certificate path) to Connect-EntraGraphSession' {
        Copy-EntraUser -TemplateUserId 'a@contoso.onmicrosoft.com' -NewUser 'b@contoso.onmicrosoft.com' `
            -TenantId '00000000-0000-0000-0000-000000000000' -ClientId '00000000-0000-0000-0000-000000000001' `
            -CertificateThumbprint 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' -Confirm:$false

        Should -Invoke Connect-EntraGraphSession -Times 1 -ModuleName $script:dscModuleName -ParameterFilter {
            $CertificateThumbprint -eq 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' -and $null -eq $CertificatePath
        }
    }

    Context 'M7: delegated session is disconnected even when a mutation throws' {
        It 'Still calls Disconnect-MgGraph when Add-EntraGroupMembership throws' {
            Mock Connect-EntraGraphSession { [pscustomobject]@{ AuthType = 'Delegated' } } -ModuleName $script:dscModuleName
            Mock Add-EntraGroupMembership { throw 'Simulated Graph failure' } -ModuleName $script:dscModuleName

            {
                Copy-EntraUser -TemplateUserId 'a@contoso.onmicrosoft.com' -NewUser 'b@contoso.onmicrosoft.com' `
                    -TenantId '00000000-0000-0000-0000-000000000000' -ClientId '00000000-0000-0000-0000-000000000001' `
                    -CertificatePath 'x.pfx' -CertificatePassword (ConvertTo-SecureString 'x' -AsPlainText -Force) -Confirm:$false
            } | Should -Throw 'Simulated Graph failure'

            Should -Invoke Disconnect-MgGraph -Times 1 -ModuleName $script:dscModuleName
        }
    }
}
