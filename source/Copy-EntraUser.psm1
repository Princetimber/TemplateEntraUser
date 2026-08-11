<#
    Development-time module loader. During development, this file dot-sources all
    .ps1 files from Private/ and Public/ so you can import the module directly.

    At build time, Sampler/ModuleBuilder compiles a different .psm1 into the
    output folder that inlines all function definitions into a single file.
    Do not add runtime logic here that you expect to survive the build.
#>

# Dot-source private functions. Import must fail if any source file is invalid.
$privateFunctions = Get-ChildItem -Path $PSScriptRoot\Private\*.ps1 -Recurse
foreach ($function in $privateFunctions) {
    . $function.FullName
}

# Dot-source and export public functions.
$publicFunctions = Get-ChildItem -Path $PSScriptRoot\Public\*.ps1 -Recurse
foreach ($function in $publicFunctions) {
    . $function.FullName
    Export-ModuleMember -Function $function.BaseName
}
