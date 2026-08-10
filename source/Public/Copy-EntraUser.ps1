function Copy-EntraUser {
    <#
    .SYNOPSIS
        Clones an Entra ID user's direct group memberships and PIM-for-Groups
        eligible assignments from a template user onto a new or existing
        target user.
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

        Authenticates via certificate-based app-only auth by default,
        falling back automatically to interactive delegated sign-in (with an
        explicit warning) if certificate-based auth cannot be established.
    .PARAMETER TemplateUserId
        The template user's UserPrincipalName or ObjectId.
    .PARAMETER NewUser
        Either the UPN/ObjectId of a pre-existing target user (pipeline
        input supported), or a hashtable of properties (DisplayName,
        UserPrincipalName, MailNickname, PasswordProfile, AccountEnabled)
        for a user to be created.
    .PARAMETER TenantId
        The Entra ID tenant ID (GUID) to connect to.
    .PARAMETER ClientId
        The app registration's application (client) ID.
    .PARAMETER CertificateThumbprint
        Thumbprint of a certificate in a local certificate store.
        Windows-only; not portable to macOS or Linux.
    .PARAMETER CertificatePath
        Path to a portable PFX certificate file. Works identically on
        Windows, macOS, and Linux.
    .PARAMETER CertificatePassword
        SecureString password protecting the PFX file at CertificatePath.
    .NOTES
        Application permissions required (CBA app registration must be
        pre-consented with these; see Get-RequiredGraphPermission):
            - User.ReadWrite.All
            - GroupMember.ReadWrite.All
            - PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup

        Delegated scopes required (interactive fallback path; passed
        explicitly to Connect-MgGraph -Scopes, never relying on cached
        consent):
            - User.ReadWrite.All
            - GroupMember.ReadWrite.All
            - PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup

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
                MailNickname = 'new.hire'; PasswordProfile = @{ Password = [System.Web.Security.Membership]::GeneratePassword(16, 4) }
                AccountEnabled = $true
            } `
            -TenantId '00000000-0000-0000-0000-000000000000' `
            -ClientId '00000000-0000-0000-0000-000000000001' `
            -CertificatePath ./missing-or-expired.pfx `
            -CertificatePassword (Read-Host -AsSecureString 'Certificate password')
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'CertificateFile')]
    param(
        [Parameter(Mandatory)]
        [string] $TemplateUserId,

        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $NewUser,

        [Parameter(Mandatory)]
        [string] $TenantId,

        [Parameter(Mandatory)]
        [string] $ClientId,

        [Parameter(Mandatory, ParameterSetName = 'Thumbprint')]
        [string] $CertificateThumbprint,

        [Parameter(Mandatory, ParameterSetName = 'CertificateFile')]
        [string] $CertificatePath,

        [Parameter(Mandatory, ParameterSetName = 'CertificateFile')]
        [securestring] $CertificatePassword
    )

    process {
        Test-RequiredGraphModule

        $connectParams = @{ TenantId = $TenantId; ClientId = $ClientId }
        if ($PSCmdlet.ParameterSetName -eq 'Thumbprint') {
            $connectParams['CertificateThumbprint'] = $CertificateThumbprint
        }
        else {
            $connectParams['CertificatePath'] = $CertificatePath
            $connectParams['CertificatePassword'] = $CertificatePassword
        }
        $context = Connect-EntraGraphSession @connectParams

        $templateUser = Resolve-EntraTemplateUser -UserId $TemplateUserId
        $newUserObject = Resolve-EntraNewUser -NewUser $NewUser

        $membership = Get-EntraTemplateGroupMembership -TemplateUserId $templateUser.Id
        $split = Split-EntraGroupMembership -DirectGroup $membership.DirectGroup `
            -EligibilitySchedule $membership.EligibilitySchedule

        foreach ($group in $split.UnsupportedGroup) {
            Write-Warning "Skipped group '$($group.DisplayName)' ($($group.Id)): dynamic-membership or role-assignable groups are not cloned by Copy-EntraUser."
        }

        if ($PSCmdlet.ShouldProcess($newUserObject.Id, "Clone group memberships and PIM-for-Groups eligibility from '$TemplateUserId'")) {
            foreach ($group in $split.PlainGroup) {
                Add-EntraGroupMembership -GroupId $group.Id -NewUserId $newUserObject.Id
            }

            foreach ($group in $split.PimGroup) {
                Grant-EntraGroupEligibility -GroupId $group.Id -NewUserId $newUserObject.Id -AccessId $group.AccessId
            }
        }

        if ($context.AuthType -eq 'Delegated') {
            Disconnect-MgGraph | Out-Null
        }
    }
}
