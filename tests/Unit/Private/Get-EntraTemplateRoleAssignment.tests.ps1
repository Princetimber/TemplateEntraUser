BeforeAll {
    $script:dscModuleName = 'Copy-EntraUser'
    Import-Module -Name $script:dscModuleName -Force
}

AfterAll {
    Get-Module -Name $script:dscModuleName -All | Remove-Module -Force
}

Describe 'Get-EntraTemplateRoleAssignment' {
    It 'Returns eligibility schedule instances, active assignment instances, and a role definition lookup' {
        InModuleScope -ModuleName $script:dscModuleName {
            Mock Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance {
                @([pscustomobject]@{
                        RoleDefinitionId = '66666666-6666-6666-6666-666666666666'
                        DirectoryScopeId = '/'
                        MemberType       = 'Direct'
                    })
            }
            Mock Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance {
                @([pscustomobject]@{
                        RoleDefinitionId = '99999999-9999-9999-9999-999999999999'
                        DirectoryScopeId = '/'
                        MemberType       = 'Direct'
                        AssignmentType   = 'Assigned'
                    })
            }
            Mock Get-MgRoleManagementDirectoryRoleDefinition {
                param($UnifiedRoleDefinitionId)
                [pscustomobject]@{ Id = $UnifiedRoleDefinitionId; DisplayName = "Role-$UnifiedRoleDefinitionId" }
            }

            $result = Get-EntraTemplateRoleAssignment -TemplateUserId '00000000-0000-0000-0000-000000000002'

            $result.EligibilitySchedule[0].RoleDefinitionId | Should -Be '66666666-6666-6666-6666-666666666666'
            $result.ActiveAssignmentSchedule[0].RoleDefinitionId | Should -Be '99999999-9999-9999-9999-999999999999'
            $result.RoleDefinitionById['66666666-6666-6666-6666-666666666666'] | Should -Be 'Role-66666666-6666-6666-6666-666666666666'
            $result.RoleDefinitionById['99999999-9999-9999-9999-999999999999'] | Should -Be 'Role-99999999-9999-9999-9999-999999999999'
        }
    }

    It 'Filters both list queries by the template user principal ID' {
        InModuleScope -ModuleName $script:dscModuleName {
            Mock Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance { @() }
            Mock Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance { @() }
            Mock Get-MgRoleManagementDirectoryRoleDefinition { $null }

            Get-EntraTemplateRoleAssignment -TemplateUserId '00000000-0000-0000-0000-000000000002' | Out-Null

            Should -Invoke Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance -Times 1 -ParameterFilter {
                $Filter -eq "principalId eq '00000000-0000-0000-0000-000000000002'"
            }
            Should -Invoke Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance -Times 1 -ParameterFilter {
                $Filter -eq "principalId eq '00000000-0000-0000-0000-000000000002'"
            }
        }
    }

    It 'Resolves each distinct RoleDefinitionId only once across both collections' {
        InModuleScope -ModuleName $script:dscModuleName {
            Mock Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance {
                @([pscustomobject]@{ RoleDefinitionId = '66666666-6666-6666-6666-666666666666'; DirectoryScopeId = '/'; MemberType = 'Direct' })
            }
            Mock Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance {
                @([pscustomobject]@{ RoleDefinitionId = '66666666-6666-6666-6666-666666666666'; DirectoryScopeId = '/'; MemberType = 'Direct'; AssignmentType = 'Activated' })
            }
            Mock Get-MgRoleManagementDirectoryRoleDefinition {
                [pscustomobject]@{ Id = '66666666-6666-6666-6666-666666666666'; DisplayName = 'Helpdesk Administrator' }
            }

            Get-EntraTemplateRoleAssignment -TemplateUserId '00000000-0000-0000-0000-000000000002' | Out-Null

            Should -Invoke Get-MgRoleManagementDirectoryRoleDefinition -Times 1
        }
    }

    It 'Warns and omits the entry when a role definition cannot be resolved' {
        InModuleScope -ModuleName $script:dscModuleName {
            Mock Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance {
                @([pscustomobject]@{ RoleDefinitionId = '66666666-6666-6666-6666-666666666666'; DirectoryScopeId = '/'; MemberType = 'Direct' })
            }
            Mock Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance { @() }
            Mock Get-MgRoleManagementDirectoryRoleDefinition { $null }

            $result = Get-EntraTemplateRoleAssignment -TemplateUserId '00000000-0000-0000-0000-000000000002' `
                -WarningVariable warnings -WarningAction SilentlyContinue

            $result.RoleDefinitionById.ContainsKey('66666666-6666-6666-6666-666666666666') | Should -BeFalse
            $warnings | Should -Not -BeNullOrEmpty
        }
    }

    It 'Returns empty arrays and an empty lookup when the template user has no role data at all' {
        InModuleScope -ModuleName $script:dscModuleName {
            Mock Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance { @() }
            Mock Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance { @() }
            Mock Get-MgRoleManagementDirectoryRoleDefinition { throw 'Should not be called when there is no role data.' }

            $result = Get-EntraTemplateRoleAssignment -TemplateUserId '00000000-0000-0000-0000-000000000002'

            $result.EligibilitySchedule | Should -BeNullOrEmpty
            $result.ActiveAssignmentSchedule | Should -BeNullOrEmpty
            $result.RoleDefinitionById.Count | Should -Be 0
        }
    }
}
