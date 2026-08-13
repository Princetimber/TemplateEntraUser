#Requires -Version 7.0
BeforeAll {
    $script:dscModuleName = 'Copy-EntraUser'
    Import-Module -Name $script:dscModuleName -Force

    function script:New-TestGraphHttpException {
        param(
            [int] $StatusCode,
            [string] $RetryAfter
        )

        $response = [pscustomobject]@{
            StatusCode = [System.Net.HttpStatusCode] $StatusCode
            Headers    = @{ 'Retry-After' = $RetryAfter }
        }
        $exception = [System.Exception]::new('Simulated Graph HTTP error')
        $exception | Add-Member -MemberType NoteProperty -Name Response -Value $response -Force
        return $exception
    }
}

AfterAll {
    Get-Module -Name $script:dscModuleName -All | Remove-Module -Force
}

Describe 'Invoke-EntraGraphRequestWithRetry' {
    Context 'The scriptblock succeeds on the first attempt' {
        It 'Returns its result without sleeping' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Start-Sleep { }

                $result = Invoke-EntraGraphRequestWithRetry -ScriptBlock { 'ok' }

                $result | Should -Be 'ok'
                Should -Invoke Start-Sleep -Times 0
            }
        }
    }

    Context 'A 429 (throttled) error is retried and then succeeds' {
        It 'Retries and returns the eventual result' {
            $throttledException = New-TestGraphHttpException -StatusCode 429 -RetryAfter '1'

            InModuleScope -ModuleName $script:dscModuleName -Parameters @{ throttledException = $throttledException } {
                param($throttledException)

                Mock Start-Sleep { }
                $script:callCount = 0

                $result = Invoke-EntraGraphRequestWithRetry -ScriptBlock {
                    $script:callCount++
                    if ($script:callCount -lt 2) {
                        throw $throttledException
                    }
                    'ok-after-retry'
                }

                $result | Should -Be 'ok-after-retry'
                Should -Invoke Start-Sleep -Times 1
            }
        }
    }

    Context 'A non-retryable error is rethrown immediately' {
        It 'Never sleeps and rethrows the original error' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Start-Sleep { }

                { Invoke-EntraGraphRequestWithRetry -ScriptBlock { throw 'Simulated non-retryable failure' } } |
                    Should -Throw '*Simulated non-retryable failure*'
                Should -Invoke Start-Sleep -Times 0
            }
        }
    }

    Context 'Retries are exhausted' {
        It 'Rethrows after -MaxRetryCount attempts' {
            $unavailableException = New-TestGraphHttpException -StatusCode 503 -RetryAfter $null

            InModuleScope -ModuleName $script:dscModuleName -Parameters @{ unavailableException = $unavailableException } {
                param($unavailableException)

                Mock Start-Sleep { }

                {
                    Invoke-EntraGraphRequestWithRetry -MaxRetryCount 2 -ScriptBlock {
                        throw $unavailableException
                    }
                } | Should -Throw '*Simulated Graph HTTP error*'

                Should -Invoke Start-Sleep -Times 1
            }
        }
    }
}
