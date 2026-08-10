#Requires -Version 7.0
BeforeAll {
    $script:dscModuleName = 'Copy-EntraUser'
    . (Join-Path $PSScriptRoot '../../../source/Private/Get-RequiredGraphPermission.ps1')
}

Describe 'Get-RequiredGraphPermission' {
    It 'Returns the exact three least-privilege permission strings, once each' {
        $result = Get-RequiredGraphPermission
        $result | Should -HaveCount 3
        $result | Should -Contain 'User.ReadWrite.All'
        $result | Should -Contain 'GroupMember.ReadWrite.All'
        $result | Should -Contain 'PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup'
    }

    It 'Returns a [string[]] typed result' {
        (Get-RequiredGraphPermission) -is [array] | Should -BeTrue
        (Get-RequiredGraphPermission)[0] | Should -BeOfType [string]
    }
}
