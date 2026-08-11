#Requires -Version 7.0
BeforeAll {
    $script:dscModuleName = 'Copy-EntraUser'
    Import-Module -Name $script:dscModuleName -Force
}

AfterAll {
    Get-Module -Name $script:dscModuleName -All | Remove-Module -Force
}

Describe 'Grant-EntraGroupEligibility' {
    Context 'No existing eligibility schedule instance' {
        It 'Creates a new eligibility request with action AdminAssign' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-MgIdentityGovernancePrivilegedAccessGroupEligibilityScheduleInstance { @() }
                Mock New-MgIdentityGovernancePrivilegedAccessGroupEligibilityScheduleRequest { }

                Grant-EntraGroupEligibility -GroupId '22222222-2222-2222-2222-222222222222' `
                    -NewUserId '00000000-0000-0000-0000-000000000004' -AccessId 'member' -Confirm:$false

                Should -Invoke New-MgIdentityGovernancePrivilegedAccessGroupEligibilityScheduleRequest -Times 1 -ParameterFilter {
                    $BodyParameter.action -eq 'AdminAssign' -and $BodyParameter.accessId -eq 'member'
                }
            }
        }
    }

    Context 'An eligibility schedule instance already exists (idempotent re-run)' {
        It 'Does not create a duplicate request' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-MgIdentityGovernancePrivilegedAccessGroupEligibilityScheduleInstance {
                    @([pscustomobject]@{ GroupId = '22222222-2222-2222-2222-222222222222'; PrincipalId = '00000000-0000-0000-0000-000000000004' })
                }
                Mock New-MgIdentityGovernancePrivilegedAccessGroupEligibilityScheduleRequest { }

                Grant-EntraGroupEligibility -GroupId '22222222-2222-2222-2222-222222222222' `
                    -NewUserId '00000000-0000-0000-0000-000000000004' -AccessId 'member' -Confirm:$false
                Should -Invoke New-MgIdentityGovernancePrivilegedAccessGroupEligibilityScheduleRequest -Times 0
            }
        }
    }
}
