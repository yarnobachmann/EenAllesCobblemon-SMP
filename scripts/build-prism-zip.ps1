param(
    [string]$Variant
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

function Read-DeploymentConfig {
    $configPath = ".\deployment.json"
    if (-not (Test-Path $configPath)) {
        $configPath = ".\deployment.example.json"
    }
    if (-not (Test-Path $configPath)) {
        throw "deployment.example.json is missing."
    }
    return Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
}

function Resolve-VariantConfig {
    param(
        [object]$DeploymentConfig,
        [string]$RequestedVariant
    )

    if ($DeploymentConfig.PSObject.Properties.Name -contains "variants") {
        $variantName = $RequestedVariant
        if ([string]::IsNullOrWhiteSpace($variantName)) {
            $variantName = $DeploymentConfig.defaultVariant
        }
        if ([string]::IsNullOrWhiteSpace($variantName)) {
            $variantName = "full"
        }
        $variantConfig = $DeploymentConfig.variants.$variantName
        if ($null -eq $variantConfig) {
            throw "Variant '$variantName' was not found in deployment config."
        }
        return [pscustomobject]@{
            Name = $variantName
            Config = $variantConfig
        }
    }

    return [pscustomobject]@{
        Name = "full"
        Config = $DeploymentConfig
    }
}

function Get-PackVersion {
    param([string]$PackRootPath)
    $packText = Get-Content -Raw -LiteralPath (Join-Path $PackRootPath "pack.toml")
    if ($packText -match '(?m)^version\s*=\s*"([^"]+)"') {
        return $Matches[1]
    }
    return (Get-Date -Format "yyyyMMdd-HHmm")
}

function Set-Utf8NoBom {
    param(
        [string]$Path,
        [string]$Value
    )
    $Value = $Value -replace "`r`n", "`n"
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Value, $encoding)
}

function Resolve-BootstrapSource {
    param([string]$RepoRootPath)

    $repoCache = Join-Path $RepoRootPath ".cache\packwiz-installer-bootstrap.jar"
    if (Test-Path -LiteralPath $repoCache -PathType Leaf) {
        return $repoCache
    }

    $prismInstances = Join-Path $env:APPDATA "PrismLauncher\instances"
    if (Test-Path -LiteralPath $prismInstances -PathType Container) {
        $existing = Get-ChildItem -LiteralPath $prismInstances -Recurse -Filter "packwiz-installer-bootstrap.jar" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($null -ne $existing) {
            return $existing.FullName
        }
    }

    return $null
}

$deployment = Read-DeploymentConfig
$variantInfo = Resolve-VariantConfig -DeploymentConfig $deployment -RequestedVariant $Variant
$variantName = $variantInfo.Name
$config = $variantInfo.Config

$packRoot = if ([string]::IsNullOrWhiteSpace($config.packRoot)) { "." } else { [string]$config.packRoot }
$packRootPath = if ($packRoot -eq ".") { $RepoRoot } else { Join-Path $RepoRoot $packRoot }

if ($variantName -eq "lite") {
    & "$PSScriptRoot\sync-lite.ps1"
}

& "$PSScriptRoot\refresh-pack.ps1" -PackRoot $packRoot

$instanceName = $config.instanceName
$minecraftVersion = $config.minecraftVersion
$loaderName = if ($config.PSObject.Properties.Name -contains "loaderName") { [string]$config.loaderName } else { "Fabric Loader" }
$loaderUid = if ($config.PSObject.Properties.Name -contains "loaderUid") { [string]$config.loaderUid } else { "net.fabricmc.fabric-loader" }
$loaderVersion = $config.loaderVersion
$packUrl = $config.packUrl
$memoryMb = $config.memoryMb
$jvmArgs = if ($config.PSObject.Properties.Name -contains "jvmArgs") { [string]$config.jvmArgs } else { "" }
$iconFile = $config.iconFile
$iconKey = $config.iconKey
$publishedZipPath = $config.publishedZipPath
$distFolder = if ([string]::IsNullOrWhiteSpace($config.distFolder)) { "dist" } else { [string]$config.distFolder }

