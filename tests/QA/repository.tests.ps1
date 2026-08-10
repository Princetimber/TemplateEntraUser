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

    Context 'Template initialization' {
        BeforeAll {
            $script:initializerContent = Get-Content -Path (
                Join-Path $script:projectPath 'Initialize-Template.ps1'
            ) -Raw
        }

        It 'Uses literal replacement for fixed template tokens' {
            $script:initializerContent | Should -Match '\$content\.Replace\(\$key, \$replacements\[\$key\]\)'
            $script:initializerContent | Should -Not -Match '-replace\s+\[regex\]::Escape\(\$key\)'
        }

        It 'Escapes apostrophes before writing secrets to PowerShell source' {
            $script:initializerContent | Should -Match '\$escapedGalleryApiKey\s*=\s*\$GalleryApiKey\.Replace\("''", "''''"\)'
            $script:initializerContent | Should -Match '\$escapedGitHubToken\s*=\s*\$GitHubToken\.Replace\("''", "''''"\)'
            $script:initializerContent | Should -Match '\$env:PSGALLERY_API_KEY = ''\$escapedGalleryApiKey'''
            $script:initializerContent | Should -Match '\$env:GITHUB_TOKEN = ''\$escapedGitHubToken'''
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
                (Join-Path $script:projectPath 'source/TemplateModule.psm1'),
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

            $loggerContent | Should -Match 'TemplateModule_\$\('
            $loggerContent | Should -Match 'Global\\TemplateModuleLog'
            $loggerContent | Should -Not -Match 'Invoke-ADDSDomainController'
        }
    }
}
