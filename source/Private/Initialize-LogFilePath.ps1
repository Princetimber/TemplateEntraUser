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
        $Global:LogFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "Copy-EntraUser_$([System.DateTimeOffset]::UtcNow.ToString($script:LogTimestampFormat)).log")
    }
    return $Global:LogFile
}
