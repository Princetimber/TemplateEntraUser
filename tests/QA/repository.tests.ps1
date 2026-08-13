#Requires -Version 7.0

BeforeAll {
    $script:projectPath = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

Describe 'Repository contracts' -Tag 'QA' {
    Context 'Release workflows' {
    BeforeAll {
        $buildYaml = Get-Content -Path (Join-Path $script:projectPath 'build.yaml') -Raw
        $script:buildWorkflows = [regex]::Matches(
            $buildYaml,
            '(?m)^  (?<Name>[A-Za-z0-9_.-]+):\s*$'
        ) | ForEach-Object { $_.Groups['Name'].Value }
    }

        It 'References defined build workflows in <Path>' -ForEach @(
            @{ Path = '.github/workflows/release.yml' }
            @{ Path = 'azure-pipelines.yml' }
        ) {
            $pipelineContent = Get-Content -Path (Join-Path $script:projectPath $Path) -Raw
            $referencedTasks = [regex]::Matches(
                $pipelineContent,
                '-tasks\s+[^A-Za-z0-9_.-]*(?<Name>publish[A-Za-z0-9_.-]*)'
            ) | ForEach-Object { $_.Groups['Name'].Value }

            $referencedTasks | Should -Not -BeNullOrEmpty
            foreach ($referencedTask in $referencedTasks) {
                $referencedTask | Should -BeIn $script:buildWorkflows
            }
        }
    }

    Context 'Source layout' {
        It 'Contains a function matching each private script filename' {
            $privateScripts = Get-ChildItem -Path (
                Join-Path $script:projectPath 'source/Private'
            ) -Filter '*.ps1' -File

            foreach ($privateScript in $privateScripts) {
                $tokens = $null
                $parseErrors = $null
                $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                    $privateScript.FullName,
                    [ref] $tokens,
                    [ref] $parseErrors
                )
                $functionNames = $ast.FindAll({
                        param($node)
                        $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
                    }, $true).Name

                $parseErrors | Should -BeNullOrEmpty
                $functionNames | Should -Contain $privateScript.BaseName
            }
        }

        It 'Fails module import when a source script cannot be loaded' {
            $tokens = $null
            $parseErrors = $null
            $moduleAst = [System.Management.Automation.Language.Parser]::ParseFile(
                (Join-Path $script:projectPath 'source/Copy-EntraUser.psm1'),
                [ref] $tokens,
                [ref] $parseErrors
            )
            $catchClauses = $moduleAst.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CatchClauseAst]
                }, $true)

            $parseErrors | Should -BeNullOrEmpty
            $catchClauses | Should -BeNullOrEmpty
        }
    }

    Context 'Logging identity' {
        It 'Uses module-specific default log and mutex names' {
            $loggerContent = Get-Content -Path (
                Join-Path $script:projectPath 'source/Private/Write-ToLog.ps1'
            ) -Raw
            # The default log file path itself is built in Initialize-LogFilePath,
            # split into its own file per the one-function-per-file convention.
            $logPathInitContent = Get-Content -Path (
                Join-Path $script:projectPath 'source/Private/Initialize-LogFilePath.ps1'
            ) -Raw

            $logPathInitContent | Should -Match 'Copy-EntraUser_\$\('
            $loggerContent | Should -Match 'Global\\Copy-EntraUserLog'
            $loggerContent | Should -Not -Match 'Invoke-ADDSDomainController'
            $logPathInitContent | Should -Not -Match 'Invoke-ADDSDomainController'
        }
    }

    Context 'Permission documentation drift' {
        It 'Copy-EntraUser.NOTES documents every permission Get-RequiredGraphPermission returns' {
            . (Join-Path $script:projectPath 'source/Private/Get-RequiredGraphPermission.ps1')
            # NOTE: Get-Help against the raw .ps1 *path* only ever surfaces comment-based
            # help attached to the file's top-level ScriptBlockAst. This file's help is
            # attached to the nested FunctionDefinitionAst (Copy-EntraUser is a
            # "one function per file" script, per the Sampler dot-sourcing convention),
            # so the script must be dot-sourced and help retrieved by function name
            # instead -- confirmed via (Get-Command <path>).ScriptBlock.Ast.GetHelpContent()
            # returning $null for path-based lookups against function-wrapped scripts.
            . (Join-Path $script:projectPath 'source/Public/Copy-EntraUser.ps1')
            $notes = (Get-Help Copy-EntraUser).AlertSet.Alert.Text

            foreach ($permission in Get-RequiredGraphPermission) {
                $notes | Should -Match ([regex]::Escape($permission))
            }
        }
    }
}
