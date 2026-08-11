#Requires -Version 7.0
BeforeAll {
    $script:dscModuleName = 'Copy-EntraUser'
    Import-Module -Name $script:dscModuleName -Force

    InModuleScope -ModuleName $script:dscModuleName {
        # Placeholder GUIDs only — never real tenant data. Shaped after the
        # real Microsoft.Graph.PowerShell.Models group type: IsAssignableToRole
        # is a TYPED top-level property, not a synthetic AdditionalProperties
        # entry — the SDK actually returns it that way by default.
        $script:plainGroup = [pscustomobject]@{
            Id = '11111111-1111-1111-1111-111111111111'; DisplayName = 'Plain Group'
            GroupTypes = @(); IsAssignableToRole = $false
        }
        $script:pimGroup = [pscustomobject]@{
            Id = '22222222-2222-2222-2222-222222222222'; DisplayName = 'PIM Group (also a direct member)'
            GroupTypes = @(); IsAssignableToRole = $false
        }
        $script:eligibilityOnlyGroup = [pscustomobject]@{
            Id = '55555555-5555-5555-5555-555555555555'; DisplayName = 'Eligible-Only Group (not a direct member)'
            GroupTypes = @(); IsAssignableToRole = $false
        }
        $script:dynamicGroup = [pscustomobject]@{
            Id = '33333333-3333-3333-3333-333333333333'; DisplayName = 'Dynamic Group'
            GroupTypes = @('DynamicMembership'); IsAssignableToRole = $false
        }
        $script:roleAssignableGroup = [pscustomobject]@{
            Id = '44444444-4444-4444-4444-444444444444'; DisplayName = 'Role-Assignable Group'
            GroupTypes = @(); IsAssignableToRole = $true
        }
        $script:pimEligibilityInstance = [pscustomobject]@{
            GroupId = '22222222-2222-2222-2222-222222222222'; AccessId = 'member'
        }
        $script:eligibilityOnlyInstance = [pscustomobject]@{
            GroupId = '55555555-5555-5555-5555-555555555555'; AccessId = 'owner'
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
                -EligibilitySchedule @($script:pimEligibilityInstance)

            $result.PlainGroup.Id | Should -Not -Contain $script:pimGroup.Id
            $result.PimGroup.Id | Should -Contain $script:pimGroup.Id
            $result.PlainGroup.Id | Should -Contain $script:plainGroup.Id
        }
    }

    It 'Carries the AccessId (member/owner) onto the PimGroup entry' {
        InModuleScope -ModuleName $script:dscModuleName {
            $result = Split-EntraGroupMembership `
                -DirectGroup @($script:pimGroup) `
                -EligibilitySchedule @($script:pimEligibilityInstance)

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

    It 'Routes role-assignable groups (typed IsAssignableToRole property) to UnsupportedGroup, not PlainGroup' {
        InModuleScope -ModuleName $script:dscModuleName {
            $result = Split-EntraGroupMembership -DirectGroup @($script:roleAssignableGroup) -EligibilitySchedule @()
            $result.UnsupportedGroup.Id | Should -Contain $script:roleAssignableGroup.Id
            $result.PlainGroup.Id | Should -Not -Contain $script:roleAssignableGroup.Id
        }
    }

    It 'Falls back to AdditionalProperties when IsAssignableToRole is not a typed property' {
        InModuleScope -ModuleName $script:dscModuleName {
            $legacyShapeGroup = [pscustomobject]@{
                Id = '77777777-7777-7777-7777-777777777777'; DisplayName = 'Legacy Shape Group'
                GroupTypes = @(); AdditionalProperties = @{ isAssignableToRole = $true }
            }
            $result = Split-EntraGroupMembership -DirectGroup @($legacyShapeGroup) -EligibilitySchedule @()
            $result.UnsupportedGroup.Id | Should -Contain $legacyShapeGroup.Id
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

    Context 'C1: eligibility-only groups (absent from DirectGroup)' {
        It 'Routes an eligibility-only group (present in EligibilityOnlyGroup, absent from DirectGroup) to PimGroup' {
            InModuleScope -ModuleName $script:dscModuleName {
                $result = Split-EntraGroupMembership `
                    -DirectGroup @($script:plainGroup) `
                    -EligibilityOnlyGroup @($script:eligibilityOnlyGroup) `
                    -EligibilitySchedule @($script:eligibilityOnlyInstance)

                $result.PimGroup.Id | Should -Contain $script:eligibilityOnlyGroup.Id
                $result.PlainGroup.Id | Should -Not -Contain $script:eligibilityOnlyGroup.Id
            }
        }

        It 'Carries the AccessId onto an eligibility-only PimGroup entry' {
            InModuleScope -ModuleName $script:dscModuleName {
                $result = Split-EntraGroupMembership `
                    -DirectGroup @() `
                    -EligibilityOnlyGroup @($script:eligibilityOnlyGroup) `
                    -EligibilitySchedule @($script:eligibilityOnlyInstance)

                ($result.PimGroup | Where-Object Id -eq $script:eligibilityOnlyGroup.Id).AccessId | Should -Be 'owner'
            }
        }

        It 'Exercises both a direct-member PIM group and an eligibility-only PIM group in the same call' {
            InModuleScope -ModuleName $script:dscModuleName {
                $result = Split-EntraGroupMembership `
                    -DirectGroup @($script:plainGroup, $script:pimGroup) `
                    -EligibilityOnlyGroup @($script:eligibilityOnlyGroup) `
                    -EligibilitySchedule @($script:pimEligibilityInstance, $script:eligibilityOnlyInstance)

                $result.PimGroup.Id | Should -Contain $script:pimGroup.Id
                $result.PimGroup.Id | Should -Contain $script:eligibilityOnlyGroup.Id
                $result.PlainGroup.Id | Should -Contain $script:plainGroup.Id
                $result.PlainGroup.Count | Should -Be 1
            }
        }

        It 'Does not duplicate a group present in both DirectGroup and EligibilityOnlyGroup' {
            InModuleScope -ModuleName $script:dscModuleName {
                $result = Split-EntraGroupMembership `
                    -DirectGroup @($script:pimGroup) `
                    -EligibilityOnlyGroup @($script:pimGroup) `
                    -EligibilitySchedule @($script:pimEligibilityInstance)

                @($result.PimGroup | Where-Object Id -eq $script:pimGroup.Id).Count | Should -Be 1
            }
        }
    }

    Context 'M6: does not mutate the caller-supplied group object' {
        It 'Leaves the original DirectGroup object without an AccessId property' {
            InModuleScope -ModuleName $script:dscModuleName {
                $original = [pscustomobject]@{
                    Id = '88888888-8888-8888-8888-888888888888'; DisplayName = 'Immutability Check Group'
                    GroupTypes = @(); IsAssignableToRole = $false
                }
                $instance = [pscustomobject]@{ GroupId = $original.Id; AccessId = 'member' }

                Split-EntraGroupMembership -DirectGroup @($original) -EligibilitySchedule @($instance) | Out-Null

                ($original.PSObject.Properties.Name -contains 'AccessId') | Should -BeFalse
            }
        }
    }
}
