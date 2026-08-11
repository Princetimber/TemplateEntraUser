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
            Mock Get-MgGroup {
                [pscustomobject]@{ Id = '22222222-2222-2222-2222-222222222222'; DisplayName = 'Eligible-Only Group' }
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
            Mock Get-MgGroup {
                [pscustomobject]@{ Id = '22222222-2222-2222-2222-222222222222'; DisplayName = 'Eligible-Only Group' }
            }

            Get-EntraTemplateGroupMembership -TemplateUserId '00000000-0000-0000-0000-000000000002' | Out-Null
            Should -Invoke Get-MgIdentityGovernancePrivilegedAccessGroupEligibilityScheduleInstance -Times 1 -ParameterFilter {
                $Filter -eq "principalId eq '00000000-0000-0000-0000-000000000002'"
            }
        }
    }

    Context 'C1: resolving eligibility-only groups' {
        It 'Resolves a group via Get-MgGroup when its GroupId is in EligibilitySchedule but absent from DirectGroup' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-MgUserMemberOfAsGroup {
                    @([pscustomobject]@{ Id = '11111111-1111-1111-1111-111111111111'; DisplayName = 'Plain Group' })
                }
                Mock Get-MgIdentityGovernancePrivilegedAccessGroupEligibilityScheduleInstance {
                    @([pscustomobject]@{ GroupId = '55555555-5555-5555-5555-555555555555'; AccessId = 'owner' })
                }
                Mock Get-MgGroup {
                    [pscustomobject]@{ Id = '55555555-5555-5555-5555-555555555555'; DisplayName = 'Eligible-Only Group' }
                }

                $result = Get-EntraTemplateGroupMembership -TemplateUserId '00000000-0000-0000-0000-000000000002'

                $result.EligibilityOnlyGroup.Id | Should -Contain '55555555-5555-5555-5555-555555555555'
                Should -Invoke Get-MgGroup -Times 1 -ParameterFilter { $GroupId -eq '55555555-5555-5555-5555-555555555555' }
            }
        }

        It 'Does not resolve a group already present in DirectGroup (no redundant Get-MgGroup call)' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-MgUserMemberOfAsGroup {
                    @([pscustomobject]@{ Id = '22222222-2222-2222-2222-222222222222'; DisplayName = 'PIM Group (also direct member)' })
                }
                Mock Get-MgIdentityGovernancePrivilegedAccessGroupEligibilityScheduleInstance {
                    @([pscustomobject]@{ GroupId = '22222222-2222-2222-2222-222222222222'; AccessId = 'member' })
                }
                Mock Get-MgGroup { throw 'Get-MgGroup should not be called for a group already present in DirectGroup.' }

                $result = Get-EntraTemplateGroupMembership -TemplateUserId '00000000-0000-0000-0000-000000000002'

                $result.EligibilityOnlyGroup | Should -BeNullOrEmpty
                Should -Invoke Get-MgGroup -Times 0
            }
        }

        It 'Resolves each distinct eligibility-only GroupId only once' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-MgUserMemberOfAsGroup { @() }
                Mock Get-MgIdentityGovernancePrivilegedAccessGroupEligibilityScheduleInstance {
                    @(
                        [pscustomobject]@{ GroupId = '55555555-5555-5555-5555-555555555555'; AccessId = 'member' },
                        [pscustomobject]@{ GroupId = '55555555-5555-5555-5555-555555555555'; AccessId = 'owner' }
                    )
                }
                Mock Get-MgGroup {
                    [pscustomobject]@{ Id = '55555555-5555-5555-5555-555555555555'; DisplayName = 'Eligible-Only Group' }
                }

                Get-EntraTemplateGroupMembership -TemplateUserId '00000000-0000-0000-0000-000000000002' | Out-Null

                Should -Invoke Get-MgGroup -Times 1
            }
        }

        It 'Warns and excludes the group when Get-MgGroup cannot resolve an eligibility-only GroupId' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-MgUserMemberOfAsGroup { @() }
                Mock Get-MgIdentityGovernancePrivilegedAccessGroupEligibilityScheduleInstance {
                    @([pscustomobject]@{ GroupId = '99999999-9999-9999-9999-999999999999'; AccessId = 'member' })
                }
                Mock Get-MgGroup { $null }

                $result = Get-EntraTemplateGroupMembership -TemplateUserId '00000000-0000-0000-0000-000000000002' -WarningVariable warnings -WarningAction SilentlyContinue
                $result.EligibilityOnlyGroup | Should -BeNullOrEmpty
                $warnings | Should -Not -BeNullOrEmpty
            }
        }

        It 'Returns an empty EligibilityOnlyGroup array when every eligibility GroupId is already a direct member' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-MgUserMemberOfAsGroup { @() }
                Mock Get-MgIdentityGovernancePrivilegedAccessGroupEligibilityScheduleInstance { @() }
                Mock Get-MgGroup { throw 'Get-MgGroup should not be called when there is no eligibility schedule.' }

                $result = Get-EntraTemplateGroupMembership -TemplateUserId '00000000-0000-0000-0000-000000000002'
                $result.EligibilityOnlyGroup | Should -BeNullOrEmpty
                Should -Invoke Get-MgGroup -Times 0
            }
        }
    }
}
