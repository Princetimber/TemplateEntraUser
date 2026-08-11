#Requires -Version 7.0
BeforeAll {
    Import-Module Microsoft.Graph.Authentication -Force
    $script:dscModuleName = 'Copy-EntraUser'
    Import-Module -Name $script:dscModuleName -Force
}

AfterAll {
    Get-Module -Name $script:dscModuleName -All | Remove-Module -Force
}

Describe 'Connect-EntraGraphSession' {
    Context 'CBA succeeds via portable certificate file' {
        It 'Connects with -Certificate and does not fall back' {
            # Generate a real, loadable self-signed PFX so the portable
            # X509Certificate2(path, password) constructor succeeds without
            # depending on any certificate store.
            $certPath = Join-Path $TestDrive 'placeholder.pfx'
            $securePassword = ConvertTo-SecureString -String 'placeholder' -AsPlainText -Force
            $selfSignedCert = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
                'CN=CopyEntraUserTest',
                [System.Security.Cryptography.RSA]::Create(2048),
                [System.Security.Cryptography.HashAlgorithmName]::SHA256,
                [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
            ).CreateSelfSigned([datetimeoffset]::UtcNow.AddDays(-1), [datetimeoffset]::UtcNow.AddDays(1))
            [System.IO.File]::WriteAllBytes(
                $certPath,
                $selfSignedCert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx, 'placeholder')
            )

            InModuleScope -ModuleName $script:dscModuleName -Parameters @{ certPath = $certPath; securePassword = $securePassword } {
                param([string] $certPath, [securestring] $securePassword)

                Mock Connect-MgGraph { }
                Mock Get-MgContext { [pscustomobject]@{ AuthType = 'AppOnly' } }

                Connect-EntraGraphSession -TenantId '00000000-0000-0000-0000-000000000000' `
                    -ClientId '00000000-0000-0000-0000-000000000001' `
                    -CertificatePath $certPath `
                    -CertificatePassword $securePassword `
                    -ErrorAction SilentlyContinue

                Should -Invoke Connect-MgGraph -Times 1 -ParameterFilter { $null -ne $Certificate }
            }
        }
    }

    Context 'CBA fails, falls back to interactive with a warning' {
        It 'Warns explicitly and calls Connect-MgGraph -Scopes with the shared permission list' {
            InModuleScope -ModuleName $script:dscModuleName {
                $script:capturedScopes = $null
                Mock Connect-MgGraph {
                    param($CertificateThumbprint, $Scopes)

                    if ($CertificateThumbprint) {
                        throw 'certificate not found'
                    }
                    if ($Scopes) {
                        $script:capturedScopes = $Scopes
                    }
                }
                Mock Get-MgContext { [pscustomobject]@{ AuthType = 'Delegated' } }

                $warnings = @()
                Connect-EntraGraphSession -TenantId '00000000-0000-0000-0000-000000000000' `
                    -ClientId '00000000-0000-0000-0000-000000000001' `
                    -CertificateThumbprint 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' `
                    -WarningVariable warnings -WarningAction SilentlyContinue

                $warnings.Message -join ' ' | Should -Match 'fallback|interactive'
                Should -Invoke Connect-MgGraph -Times 1 -ParameterFilter { $null -ne $Scopes }
                Compare-Object $script:capturedScopes (Get-RequiredGraphPermission) | Should -BeNullOrEmpty
            }
        }
    }

    Context '-WhatIf prevents any live connection' {
        It 'Calls neither the CBA attempt nor the interactive fallback' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Connect-MgGraph { }
                Mock Get-MgContext { [pscustomobject]@{ AuthType = 'None' } }

                Connect-EntraGraphSession -TenantId '00000000-0000-0000-0000-000000000000' `
                    -ClientId '00000000-0000-0000-0000-000000000001' `
                    -CertificateThumbprint 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' `
                    -WhatIf

                Should -Invoke Connect-MgGraph -Times 0
            }
        }
    }

    Context 'No certificate supplied at all' {
        It 'Skips the CBA attempt entirely and connects interactively on the first attempt' {
            InModuleScope -ModuleName $script:dscModuleName {
                $script:capturedScopes = $null
                Mock Connect-MgGraph {
                    param($Scopes)
                    if ($Scopes) { $script:capturedScopes = $Scopes }
                }
                Mock Get-MgContext { [pscustomobject]@{ AuthType = 'Delegated' } }

                Connect-EntraGraphSession

                Should -Invoke Connect-MgGraph -Times 1
                Should -Invoke Connect-MgGraph -Times 0 -ParameterFilter { $null -ne $Certificate -or $null -ne $CertificateThumbprint }
                Compare-Object $script:capturedScopes (Get-RequiredGraphPermission) | Should -BeNullOrEmpty
            }
        }

        It 'Passes TenantId/ClientId through to the interactive call only when supplied' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Connect-MgGraph { }
                Mock Get-MgContext { [pscustomobject]@{ AuthType = 'Delegated' } }

                Connect-EntraGraphSession -TenantId '00000000-0000-0000-0000-000000000000'

                Should -Invoke Connect-MgGraph -Times 1 -ParameterFilter {
                    $TenantId -eq '00000000-0000-0000-0000-000000000000' -and $null -eq $ClientId
                }
            }
        }

        It 'Does not warn about a fallback, since no CBA attempt was ever made' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Connect-MgGraph { }
                Mock Get-MgContext { [pscustomobject]@{ AuthType = 'Delegated' } }

                $warnings = @()
                Connect-EntraGraphSession -WarningVariable warnings -WarningAction SilentlyContinue

                $warnings | Should -BeNullOrEmpty
            }
        }
    }

    Context 'Certificate parameters supplied but TenantId/ClientId missing' {
        It 'Throws an actionable error before attempting to connect' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Connect-MgGraph { }

                { Connect-EntraGraphSession -CertificateThumbprint 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' } |
                    Should -Throw '*TenantId*ClientId*'
                Should -Invoke Connect-MgGraph -Times 0
            }
        }
    }
}
