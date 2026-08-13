# Escapes a value for safe interpolation into an OData $filter string literal.
# OData string literals delimit on a single quote; doubling any embedded quote
# prevents a value containing one from breaking out of the filter literal and
# redirecting the query to a different principal/object.
function ConvertTo-EscapedODataString {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Value
    )

    return $Value.Replace("'", "''")
}
