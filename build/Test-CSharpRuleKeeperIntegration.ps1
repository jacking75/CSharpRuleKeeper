[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$toolRoot = Split-Path -Parent $PSScriptRoot
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) "CSharpRuleKeeper integration (non-ascii path)-$([Guid]::NewGuid().ToString('N'))"
$analyzerPath = Join-Path $toolRoot "src\CSharpRuleKeeper.Analyzers\bin\Release\netstandard2.0\CSharpRuleKeeper.Analyzers.dll"

function Assert-True([bool]$Condition, [string]$Message)
{
    if (-not $Condition) { throw $Message }
}

function Invoke-Checker([string]$SolutionPath, [string]$ReportPath, [string]$JsonPath, [switch]$Fix)
{
    & "$PSScriptRoot\Invoke-CSharpRuleKeeper.ps1" -Solution $SolutionPath -AnalyzerPath $analyzerPath -OutputPath $ReportPath -JsonOutputPath $JsonPath -Fix:$Fix
    return $LASTEXITCODE
}

function Write-ProjectFiles([string]$Directory, [bool]$HasBuildExtension)
{
    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    $extensionProperty = if ($HasBuildExtension) { "<CustomAfterMicrosoftCommonTargets>`$(MSBuildProjectDirectory)\marker.targets</CustomAfterMicrosoftCommonTargets>" } else { "" }
    @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <TreatWarningsAsErrors>false</TreatWarningsAsErrors>
    $extensionProperty
  </PropertyGroup>
</Project>
"@ | Set-Content -LiteralPath (Join-Path $Directory "Fixture.csproj") -Encoding UTF8
    if ($HasBuildExtension)
    {
        @"
<Project>
  <Target Name="WriteMarker" AfterTargets="Build">
    <WriteLinesToFile File="`$(MSBuildProjectDirectory)\marker.txt" Lines="ran" Overwrite="true" />
  </Target>
</Project>
"@ | Set-Content -LiteralPath (Join-Path $Directory "marker.targets") -Encoding UTF8
    }
}

try
{
    New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
    @"
root = true

[*.cs]
indent_style = space
indent_size = 4
dotnet_diagnostic.HBCS002.severity = warning
"@ | Set-Content -LiteralPath (Join-Path $fixtureRoot ".editorconfig") -Encoding UTF8
    Write-ProjectFiles $fixtureRoot $true
    @"
using System;

sealed class Example
{
    Boolean IsReady => true;
}
"@ | Set-Content -LiteralPath (Join-Path $fixtureRoot "Program.cs") -Encoding UTF8

    & dotnet restore (Join-Path $fixtureRoot "Fixture.csproj") | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "fixture restore failed" }
    & dotnet build (Join-Path $toolRoot "src\CSharpRuleKeeper.Analyzers\CSharpRuleKeeper.Analyzers.csproj") --configuration Release | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "analyzer release build failed" }

    $projectHash = (Get-FileHash -LiteralPath (Join-Path $fixtureRoot "Fixture.csproj")).Hash
    $sourceHash = (Get-FileHash -LiteralPath (Join-Path $fixtureRoot "Program.cs")).Hash
    $normalExitCode = Invoke-Checker (Join-Path $fixtureRoot "Fixture.csproj") (Join-Path $fixtureRoot "report.md") (Join-Path $fixtureRoot "report.json")
    $result = Get-Content -LiteralPath (Join-Path $fixtureRoot "report.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($normalExitCode -eq 0) "The clean fixture did not succeed. Exit code: $normalExitCode, analysis: $($result.analysisStatus), errors: $($result.executionErrors -join '; ')"
    Assert-True ($result.analysisCompleted -eq $true) "Analysis completion was not proven."
    Assert-True ($result.totalDiagnostics -eq 0) "The clean fixture reported diagnostics."
    Assert-True (Test-Path -LiteralPath (Join-Path $fixtureRoot "marker.txt")) "The project's own CustomAfterMicrosoftCommonTargets did not run."
    Assert-True ((Get-FileHash -LiteralPath (Join-Path $fixtureRoot "Fixture.csproj")).Hash -eq $projectHash) "The project file was modified."
    Assert-True ((Get-FileHash -LiteralPath (Join-Path $fixtureRoot "Program.cs")).Hash -eq $sourceHash) "The default check modified the source."

    @"
using System;

sealed class Example
{
    public Int32 Count;
}
"@ | Set-Content -LiteralPath (Join-Path $fixtureRoot "Program.cs") -Encoding UTF8
    foreach ($attempt in 1..2)
    {
        $violationExitCode = Invoke-Checker (Join-Path $fixtureRoot "Fixture.csproj") (Join-Path $fixtureRoot "violation-$attempt.md") (Join-Path $fixtureRoot "violation-$attempt.json")
        Assert-True ($violationExitCode -eq 1) "The HBCS001 fixture exit code is not 1."
        $violation = Get-Content -LiteralPath (Join-Path $fixtureRoot "violation-$attempt.json") -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert-True ($violation.totalDiagnostics -eq 1 -and @($violation.diagnostics | Where-Object ruleId -eq "HBCS001").Count -eq 1) "HBCS001 should be reported exactly once, got $($violation.totalDiagnostics)."
    }

    # Solution target: only the project that defines CustomAfterMicrosoftCommonTargets may run its extension.
    $solutionRoot = Join-Path $fixtureRoot "solution"
    New-Item -ItemType Directory -Path $solutionRoot | Out-Null
    Write-ProjectFiles (Join-Path $solutionRoot "WithExtension") $true
    Write-ProjectFiles (Join-Path $solutionRoot "WithoutExtension") $false
    foreach ($projectName in @("WithExtension", "WithoutExtension"))
    {
        "sealed class Clean { }" | Set-Content -LiteralPath (Join-Path $solutionRoot "$projectName\Program.cs") -Encoding UTF8
    }
    Push-Location $solutionRoot
    try
    {
        & dotnet new sln --name Fixture --format sln | Out-Host
        & dotnet sln Fixture.sln add (Join-Path $solutionRoot "WithExtension\Fixture.csproj") (Join-Path $solutionRoot "WithoutExtension\Fixture.csproj") | Out-Host
        & dotnet restore Fixture.sln | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "solution fixture restore failed" }
    }
    finally
    {
        Pop-Location
    }

    $solutionExitCode = Invoke-Checker (Join-Path $solutionRoot "Fixture.sln") (Join-Path $fixtureRoot "solution-report.md") (Join-Path $fixtureRoot "solution-report.json")
    $solutionResult = Get-Content -LiteralPath (Join-Path $fixtureRoot "solution-report.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($solutionExitCode -eq 0) "The solution fixture did not succeed. Exit code: $solutionExitCode, errors: $($solutionResult.executionErrors -join '; ')"
    Assert-True (Test-Path -LiteralPath (Join-Path $solutionRoot "WithExtension\marker.txt")) "A solution project's own build extension was dropped."
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $solutionRoot "WithoutExtension\marker.txt"))) "A project without a build extension ran another project's extension."

    Write-Host "CSharpRuleKeeper integration tests passed."
}
finally
{
    if (Test-Path -LiteralPath $fixtureRoot) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }
}

exit 0
