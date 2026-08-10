#Requires -Version 7.0

BeforeAll {
    $script:dscModuleName = 'TemplateModule'

    Import-Module -Name $script:dscModuleName
}

AfterAll {
    Get-Module -Name $script:dscModuleName -All | Remove-Module -Force
}

Describe 'Write-ToLog' -Tag 'Unit' {

    BeforeEach {
        InModuleScope -ModuleName $script:dscModuleName {
            # Point logging at TestDrive and skip directory-creation logic
            $script:LogFile = Join-Path $TestDrive 'test.log'
            $script:LogDirectoryCreated = $true
            $script:LogMutex = $null
        }
    }

    Context 'When writing a message at INFO level' {
        It 'Should write a timestamped entry containing [INFO] to the log file' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Add-ContentWrapper
                Mock Test-PathWrapper { $false }

                Write-ToLog -Message 'Info message' -Level INFO

                Should -Invoke Add-ContentWrapper -Times 1 -ParameterFilter {
                    $Value -match '\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] \[INFO\] Info message'
                }
            }
        }
    }

    Context 'When writing a message at WARN level' {
        It 'Should write a timestamped entry containing [WARN]' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Add-ContentWrapper
                Mock Test-PathWrapper { $false }

                Write-ToLog -Message 'Warning message' -Level WARN

                Should -Invoke Add-ContentWrapper -Times 1 -ParameterFilter {
                    $Value -match '\[WARN\] Warning message'
                }
            }
        }
    }

    Context 'When writing a message at ERROR level' {
        It 'Should write a timestamped entry containing [ERROR]' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Add-ContentWrapper
                Mock Test-PathWrapper { $false }

                Write-ToLog -Message 'Error message' -Level ERROR

                Should -Invoke Add-ContentWrapper -Times 1 -ParameterFilter {
                    $Value -match '\[ERROR\] Error message'
                }
            }
        }
    }

    Context 'When writing a message at SUCCESS level' {
        It 'Should write a timestamped entry containing [SUCCESS]' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Add-ContentWrapper
                Mock Test-PathWrapper { $false }

                Write-ToLog -Message 'Success message' -Level SUCCESS

                Should -Invoke Add-ContentWrapper -Times 1 -ParameterFilter {
                    $Value -match '\[SUCCESS\] Success message'
                }
            }
        }
    }

    Context 'When writing a message at DEBUG level' {
        It 'Should write a timestamped entry containing [DEBUG]' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Add-ContentWrapper
                Mock Test-PathWrapper { $false }

                Write-ToLog -Message 'Debug message' -Level DEBUG

                Should -Invoke Add-ContentWrapper -Times 1 -ParameterFilter {
                    $Value -match '\[DEBUG\] Debug message'
                }
            }
        }
    }

    Context 'When using default level' {
        It 'Should default to INFO when no level is specified' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Add-ContentWrapper
                Mock Test-PathWrapper { $false }

                Write-ToLog -Message 'Default level'

                Should -Invoke Add-ContentWrapper -Times 1 -ParameterFilter {
                    $Value -match '\[INFO\]'
                }
            }
        }
    }

    Context 'When using positional parameters' {
        It 'Should accept message as first positional parameter' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Add-ContentWrapper
                Mock Test-PathWrapper { $false }

                Write-ToLog 'Positional message'

                Should -Invoke Add-ContentWrapper -Times 1 -ParameterFilter {
                    $Value -match 'Positional message'
                }
            }
        }

        It 'Should accept level as second positional parameter' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Add-ContentWrapper
                Mock Test-PathWrapper { $false }

                Write-ToLog 'Test message' WARN

                Should -Invoke Add-ContentWrapper -Times 1 -ParameterFilter {
                    $Value -match '\[WARN\] Test message'
                }
            }
        }
    }

    Context 'When using PassThru' {
        It 'Should return $true on a successful write' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Add-ContentWrapper
                Mock Test-PathWrapper { $false }

                $result = Write-ToLog -Message 'Test' -PassThru

                $result | Should -BeTrue
            }
        }

        It 'Should return nothing without PassThru' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Add-ContentWrapper
                Mock Test-PathWrapper { $false }

                $result = Write-ToLog -Message 'Test'

                $result | Should -BeNullOrEmpty
            }
        }
    }

    Context 'When NoConsole is specified' {
        It 'Should not call Write-Host' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Add-ContentWrapper
                Mock Test-PathWrapper { $false }
                Mock Write-Host

                Write-ToLog -Message 'Silent entry' -Level INFO -NoConsole

                Should -Invoke Write-Host -Times 0
            }
        }
    }

    Context 'When sensitive data is present in the message' {
        It 'Should redact password in key=value format' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Add-ContentWrapper
                Mock Test-PathWrapper { $false }

                Write-ToLog -Message 'Connecting with password=SuperSecret123' -Level INFO

                Should -Invoke Add-ContentWrapper -Times 1 -ParameterFilter {
                    $Value -match 'password=\*\*\*REDACTED\*\*\*' -and
                    $Value -notmatch 'SuperSecret123'
                }
            }
        }

        It 'Should redact token in JSON format' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Add-ContentWrapper
                Mock Test-PathWrapper { $false }

                Write-ToLog -Message '{"token": "my-secret-token"}' -Level INFO

                Should -Invoke Add-ContentWrapper -Times 1 -ParameterFilter {
                    $Value -match '"token": "\*\*\*REDACTED\*\*\*"' -and
                    $Value -notmatch 'my-secret-token'
                }
            }
        }

        It 'Should redact secret in XML format' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Add-ContentWrapper
                Mock Test-PathWrapper { $false }

                Write-ToLog -Message '<secret>hiddenvalue</secret>' -Level INFO

                Should -Invoke Add-ContentWrapper -Times 1 -ParameterFilter {
                    $Value -match '<secret>\*\*\*REDACTED\*\*\*</secret>' -and
                    $Value -notmatch 'hiddenvalue'
                }
            }
        }

        It 'Should redact an unquoted key: value pair' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Add-ContentWrapper
                Mock Test-PathWrapper { $false }

                Write-ToLog -Message 'Using password: SuperSecret123' -Level INFO

                Should -Invoke Add-ContentWrapper -Times 1 -ParameterFilter {
                    $Value -match 'password: \*\*\*REDACTED\*\*\*' -and
                    $Value -notmatch 'SuperSecret123'
                }
            }
        }

        It 'Should redact a Bearer token' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Add-ContentWrapper
                Mock Test-PathWrapper { $false }

                Write-ToLog -Message 'Authorization: Bearer eyJhbGciOiJInotarealtoken' -Level INFO

                Should -Invoke Add-ContentWrapper -Times 1 -ParameterFilter {
                    $Value -match 'Bearer \*\*\*REDACTED\*\*\*' -and
                    $Value -notmatch 'eyJhbGciOiJInotarealtoken'
                }
            }
        }
    }

    Context 'When using the ErrorRecord parameter set' {
        It 'Should log the exception message at ERROR level' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Add-ContentWrapper
                Mock Test-PathWrapper { $false }

                $exception = [System.Exception]::new('Something went wrong')
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception, 'TestError',
                    [System.Management.Automation.ErrorCategory]::NotSpecified, $null
                )

                Write-ToLog -ErrorRecord $errorRecord

                Should -Invoke Add-ContentWrapper -Times 1 -ParameterFilter {
                    $Value -match '\[ERROR\] Something went wrong'
                }
            }
        }

        It 'Should log error details at DEBUG level as a second write' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Add-ContentWrapper
                Mock Test-PathWrapper { $false }

                $exception = [System.Exception]::new('Test exception')
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception, 'TestError',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation, $null
                )

                Write-ToLog -ErrorRecord $errorRecord

                # ERROR entry + DEBUG details entry
                Should -Invoke Add-ContentWrapper -Times 2
            }
        }

        It 'Should return combined PassThru result when PassThru is used with ErrorRecord' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Add-ContentWrapper
                Mock Test-PathWrapper { $false }

                $exception = [System.Exception]::new('Passthru error')
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception, 'TestError',
                    [System.Management.Automation.ErrorCategory]::NotSpecified, $null
                )

                $result = Write-ToLog -ErrorRecord $errorRecord -PassThru

                $result | Should -BeTrue
            }
        }

        It 'Should include invocation location and inner exception in the DEBUG details' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Add-ContentWrapper
                Mock Test-PathWrapper { $false }

                try {
                    $inner = [System.Exception]::new('Root cause')
                    $outer = [System.Exception]::new('Wrapper error', $inner)
                    throw $outer
                } catch {
                    $realErrorRecord = $_
                }

                Write-ToLog -ErrorRecord $realErrorRecord

                Should -Invoke Add-ContentWrapper -Times 1 -ParameterFilter {
                    $Value -match '\[DEBUG\]' -and
                    $Value -match 'Location:' -and
                    $Value -match 'Command:' -and
                    $Value -match 'Inner Exception: Root cause'
                }
            }
        }
    }

    Context 'When the log file exceeds the size threshold' {
        It 'Should invoke log rotation' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Add-ContentWrapper
                Mock Invoke-LogRotation
                Mock Test-PathWrapper { $true }
                Mock Get-ItemWrapper { [PSCustomObject]@{ Length = 15MB } }

                Write-ToLog -Message 'Triggers rotation' -Level INFO

                Should -Invoke Invoke-LogRotation -Times 1
            }
        }

        It 'Should not rotate when the file is within the size limit' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Add-ContentWrapper
                Mock Invoke-LogRotation
                Mock Test-PathWrapper { $true }
                Mock Get-ItemWrapper { [PSCustomObject]@{ Length = 5MB } }

                Write-ToLog -Message 'No rotation needed' -Level INFO

                Should -Invoke Invoke-LogRotation -Times 0
            }
        }

        It 'Should warn and continue writing when rotation itself fails' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Add-ContentWrapper
                Mock Invoke-LogRotation { throw 'Disk full' }
                Mock Test-PathWrapper { $true }
                Mock Get-ItemWrapper { [PSCustomObject]@{ Length = 15MB } }
                Mock Write-Warning

                Write-ToLog -Message 'Rotation fails but write continues' -Level INFO

                Should -Invoke Write-Warning -Times 1 -ParameterFilter {
                    $Message -match 'Log rotation failed'
                }
                Should -Invoke Add-ContentWrapper -Times 1
            }
        }
    }

    Context 'When the log directory cannot be created' {
        It 'Should rethrow if the directory is still missing after an IOException' {
            InModuleScope -ModuleName $script:dscModuleName {
                $script:LogDirectoryCreated = $false
                Mock Test-PathWrapper { $false }
                Mock New-ItemDirectoryWrapper { throw [System.IO.IOException]::new('Race condition') }

                { Write-ToLog -Message 'Test' -Level INFO } | Should -Throw
            }
        }
    }

    Context 'When the log mutex cannot be acquired' {
        It 'Should warn and skip the write without throwing' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Add-ContentWrapper
                Mock Test-PathWrapper { $false }
                Mock Write-Warning

                $fakeMutex = [PSCustomObject]@{}
                $fakeMutex | Add-Member -MemberType ScriptMethod -Name WaitOne -Value { param($Timeout) $false }
                $script:LogMutex = $fakeMutex

                { Write-ToLog -Message 'Test' -Level INFO } | Should -Not -Throw

                Should -Invoke Write-Warning -Times 1 -ParameterFilter {
                    $Message -match 'Failed to acquire log mutex'
                }
                Should -Invoke Add-ContentWrapper -Times 0
            }
        }
    }

    Context 'When the log write itself fails' {
        It 'Should warn and return $false via PassThru' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Add-ContentWrapper { throw 'Access denied' }
                Mock Test-PathWrapper { $false }
                Mock Write-Warning

                $result = Write-ToLog -Message 'Test' -Level INFO -PassThru

                $result | Should -BeFalse
                Should -Invoke Write-Warning -Times 1 -ParameterFilter {
                    $Message -match 'Failed to write log entry'
                }
            }
        }
    }

    Context 'When validating parameters' {
        It 'Should throw on an invalid level value' {
            InModuleScope -ModuleName $script:dscModuleName {
                { Write-ToLog -Message 'Test' -Level 'INVALID' } | Should -Throw
            }
        }
    }
}
