#Requires -Version 7.0

function Format-GreetingMessage {
    <#
    .SYNOPSIS
        Formats a greeting message based on the specified style.

    .DESCRIPTION
        Private helper function that creates a formatted greeting string.
        Supports multiple greeting styles and handles edge cases such as
        whitespace-only names. This function is called by the public
        Get-Greeting function and should not be invoked directly.

        As a private function, ShouldProcess is handled by the calling
        public function.

    .PARAMETER Name
        The name of the person or entity to greet.
        Leading and trailing whitespace is automatically trimmed.

    .PARAMETER Style
        The greeting style to apply. Determines the greeting format:
        - Formal: "Good day, NAME."
        - Casual: "Hey NAME!"
        - Professional: "Hello NAME, welcome."

    .EXAMPLE
        Format-GreetingMessage -Name "Alice" -Style Formal

        Returns: "Good day, Alice."

    .EXAMPLE
        Format-GreetingMessage -Name "Bob" -Style Casual

        Returns: "Hey Bob!"

    .EXAMPLE
        Format-GreetingMessage -Name "Carol" -Style Professional

        Returns: "Hello Carol, welcome."

    .OUTPUTS
        [string]
            The formatted greeting message.

    .NOTES
        This is a private helper function. ShouldProcess is not required here
        as the public wrapper (Get-Greeting) handles confirmation.
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern('\S')]
        [string]
        $Name,

        [Parameter()]
        [ValidateSet('Formal', 'Casual', 'Professional')]
        [string]
        $Style = 'Professional'
    )

    $trimmedName = $Name.Trim()

    $greeting = switch ($Style) {
        'Formal'       { "Good day, $trimmedName." }
        'Casual'       { "Hey $trimmedName!" }
        'Professional' { "Hello $trimmedName, welcome." }
    }

    Write-ToLog -Message "Formatted greeting: Style=$Style, Name=$trimmedName" -Level DEBUG

    return $greeting
}
