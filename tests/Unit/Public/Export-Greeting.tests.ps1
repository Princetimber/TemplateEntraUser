#Requires -Version 7.0

BeforeAll {
    $script:dscModuleName = 'TemplateModule'

    Import-Module -Name $script:dscModuleName
}

AfterAll {
    Get-Module -Name $script:dscModuleName -All | Remove-Module -Force
}

Describe 'Export-Greeting' -Tag 'Unit' {

    BeforeAll {
        Mock -ModuleName $script:dscModuleName -CommandName Write-ToLog -MockWith {}
    }

    BeforeEach {
        $script:testDir = Join-Path $TestDrive 'export'
        if (Test-Path -LiteralPath $script:testDir) {
            Remove-Item -Path $script:testDir -Recurse -Force
        }
        New-Item -Path $script:testDir -ItemType Directory -Force | Out-Null
        $script:testFile = Join-Path $script:testDir 'greetings.txt'
    }

    Context 'When exporting a single greeting' {
        It 'Should create the file with the greeting' {
            Export-Greeting -Greeting 'Hello World, welcome.' -FilePath $script:testFile

            Test-Path -LiteralPath $script:testFile | Should -BeTrue
            Get-Content -LiteralPath $script:testFile | Should -Be 'Hello World, welcome.'
        }
    }

    Context 'When exporting multiple greetings' {
        It 'Should write all greetings to the file' {
            Export-Greeting -Greeting 'Hello Alice, welcome.', 'Hey Bob!' -FilePath $script:testFile

            $content = Get-Content -LiteralPath $script:testFile
            $content | Should -HaveCount 2
            $content[0] | Should -Be 'Hello Alice, welcome.'
            $content[1] | Should -Be 'Hey Bob!'
        }
    }

    Context 'When piping from Get-Greeting' {
        It 'Should accept pipeline string input' {
            'Hello Alice, welcome.' | Export-Greeting -FilePath $script:testFile

            Get-Content -LiteralPath $script:testFile | Should -Be 'Hello Alice, welcome.'
        }

        It 'Should accept multiple pipeline strings' {
            @('Hello Alice, welcome.', 'Hey Bob!') | Export-Greeting -FilePath $script:testFile

            $content = Get-Content -LiteralPath $script:testFile
            $content | Should -HaveCount 2
        }
    }

    Context 'When using Append' {
        It 'Should append to existing file' {
            Set-Content -LiteralPath $script:testFile -Value 'Existing line'

            Export-Greeting -Greeting 'New greeting' -FilePath $script:testFile -Append

            $content = Get-Content -LiteralPath $script:testFile
            $content | Should -HaveCount 2
            $content[0] | Should -Be 'Existing line'
            $content[1] | Should -Be 'New greeting'
        }
    }

    Context 'When using Force' {
        It 'Should overwrite existing file' {
            Set-Content -LiteralPath $script:testFile -Value 'Old content'

            Export-Greeting -Greeting 'New content' -FilePath $script:testFile -Force

            Get-Content -LiteralPath $script:testFile | Should -Be 'New content'
        }
    }

    Context 'When using WhatIf' {
        It 'Should not create the file' {
            Export-Greeting -Greeting 'Hello' -FilePath $script:testFile -WhatIf

            Test-Path -LiteralPath $script:testFile | Should -BeFalse
        }
    }

    Context 'When file already exists without Force or Append' {
        It 'Should throw a terminating error' {
            Set-Content -LiteralPath $script:testFile -Value 'Existing'

            { Export-Greeting -Greeting 'New' -FilePath $script:testFile } |
                Should -Throw '*already exists*'
        }
    }

    Context 'When parent directory does not exist' {
        It 'Should throw a terminating error' {
            $badPath = Join-Path $TestDrive 'nonexistent' 'file.txt'

            { Export-Greeting -Greeting 'Hello' -FilePath $badPath } |
                Should -Throw '*does not exist*'
        }
    }

    Context 'When using PassThru' {
        It 'Should return a FileInfo object' {
            $result = Export-Greeting -Greeting 'Hello' -FilePath $script:testFile -PassThru

            $result | Should -BeOfType [System.IO.FileInfo]
            $result.FullName | Should -Be $script:testFile
        }
    }

    Context 'When validating parameters' {
        It 'Should throw on null Greeting' {
            { Export-Greeting -Greeting $null -FilePath $script:testFile } | Should -Throw
        }

        It 'Should throw on empty Greeting' {
            { Export-Greeting -Greeting '' -FilePath $script:testFile } | Should -Throw
        }

        It 'Should throw on null FilePath' {
            { Export-Greeting -Greeting 'Hello' -FilePath $null } | Should -Throw
        }

        It 'Should have SupportsShouldProcess' {
            $cmd = Get-Command -Name Export-Greeting
            $cmd.Parameters.ContainsKey('WhatIf') | Should -BeTrue
            $cmd.Parameters.ContainsKey('Confirm') | Should -BeTrue
        }
    }
}
