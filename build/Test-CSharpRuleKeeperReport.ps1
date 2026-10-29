[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$testRoot = Join-Path ([IO.Path]::GetTempPath()) "CSharpRuleKeeper-report-$([Guid]::NewGuid().ToString('N'))"
$reportScript = Join-Path $PSScriptRoot "New-CodingAgentChangeReport.ps1"

function Assert-Report([string]$Name, [Int32]$BuildExitCode, [string]$FormatStatus, [string]$AnalysisStatus, [string[]]$Lines, [Int32]$ExpectedDiagnostics, [bool]$ExpectedCompleted)
{
    $markdownPath = Join-Path $testRoot "$Name.md"
    $jsonPath = Join-Path $testRoot "$Name.json"
    & $reportScript -BuildOutput $Lines -OutputPath $markdownPath -JsonOutputPath $jsonPath -Target "Fixture.csproj" -BuildExitCode $BuildExitCode -FormatStatus $FormatStatus -AnalysisStatus $AnalysisStatus
    $result = Get-Content -LiteralPath $jsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($result.totalDiagnostics -ne $ExpectedDiagnostics) { throw "$Name diagnostic count differs." }
    if ($result.analysisCompleted -ne $ExpectedCompleted) { throw "$Name analysis completion state differs." }
    if ($BuildExitCode -ne 0 -and $result.status -ne "failed") { throw "$Name failure status was not preserved." }
}

try
{
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $errorLine = "C:\src\File.cs(1,2): error HBCS001: Public field 'Value' must be replaced"
    $warningLine = "C:\src\File.cs(2,3): warning HBCS002: Boolean property 'Ready' must start with Is"
    Assert-Report "build-failure-no-hbcs" 1 "passed" "failed" @("MSBuild failed") 0 $false
    Assert-Report "hbcs-error" 1 "passed" "passed" @($errorLine) 1 $true
    Assert-Report "warning-only" 0 "passed" "passed" @($warningLine) 1 $true
    Assert-Report "clean-success" 0 "passed" "passed" @() 0 $true
    Assert-Report "analyzer-build-failure" 2 "notRun" "failed" @("Analyzer build failed") 0 $false
    Assert-Report "unknown-log" -1 "unknown" "unknown" @("historical output") 0 $false

    $sarifPath = Join-Path $testRoot "Fixture-net10.0-Debug.sarif"
    $sarifJson = @{
        runs = @(@{
            results = @(@{
                ruleId = "HBCS001"
                level = "error"
                message = @{ text = "Public field 'Value' must be replaced" }
                locations = @(@{ physicalLocation = @{ artifactLocation = @{ uri = "file:///C:/src/File.cs" }; region = @{ startLine = 1; startColumn = 2 } } })
            })
        })
    } | ConvertTo-Json -Depth 10
    Set-Content -LiteralPath $sarifPath -Value $sarifJson -Encoding UTF8
    & $reportScript -BuildOutput @($errorLine) -SarifPaths $sarifPath -OutputPath (Join-Path $testRoot "dedupe.md") -JsonOutputPath (Join-Path $testRoot "dedupe.json") -Target "C:\src\Fixture.csproj" -BuildExitCode 1 -FormatStatus passed -AnalysisStatus passed
    $dedupe = Get-Content -LiteralPath (Join-Path $testRoot "dedupe.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($dedupe.totalDiagnostics -ne 1) { throw "The same diagnostic from SARIF and console output was counted $($dedupe.totalDiagnostics) times." }

    $baselinePath = Join-Path $testRoot "baseline.json"
    & $reportScript -BuildOutput @($errorLine) -OutputPath (Join-Path $testRoot "baseline-create.md") -JsonOutputPath (Join-Path $testRoot "baseline-create.json") -Target "Fixture.csproj" -BuildExitCode 1 -FormatStatus passed -AnalysisStatus passed -BaselinePath $baselinePath -CreateBaseline
    $shiftedErrorLine = "C:\src\File.cs(20,2): error HBCS001: Public field 'Value' must be replaced"
    & $reportScript -BuildOutput @($shiftedErrorLine, $warningLine) -OutputPath (Join-Path $testRoot "baseline-check.md") -JsonOutputPath (Join-Path $testRoot "baseline-check.json") -Target "Fixture.csproj" -BuildExitCode 1 -FormatStatus passed -AnalysisStatus passed -BaselinePath $baselinePath
    $baselineResult = Get-Content -LiteralPath (Join-Path $testRoot "baseline-check.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($baselineResult.baseline.existing -ne 1 -or $baselineResult.baseline.new -ne 1) { throw "Baseline new/existing classification differs." }

    $blockedParent = Join-Path $testRoot "blocked-parent"
    Set-Content -LiteralPath $blockedParent -Value "file" -Encoding UTF8
    $ErrorActionPreference = "Continue"
    & powershell -NoProfile -ExecutionPolicy Bypass -File $reportScript -OutputPath (Join-Path $blockedParent "report.md") -JsonOutputPath (Join-Path $testRoot "blocked.json") -Target "Fixture.csproj" -BuildExitCode 0 -FormatStatus passed -AnalysisStatus passed 2>$null
    $writeFailureExitCode = $LASTEXITCODE
    $ErrorActionPreference = "Stop"
    if ($writeFailureExitCode -ne 2) { throw "Report save failure exit code was $writeFailureExitCode, expected 2." }
    Write-Host "CSharpRuleKeeper report contract tests passed."
}
finally
{
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}

exit 0
