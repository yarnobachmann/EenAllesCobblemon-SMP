param(
    [string]$PackRoot = ".",
    [string[]]$ExcludePackPaths = @()
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$PackRootPath = if ($PackRoot -eq ".") {
    $RepoRoot
} else {
    Join-Path $RepoRoot $PackRoot
}

if (-not (Test-Path -LiteralPath $PackRootPath -PathType Container)) {
    throw "Pack root not found: $PackRoot"
}

function ConvertTo-PackPath {
    param([string]$Path)
    $fullRoot = (Resolve-Path -LiteralPath $PackRootPath).Path.TrimEnd("\", "/")
    $fullPath = (Resolve-Path -LiteralPath $Path).Path
    $relative = $fullPath.Substring($fullRoot.Length).TrimStart("\", "/")
    return ($relative -replace "\\", "/")
}

function Get-Sha256 {
    param([string]$Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Set-Utf8NoBom {
    param(
        [string]$Path,
        [string]$Value
    )
    $Value = $Value -replace "`r`n", "`n"
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText((Join-Path $PackRootPath $Path), $Value, $encoding)
}

function Add-IndexedFile {
    param(
        [System.Collections.Generic.List[object]]$Files,
        [string]$Path,
        [bool]$Metafile
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return
    }

    if (Test-PackPathExcluded $Path) {
        return
    }

    $Files.Add([pscustomobject]@{
        file = ConvertTo-PackPath $Path
        hash = Get-Sha256 $Path
        metafile = $Metafile
    })
}

$packTomlPath = Join-Path $PackRootPath "pack.toml"
if (-not (Test-Path -LiteralPath $packTomlPath -PathType Leaf)) {
    throw "pack.toml is missing at $PackRoot\pack.toml"
}

$indexed = [System.Collections.Generic.List[object]]::new()
$managedModJars = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$managedContentFiles = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$excludedPackPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$excludedPackPrefixes = [System.Collections.Generic.List[string]]::new()

@(
    "config/jei/world/",
    "config/litematica/"
) | ForEach-Object { $excludedPackPrefixes.Add($_) }

@(
    "config/defaultoptions/servers.dat",
    "config/voicechat/username-cache.json",
    "fancymenu_data/last_world.fmdata"
) | ForEach-Object { [void]$excludedPackPaths.Add($_) }

foreach ($excluded in $ExcludePackPaths) {
    if (-not [string]::IsNullOrWhiteSpace($excluded)) {
        [void]$excludedPackPaths.Add(($excluded -replace "\\", "/"))
    }
}

function Test-PackPathExcluded {
    param([string]$Path)
    $packPath = ConvertTo-PackPath $Path
    if ($excludedPackPaths.Contains($packPath)) {
        return $true
    }
    foreach ($prefix in $excludedPackPrefixes) {
        if ($packPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

$modsPath = Join-Path $PackRootPath "mods"
if (Test-Path -LiteralPath $modsPath -PathType Container) {
    Get-ChildItem -LiteralPath $modsPath -Filter "*.pw.toml" -File -ErrorAction SilentlyContinue | Sort-Object FullName | ForEach-Object {
        if (Test-PackPathExcluded $_.FullName) {
            return
        }
        $content = Get-Content -Raw -LiteralPath $_.FullName
        if ($content -match '(?m)^filename\s*=\s*"([^"]+)"') {
            [void]$managedModJars.Add($Matches[1])
        }
        Add-IndexedFile -Files $indexed -Path $_.FullName -Metafile $true
    }

    Get-ChildItem -LiteralPath $modsPath -Filter "*.jar" -File -ErrorAction SilentlyContinue | Sort-Object FullName | ForEach-Object {
        if (Test-PackPathExcluded $_.FullName) {
            return
        }
        if (-not $managedModJars.Contains($_.Name)) {
            Add-IndexedFile -Files $indexed -Path $_.FullName -Metafile $false
        }
    }
}

function Add-MetafilesForDirectory {
    param(
        [string]$DirectoryName,
        [System.Collections.Generic.HashSet[string]]$ManagedFiles
    )

    $directoryPath = Join-Path $PackRootPath $DirectoryName
    if (-not (Test-Path -LiteralPath $directoryPath -PathType Container)) {
        return
    }

    Get-ChildItem -LiteralPath $directoryPath -Filter "*.pw.toml" -File -ErrorAction SilentlyContinue | Sort-Object FullName | ForEach-Object {
        if (Test-PackPathExcluded $_.FullName) {
            return
        }
        $content = Get-Content -Raw -LiteralPath $_.FullName
        if ($content -match '(?m)^filename\s*=\s*"([^"]+)"') {
            [void]$ManagedFiles.Add("$DirectoryName/$($Matches[1])")
        }
        Add-IndexedFile -Files $indexed -Path $_.FullName -Metafile $true
    }
}

Add-MetafilesForDirectory -DirectoryName "resourcepacks" -ManagedFiles $managedContentFiles

$contentDirs = @(
    "config",
    "defaultconfigs",
    "kubejs",
    "resourcepacks",
    "shaderpacks",
    "datapacks",
    "cobblemon",
    "cobblenav",
    "fancymenu_data"
)

foreach ($dir in $contentDirs) {
    $dirPath = Join-Path $PackRootPath $dir
    if (Test-Path -LiteralPath $dirPath -PathType Container) {
        Get-ChildItem -LiteralPath $dirPath -File -Recurse | Sort-Object FullName | ForEach-Object {
            $packPath = ConvertTo-PackPath $_.FullName
            if ($managedContentFiles.Contains($packPath)) {
                return
            }
            if ($_.Name.EndsWith(".pw.toml", [System.StringComparison]::OrdinalIgnoreCase)) {
                return
            }
            Add-IndexedFile -Files $indexed -Path $_.FullName -Metafile $false
        }
    }
}

$rootFiles = @(
    "servers.dat"
)

foreach ($file in $rootFiles) {
    Add-IndexedFile -Files $indexed -Path (Join-Path $PackRootPath $file) -Metafile $false
}

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('hash-format = "sha256"')
$lines.Add("")

foreach ($entry in ($indexed | Sort-Object file)) {
    $lines.Add("[[files]]")
    $lines.Add("file = `"$($entry.file)`"")
    $lines.Add("hash = `"$($entry.hash)`"")
    $lines.Add("metafile = $($entry.metafile.ToString().ToLowerInvariant())")
    $lines.Add("")
}

$indexText = $lines -join "`n"
Set-Utf8NoBom -Path "index.toml" -Value $indexText

$indexHash = Get-Sha256 (Join-Path $PackRootPath "index.toml")
$packText = Get-Content -Raw -LiteralPath $packTomlPath
if ($packText -match '(?s)(\[index\].*?hash\s*=\s*")[^"]+(")') {
    $packText = [regex]::Replace($packText, '(?s)(\[index\].*?hash\s*=\s*")[^"]+(")', "`${1}$indexHash`${2}", 1)
} else {
    throw "Could not find [index] hash in $PackRoot\pack.toml."
}
Set-Utf8NoBom -Path "pack.toml" -Value $packText

Write-Host "Indexed $($indexed.Count) files for $PackRoot."
Write-Host "index.toml sha256: $indexHash"
