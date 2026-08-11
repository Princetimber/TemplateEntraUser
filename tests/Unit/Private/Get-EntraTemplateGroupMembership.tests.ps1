#Requires -Version 7.0
BeforeAll {
    $script:dscModuleName = 'Copy-EntraUser'
    Import-Module -Name $script:dscModuleName -Force
}

AfterAll {
    Get-Module -Name $script:dscModuleName -All | Remove-Module -Force
}

Describe 'Get-EntraTemplateGroupMembership' {
    It 'Returns both direct memberships and eligibility schedule instances' {
        InModuleScope -ModuleName $script:dscModuleName {
            Mock Get-MgUserMemberOfAsGroup {
                @([pscustomobject]@{ Id = '11111111-1111-1111-1111-111111111111' })
            }
            Mock Get-MgIdentityGovernancePrivilegedAccessGroupEligibilityScheduleInstance {
                @([pscustomobject]@{ GroupId = '22222222-2222-2222-2222-222222222222'; AccessId = 'member' })
            }

            $result = Get-EntraTemplateGroupMembership -TemplateUserId '00000000-0000-0000-0000-000000000002'
            $result.DirectGroup[0].Id | Should -Be '11111111-1111-1111-1111-111111111111'
            $result.EligibilitySchedule[0].GroupId | Should -Be '22222222-2222-2222-2222-222222222222'
        }
    }

    It 'Filters the eligibility query by the template user principal ID' {
        InModuleScope -ModuleName $script:dscModuleName {
            Mock Get-MgUserMemberOfAsGroup {
                @([pscustomobject]@{ Id = '11111111-1111-1111-1111-111111111111' })
            }
            Mock Get-MgIdentityGovernancePrivilegedAccessGroupEligibilityScheduleInstance {
                @([pscustomobject]@{ GroupId = '22222222-2222-2222-2222-222222222222'; AccessId = 'member' })
            }

            Get-EntraTemplateGroupMembership -TemplateUserId '00000000-0000-0000-0000-000000000002' | Out-Null
            Should -Invoke Get-MgIdentityGovernancePrivilegedAccessGroupEligibilityScheduleInstance -Times 1 -ParameterFilter {
                $Filter -eq "principalId eq '00000000-0000-0000-0000-000000000002'"
            }
        }
    }
}
