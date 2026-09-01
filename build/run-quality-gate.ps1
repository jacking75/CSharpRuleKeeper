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
    $buildOutput | & "$PSScriptRoot\New-CodingAgentChangeReport.ps1" -OutputPath $AgentReportPath -Target $Solution
}

if ($buildExitCode -ne 0)
{
    exit $buildExitCode
}

dotnet test $Solution --no-build --configuration Debug
exit $LASTEXITCODE
