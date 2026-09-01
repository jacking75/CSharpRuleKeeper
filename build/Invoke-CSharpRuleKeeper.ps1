[CmdletBinding()]
param(
    [string]$Solution,

    [string]$OutputPath = "coding-agent-change-report.md",

    [switch]$Fix,

    [switch]$ExplainEditorConfig,

    [string]$OptionsDocumentationPath,

    [string]$DefineConstants
)

$ErrorActionPreference = "Stop"
$toolRoot = Split-Path -Parent $PSScriptRoot
$analyzerProject = Join-Path $toolRoot "src\CSharpRuleKeeper.Analyzers\CSharpRuleKeeper.Analyzers.csproj"
$analyzerPath = Join-Path $toolRoot "src\CSharpRuleKeeper.Analyzers\bin\Debug\netstandard2.0\CSharpRuleKeeper.Analyzers.dll"
$targetsPath = Join-Path $PSScriptRoot "CSharpRuleKeeper.targets"

if ($ExplainEditorConfig)
{
    & "$PSScriptRoot\Show-CSharpRuleKeeperOptions.ps1" -OutputPath $OptionsDocumentationPath
    exit $LASTEXITCODE
}

if ([string]::IsNullOrWhiteSpace($Solution))
{
    throw "-Solution은 검사 실행 시 필수입니다. 옵션 설명만 보려면 -ExplainEditorConfig를 사용하세요."
}

if (-not (Test-Path -LiteralPath $Solution))
{
    throw "검사할 솔루션 또는 프로젝트를 찾을 수 없습니다: $Solution"
}

& dotnet build $analyzerProject --configuration Debug
if ($LASTEXITCODE -ne 0)
{
    exit $LASTEXITCODE
}

if ($Fix)
{
    & dotnet format $Solution
    if ($LASTEXITCODE -ne 0)
    {
        exit $LASTEXITCODE
    }
}

$buildArguments = @(
    "build",
    $Solution,
    "--configuration",
    "Debug",
    "/p:CustomAfterMicrosoftCommonTargets=$targetsPath",
    "/p:CSharpRuleKeeperAnalyzerPath=$analyzerPath"
)

if (-not [string]::IsNullOrWhiteSpace($DefineConstants))
{
    $buildArguments += "/p:DefineConstants=$DefineConstants"
}

$buildOutput = @(& dotnet @buildArguments 2>&1 | ForEach-Object {
    $_.ToString()
})
$buildExitCode = $LASTEXITCODE
$buildOutput | ForEach-Object {
    Write-Host $_
}

$buildOutput | & "$PSScriptRoot\New-CodingAgentChangeReport.ps1" -OutputPath $OutputPath -Target $Solution
exit $buildExitCode
