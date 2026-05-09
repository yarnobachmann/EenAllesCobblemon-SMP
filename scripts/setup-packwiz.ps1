$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

Write-Host "Checking packwiz setup in $Root"

$packwiz = Get-Command packwiz -ErrorAction SilentlyContinue
if ($packwiz) {
    Write-Host "packwiz found: $($packwiz.Source)"
    & packwiz --version
} else {
    Write-Warning "packwiz was not found on PATH."
    Write-Host "Install options:"
    Write-Host "  1. Download a Windows release from https://github.com/packwiz/packwiz/releases"
    Write-Host "  2. Put packwiz.exe in a folder on PATH"
    Write-Host "  3. Re-run: .\scripts\setup-packwiz.ps1"
}

$java = Get-Command java -ErrorAction SilentlyContinue
if ($java) {
    Write-Host "java found: $($java.Source)"
    & java -version
    Write-Warning "Minecraft 1.21.1 normally needs Java 21 in Prism. The Java shown above is only your shell PATH Java."
} else {
    Write-Warning "java was not found on PATH. Prism can still use its own Java runtime."
}

if (-not (Test-Path ".\deployment.json") -and (Test-Path ".\deployment.example.json")) {
    Write-Host "Copy deployment.example.json to deployment.json and edit it when you are ready to build a real Prism zip."
}

if (Test-Path ".\pack.toml") {
    Write-Host "pack.toml exists."
} else {
    Write-Warning "pack.toml is missing."
}

if (Test-Path ".\index.toml") {
    Write-Host "index.toml exists."
} else {
    Write-Warning "index.toml is missing. Run .\scripts\refresh-pack.ps1 after pack.toml exists."
}
