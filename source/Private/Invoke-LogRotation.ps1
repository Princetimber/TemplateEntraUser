#Requires -Version 7.0

# Rotates log files: shifts numbered backups up (log.4→removed, log.3→log.4, ..., log→log.1).
# Called inside the Write-ToLog mutex — do NOT call this function directly.
function Invoke-LogRotation {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param()

    try {
        # Don't rotate if file doesn't exist
        if (-not (Test-PathWrapper -LiteralPath $script:LogFile)) {
            return
        }

        # Remove oldest log file if it exists
        $oldestLog = "$script:LogFile.$script:MaxLogFiles"
        if (Test-PathWrapper -LiteralPath $oldestLog) {
            if ($PSCmdlet.ShouldProcess($oldestLog, 'Remove oldest rotated log file')) {
                Remove-ItemWrapper -LiteralPath $oldestLog
            }
        }

        # Shift existing rotated logs up
        for ($i = $script:MaxLogFiles - 1; $i -ge 1; $i--) {
            $currentLog = "$script:LogFile.$i"
            $nextLog = "$script:LogFile.$($i + 1)"

            if (Test-PathWrapper -LiteralPath $currentLog) {
                if ($PSCmdlet.ShouldProcess("$currentLog -> $nextLog", 'Shift rotated log file')) {
                    Move-ItemWrapper -LiteralPath $currentLog -Destination $nextLog
                }
            }
        }

        # Rotate current log to .1
        if ($PSCmdlet.ShouldProcess("$($script:LogFile) -> $($script:LogFile).1", 'Rotate current log file')) {
            Move-ItemWrapper -LiteralPath $script:LogFile -Destination "$script:LogFile.1"
        }

        Write-Verbose "Log rotated: $script:LogFile -> $script:LogFile.1"
    } catch {
        Write-Warning "Failed to rotate log file: $($_.Exception.Message)"
    }
}

# Move-ItemWrapper and Remove-ItemWrapper (used above for Pester mockability)
# now live in their own files under source/Private/, per the project's
# one-function-per-file convention.
