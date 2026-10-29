[CmdletBinding()]
param(
    [string]$OutputDirectory = "artifacts",
    [string]$Version
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($Version)) { $Version = (Get-Content -LiteralPath (Join-Path $PSScriptRoot "version.txt") -Raw).Trim() }
$toolRoot = Split-Path -Parent $PSScriptRoot
$outputRoot = [IO.Path]::GetFullPath((Join-Path (Get-Location) $OutputDirectory))
$stagingRoot = Join-Path $outputRoot "CSharpRuleKeeper-$Version"
$archivePath = Join-Path $outputRoot "CSharpRuleKeeper-$Version.zip"

& dotnet build (Join-Path $toolRoot "src\CSharpRuleKeeper.Analyzers\CSharpRuleKeeper.Analyzers.csproj") --configuration Release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if (Test-Path -LiteralPath $stagingRoot) { Remove-Item -LiteralPath $stagingRoot -Recurse -Force }
New-Item -ItemType Directory -Path (Join-Path $stagingRoot "build") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stagingRoot "analyzers") -Force | Out-Null

Copy-Item -LiteralPath (Join-Path $toolRoot "src\CSharpRuleKeeper.Analyzers\bin\Release\netstandard2.0\CSharpRuleKeeper.Analyzers.dll") -Destination (Join-Path $stagingRoot "analyzers")
foreach ($buildFile in @("Invoke-CSharpRuleKeeper.ps1", "Invoke-CSharpRuleKeeperHook.ps1", "New-CodingAgentChangeReport.ps1", "Show-CSharpRuleKeeperOptions.ps1", "CSharpRuleKeeper.targets", "version.txt"))
{
    Copy-Item -LiteralPath (Join-Path $toolRoot "build\$buildFile") -Destination (Join-Path $stagingRoot "build")
}
foreach ($folder in @("hooks", "docs", "config\presets"))
{
    $destination = Join-Path $stagingRoot $folder
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $toolRoot $folder) -Destination $destination -Recurse
}
foreach ($rootFile in @("README.md", "README_kr.md", "LICENSE", "CHANGELOG.md"))
{
    Copy-Item -LiteralPath (Join-Path $toolRoot $rootFile) -Destination $stagingRoot
}

$manifest = [ordered]@{
    name = "CSharpRuleKeeper"
    version = $Version
    analyzer = "analyzers/CSharpRuleKeeper.Analyzers.dll"
    entrypoint = "build/Invoke-CSharpRuleKeeper.ps1"
    hookEntrypoint = "build/Invoke-CSharpRuleKeeperHook.ps1"
    createdAt = [DateTimeOffset]::UtcNow.ToString("o")
}
$manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $stagingRoot "manifest.json") -Encoding UTF8
if (Test-Path -LiteralPath $archivePath) { Remove-Item -LiteralPath $archivePath -Force }
Compress-Archive -LiteralPath $stagingRoot -DestinationPath $archivePath

# Verify the archive from a clean folder: doctor, a clean fixture (exit 0) and a violating fixture (exit 1).
$verifyRoot = Join-Path ([IO.Path]::GetTempPath()) "CSharpRuleKeeper-verify-$([Guid]::NewGuid().ToString('N'))"
$isVerified = $false
try
{
    New-Item -ItemType Directory -Path $verifyRoot | Out-Null
    Expand-Archive -LiteralPath $archivePath -DestinationPath (Join-Path $verifyRoot "bundle")
    $checker = Join-Path $verifyRoot "bundle\CSharpRuleKeeper-$Version\build\Invoke-CSharpRuleKeeper.ps1"
    $fixture = Join-Path $verifyRoot "fixture"
    New-Item -ItemType Directory -Path $fixture | Out-Null
    "<Project Sdk=`"Microsoft.NET.Sdk`"><PropertyGroup><TargetFramework>net10.0</TargetFramework></PropertyGroup></Project>" | Set-Content -LiteralPath (Join-Path $fixture "Fixture.csproj") -Encoding UTF8
    "root = true`r`n`r`n[*.cs]`r`nindent_style = space`r`nindent_size = 4" | Set-Content -LiteralPath (Join-Path $fixture ".editorconfig") -Encoding UTF8
    & dotnet restore (Join-Path $fixture "Fixture.csproj") | Out-Null

    & powershell -NoProfile -ExecutionPolicy Bypass -File $checker -Doctor -Solution $fixture | Out-Host
    $doctorExitCode = $LASTEXITCODE
    "using System;`r`n`r`nsealed class Clean`r`n{`r`n    public Int32 Count { get; set; }`r`n}`r`n" | Set-Content -LiteralPath (Join-Path $fixture "Program.cs") -Encoding UTF8
    & powershell -NoProfile -ExecutionPolicy Bypass -File $checker -Solution (Join-Path $fixture "Fixture.csproj") -OutputPath (Join-Path $verifyRoot "clean.md") | Out-Null
    $cleanExitCode = $LASTEXITCODE
    "using System;`r`n`r`nsealed class Dirty`r`n{`r`n    public Int32 Count;`r`n}`r`n" | Set-Content -LiteralPath (Join-Path $fixture "Program.cs") -Encoding UTF8
    & powershell -NoProfile -ExecutionPolicy Bypass -File $checker -Solution (Join-Path $fixture "Fixture.csproj") -OutputPath (Join-Path $verifyRoot "dirty.md") | Out-Null
    $dirtyExitCode = $LASTEXITCODE
    $isVerified = $doctorExitCode -eq 0 -and $cleanExitCode -eq 0 -and $dirtyExitCode -eq 1
    if (-not $isVerified) { [Console]::Error.WriteLine("Bundle verification failed: doctor=$doctorExitCode clean=$cleanExitCode violation=$dirtyExitCode (expected 0, 0, 1).") }
}
finally
{
    if (Test-Path -LiteralPath $verifyRoot) { Remove-Item -LiteralPath $verifyRoot -Recurse -Force }
}

if (-not $isVerified)
{
    Remove-Item -LiteralPath $archivePath -Force
    exit 2
}

$checksum = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath "$archivePath.sha256" -Value "$checksum  $([IO.Path]::GetFileName($archivePath))" -Encoding ASCII
Write-Host "Bundle: $archivePath"
Write-Host "SHA256: $checksum"
