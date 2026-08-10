#Requires -Version 7.0

function Export-Greeting {
    <#
    .SYNOPSIS
        Exports greeting messages to a file on disk.

    .DESCRIPTION
        Writes one or more greeting strings to a specified file path. This is a
        state-changing operation that correctly uses SupportsShouldProcess to
        enable -WhatIf and -Confirm. Accepts greeting strings from the pipeline,
        including output from Get-Greeting. Use -Append to add to an existing
        file, -Force to overwrite without prompting, and -PassThru to return the
        resulting FileInfo object.

    .PARAMETER Greeting
        One or more greeting strings to write to the file. Accepts pipeline
        input by value. Alias: Message (for binding with Get-Greeting -PassThru).

    .PARAMETER FilePath
        The full path to the output file. The parent directory must exist
        unless the directory is created beforehand.

    .PARAMETER Append
        Appends greetings to the file instead of overwriting it. Without this
        switch, an existing file causes a terminating error unless -Force is used.

    .PARAMETER Force
        Overwrites an existing file without prompting for confirmation.

    .PARAMETER PassThru
        Returns the System.IO.FileInfo object for the written file after the
        export completes.

    .EXAMPLE
        Export-Greeting -Greeting 'Hello World, welcome.' -FilePath './greetings.txt'

        Writes a single greeting to greetings.txt in the current directory.

    .EXAMPLE
        Get-Greeting -Name 'Alice', 'Bob' | Export-Greeting -FilePath './greetings.txt'

        Pipes greeting strings from Get-Greeting into a file.

    .EXAMPLE
        Export-Greeting -Greeting 'Hey Carol!' -FilePath './greetings.txt' -Append

        Appends a greeting to an existing file.

    .EXAMPLE
        Export-Greeting -Greeting 'Hello World, welcome.' -FilePath './out.txt' -WhatIf

        Shows what would happen without writing to disk.

    .OUTPUTS
        [System.IO.FileInfo]
            When -PassThru is specified, returns the FileInfo for the output file.

    .NOTES
        This function demonstrates the correct use of SupportsShouldProcess for
        state-changing operations. Read-only functions like Get-Greeting should
        not use ShouldProcess.
    #>

    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([System.IO.FileInfo])]
    param (
        [Parameter(
            Mandatory,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            Position = 0
        )]
        [ValidateNotNullOrEmpty()]
        [Alias('Message')]
        [string[]]
        $Greeting,

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]
        $FilePath,

        [Parameter()]
        [switch]
        $Append,

        [Parameter()]
        [switch]
        $Force,

        [Parameter()]
        [switch]
        $PassThru
    )

    begin {
        $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($FilePath)
        $parentDir = Split-Path -Path $resolvedPath -Parent

        if ($parentDir -and -not (Test-Path -LiteralPath $parentDir)) {
            $exception = [System.IO.DirectoryNotFoundException]::new(
                "The directory '$parentDir' does not exist."
            )
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'DirectoryNotFound',
                [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                $parentDir
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        if (-not $Append -and -not $Force -and (Test-Path -LiteralPath $resolvedPath)) {
            $exception = [System.IO.IOException]::new(
                "The file '$resolvedPath' already exists. Use -Force to overwrite or -Append to add to it."
            )
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'FileAlreadyExists',
                [System.Management.Automation.ErrorCategory]::ResourceExists,
                $resolvedPath
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        $collectedGreetings = [System.Collections.Generic.List[string]]::new()
    }

    process {
        foreach ($line in $Greeting) {
            $collectedGreetings.Add($line)
        }
    }

    end {
        if ($collectedGreetings.Count -eq 0) {
            return
        }

        $action = if ($Append) { 'Append to' } else { 'Write to' }
        $target = "$resolvedPath ($($collectedGreetings.Count) greeting(s))"

        if ($PSCmdlet.ShouldProcess($target, $action)) {
            if ($Append) {
                Add-Content -LiteralPath $resolvedPath -Value $collectedGreetings -ErrorAction Stop
            }
            else {
                Set-Content -LiteralPath $resolvedPath -Value $collectedGreetings -Force -ErrorAction Stop
            }

            Write-ToLog -Message "Exported $($collectedGreetings.Count) greeting(s) to '$resolvedPath'" -Level SUCCESS

            if ($PassThru) {
                return Get-Item -LiteralPath $resolvedPath
            }
        }
    }
}
