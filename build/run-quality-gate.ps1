param(
    [string]$Solution = "CSharpRuleKeeper.sln",
    [switch]$Fix
)

$ErrorActionPreference = "Stop"
$toolRoot = Split-Path -Parent $PSScriptRoot
# Relative to the tool root, so the gate works from any current directory.
$solutionPath = if ([IO.Path]::IsPathRooted($Solution)) { $Solution } else { Join-Path $toolRoot $Solution }

function Stop-OnFailure([Int32]$ExitCode, [string]$Step)
{
    if ($ExitCode -ne 0)
    {
        [Console]::Error.WriteLine("Quality gate failed at step: $Step (exit code $ExitCode)")
        exit $ExitCode
    }
}

# Restore first: format, build and test below run without restoring, and dotnet format only warns
# (and exits 0) for projects it cannot load, which would silently skip the style verification.
dotnet restore $solutionPath
Stop-OnFailure $LASTEXITCODE "dotnet restore"

if ($Fix)
{
    dotnet format $solutionPath --no-restore
}
else
{
    dotnet format $solutionPath --verify-no-changes --no-restore
}
Stop-OnFailure $LASTEXITCODE "dotnet format"

dotnet build $solutionPath --no-restore --configuration Debug
Stop-OnFailure $LASTEXITCODE "dotnet build"

dotnet test $solutionPath --no-build --configuration Debug
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

# Self check: the tool must pass its own rules with zero diagnostics, so even info-severity findings fail it.
# The integration test already built the Release analyzer.
$analyzerPath = Join-Path $toolRoot "src\CSharpRuleKeeper.Analyzers\bin\Release\netstandard2.0\CSharpRuleKeeper.Analyzers.dll"
$selfCheckPath = Join-Path $toolRoot "artifacts\self-check.md"
& "$PSScriptRoot\Invoke-CSharpRuleKeeper.ps1" -Solution $solutionPath -AnalyzerPath $analyzerPath -OutputPath $selfCheckPath -FailOn info
Stop-OnFailure $LASTEXITCODE "self check (see $selfCheckPath)"

exit 0
