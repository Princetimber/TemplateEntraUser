#Requires -Version 7.0

BeforeAll {
    $script:dscModuleName = 'TemplateModule'

    Import-Module -Name $script:dscModuleName
}

AfterAll {
    Get-Module -Name $script:dscModuleName -All | Remove-Module -Force
}

Describe 'Get-Greeting' -Tag 'Unit' {

    BeforeAll {
        Mock -ModuleName $script:dscModuleName -CommandName Write-ToLog -MockWith {}
    }

    Context 'When generating greetings with default style' {
        It 'Should return a professional greeting' {
            $result = Get-Greeting -Name 'World'

            $result | Should -Be 'Hello World, welcome.'
        }

        It 'Should accept Name via pipeline' {
            $result = 'Alice' | Get-Greeting

            $result | Should -Be 'Hello Alice, welcome.'
        }

        It 'Should process multiple names from pipeline' {
            $results = @('Bob', 'Carol') | Get-Greeting

            $results | Should -HaveCount 2
            $results[0] | Should -Be 'Hello Bob, welcome.'
            $results[1] | Should -Be 'Hello Carol, welcome.'
        }
    }

    Context 'When using different styles' {
        It 'Should return a formal greeting' {
            $result = Get-Greeting -Name 'Alice' -Style Formal

            $result | Should -Be 'Good day, Alice.'
        }

        It 'Should return a casual greeting' {
            $result = Get-Greeting -Name 'Bob' -Style Casual

            $result | Should -Be 'Hey Bob!'
        }

        It 'Should return a professional greeting' {
            $result = Get-Greeting -Name 'Carol' -Style Professional

            $result | Should -Be 'Hello Carol, welcome.'
        }
    }

    Context 'When using PassThru parameter' {
        It 'Should return a PSCustomObject' {
            $result = Get-Greeting -Name 'Alice' -PassThru

            $result | Should -BeOfType [PSCustomObject]
        }

        It 'Should include Name property' {
            $result = Get-Greeting -Name 'Alice' -PassThru

            $result.Name | Should -Be 'Alice'
        }

        It 'Should include Style property' {
            $result = Get-Greeting -Name 'Alice' -Style Formal -PassThru

            $result.Style | Should -Be 'Formal'
        }

        It 'Should include Message property' {
            $result = Get-Greeting -Name 'Alice' -PassThru

            $result.Message | Should -Be 'Hello Alice, welcome.'
        }

        It 'Should include Created timestamp' {
            $before = Get-Date
            $result = Get-Greeting -Name 'Alice' -PassThru
            $after = Get-Date

            $result.Created | Should -BeGreaterOrEqual $before
            $result.Created | Should -BeLessOrEqual $after
        }
    }

    Context 'When verifying CmdletBinding' {
        It 'Should not have SupportsShouldProcess' {
            $cmd = Get-Command -Name Get-Greeting
            $cmd.Parameters.ContainsKey('WhatIf') | Should -BeFalse
            $cmd.Parameters.ContainsKey('Confirm') | Should -BeFalse
        }
    }

    Context 'When handling parameter validation' {
        It 'Should throw on null Name' {
            { Get-Greeting -Name $null } | Should -Throw
        }

        It 'Should throw on empty Name' {
            { Get-Greeting -Name '' } | Should -Throw
        }

        It 'Should throw on invalid Style' {
            { Get-Greeting -Name 'Alice' -Style 'Invalid' } | Should -Throw
        }
    }

    Context 'When Format-GreetingMessage fails to produce a greeting' {
        It 'Should throw a terminating error' {
            Mock -ModuleName $script:dscModuleName -CommandName Format-GreetingMessage -MockWith { return $null }

            { Get-Greeting -Name 'Alice' -ErrorAction Stop } | Should -Throw -ErrorId 'GreetingFormatFailed,Get-Greeting'
        }
    }

    Context 'When logging operations' {
        It 'Should call Write-ToLog during execution' {
            Get-Greeting -Name 'Alice'

            Should -Invoke -ModuleName $script:dscModuleName -CommandName Write-ToLog -Times 4 -Exactly
        }
    }
}
