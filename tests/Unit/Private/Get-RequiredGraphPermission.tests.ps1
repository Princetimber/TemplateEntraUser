#Requires -Version 7.0
BeforeAll {
    $script:dscModuleName = 'Copy-EntraUser'
    Import-Module -Name $script:dscModuleName -Force
}

AfterAll {
    Get-Module -Name $script:dscModuleName -All | Remove-Module -Force
}

Describe 'Get-RequiredGraphPermission' {
    It 'Returns the exact six least-privilege permission strings, once each' {
        InModuleScope -ModuleName $script:dscModuleName {
            $result = Get-RequiredGraphPermission
            $result | Should -HaveCount 6
            $result | Should -Contain 'User.ReadWrite.All'
            $result | Should -Contain 'GroupMember.ReadWrite.All'
            $result | Should -Contain 'PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup'
            $result | Should -Contain 'RoleEligibilitySchedule.ReadWrite.Directory'
            $result | Should -Contain 'RoleAssignmentSchedule.Read.Directory'
            $result | Should -Contain 'RoleManagement.Read.Directory'
        }
    }

    It 'Returns a [string[]] typed result' {
        InModuleScope -ModuleName $script:dscModuleName {
            (Get-RequiredGraphPermission) -is [array] | Should -BeTrue
            (Get-RequiredGraphPermission)[0] | Should -BeOfType [string]
        }
    }
}
