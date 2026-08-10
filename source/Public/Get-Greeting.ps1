#Requires -Version 7.0

function Get-Greeting {
    <#
    .SYNOPSIS
        Generates a personalized greeting message.

    .DESCRIPTION
        Creates a formatted greeting message for the specified recipient.
        Demonstrates PowerShell patterns including comprehensive input
        validation, pipeline support, and PassThru for rich object output.

        The function delegates message formatting to the private helper
        Format-GreetingMessage and logs all operations.

    .PARAMETER Name
        The name of the person or entity to greet. Must not be null or empty.
        Accepts pipeline input by value.

    .PARAMETER Style
        The greeting style to use. Valid options are:
        - Formal: Professional greeting (e.g., "Good day, NAME.")
        - Casual: Friendly greeting (e.g., "Hey NAME!")
        - Professional: Business greeting (e.g., "Hello NAME, welcome.")
        Default is 'Professional'.

    .PARAMETER PassThru
        Returns a rich PSCustomObject containing the greeting details instead of
        just the greeting string. Useful for pipeline processing and automation.

    .EXAMPLE
        Get-Greeting -Name "World"

        Generates a professional greeting: "Hello World, welcome."

    .EXAMPLE
        Get-Greeting -Name "Alice" -Style Formal -PassThru

        Returns a rich object with greeting details:
        Name     : Alice
        Style    : Formal
        Message  : Good day, Alice.
        Created  : 2025-01-15 10:30:00

    .EXAMPLE
        "Bob", "Carol" | Get-Greeting -Style Casual

        Generates casual greetings for multiple recipients via pipeline:
        Hey Bob!
        Hey Carol!

    .OUTPUTS
        [string]
            The formatted greeting message (default behavior).

        [PSCustomObject]
            When -PassThru is specified, returns an object with properties:
            Name, Style, Message, Created.

    .NOTES
        This is an example function demonstrating PowerShell patterns.
        Replace this function with your own module logic after running
        Initialize-Template.ps1.
    #>

    [CmdletBinding()]
    [OutputType([string])]
    [OutputType([PSCustomObject], ParameterSetName = 'PassThru')]
    param (
        [Parameter(
            Position = 0,
            Mandatory,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName
        )]
        [ValidateNotNullOrEmpty()]
        [string]
        $Name,

        [Parameter(Position = 1)]
        [ValidateSet('Formal', 'Casual', 'Professional')]
        [string]
        $Style = 'Professional',

        [Parameter()]
        [switch]
        $PassThru
    )

    begin {
        Write-ToLog -Message "Get-Greeting invoked with Style='$Style'" -Level INFO
    }

    process {
        $greeting = Format-GreetingMessage -Name $Name -Style $Style

        if (-not $greeting) {
            $exception = [System.ArgumentException]::new(
                "Failed to format greeting for '$Name'."
            )
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'GreetingFormatFailed',
                [System.Management.Automation.ErrorCategory]::InvalidArgument,
                $Name
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        Write-ToLog -Message "Greeting generated for '$Name' with style '$Style'" -Level SUCCESS

        if ($PassThru) {
            return [PSCustomObject]@{
                PSTypeName = 'TemplateModule.GreetingResult'
                Name       = $Name
                Style      = $Style
                Message    = $greeting
                Created    = Get-Date
            }
        }

        return $greeting
    }

    end {
        Write-ToLog -Message "Get-Greeting completed" -Level INFO
    }
}
