# Runs a Microsoft Graph SDK call (as a scriptblock) with retry/backoff for
# throttling (429) and transient service unavailability (503). Honors a
# Retry-After header when the underlying exception exposes one; otherwise
# falls back to exponential backoff. Any other error, or exhausting
# -MaxRetryCount, rethrows the original terminating error unchanged.
function Invoke-EntraGraphRequestWithRetry {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [scriptblock] $ScriptBlock,

        [Parameter()]
        [ValidateRange(1, 10)]
        [int] $MaxRetryCount = 5,

        [Parameter()]
        [ValidateRange(1, 300)]
        [int] $BaseDelaySeconds = 2
    )

    $attempt = 0
    while ($true) {
        try {
            return & $ScriptBlock
        }
        catch {
            $attempt++

            $statusCode = $null
            $response = $_.Exception.Response
            if ($response) {
                try { $statusCode = [int]$response.StatusCode } catch { $statusCode = $null }
            }
            if (-not $statusCode -and $_.Exception.PSObject.Properties['ResponseStatusCode']) {
                $statusCode = [int]$_.Exception.ResponseStatusCode
            }

            $isRetryable = $statusCode -in 429, 503
            if (-not $isRetryable -or $attempt -ge $MaxRetryCount) {
                throw
            }

            $retryAfterSeconds = $null
            if ($response -and $response.Headers -and $response.Headers['Retry-After']) {
                $parsedRetryAfter = 0
                if ([int]::TryParse([string]$response.Headers['Retry-After'], [ref] $parsedRetryAfter)) {
                    $retryAfterSeconds = $parsedRetryAfter
                }
            }

            $delaySeconds = if ($null -ne $retryAfterSeconds) {
                $retryAfterSeconds
            }
            else {
                $BaseDelaySeconds * [Math]::Pow(2, $attempt - 1)
            }

            Write-Verbose "Graph request throttled/unavailable (status $statusCode); retrying in $delaySeconds second(s) (attempt $attempt of $MaxRetryCount)."
            Start-Sleep -Seconds $delaySeconds
        }
    }
}