if ([string]::IsNullOrWhiteSpace($instanceName)) { throw "instanceName is missing from deployment config." }
if ([string]::IsNullOrWhiteSpace($minecraftVersion)) { throw "minecraftVersion is missing from deployment config." }
if ([string]::IsNullOrWhiteSpace($loaderVersion)) { throw "loaderVersion is missing from deployment config." }
if ([string]::IsNullOrWhiteSpace($packUrl)) { throw "packUrl is missing from deployment config." }
if (-not $memoryMb) { $memoryMb = 6144 }
if ([string]::IsNullOrWhiteSpace($iconKey)) { $iconKey = "eak-season-3" }

$dist = Join-Path $RepoRoot $distFolder
$stagingRoot = Join-Path $dist "prism-staging-$variantName"
$minecraftRoot = Join-Path $stagingRoot "minecraft"
$bootstrapPath = Join-Path $minecraftRoot "packwiz-installer-bootstrap.jar"

if (Test-Path $stagingRoot) {
    Remove-Item -LiteralPath $stagingRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $minecraftRoot | Out-Null

$instanceCfg = @"
name=$instanceName
InstanceType=OneSix
MCLaunchMethod=LauncherPart
iconKey=$iconKey
OverrideCommands=true
PreLaunchCommand=`"`$INST_JAVA`" -jar packwiz-installer-bootstrap.jar $packUrl
OverrideMemory=true
MinMemAlloc=$memoryMb
MaxMemAlloc=$memoryMb
"@

if (-not [string]::IsNullOrWhiteSpace($jvmArgs)) {
    $instanceCfg += @"

OverrideJavaArgs=true
JvmArgs=$jvmArgs
"@
}

Set-Utf8NoBom -Path (Join-Path $stagingRoot "instance.cfg") -Value $instanceCfg

if (-not [string]::IsNullOrWhiteSpace($iconFile)) {
    $iconPath = Join-Path $RepoRoot $iconFile
    if (Test-Path -LiteralPath $iconPath -PathType Leaf) {
        Copy-Item -LiteralPath $iconPath -Destination (Join-Path $stagingRoot "$iconKey.png") -Force
    } else {
        Write-Warning "Configured icon file was not found: $iconFile"
    }
}

$mmcPack = [ordered]@{
    components = @(
        [ordered]@{
            cachedName = "Minecraft"
            important = $true
            uid = "net.minecraft"
            version = $minecraftVersion
        },
        [ordered]@{
            cachedName = $loaderName
            uid = $loaderUid
            version = $loaderVersion
        }
    )
    formatVersion = 1
}
Set-Utf8NoBom -Path (Join-Path $stagingRoot "mmc-pack.json") -Value ($mmcPack | ConvertTo-Json -Depth 5)

$bootstrapUrl = "https://github.com/packwiz/packwiz-installer-bootstrap/releases/latest/download/packwiz-installer-bootstrap.jar"
$bootstrapSource = Resolve-BootstrapSource -RepoRootPath $RepoRoot
if ($null -ne $bootstrapSource) {
    Copy-Item -LiteralPath $bootstrapSource -Destination $bootstrapPath -Force
} else {
    Invoke-WebRequest -Uri $bootstrapUrl -OutFile $bootstrapPath
}

$safeName = ($instanceName -replace '[^A-Za-z0-9._-]+', '-').Trim("-")
$version = Get-PackVersion -PackRootPath $packRootPath
$zipPath = Join-Path $dist "$safeName-$version-prism.zip"
if (Test-Path $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}

$stagingFiles = Get-ChildItem -LiteralPath $stagingRoot -Force
if (-not (Test-Path -LiteralPath $dist -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $dist | Out-Null
}
Compress-Archive -LiteralPath $stagingFiles.FullName -DestinationPath $zipPath -Force

if (-not [string]::IsNullOrWhiteSpace($publishedZipPath)) {
    $publishedZipFullPath = Join-Path $RepoRoot $publishedZipPath
    $publishedDir = Split-Path -Parent $publishedZipFullPath
    if (-not (Test-Path -LiteralPath $publishedDir -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $publishedDir | Out-Null
    }
    Copy-Item -LiteralPath $zipPath -Destination $publishedZipFullPath -Force
}

Remove-Item -LiteralPath $stagingRoot -Recurse -Force
Write-Host "Created $zipPath"
if (-not [string]::IsNullOrWhiteSpace($publishedZipPath)) {
    Write-Host "Published zip copy at $publishedZipPath"
}
