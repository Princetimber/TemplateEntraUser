#Requires -Version 7.0
BeforeAll {
    $script:dscModuleName = 'Copy-EntraUser'
    Import-Module -Name $script:dscModuleName -Force

    InModuleScope -ModuleName $script:dscModuleName {
        # Placeholder GUIDs only — never real tenant data.
        $script:plainGroup = [pscustomobject]@{
            Id = '11111111-1111-1111-1111-111111111111'; DisplayName = 'Plain Group'
            GroupTypes = @(); AdditionalProperties = @{ isAssignableToRole = $false }
        }
        $script:pimGroup = [pscustomobject]@{
            Id = '22222222-2222-2222-2222-222222222222'; DisplayName = 'PIM Group'
            GroupTypes = @(); AdditionalProperties = @{ isAssignableToRole = $false }
        }
        $script:dynamicGroup = [pscustomobject]@{
            Id = '33333333-3333-3333-3333-333333333333'; DisplayName = 'Dynamic Group'
            GroupTypes = @('DynamicMembership'); AdditionalProperties = @{ isAssignableToRole = $false }
        }
        $script:roleAssignableGroup = [pscustomobject]@{
            Id = '44444444-4444-4444-4444-444444444444'; DisplayName = 'Role-Assignable Group'
            GroupTypes = @(); AdditionalProperties = @{ isAssignableToRole = $true }
        }
        $script:eligibilityInstance = [pscustomobject]@{
            GroupId = '22222222-2222-2222-2222-222222222222'; AccessId = 'member'
        }
    }
}

AfterAll {
    Get-Module -Name $script:dscModuleName -All | Remove-Module -Force
}

Describe 'Split-EntraGroupMembership' {
    It 'Never places the same group in both PlainGroup and PimGroup (overlap is resolved to PIM)' {
        InModuleScope -ModuleName $script:dscModuleName {
            $result = Split-EntraGroupMembership `
                -DirectGroup @($script:plainGroup, $script:pimGroup) `
                -EligibilitySchedule @($script:eligibilityInstance)

            $result.PlainGroup.Id | Should -Not -Contain $script:pimGroup.Id
            $result.PimGroup.Id | Should -Contain $script:pimGroup.Id
            $result.PlainGroup.Id | Should -Contain $script:plainGroup.Id
        }
    }

    It 'Carries the AccessId (member/owner) onto the PimGroup entry' {
        InModuleScope -ModuleName $script:dscModuleName {
            $result = Split-EntraGroupMembership `
                -DirectGroup @($script:pimGroup) `
                -EligibilitySchedule @($script:eligibilityInstance)

            ($result.PimGroup | Where-Object Id -eq $script:pimGroup.Id).AccessId | Should -Be 'member'
        }
    }

    It 'Routes dynamic-membership groups to UnsupportedGroup, not PlainGroup' {
        InModuleScope -ModuleName $script:dscModuleName {
            $result = Split-EntraGroupMembership -DirectGroup @($script:dynamicGroup) -EligibilitySchedule @()
            $result.UnsupportedGroup.Id | Should -Contain $script:dynamicGroup.Id
            $result.PlainGroup.Id | Should -Not -Contain $script:dynamicGroup.Id
        }
    }

    It 'Routes role-assignable groups to UnsupportedGroup, not PlainGroup' {
        InModuleScope -ModuleName $script:dscModuleName {
            $result = Split-EntraGroupMembership -DirectGroup @($script:roleAssignableGroup) -EligibilitySchedule @()
            $result.UnsupportedGroup.Id | Should -Contain $script:roleAssignableGroup.Id
            $result.PlainGroup.Id | Should -Not -Contain $script:roleAssignableGroup.Id
        }
    }

    It 'Handles empty input without error' {
        InModuleScope -ModuleName $script:dscModuleName {
            $result = Split-EntraGroupMembership -DirectGroup @() -EligibilitySchedule @()
            $result.PlainGroup | Should -BeNullOrEmpty
            $result.PimGroup | Should -BeNullOrEmpty
            $result.UnsupportedGroup | Should -BeNullOrEmpty
        }
    }
}
