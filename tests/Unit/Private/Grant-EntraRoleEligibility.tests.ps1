BeforeAll {
    $script:dscModuleName = 'Copy-EntraUser'
    Import-Module -Name $script:dscModuleName -Force
}

AfterAll {
    Get-Module -Name $script:dscModuleName -All | Remove-Module -Force
}

Describe 'Grant-EntraRoleEligibility' {
    Context 'No existing eligibility schedule instance' {
        It 'Creates a new eligibility request with action AdminAssign and no expiration' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance { @() }
                Mock New-MgRoleManagementDirectoryRoleEligibilityScheduleRequest { }

                Grant-EntraRoleEligibility -RoleDefinitionId '66666666-6666-6666-6666-666666666666' `
                    -NewUserId '00000000-0000-0000-0000-000000000004' -Confirm:$false

                Should -Invoke New-MgRoleManagementDirectoryRoleEligibilityScheduleRequest -Times 1 -ParameterFilter {
                    $BodyParameter.action -eq 'AdminAssign' -and
                    $BodyParameter.roleDefinitionId -eq '66666666-6666-6666-6666-666666666666' -and
                    $BodyParameter.principalId -eq '00000000-0000-0000-0000-000000000004' -and
                    $BodyParameter.directoryScopeId -eq '/' -and
                    $BodyParameter.scheduleInfo.expiration.type -eq 'NoExpiration'
                }
            }
        }

        It 'Passes a non-tenant-wide DirectoryScopeId through unchanged' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance { @() }
                Mock New-MgRoleManagementDirectoryRoleEligibilityScheduleRequest { }

                Grant-EntraRoleEligibility -RoleDefinitionId '66666666-6666-6666-6666-666666666666' `
                    -NewUserId '00000000-0000-0000-0000-000000000004' -DirectoryScopeId '/' -Confirm:$false

                Should -Invoke New-MgRoleManagementDirectoryRoleEligibilityScheduleRequest -Times 1 -ParameterFilter {
                    $BodyParameter.directoryScopeId -eq '/'
                }
            }
        }
    }

    Context 'An eligibility schedule instance already exists (idempotent re-run)' {
        It 'Does not create a duplicate request' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance {
                    @([pscustomobject]@{
                            RoleDefinitionId = '66666666-6666-6666-6666-666666666666'
                            PrincipalId      = '00000000-0000-0000-0000-000000000004'
                            DirectoryScopeId = '/'
                        })
                }
                Mock New-MgRoleManagementDirectoryRoleEligibilityScheduleRequest { }

                Grant-EntraRoleEligibility -RoleDefinitionId '66666666-6666-6666-6666-666666666666' `
                    -NewUserId '00000000-0000-0000-0000-000000000004' -Confirm:$false

                Should -Invoke New-MgRoleManagementDirectoryRoleEligibilityScheduleRequest -Times 0
            }
        }
    }

    Context '-WhatIf support' {
        It 'Does not call New-MgRoleManagementDirectoryRoleEligibilityScheduleRequest under -WhatIf' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance { @() }
                Mock New-MgRoleManagementDirectoryRoleEligibilityScheduleRequest { }

                Grant-EntraRoleEligibility -RoleDefinitionId '66666666-6666-6666-6666-666666666666' `
                    -NewUserId '00000000-0000-0000-0000-000000000004' -WhatIf

                Should -Invoke New-MgRoleManagementDirectoryRoleEligibilityScheduleRequest -Times 0
            }
        }
    }
}
