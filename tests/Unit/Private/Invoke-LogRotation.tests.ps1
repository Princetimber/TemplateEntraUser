#Requires -Version 7.0

BeforeAll {
    $script:dscModuleName = 'TemplateModule'

    Import-Module -Name $script:dscModuleName
}

AfterAll {
    Get-Module -Name $script:dscModuleName -All | Remove-Module -Force
}

Describe 'Invoke-LogRotation' -Tag 'Unit' {

    BeforeEach {
        InModuleScope -ModuleName $script:dscModuleName {
            $script:LogFile = Join-Path $TestDrive 'module.log'
            $script:MaxLogFiles = 5
        }
    }

    Context 'When the log file does not exist' {
        It 'Should return without moving or removing any files' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Test-PathWrapper { $false }
                Mock Move-ItemWrapper
                Mock Remove-ItemWrapper

                Invoke-LogRotation

                Should -Invoke Move-ItemWrapper -Times 0
                Should -Invoke Remove-ItemWrapper -Times 0
            }
        }
    }

    Context 'When the log file exists with no existing backups' {
        It 'Should move the current log to .1' {
            InModuleScope -ModuleName $script:dscModuleName {
                # Only the current log exists; no numbered backups
                Mock Test-PathWrapper -ParameterFilter {
                    $LiteralPath -eq $script:LogFile
                } { $true }
                Mock Test-PathWrapper { $false }
                Mock Move-ItemWrapper
                Mock Remove-ItemWrapper

                Invoke-LogRotation

                Should -Invoke Move-ItemWrapper -Times 1 -ParameterFilter {
                    $LiteralPath -eq $script:LogFile -and
                    $Destination -eq "$script:LogFile.1"
                }
            }
        }

        It 'Should not call Remove-Item when the oldest backup does not exist' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Test-PathWrapper -ParameterFilter {
                    $LiteralPath -eq $script:LogFile
                } { $true }
                Mock Test-PathWrapper { $false }
                Mock Move-ItemWrapper
                Mock Remove-ItemWrapper

                Invoke-LogRotation

                Should -Invoke Remove-ItemWrapper -Times 0
            }
        }
    }

    Context 'When the oldest backup (MaxLogFiles) already exists' {
        It 'Should remove the oldest backup file' {
            InModuleScope -ModuleName $script:dscModuleName {
                $oldestLog = "$script:LogFile.$script:MaxLogFiles"

                Mock Test-PathWrapper -ParameterFilter {
                    $LiteralPath -eq $script:LogFile
                } { $true }
                Mock Test-PathWrapper -ParameterFilter {
                    $LiteralPath -eq $oldestLog
                } { $true }
                Mock Test-PathWrapper { $false }
                Mock Remove-ItemWrapper
                Mock Move-ItemWrapper

                Invoke-LogRotation

                Should -Invoke Remove-ItemWrapper -Times 1 -ParameterFilter {
                    $LiteralPath -eq $oldestLog
                }
            }
        }
    }

    Context 'When intermediate backups exist' {
        It 'Should shift .1 to .2 and .2 to .3' {
            InModuleScope -ModuleName $script:dscModuleName {
                $log1 = "$script:LogFile.1"
                $log2 = "$script:LogFile.2"

                Mock Test-PathWrapper -ParameterFilter {
                    $LiteralPath -eq $script:LogFile
                } { $true }
                Mock Test-PathWrapper -ParameterFilter {
                    $LiteralPath -eq $log1
                } { $true }
                Mock Test-PathWrapper -ParameterFilter {
                    $LiteralPath -eq $log2
                } { $true }
                Mock Test-PathWrapper { $false }
                Mock Move-ItemWrapper
                Mock Remove-ItemWrapper

                Invoke-LogRotation

                Should -Invoke Move-ItemWrapper -Times 1 -ParameterFilter {
                    $LiteralPath -eq $log2 -and $Destination -eq "$script:LogFile.3"
                }
                Should -Invoke Move-ItemWrapper -Times 1 -ParameterFilter {
                    $LiteralPath -eq $log1 -and $Destination -eq "$script:LogFile.2"
                }
            }
        }
    }

    Context 'When a rotation step fails' {
        It 'Should warn and return without throwing' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Test-PathWrapper -ParameterFilter {
                    $LiteralPath -eq $script:LogFile
                } { $true }
                Mock Test-PathWrapper { $false }
                Mock Move-ItemWrapper { throw [System.IO.IOException]::new('disk full') }
                Mock Remove-ItemWrapper
                Mock Write-Warning

                { Invoke-LogRotation } | Should -Not -Throw

                Should -Invoke Write-Warning -Times 1 -ParameterFilter {
                    $Message -match 'Failed to rotate log file'
                }
            }
        }
    }

    Context 'When using -WhatIf' {
        It 'Should not move or remove any files' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Test-PathWrapper { $true }
                Mock Move-ItemWrapper
                Mock Remove-ItemWrapper

                Invoke-LogRotation -WhatIf

                Should -Invoke Move-ItemWrapper -Times 0
                Should -Invoke Remove-ItemWrapper -Times 0
            }
        }
    }
}
