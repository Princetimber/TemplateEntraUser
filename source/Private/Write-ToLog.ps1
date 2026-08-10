#Requires -Version 7.0

# Timestamp format used for log file names and archives
$script:LogTimestampFormat = 'yyyyMMdd_HHmmss'

# Thread-safe, auto-rotating logger for TemplateModule.
# Entry point: Write-ToLog. Levels: INFO, DEBUG, WARN, ERROR, SUCCESS.

# ============================================================================
# LOG FILE CONFIGURATION
# ============================================================================

# Initialize log file path (backward compatible with $Global:LogFile)
# Uses helper function to isolate global variable access for ScriptAnalyzer compliance.
function Initialize-LogFilePath {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '',
        Justification = 'Required for backward compatibility with scripts that set $Global:LogFile before importing the module.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Private initializer - no external side effects, only sets module-scoped variable.')]
    [OutputType([string])]
    param()

    if (-not $Global:LogFile) {
        $Global:LogFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "TemplateModule_$([System.DateTimeOffset]::UtcNow.ToString($script:LogTimestampFormat)).log")
    }
    return $Global:LogFile
}

if (-not $script:LogFile) {
    $script:LogFile = Initialize-LogFilePath
}

# Log rotation settings
$script:MaxLogSizeBytes = 10MB  # Rotate when log exceeds this size
$script:MaxLogFiles = 5         # Keep this many rotated logs

$script:LogDirectoryCreated = $false
$script:LogMutex = $null

# Register cleanup handler to dispose mutex on module removal or PowerShell exit
$null = Register-EngineEvent -SourceIdentifier ([System.Management.Automation.PsEngineEvent]::Exiting) -Action {
    if ($script:LogMutex) {
        $script:LogMutex.Dispose()
        $script:LogMutex = $null
    }
}

# ============================================================================
# WRITE-TOLOG FUNCTION
# ============================================================================

