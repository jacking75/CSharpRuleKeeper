[CmdletBinding()]
param(
    [string]$OutputDirectory = "artifacts",
    [string]$Version = "1.1.0"
)

$ErrorActionPreference = "Stop"
$toolRoot = Split-Path -Parent $PSScriptRoot
$outputRoot = [IO.Path]::GetFullPath((Join-Path (Get-Location) $OutputDirectory))
$stagingRoot = Join-Path $outputRoot "CSharpRuleKeeper-$Version"
$archivePath = Join-Path $outputRoot "CSharpRuleKeeper-$Version.zip"

& dotnet build (Join-Path $toolRoot "src\CSharpRuleKeeper.Analyzers\CSharpRuleKeeper.Analyzers.csproj") --configuration Release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if (Test-Path -LiteralPath $stagingRoot) { Remove-Item -LiteralPath $stagingRoot -Recurse -Force }
New-Item -ItemType Directory -Path (Join-Path $stagingRoot "build") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stagingRoot "analyzers") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stagingRoot "docs\rules") -Force | Out-Null

Copy-Item -LiteralPath (Join-Path $toolRoot "src\CSharpRuleKeeper.Analyzers\bin\Release\netstandard2.0\CSharpRuleKeeper.Analyzers.dll") -Destination (Join-Path $stagingRoot "analyzers")
Copy-Item -LiteralPath (Join-Path $toolRoot "build\Invoke-CSharpRuleKeeper.ps1") -Destination (Join-Path $stagingRoot "build")
Copy-Item -LiteralPath (Join-Path $toolRoot "build\New-CodingAgentChangeReport.ps1") -Destination (Join-Path $stagingRoot "build")
Copy-Item -LiteralPath (Join-Path $toolRoot "build\Show-CSharpRuleKeeperOptions.ps1") -Destination (Join-Path $stagingRoot "build")
Copy-Item -LiteralPath (Join-Path $toolRoot "build\CSharpRuleKeeper.targets") -Destination (Join-Path $stagingRoot "build")
Copy-Item -LiteralPath (Join-Path $toolRoot "docs\options.json") -Destination (Join-Path $stagingRoot "docs")
Copy-Item -LiteralPath (Join-Path $toolRoot "docs\report-schema-v1.json") -Destination (Join-Path $stagingRoot "docs")
Copy-Item -Path (Join-Path $toolRoot "docs\rules\*.md") -Destination (Join-Path $stagingRoot "docs\rules")
Copy-Item -LiteralPath (Join-Path $toolRoot "README.md") -Destination $stagingRoot
Copy-Item -LiteralPath (Join-Path $toolRoot "README_kr.md") -Destination $stagingRoot
Copy-Item -LiteralPath (Join-Path $toolRoot "LICENSE") -Destination $stagingRoot

$manifest = [ordered]@{
    name = "CSharpRuleKeeper"
    version = $Version
    analyzer = "analyzers/CSharpRuleKeeper.Analyzers.dll"
    entrypoint = "build/Invoke-CSharpRuleKeeper.ps1"
    createdAt = [DateTimeOffset]::UtcNow.ToString("o")
}
$manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $stagingRoot "manifest.json") -Encoding UTF8
if (Test-Path -LiteralPath $archivePath) { Remove-Item -LiteralPath $archivePath -Force }
Compress-Archive -LiteralPath $stagingRoot -DestinationPath $archivePath
$checksum = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath "$archivePath.sha256" -Value "$checksum  $([IO.Path]::GetFileName($archivePath))" -Encoding ASCII
Write-Host "Bundle: $archivePath"
Write-Host "SHA256: $checksum"
