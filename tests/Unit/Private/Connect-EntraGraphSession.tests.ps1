#Requires -Version 7.0
BeforeAll {
    Import-Module Microsoft.Graph.Authentication -Force
    . (Join-Path $PSScriptRoot '../../../source/Private/Get-RequiredGraphPermission.ps1')
    . (Join-Path $PSScriptRoot '../../../source/Private/Connect-EntraGraphSession.ps1')
}

Describe 'Connect-EntraGraphSession' {
    Context 'CBA succeeds via portable certificate file' {
        BeforeAll {
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

            Mock Connect-MgGraph { }
            Mock Get-MgContext { [pscustomobject]@{ AuthType = 'AppOnly' } }
        }

        It 'Connects with -Certificate and does not fall back' {
            Connect-EntraGraphSession -TenantId '00000000-0000-0000-0000-000000000000' `
                -ClientId '00000000-0000-0000-0000-000000000001' `
                -CertificatePath $certPath `
                -CertificatePassword $securePassword `
                -ErrorAction SilentlyContinue

            Should -Invoke Connect-MgGraph -Times 1 -ParameterFilter { $null -ne $Certificate }
        }
    }

    Context 'CBA fails, falls back to interactive with a warning' {
        BeforeAll {
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
        }

        It 'Warns explicitly and calls Connect-MgGraph -Scopes with the shared permission list' {
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