# Appends a formatted, timestamped log entry to the module log file.
# Thread-safe via a named mutex. Auto-rotates at 10 MB (5 backups).
# Redacts passwords, tokens, keys, and secrets. Supports -Message and -ErrorRecord parameter sets.
function Write-ToLog {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Write-Host is intentional for colored console output in a logging function.')]
    param (
        [Parameter(
            Mandatory,
            ValueFromPipeline,
            Position = 0,
            ParameterSetName = 'Message'
        )]
        [AllowEmptyString()]
        [string]$Message,

        [Parameter(
            Position = 1,
            ParameterSetName = 'Message'
        )]
        [ValidateSet('INFO', 'DEBUG', 'WARN', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO',

        [Parameter(
            Mandatory,
            ParameterSetName = 'ErrorRecord'
        )]
        [System.Management.Automation.ErrorRecord]$ErrorRecord,

        [Parameter()]
        [switch]$NoConsole,

        [Parameter()]
        [switch]$PassThru
    )

    begin {
        # Sync script-scoped variable with global for backward compatibility
        if ($Global:LogFile -and $script:LogFile -ne $Global:LogFile) {
            $script:LogFile = $Global:LogFile
            $script:LogDirectoryCreated = $false  # Reset so new directory is validated
        }

        # Ensure log directory exists (once per invocation)
        if (-not $script:LogDirectoryCreated) {
            $logDir = Split-Path -Path $script:LogFile -Parent

            if ($logDir -and -not (Test-PathWrapper -LiteralPath $logDir)) {
                try {
                    $null = New-ItemDirectoryWrapper -Path $logDir
                } catch [System.IO.IOException] {
                    # Directory may have been created by another process
                    if (-not (Test-PathWrapper -LiteralPath $logDir)) {
                        throw
                    }
                }
            }
            $script:LogDirectoryCreated = $true
        }

        # Initialize mutex for thread safety (reuse existing if available)
        if (-not $script:LogMutex) {
            $script:LogMutex = [System.Threading.Mutex]::new($false, 'Global\TemplateModuleLog')
        }
    }

    process {
        # Process ErrorRecord if provided
        if ($PSCmdlet.ParameterSetName -eq 'ErrorRecord') {
            $Message = $ErrorRecord.Exception.Message
            $Level = 'ERROR'

            # Add additional error details
            $errorDetails = @"
Exception Type: $($ErrorRecord.Exception.GetType().FullName)
Category: $($ErrorRecord.CategoryInfo.Category)
Target: $($ErrorRecord.TargetObject)
"@

            if ($ErrorRecord.InvocationInfo) {
                $errorDetails += @"

Location: $($ErrorRecord.InvocationInfo.ScriptName):$($ErrorRecord.InvocationInfo.ScriptLineNumber)
Command: $($ErrorRecord.InvocationInfo.Line.Trim())
"@
            }

            if ($ErrorRecord.Exception.InnerException) {
                $errorDetails += @"

Inner Exception: $($ErrorRecord.Exception.InnerException.Message)
"@
            }

            # Log main message first, then details as DEBUG
            $mainResult = Write-ToLog -Message $Message -Level 'ERROR' -NoConsole:$NoConsole -PassThru
            $detailResult = Write-ToLog -Message $errorDetails -Level 'DEBUG' -NoConsole:$NoConsole -PassThru

            if ($PassThru) {
                return ($mainResult -and $detailResult)
            }
            return
        }

        # Redact sensitive information from log messages (case-insensitive)
        $sanitizedMessage = $Message

        # Pattern 1: key=value format
        $sanitizedMessage = $sanitizedMessage -replace '(?i)(password|token|key|secret|apikey|api_key|access_key|auth)=\S+', '$1=***REDACTED***'

        # Pattern 2: JSON format
        $sanitizedMessage = $sanitizedMessage -replace '(?i)(password|token|key|secret|apikey|api_key|access_key|auth)"\s*:\s*"[^"]*"', '$1": "***REDACTED***"'

        # Pattern 3: XML/HTML format - preserve closing tag
        $sanitizedMessage = $sanitizedMessage -replace '(?i)<(password|token|key|secret|apikey|api_key|access_key|auth)>[^<]*</(password|token|key|secret|apikey|api_key|access_key|auth)>', '<$1>***REDACTED***</$2>'

        # Pattern 4: Bearer token (e.g. an Authorization header)
        $sanitizedMessage = $sanitizedMessage -replace '(?i)\b(bearer)\s+\S+', '$1 ***REDACTED***'

        # Pattern 5: unquoted 'key: value' form. The negative lookbehind/lookahead on a
        # quote keep this from re-touching the quoted JSON form handled by Pattern 2.
        $sanitizedMessage = $sanitizedMessage -replace '(?i)(?<![\"''])\b(password|token|key|secret|apikey|api_key|access_key|auth)\b\s*:\s*(?![\"''])\S+', '$1: ***REDACTED***'

        $timestamp = [System.DateTimeOffset]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss')
        $entry = "[$timestamp] [$Level] $sanitizedMessage"

        $success = $true

        if ($PSCmdlet.ShouldProcess($script:LogFile, "Write log entry: $Level")) {
            # Thread-safe file write using mutex
            $mutexAcquired = $false
            try {
                $mutexAcquired = $script:LogMutex.WaitOne(10000)  # 10-second timeout to prevent deadlock
                if (-not $mutexAcquired) {
                    Write-Warning "Failed to acquire log mutex within 10 seconds. Log entry may be lost."
                    $success = $false
                    return
                }

                # Check if log rotation is needed (inside mutex to prevent race conditions)
                if ((Test-PathWrapper -LiteralPath $script:LogFile) -and
                    (Get-ItemWrapper -LiteralPath $script:LogFile).Length -gt $script:MaxLogSizeBytes) {

                    try {
                        Write-Verbose "Log file exceeds $($script:MaxLogSizeBytes / 1MB)MB, rotating..."
                        Invoke-LogRotation
                    } catch {
                        Write-Warning "Log rotation failed: $($_.Exception.Message). Continuing without rotation."
                    }
                }

                # UTF-8 without BOM is default in PowerShell 7+
                # IMPORTANT: Using Add-Content appends to existing file
                Add-ContentWrapper -LiteralPath $script:LogFile -Value $entry
            } catch {
                $errorMsg = "Failed to write log entry to '{0}': {1}" -f $script:LogFile, $_.Exception.Message
                Write-Warning $errorMsg
                $success = $false
            } finally {
                if ($mutexAcquired -and $script:LogMutex) {
                    $script:LogMutex.ReleaseMutex()
                }
            }
        }

        # Console output with ANSI colors (PowerShell 7.2+ PSStyle, fallback to escape codes)
        if (-not $NoConsole) {
            if ($PSStyle) {
                $colorRed = $PSStyle.Foreground.Red
                $colorYellow = $PSStyle.Foreground.Yellow
                $colorGreen = $PSStyle.Foreground.Green
                $colorCyan = $PSStyle.Foreground.Cyan
                $colorReset = $PSStyle.Reset
            } else {
                $colorRed = "`e[31m"
                $colorYellow = "`e[33m"
                $colorGreen = "`e[32m"
                $colorCyan = "`e[36m"
                $colorReset = "`e[0m"
            }

            switch ($Level) {
                'ERROR' {
                    Write-Host "${colorRed}✗ $sanitizedMessage${colorReset}"
                }
                'WARN' {
                    Write-Host "${colorYellow}⚠ $sanitizedMessage${colorReset}"
                }
                'SUCCESS' {
                    Write-Host "${colorGreen}✓ $sanitizedMessage${colorReset}"
                }
                'DEBUG' {
                    Write-Verbose -Message $sanitizedMessage
                }
                default {
                    Write-Host "${colorCyan}ℹ $sanitizedMessage${colorReset}"
                }
            }
        }

        if ($PassThru) {
            return $success
        }
    }

    end {
        # Cleanup is handled by caller or module removal
    }
}

# ============================================================================
# WRAPPER FUNCTIONS FOR MOCKABILITY
# ============================================================================

# Wraps Test-Path for Pester mocking.
function Test-PathWrapper {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [string]
        $Path,

        [Parameter(Mandatory, ParameterSetName = 'LiteralPath')]
        [string]
        $LiteralPath,

        [Parameter(ParameterSetName = 'Path')]
        [ValidateSet('Any', 'Container', 'Leaf')]
        [string]
        $PathType
    )

    if ($PSCmdlet.ParameterSetName -eq 'LiteralPath') {
        return Test-Path -LiteralPath $LiteralPath
    }

    if ($PathType) {
        return Test-Path -Path $Path -PathType $PathType
    }

    return Test-Path -Path $Path
}

# Wraps New-Item -ItemType Directory for Pester mocking.
function New-ItemDirectoryWrapper {
    [CmdletBinding()]
    [OutputType([System.IO.DirectoryInfo])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Wrapper function; ShouldProcess handled by calling function.')]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    return New-Item -Path $Path -ItemType Directory -Force -ErrorAction Stop
}

# Wraps Get-Item for Pester mocking.
function Get-ItemWrapper {
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [string]$LiteralPath
    )

    return Get-Item -LiteralPath $LiteralPath
}

# Wraps Add-Content for Pester mocking.
function Add-ContentWrapper {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Wrapper function; ShouldProcess handled by calling function.')]
    param(
        [Parameter(Mandatory)]
        [string]$LiteralPath,

        [Parameter(Mandatory)]
        [string]$Value
    )

    Add-Content -LiteralPath $LiteralPath -Value $Value -ErrorAction Stop
}
