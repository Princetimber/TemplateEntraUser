BeforeAll {
    $script:dscModuleName = 'Copy-EntraUser'
    Import-Module -Name $script:dscModuleName -Force

    InModuleScope -ModuleName $script:dscModuleName {
        $script:tenantWideEligibility = [pscustomobject]@{
            RoleDefinitionId = '66666666-6666-6666-6666-666666666666'
            DirectoryScopeId = '/'
            MemberType       = 'Direct'
        }
        $script:auScopedEligibility = [pscustomobject]@{
            RoleDefinitionId = '77777777-7777-7777-7777-777777777777'
            DirectoryScopeId = '/administrativeUnits/88888888-8888-8888-8888-888888888888'
            MemberType       = 'Direct'
        }
        $script:groupInheritedEligibility = [pscustomobject]@{
            RoleDefinitionId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
            DirectoryScopeId = '/'
            MemberType       = 'Group'
        }
        $script:permanentAssignment = [pscustomobject]@{
            RoleDefinitionId = '99999999-9999-9999-9999-999999999999'
            DirectoryScopeId = '/'
            MemberType       = 'Direct'
            AssignmentType   = 'Assigned'
        }
        $script:activatedAssignment = [pscustomobject]@{
            RoleDefinitionId = '66666666-6666-6666-6666-666666666666'
            DirectoryScopeId = '/'
            MemberType       = 'Direct'
            AssignmentType   = 'Activated'
        }
        $script:inheritedAssignment = [pscustomobject]@{
            RoleDefinitionId = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
            DirectoryScopeId = '/'
            MemberType       = 'Inherited'
            AssignmentType   = 'Assigned'
        }
        $script:roleDefinitionById = @{
            '66666666-6666-6666-6666-666666666666' = 'Helpdesk Administrator'
            '77777777-7777-7777-7777-777777777777' = 'User Administrator'
            '99999999-9999-9999-9999-999999999999' = 'Global Reader'
        }
    }
}

AfterAll {
    Get-Module -Name $script:dscModuleName -All | Remove-Module -Force
}

Describe 'Split-EntraRoleAssignment' {
    It 'Routes a Direct, tenant-wide eligibility instance to PimRole' {
        InModuleScope -ModuleName $script:dscModuleName {
            $result = Split-EntraRoleAssignment -EligibilitySchedule @($script:tenantWideEligibility) `
                -ActiveAssignmentSchedule @() -RoleDefinitionById $script:roleDefinitionById

            $result.PimRole.RoleDefinitionId | Should -Contain $script:tenantWideEligibility.RoleDefinitionId
            $result.UnsupportedRole | Should -BeNullOrEmpty
        }
    }

    It 'Carries the resolved DisplayName onto the PimRole entry' {
        InModuleScope -ModuleName $script:dscModuleName {
            $result = Split-EntraRoleAssignment -EligibilitySchedule @($script:tenantWideEligibility) `
                -ActiveAssignmentSchedule @() -RoleDefinitionById $script:roleDefinitionById

            ($result.PimRole | Where-Object RoleDefinitionId -eq $script:tenantWideEligibility.RoleDefinitionId).DisplayName |
                Should -Be 'Helpdesk Administrator'
        }
    }

    It 'Routes an Administrative Unit-scoped eligibility instance to UnsupportedRole, not PimRole' {
        InModuleScope -ModuleName $script:dscModuleName {
            $result = Split-EntraRoleAssignment -EligibilitySchedule @($script:auScopedEligibility) `
                -ActiveAssignmentSchedule @() -RoleDefinitionById $script:roleDefinitionById

            $result.UnsupportedRole.RoleDefinitionId | Should -Contain $script:auScopedEligibility.RoleDefinitionId
            $result.PimRole | Should -BeNullOrEmpty
            ($result.UnsupportedRole | Where-Object RoleDefinitionId -eq $script:auScopedEligibility.RoleDefinitionId).Reason |
                Should -Match 'Administrative Unit'
        }
    }

    It 'Drops a Group-memberType eligibility instance silently (not PimRole, not UnsupportedRole)' {
        InModuleScope -ModuleName $script:dscModuleName {
            $result = Split-EntraRoleAssignment -EligibilitySchedule @($script:groupInheritedEligibility) `
                -ActiveAssignmentSchedule @() -RoleDefinitionById $script:roleDefinitionById

            $result.PimRole | Should -BeNullOrEmpty
            $result.UnsupportedRole | Should -BeNullOrEmpty
        }
    }

    It 'Routes a permanent (Assigned) active assignment with no matching eligibility to UnsupportedRole' {
        InModuleScope -ModuleName $script:dscModuleName {
            $result = Split-EntraRoleAssignment -EligibilitySchedule @() `
                -ActiveAssignmentSchedule @($script:permanentAssignment) -RoleDefinitionById $script:roleDefinitionById

            $result.UnsupportedRole.RoleDefinitionId | Should -Contain $script:permanentAssignment.RoleDefinitionId
            ($result.UnsupportedRole | Where-Object RoleDefinitionId -eq $script:permanentAssignment.RoleDefinitionId).Reason |
                Should -Match 'non-PIM'
        }
    }

    It 'Ignores an Activated active assignment that is already covered by its eligibility instance (no double-report)' {
        InModuleScope -ModuleName $script:dscModuleName {
            $result = Split-EntraRoleAssignment -EligibilitySchedule @($script:tenantWideEligibility) `
                -ActiveAssignmentSchedule @($script:activatedAssignment) -RoleDefinitionById $script:roleDefinitionById

            @($result.PimRole | Where-Object RoleDefinitionId -eq $script:tenantWideEligibility.RoleDefinitionId).Count | Should -Be 1
            $result.UnsupportedRole | Should -BeNullOrEmpty
        }
    }

    It 'Drops an Inherited-memberType active assignment silently' {
        InModuleScope -ModuleName $script:dscModuleName {
            $result = Split-EntraRoleAssignment -EligibilitySchedule @() `
                -ActiveAssignmentSchedule @($script:inheritedAssignment) -RoleDefinitionById $script:roleDefinitionById

            $result.PimRole | Should -BeNullOrEmpty
            $result.UnsupportedRole | Should -BeNullOrEmpty
        }
    }

    It 'Handles empty input without error and defaults RoleDefinitionById' {
        InModuleScope -ModuleName $script:dscModuleName {
            $result = Split-EntraRoleAssignment -EligibilitySchedule @() -ActiveAssignmentSchedule @()

            $result.PimRole | Should -BeNullOrEmpty
            $result.UnsupportedRole | Should -BeNullOrEmpty
        }
    }
}
