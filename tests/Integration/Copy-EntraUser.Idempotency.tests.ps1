#Requires -Version 7.0

BeforeAll {
    $script:dscModuleName = 'Copy-EntraUser'
    Import-Module -Name $script:dscModuleName -Force
}

AfterAll {
    Get-Module -Name $script:dscModuleName -All | Remove-Module -Force
}

Describe 'Copy-EntraUser end-to-end idempotency' -Tag 'Integration' {
    BeforeAll {
        # Real private helpers, real orchestrator. Only the connection/resolution
        # steps and the Graph edges are mocked — never the private helpers
        # themselves — so this proves the FULL chain, not a composed assumption.
        Mock Test-RequiredGraphModule { } -ModuleName $script:dscModuleName
        Mock Connect-EntraGraphSession {
            [pscustomobject]@{ AuthType = 'AppOnly' }
        } -ModuleName $script:dscModuleName
        # Template user resolves to '...002'; the new user (a plain string,
        # so Resolve-EntraNewUser calls Get-MgUser -UserId) resolves to
        # '...004' -- the principal that is already fully provisioned below.
        Mock Get-MgUser {
            [pscustomobject]@{ Id = '00000000-0000-0000-0000-000000000002' }
        } -ModuleName $script:dscModuleName -ParameterFilter {
            $UserId -eq 'template.user@contoso.onmicrosoft.com'
        }
        Mock Get-MgUser {
            [pscustomobject]@{ Id = '00000000-0000-0000-0000-000000000004' }
        } -ModuleName $script:dscModuleName
        # Two direct memberships: a plain group (no matching eligibility
        # instance) and a group that ALSO has a PIM-for-Groups eligibility
        # instance (GroupId matches the eligibility mock below) — so
        # Split-EntraGroupMembership routes one to PlainGroup and the other
        # to PimGroup, exercising both the Add-EntraGroupMembership and the
        # Grant-EntraGroupEligibility idempotency paths in this single run.
        # A THIRD group is eligibility-only (GroupId '33333333-...' below) --
        # deliberately absent from this direct-membership mock -- so
        # Get-EntraTemplateGroupMembership's Get-MgGroup resolution and the
        # DirectGroup/EligibilityOnlyGroup union in Split-EntraGroupMembership
        # are exercised end-to-end, not just the "PIM group also happens to
        # be a direct member" shape.
        Mock Get-MgUserMemberOfAsGroup {
            @(
                [pscustomobject]@{
                    Id = '11111111-1111-1111-1111-111111111111'; DisplayName = 'Plain Group'
                    GroupTypes = @(); IsAssignableToRole = $false
                },
                [pscustomobject]@{
                    Id = '22222222-2222-2222-2222-222222222222'; DisplayName = 'PIM Group (also a direct member)'
                    GroupTypes = @(); IsAssignableToRole = $false
                }
            )
        } -ModuleName $script:dscModuleName
        # Get-EntraTemplateGroupMembership filters by principalId only (the
        # template user's own eligibility, used to build the PIM/plain
        # split); Grant-EntraGroupEligibility filters by principalId AND
        # groupId (the "does the target already have this exact grant"
        # idempotency check). Distinguish the two call sites on the
        # presence of 'groupId' in the -Filter string so each can be
        # exercised/falsified independently.
        Mock Get-MgIdentityGovernancePrivilegedAccessGroupEligibilityScheduleInstance {
            @(
                [pscustomobject]@{
                    GroupId = '22222222-2222-2222-2222-222222222222'
                    PrincipalId = '00000000-0000-0000-0000-000000000004'
                    AccessId = 'member'
                },
                [pscustomobject]@{
                    GroupId = '33333333-3333-3333-3333-333333333333'
                    PrincipalId = '00000000-0000-0000-0000-000000000004'
                    AccessId = 'owner'
                }
            )
        } -ModuleName $script:dscModuleName -ParameterFilter { $Filter -notmatch 'groupId' }
        # Already-fully-provisioned state: an eligibility instance already
        # exists for both exact principal/group pairs (the direct-member PIM
        # group and the eligibility-only PIM group).
        Mock Get-MgIdentityGovernancePrivilegedAccessGroupEligibilityScheduleInstance {
            @([pscustomobject]@{
                    GroupId = '22222222-2222-2222-2222-222222222222'
                    PrincipalId = '00000000-0000-0000-0000-000000000004'
                    AccessId = 'member'
                })
        } -ModuleName $script:dscModuleName -ParameterFilter { $Filter -match "groupId eq '22222222-2222-2222-2222-222222222222'" }
        Mock Get-MgIdentityGovernancePrivilegedAccessGroupEligibilityScheduleInstance {
            @([pscustomobject]@{
                    GroupId = '33333333-3333-3333-3333-333333333333'
                    PrincipalId = '00000000-0000-0000-0000-000000000004'
                    AccessId = 'owner'
                })
        } -ModuleName $script:dscModuleName -ParameterFilter { $Filter -match "groupId eq '33333333-3333-3333-3333-333333333333'" }
        # Resolves the eligibility-only group (GroupId '33333333-...') to an
        # actual group object -- this is the C1 union path.
        Mock Get-MgGroup {
            [pscustomobject]@{
                Id = '33333333-3333-3333-3333-333333333333'; DisplayName = 'Eligible-Only Group'
                GroupTypes = @(); IsAssignableToRole = $false
            }
        } -ModuleName $script:dscModuleName
        # Already-fully-provisioned state: the target is already a direct member.
        Mock Get-MgGroupMember {
            @([pscustomobject]@{ Id = '00000000-0000-0000-0000-000000000004' })
        } -ModuleName $script:dscModuleName
        Mock New-MgGroupMemberByRef {
            throw 'MUTATION SHOULD NEVER BE CALLED: New-MgGroupMemberByRef'
        } -ModuleName $script:dscModuleName
        Mock New-MgIdentityGovernancePrivilegedAccessGroupEligibilityScheduleRequest {
            throw 'MUTATION SHOULD NEVER BE CALLED: New-MgIdentityGovernancePrivilegedAccessGroupEligibilityScheduleRequest'
        } -ModuleName $script:dscModuleName
        Mock Disconnect-MgGraph { } -ModuleName $script:dscModuleName
        # No directory-role PIM eligibility/active assignments for this
        # scenario -- Get-EntraTemplateRoleAssignment now hard-fails (rather
        # than silently continuing) on an unmocked/unauthenticated Graph
        # call per its own error-handling contract, so these must be mocked
        # explicitly even though this scenario has nothing to exercise there.
        Mock Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance { @() } -ModuleName $script:dscModuleName
        Mock Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance { @() } -ModuleName $script:dscModuleName
        Mock Write-ToLog { } -ModuleName $script:dscModuleName
    }

    It 'Makes zero mutating Graph calls when the target user is already fully provisioned' {
        {
            Copy-EntraUser -TemplateUserId 'template.user@contoso.onmicrosoft.com' `
                -NewUser 'new.user@contoso.onmicrosoft.com' `
                -TenantId '00000000-0000-0000-0000-000000000000' `
                -ClientId '00000000-0000-0000-0000-000000000001' `
                -CertificatePath (Join-Path $TestDrive 'placeholder.pfx') `
                -CertificatePassword (ConvertTo-SecureString 'placeholder' -AsPlainText -Force) `
                -Confirm:$false
        } | Should -Not -Throw

        Should -Invoke New-MgGroupMemberByRef -Times 0 -ModuleName $script:dscModuleName
        Should -Invoke New-MgIdentityGovernancePrivilegedAccessGroupEligibilityScheduleRequest -Times 0 -ModuleName $script:dscModuleName
    }
}
