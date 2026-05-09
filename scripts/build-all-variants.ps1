$ErrorActionPreference = "Stop"

$ScriptRoot = $PSScriptRoot

& "$ScriptRoot\build-prism-zip.ps1" -Variant "full"
