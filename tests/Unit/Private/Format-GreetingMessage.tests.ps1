#Requires -Version 7.0

BeforeAll {
    $script:dscModuleName = 'TemplateModule'

    Import-Module -Name $script:dscModuleName
}

AfterAll {
    Get-Module -Name $script:dscModuleName -All | Remove-Module -Force
}

Describe 'Format-GreetingMessage' -Tag 'Unit' {

    BeforeAll {
        Mock -ModuleName $script:dscModuleName -CommandName Write-ToLog -MockWith {}
    }

    Context 'When formatting with Formal style' {
        It 'Should return formal greeting' {
            InModuleScope -ModuleName $script:dscModuleName {
                $result = Format-GreetingMessage -Name 'Alice' -Style Formal

                $result | Should -Be 'Good day, Alice.'
            }
        }
    }

    Context 'When formatting with Casual style' {
        It 'Should return casual greeting' {
            InModuleScope -ModuleName $script:dscModuleName {
                $result = Format-GreetingMessage -Name 'Bob' -Style Casual

                $result | Should -Be 'Hey Bob!'
            }
        }
    }

    Context 'When formatting with Professional style' {
        It 'Should return professional greeting' {
            InModuleScope -ModuleName $script:dscModuleName {
                $result = Format-GreetingMessage -Name 'Carol' -Style Professional

                $result | Should -Be 'Hello Carol, welcome.'
            }
        }

        It 'Should use Professional as default style' {
            InModuleScope -ModuleName $script:dscModuleName {
                $result = Format-GreetingMessage -Name 'Dave'

                $result | Should -Be 'Hello Dave, welcome.'
            }
        }
    }

    Context 'When handling whitespace in names' {
        It 'Should trim leading whitespace' {
            InModuleScope -ModuleName $script:dscModuleName {
                $result = Format-GreetingMessage -Name '  Alice' -Style Casual

                $result | Should -Be 'Hey Alice!'
            }
        }

        It 'Should trim trailing whitespace' {
            InModuleScope -ModuleName $script:dscModuleName {
                $result = Format-GreetingMessage -Name 'Alice  ' -Style Casual

                $result | Should -Be 'Hey Alice!'
            }
        }

        It 'Should throw on whitespace-only name' {
            InModuleScope -ModuleName $script:dscModuleName {
                { Format-GreetingMessage -Name '   ' } | Should -Throw
            }
        }

        It 'Should throw on empty string' {
            InModuleScope -ModuleName $script:dscModuleName {
                { Format-GreetingMessage -Name '' } | Should -Throw
            }
        }
    }

    Context 'When handling special characters in names' {
        It 'Should handle names with hyphens' {
            InModuleScope -ModuleName $script:dscModuleName {
                $result = Format-GreetingMessage -Name 'Mary-Jane' -Style Formal

                $result | Should -Be 'Good day, Mary-Jane.'
            }
        }

        It 'Should handle names with apostrophes' {
            InModuleScope -ModuleName $script:dscModuleName {
                $result = Format-GreetingMessage -Name "O'Brien" -Style Professional

                $result | Should -Be "Hello O'Brien, welcome."
            }
        }

        It 'Should handle names with spaces' {
            InModuleScope -ModuleName $script:dscModuleName {
                $result = Format-GreetingMessage -Name 'John Doe' -Style Casual

                $result | Should -Be 'Hey John Doe!'
            }
        }
    }
}
