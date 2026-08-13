function Copy-EntraUser {
    <#
    .SYNOPSIS
        Clones an Entra ID user's direct group memberships, PIM-for-Groups
        eligible assignments, and PIM directory role eligible assignments
        from a template user onto a new or existing target user.
    .DESCRIPTION
        Resolves the template user and the target user, enumerates the
        template user's direct (non-transitive) group memberships and
        current PIM-for-Groups eligibility schedule instances, partitions
        those memberships into plain groups and PIM-for-Groups groups, then
        idempotently adds the target user as a direct member of each plain
        group and grants an ELIGIBLE (never active/permanent) PIM-for-Groups
        assignment for each PIM group, mirroring the template user's access
        tier (member vs owner). Dynamic-membership and role-assignable
        groups found in the template user's direct memberships are skipped
        with a named Write-Warning rather than cloned or silently dropped.

        Separately, enumerates the template user's directly-assigned (never
        inherited via a group or an Administrative Unit) PIM directory role
        eligibility schedule instances scoped tenant-wide, and grants an
        ELIGIBLE (never active/permanent) PIM directory role assignment for
        each one. Administrative Unit-scoped role eligibilities and
        permanent (non-PIM) role assignments are skipped with a named
        Write-Warning rather than cloned or silently dropped.

        Authenticates via certificate-based app-only auth when a certificate
        is supplied, falling back automatically to interactive delegated
        sign-in (with an explicit warning) if certificate-based auth cannot
        be established. When no certificate parameter is supplied at all --
        e.g. no app registration/certificate exists yet -- this connects
        interactively from the start, with no CBA attempt and no fallback
        warning (there is nothing to fall back from).
    .PARAMETER TemplateUserId
        The template user's UserPrincipalName or ObjectId.
    .PARAMETER NewUser
        Either the UPN/ObjectId of a pre-existing target user (pipeline
        input supported), or a hashtable of properties (DisplayName,
        UserPrincipalName, MailNickname, PasswordProfile, AccountEnabled)
        for a user to be created. Mutually exclusive with -NewUserPrincipalName
        and its companion parameters below -- specify one style or the other,
        not both.
    .PARAMETER NewUserPrincipalName
        The UserPrincipalName for a new user to be created, specified
        alongside -NewUserDisplayName and -NewUserMailNickname instead of
        building a -NewUser hashtable by hand. Mutually exclusive with
        -NewUser.
    .PARAMETER NewUserDisplayName
        The new user's display name. Required together with
        -NewUserPrincipalName.
    .PARAMETER NewUserMailNickname
        The new user's mail nickname. Required together with
        -NewUserPrincipalName.
    .PARAMETER NewUserPassword
        SecureString password for the new user. If omitted, a random
        password is generated via New-EntraUserPassword (a CSPRNG) and is
        never written to any output stream -- the operator must retrieve or
        reset the new user's password through a separate flow (e.g. Entra's
        Temporary Access Pass, self-service password reset, or an admin
        password reset) since it cannot be recovered from this function's
        output. The generated password sets ForceChangePasswordNextSignIn,
        so it only ever needs to work for a single first sign-in.
    .PARAMETER NewUserAccountEnabled
        Whether the newly created account is enabled. Defaults to $true.
    .PARAMETER PassThru
        Returns a result object with NewUserId and GeneratedPassword
        properties. GeneratedPassword is populated only when a password was
        auto-generated (i.e. -NewUserPassword was omitted on the named-
        parameter create-user path); it is $null when the caller supplied
        their own -NewUserPassword, or when -NewUser (an existing user or a
        hand-built hashtable) was used instead. Without -PassThru, the
        function produces no pipeline output at all -- this is the only
        supported way to retrieve an auto-generated password, since it is
        never written to any other output stream.
    .PARAMETER TenantId
        The Entra ID tenant ID (GUID) to connect to. Required when a
        certificate parameter is supplied; optional for interactive-only
        sign-in (Graph will prompt for a tenant if omitted).
    .PARAMETER ClientId
        The app registration's application (client) ID. Required when a
        certificate parameter is supplied; optional for interactive-only
        sign-in.
    .PARAMETER CertificateThumbprint
        Thumbprint of a certificate in a local certificate store.
        Windows-only; not portable to macOS or Linux. Omit this and
        -CertificatePath entirely to connect interactively instead.
    .PARAMETER CertificatePath
        Path to a portable PFX certificate file. Works identically on
        Windows, macOS, and Linux. Omit this and -CertificateThumbprint
        entirely to connect interactively instead.
    .PARAMETER CertificatePassword
        SecureString password protecting the PFX file at CertificatePath.
    .NOTES
        Application permissions required (CBA app registration must be
        pre-consented with these; see Get-RequiredGraphPermission):
            - User.ReadWrite.All
            - GroupMember.ReadWrite.All
            - PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup
            - RoleEligibilitySchedule.ReadWrite.Directory
            - RoleAssignmentSchedule.Read.Directory
            - RoleManagement.Read.Directory

        Delegated scopes required (interactive fallback path; passed
        explicitly to Connect-MgGraph -Scopes, never relying on cached
        consent):
            - User.ReadWrite.All
            - GroupMember.ReadWrite.All
            - PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup
            - RoleEligibilitySchedule.ReadWrite.Directory
            - RoleAssignmentSchedule.Read.Directory
            - RoleManagement.Read.Directory

        RoleAssignmentSchedule.Read.Directory is read-only and used solely
        to detect permanent (non-PIM) directory role assignments so they
        can be skipped with a warning instead of silently cloned as
        standing access.

        RoleManagement.Read.Directory is read-only and used solely by
        Get-MgRoleManagementDirectoryRoleDefinition to resolve directory
        role display names for warning messages.

        PIM-for-Groups and PIM directory role eligibility grants always use
        an expiration type of 'NoExpiration', regardless of whether the
        template user's own eligibility carried an end date. Expiration is
        deliberately normalized rather than mirrored: an eligibility end
        date reflects the template principal's own circumstances (e.g. a
        fixed-term project or contract) and would be semantically wrong to
        silently carry onto an unrelated new principal. Operators who need
        a bounded eligibility window should apply one deliberately after
        cloning, via PIM itself.

        Verb choice: Copy- (approved verb) was chosen over New- because this
        function's defining behaviour is replicating an existing principal's
        access model onto another principal, not creating a novel resource
        from a caller-authored specification.
    .EXAMPLE
        # Certificate-based (app-only), portable PFX file
        Copy-EntraUser -TemplateUserId 'template.user@contoso.onmicrosoft.com' `
            -NewUser 'new.hire@contoso.onmicrosoft.com' `
            -TenantId '00000000-0000-0000-0000-000000000000' `
            -ClientId '00000000-0000-0000-0000-000000000001' `
            -CertificatePath ./copy-entrauser.pfx `
            -CertificatePassword (Read-Host -AsSecureString 'Certificate password')
    .EXAMPLE
        # Interactive fallback: if the certificate cannot be loaded, this
        # automatically falls back to interactive sign-in with a warning.
        Copy-EntraUser -TemplateUserId 'template.user@contoso.onmicrosoft.com' `
            -NewUser @{
                DisplayName = 'New Hire'; UserPrincipalName = 'new.hire@contoso.onmicrosoft.com'
                MailNickname = 'new.hire'; PasswordProfile = @{ Password = -join (1..16 | ForEach-Object { $c = [char[]](48..57 + 65..90 + 97..122 + 33 + 35 + 36 + 37); $c[[System.Security.Cryptography.RandomNumberGenerator]::GetInt32(0, $c.Length)] }) }
                AccountEnabled = $true
            } `
            -TenantId '00000000-0000-0000-0000-000000000000' `
            -ClientId '00000000-0000-0000-0000-000000000001' `
            -CertificatePath ./missing-or-expired.pfx `
            -CertificatePassword (Read-Host -AsSecureString 'Certificate password')
    .EXAMPLE
        # No app registration/certificate available yet: connects interactively
        # from the start, with no certificate-based attempt or fallback warning.
        Copy-EntraUser -TemplateUserId 'template.user@contoso.onmicrosoft.com' `
            -NewUser 'new.hire@contoso.onmicrosoft.com'
    .EXAMPLE
        # Create a new user via named parameters instead of hand-building a
        # -NewUser hashtable. No password supplied, so one is generated
        # automatically and never displayed -- retrieve/reset it separately.
        Copy-EntraUser -TemplateUserId 'template.user@contoso.onmicrosoft.com' `
            -NewUserPrincipalName 'new.hire@contoso.onmicrosoft.com' `
            -NewUserDisplayName 'New Hire' `
            -NewUserMailNickname 'new.hire'
    .EXAMPLE
        # Retrieve the auto-generated password explicitly via -PassThru.
        # Without -PassThru, the generated password cannot be recovered.
        $result = Copy-EntraUser -TemplateUserId 'template.user@contoso.onmicrosoft.com' `
            -NewUserPrincipalName 'new.hire@contoso.onmicrosoft.com' `
            -NewUserDisplayName 'New Hire' `
            -NewUserMailNickname 'new.hire' `
            -PassThru
        $result.GeneratedPassword
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Interactive')]
    param(
        [Parameter(Mandatory)]
        [string] $TemplateUserId,

        [Parameter(ValueFromPipeline)]
        [object] $NewUser,

        [Parameter()]
        [string] $NewUserPrincipalName,

        [Parameter()]
        [string] $NewUserDisplayName,

        [Parameter()]
        [string] $NewUserMailNickname,

        [Parameter()]
        [securestring] $NewUserPassword,

        [Parameter()]
        [bool] $NewUserAccountEnabled = $true,

        [Parameter()]
        [switch] $PassThru,

        [Parameter()]
        [string] $TenantId,

        [Parameter()]
        [string] $ClientId,

        [Parameter(Mandatory, ParameterSetName = 'Thumbprint')]
        [string] $CertificateThumbprint,

        [Parameter(Mandatory, ParameterSetName = 'CertificateFile')]
        [string] $CertificatePath,

        [Parameter(Mandatory, ParameterSetName = 'CertificateFile')]
        [securestring] $CertificatePassword
    )

    begin {
        Test-RequiredGraphModule

        $connectParams = @{}
        if ($TenantId) { $connectParams['TenantId'] = $TenantId }
        if ($ClientId) { $connectParams['ClientId'] = $ClientId }
        switch ($PSCmdlet.ParameterSetName) {
            'Thumbprint' { $connectParams['CertificateThumbprint'] = $CertificateThumbprint }
            'CertificateFile' {
                $connectParams['CertificatePath'] = $CertificatePath
                $connectParams['CertificatePassword'] = $CertificatePassword
            }
        }
        $context = Connect-EntraGraphSession @connectParams
        $connectionClosed = $false
        Write-ToLog -Message "Connected to Microsoft Graph (AuthType=$($context.AuthType)) for Copy-EntraUser." -Level 'INFO' -WhatIf:$false -Confirm:$false
    }

    process {
        $newUserCompanionParameter = @('NewUserPrincipalName', 'NewUserDisplayName', 'NewUserMailNickname', 'NewUserPassword', 'NewUserAccountEnabled')
        $suppliedNewUser = $PSBoundParameters.ContainsKey('NewUser')
        $suppliedAnyNewUserCompanion = [bool]($newUserCompanionParameter | Where-Object { $PSBoundParameters.ContainsKey($_) })
        $suppliedNewUserPrincipalName = $PSBoundParameters.ContainsKey('NewUserPrincipalName')

        if ($suppliedNewUser -and $suppliedAnyNewUserCompanion) {
            throw 'Specify either -NewUser or -NewUserPrincipalName (with -NewUserDisplayName, -NewUserMailNickname, and optionally -NewUserPassword/-NewUserAccountEnabled), not both.'
        }
        if (-not $suppliedNewUser -and -not $suppliedNewUserPrincipalName) {
            throw 'You must supply either -NewUser (an existing user identifier or a properties hashtable) or -NewUserPrincipalName (with -NewUserDisplayName and -NewUserMailNickname) to create a new user.'
        }

        $passwordWasGenerated = $false
        $plainPassword = $null

        if ($suppliedNewUserPrincipalName) {
            if (-not $NewUserDisplayName -or -not $NewUserMailNickname) {
                throw '-NewUserDisplayName and -NewUserMailNickname are both required alongside -NewUserPrincipalName.'
            }

            $passwordWasGenerated = -not $PSBoundParameters.ContainsKey('NewUserPassword')
            $securePassword = if ($passwordWasGenerated) { New-EntraUserPassword } else { $NewUserPassword }
            $plainPassword = [System.Net.NetworkCredential]::new('', $securePassword).Password

            $NewUser = @{
                DisplayName       = $NewUserDisplayName
                UserPrincipalName = $NewUserPrincipalName
                MailNickname      = $NewUserMailNickname
                PasswordProfile   = @{
                    Password                      = $plainPassword
                    ForceChangePasswordNextSignIn = $true
                }
                AccountEnabled    = $NewUserAccountEnabled
            }
        }

        try {
            $templateUser = Resolve-EntraTemplateUser -UserId $TemplateUserId
            $newUserObject = Resolve-EntraNewUser -NewUser $NewUser

            $membership = Get-EntraTemplateGroupMembership -TemplateUserId $templateUser.Id
            $split = Split-EntraGroupMembership -DirectGroup $membership.DirectGroup `
                -EligibilityOnlyGroup $membership.EligibilityOnlyGroup `
                -EligibilitySchedule $membership.EligibilitySchedule

            foreach ($group in $split.UnsupportedGroup) {
                Write-Warning "Skipped group '$($group.DisplayName)' ($($group.Id)): dynamic-membership or role-assignable groups are not cloned by Copy-EntraUser."
                Write-ToLog -Message "Skipped group '$($group.DisplayName)' ($($group.Id)): dynamic-membership or role-assignable groups are not cloned by Copy-EntraUser." -Level 'WARN' -WhatIf:$false -Confirm:$false
            }

            $roleAssignment = Get-EntraTemplateRoleAssignment -TemplateUserId $templateUser.Id
            $roleSplit = Split-EntraRoleAssignment -EligibilitySchedule $roleAssignment.EligibilitySchedule `
                -ActiveAssignmentSchedule $roleAssignment.ActiveAssignmentSchedule `
                -RoleDefinitionById $roleAssignment.RoleDefinitionById

            foreach ($role in $roleSplit.UnsupportedRole) {
                Write-Warning "Skipped role '$($role.DisplayName)' ($($role.RoleDefinitionId)): $($role.Reason)"
                Write-ToLog -Message "Skipped role '$($role.DisplayName)' ($($role.RoleDefinitionId)): $($role.Reason)" -Level 'WARN' -WhatIf:$false -Confirm:$false
            }

            if ($PSCmdlet.ShouldProcess($newUserObject.Id, "Clone group memberships, PIM-for-Groups eligibility, and PIM directory role eligibility from '$TemplateUserId'")) {
                foreach ($group in $split.PlainGroup) {
                    Add-EntraGroupMembership -GroupId $group.Id -NewUserId $newUserObject.Id
                    Write-ToLog -Message "Added user '$($newUserObject.Id)' as a direct member of group '$($group.Id)'." -Level 'SUCCESS' -WhatIf:$false -Confirm:$false
                }

                foreach ($group in $split.PimGroup) {
                    Grant-EntraGroupEligibility -GroupId $group.Id -NewUserId $newUserObject.Id -AccessId $group.AccessId
                    Write-ToLog -Message "Granted PIM-for-Groups '$($group.AccessId)' eligibility to user '$($newUserObject.Id)' for group '$($group.Id)'." -Level 'SUCCESS' -WhatIf:$false -Confirm:$false
                }

                foreach ($role in $roleSplit.PimRole) {
                    Grant-EntraRoleEligibility -RoleDefinitionId $role.RoleDefinitionId -NewUserId $newUserObject.Id -DirectoryScopeId $role.DirectoryScopeId
                    Write-ToLog -Message "Granted PIM directory role eligibility to user '$($newUserObject.Id)' for role '$($role.RoleDefinitionId)' at scope '$($role.DirectoryScopeId)'." -Level 'SUCCESS' -WhatIf:$false -Confirm:$false
                }
            }
        }
        catch {
            if (-not $connectionClosed -and $context.AuthType -eq 'Delegated') {
                Disconnect-MgGraph | Out-Null
                Write-ToLog -Message 'Disconnected from Microsoft Graph after an error.' -Level 'INFO' -WhatIf:$false -Confirm:$false
                $connectionClosed = $true
            }
            throw
        }

        if ($PassThru) {
            [pscustomobject]@{
                NewUserId         = $newUserObject.Id
                GeneratedPassword = if ($passwordWasGenerated) { $plainPassword } else { $null }
            }
        }
    }

    end {
        if (-not $connectionClosed -and $context.AuthType -eq 'Delegated') {
            Disconnect-MgGraph | Out-Null
            Write-ToLog -Message 'Disconnected from Microsoft Graph.' -Level 'INFO' -WhatIf:$false -Confirm:$false
        }
    }
}
