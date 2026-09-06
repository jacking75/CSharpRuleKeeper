[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$toolRoot = Split-Path -Parent $PSScriptRoot
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) "CSharpRuleKeeper 통합 (한글)-$([Guid]::NewGuid().ToString('N'))"
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

function Invoke-CheckerProcess([string[]]$Arguments)
{
    $allArguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "$PSScriptRoot\Invoke-CSharpRuleKeeper.ps1") + $Arguments
    $quotedArguments = @($allArguments | ForEach-Object {
        if ($_ -notmatch '[\s"]') { $_ } else { '"' + ($_ -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"' }
    }) -join " "
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = "powershell"
    $startInfo.Arguments = $quotedArguments
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try
    {
        $null = $process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        Write-Host $stdout.Result
        if ($stderr.Result) { Write-Host $stderr.Result }
        return $process.ExitCode
    }
    finally
    {
        $process.Dispose()
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
    @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <TreatWarningsAsErrors>false</TreatWarningsAsErrors>
    <CustomAfterMicrosoftCommonTargets>`$(MSBuildProjectDirectory)\marker.targets</CustomAfterMicrosoftCommonTargets>
  </PropertyGroup>
</Project>
"@ | Set-Content -LiteralPath (Join-Path $fixtureRoot "Fixture.csproj") -Encoding UTF8
    @"
<Project>
  <Target Name="WriteMarker" AfterTargets="Build">
    <WriteLinesToFile File="`$(MSBuildProjectDirectory)\marker.txt" Lines="ran" Overwrite="true" />
  </Target>
</Project>
"@ | Set-Content -LiteralPath (Join-Path $fixtureRoot "marker.targets") -Encoding UTF8
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
    Assert-True ($normalExitCode -eq 0) "정상 fixture가 성공하지 않았다. 종료 코드: $normalExitCode, 분석: $($result.analysisStatus), 오류: $($result.executionErrors -join '; ')"
    Assert-True ($result.analysisCompleted -eq $true) "분석 완료가 입증되지 않았다."
    Assert-True ($result.totalDiagnostics -eq 0) "정상 fixture에 진단이 있다."
    Assert-True (Test-Path -LiteralPath (Join-Path $fixtureRoot "marker.txt")) "기존 CustomAfterMicrosoftCommonTargets가 실행되지 않았다."
    Assert-True ((Get-FileHash -LiteralPath (Join-Path $fixtureRoot "Fixture.csproj")).Hash -eq $projectHash) "프로젝트 파일이 변경됐다."
    Assert-True ((Get-FileHash -LiteralPath (Join-Path $fixtureRoot "Program.cs")).Hash -eq $sourceHash) "기본 검사에서 소스가 변경됐다."

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
        Assert-True ($violationExitCode -eq 1) "HBCS001 fixture 종료 코드가 1이 아니다."
        $violation = Get-Content -LiteralPath (Join-Path $fixtureRoot "violation-$attempt.json") -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert-True (@($violation.diagnostics | Where-Object ruleId -eq "HBCS001").Count -ge 1) "HBCS001이 수집되지 않았다."
    }

    Write-Host "CSharpRuleKeeper 통합 테스트가 통과했다."
}
finally
{
    if (Test-Path -LiteralPath $fixtureRoot) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }
}

exit 0
