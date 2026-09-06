param(
    [string]$Solution = "CSharpRuleKeeper.sln",
    [switch]$Fix,
    [string]$AgentReportPath
)

$ErrorActionPreference = "Stop"

if ($Fix)
{
    dotnet format $Solution --no-restore
}
else
{
    dotnet format $Solution --verify-no-changes --no-restore
}

if ($LASTEXITCODE -ne 0)
{
    Write-Error "서식 규칙 검사가 실패했다."
    exit $LASTEXITCODE
}

$buildOutput = @(& dotnet build $Solution --no-restore --configuration Debug 2>&1 | ForEach-Object {
    $_.ToString()
})
$buildExitCode = $LASTEXITCODE
$buildOutput | ForEach-Object {
    Write-Host $_
}

if ($AgentReportPath)
{
    $analysisStatus = if ($buildExitCode -eq 0) { "passed" } else { "failed" }
    $buildOutput | & "$PSScriptRoot\New-CodingAgentChangeReport.ps1" -OutputPath $AgentReportPath -Target $Solution -BuildExitCode $buildExitCode -FormatStatus passed -AnalysisStatus $analysisStatus
}

if ($buildExitCode -ne 0)
{
    exit $buildExitCode
}

dotnet test $Solution --no-build --configuration Debug
$testExitCode = $LASTEXITCODE
if ($testExitCode -ne 0)
{
    exit $testExitCode
}

& "$PSScriptRoot\Test-CSharpRuleKeeperIntegration.ps1"
$integrationExitCode = $LASTEXITCODE
if ($integrationExitCode -ne 0)
{
    exit $integrationExitCode
}

& "$PSScriptRoot\Test-CSharpRuleKeeperFailureAndFormat.ps1"
$failureAndFormatExitCode = $LASTEXITCODE
if ($failureAndFormatExitCode -ne 0)
{
    exit $failureAndFormatExitCode
}

& "$PSScriptRoot\Test-CSharpRuleKeeperReport.ps1"
exit $LASTEXITCODE
