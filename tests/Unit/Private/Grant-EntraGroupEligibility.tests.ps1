#Requires -Version 7.0
BeforeAll {
    $script:dscModuleName = 'Copy-EntraUser'
    Import-Module -Name $script:dscModuleName -Force
}

AfterAll {
    Get-Module -Name $script:dscModuleName -All | Remove-Module -Force
}

Describe 'Grant-EntraGroupEligibility' {
    BeforeAll {
        Mock Write-ToLog { } -ModuleName $script:dscModuleName
    }

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

    Context 'startDateTime uses UTC' {
        It 'Passes a UTC startDateTime rather than local time' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-MgIdentityGovernancePrivilegedAccessGroupEligibilityScheduleInstance { @() }
                Mock New-MgIdentityGovernancePrivilegedAccessGroupEligibilityScheduleRequest { }

                Grant-EntraGroupEligibility -GroupId '22222222-2222-2222-2222-222222222222' `
                    -NewUserId '00000000-0000-0000-0000-000000000004' -AccessId 'member' -Confirm:$false

                Should -Invoke New-MgIdentityGovernancePrivilegedAccessGroupEligibilityScheduleRequest -Times 1 -ParameterFilter {
                    $BodyParameter.scheduleInfo.startDateTime.Kind -eq [System.DateTimeKind]::Utc
                }
            }
        }
    }

    Context 'Get-Mg* read fails' {
        It 'Rethrows an actionable error' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-MgIdentityGovernancePrivilegedAccessGroupEligibilityScheduleInstance { throw 'Simulated Graph failure' }

                { Grant-EntraGroupEligibility -GroupId '22222222-2222-2222-2222-222222222222' `
                        -NewUserId '00000000-0000-0000-0000-000000000004' -AccessId 'member' -Confirm:$false } |
                    Should -Throw '*22222222-2222-2222-2222-222222222222*'
            }
        }
    }
}
