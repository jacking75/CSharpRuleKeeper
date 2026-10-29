param(
    [string]$Solution = "CSharpRuleKeeper.sln",
    [switch]$Fix
)

$ErrorActionPreference = "Stop"
$toolRoot = Split-Path -Parent $PSScriptRoot

function Stop-OnFailure([Int32]$ExitCode, [string]$Step)
{
    if ($ExitCode -ne 0)
    {
        [Console]::Error.WriteLine("Quality gate failed at step: $Step (exit code $ExitCode)")
        exit $ExitCode
    }
}

if ($Fix)
{
    dotnet format $Solution --no-restore
}
else
{
    dotnet format $Solution --verify-no-changes --no-restore
}
Stop-OnFailure $LASTEXITCODE "dotnet format"

dotnet build $Solution --no-restore --configuration Debug
Stop-OnFailure $LASTEXITCODE "dotnet build"

dotnet test $Solution --no-build --configuration Debug
Stop-OnFailure $LASTEXITCODE "dotnet test"

$scriptTests = @(
    "Test-CSharpRuleKeeperIntegration.ps1",
    "Test-CSharpRuleKeeperFailureAndFormat.ps1",
    "Test-CSharpRuleKeeperReport.ps1",
    "Test-CSharpRuleKeeperHook.ps1",
    "Test-CSharpRuleKeeperDocs.ps1"
)
foreach ($scriptTest in $scriptTests)
{
    & "$PSScriptRoot\$scriptTest"
    Stop-OnFailure $LASTEXITCODE $scriptTest
}

# Self check: the tool must pass its own rules. The integration test already built the Release analyzer.
$analyzerPath = Join-Path $toolRoot "src\CSharpRuleKeeper.Analyzers\bin\Release\netstandard2.0\CSharpRuleKeeper.Analyzers.dll"
$selfCheckPath = Join-Path $toolRoot "artifacts\self-check.md"
& "$PSScriptRoot\Invoke-CSharpRuleKeeper.ps1" -Solution (Join-Path $toolRoot $Solution) -AnalyzerPath $analyzerPath -OutputPath $selfCheckPath
Stop-OnFailure $LASTEXITCODE "self check (see $selfCheckPath)"

exit 0
