#Requires -Version 7.0

BeforeAll {
    $script:dscModuleName = 'TemplateModule'

    Import-Module -Name $script:dscModuleName
}

AfterAll {
    Get-Module -Name $script:dscModuleName -All | Remove-Module -Force
}

Describe 'Log file I/O wrappers' -Tag 'Unit' {
    Context 'Test-PathWrapper' {
        It 'Returns true for an existing path via -LiteralPath' {
            InModuleScope -ModuleName $script:dscModuleName {
                $file = Join-Path -Path $TestDrive -ChildPath 'exists.txt'
                Set-Content -LiteralPath $file -Value 'x'

                Test-PathWrapper -LiteralPath $file | Should -BeTrue
            }
        }

        It 'Returns true for an existing path via -Path' {
            InModuleScope -ModuleName $script:dscModuleName {
                $file = Join-Path -Path $TestDrive -ChildPath 'exists-path.txt'
                Set-Content -LiteralPath $file -Value 'x'

                Test-PathWrapper -Path $file | Should -BeTrue
            }
        }

        It 'Honours -PathType Container' {
            InModuleScope -ModuleName $script:dscModuleName {
                Test-PathWrapper -Path $TestDrive -PathType 'Container' | Should -BeTrue
            }
        }
    }

    Context 'Get-ItemWrapper' {
        It 'Returns the item for a file' {
            InModuleScope -ModuleName $script:dscModuleName {
                $file = Join-Path -Path $TestDrive -ChildPath 'item.txt'
                Set-Content -LiteralPath $file -Value 'x'

                (Get-ItemWrapper -LiteralPath $file).Name | Should -Be 'item.txt'
            }
        }
    }

    Context 'Add-ContentWrapper' {
        It 'Appends content to a file' {
            InModuleScope -ModuleName $script:dscModuleName {
                $file = Join-Path -Path $TestDrive -ChildPath 'add.txt'

                Add-ContentWrapper -LiteralPath $file -Value 'line1'

                Get-Content -LiteralPath $file | Should -Be 'line1'
            }
        }
    }

    Context 'Move-ItemWrapper' {
        It 'Moves a file to the destination' {
            InModuleScope -ModuleName $script:dscModuleName {
                $src = Join-Path -Path $TestDrive -ChildPath 'move-src.txt'
                $dst = Join-Path -Path $TestDrive -ChildPath 'move-dst.txt'
                Set-Content -LiteralPath $src -Value 'data'

                Move-ItemWrapper -LiteralPath $src -Destination $dst

                Test-Path -LiteralPath $src | Should -BeFalse
                Get-Content -LiteralPath $dst | Should -Be 'data'
            }
        }
    }

    Context 'Remove-ItemWrapper' {
        It 'Removes a file' {
            InModuleScope -ModuleName $script:dscModuleName {
                $file = Join-Path -Path $TestDrive -ChildPath 'remove.txt'
                Set-Content -LiteralPath $file -Value 'data'

                Remove-ItemWrapper -LiteralPath $file

                Test-Path -LiteralPath $file | Should -BeFalse
            }
        }
    }
}
