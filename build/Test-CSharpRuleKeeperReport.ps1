[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$testRoot = Join-Path ([IO.Path]::GetTempPath()) "CSharpRuleKeeper-report-$([Guid]::NewGuid().ToString('N'))"
$reportScript = Join-Path $PSScriptRoot "New-CodingAgentChangeReport.ps1"
$statusByExitCode = @{ 0 = "passed"; 1 = "failed"; 2 = "failed" }
# Child scripts run under the PowerShell that runs this test (pwsh or Windows PowerShell).
$powerShellPath = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
# The fixture paths are rooted the way the OS that runs the test roots them.
$isWindowsHost = $PSVersionTable.PSEdition -ne "Core" -or $IsWindows
$sourceRoot = if ($isWindowsHost) { "C:\src" } else { "/src" }
$sourceFile = [IO.Path]::Combine($sourceRoot, "File.cs")

function Invoke-Report([string]$Name, [string[]]$Lines, [hashtable]$Extra = @{})
{
    $arguments = @{
        BuildOutput = $Lines
        OutputPath = (Join-Path $testRoot "$Name.md")
        JsonOutputPath = (Join-Path $testRoot "$Name.json")
        Target = [IO.Path]::Combine($sourceRoot, "Fixture.csproj")
        BuildExitCode = 0
        FormatStatus = "passed"
        AnalysisStatus = "passed"
    }
    foreach ($key in $Extra.Keys) { $arguments[$key] = $Extra[$key] }
    $null = & $reportScript @arguments
    return Get-Content -LiteralPath (Join-Path $testRoot "$Name.json") -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Assert-Verdict([string]$Name, $Result, [Int32]$ExpectedExitCode, [Int32]$ExpectedDiagnostics)
{
    if ($Result.exitCode -ne $ExpectedExitCode) { throw "${Name}: exit code $($Result.exitCode), expected $ExpectedExitCode." }
    if ($Result.status -ne $statusByExitCode[$ExpectedExitCode]) { throw "${Name}: status '$($Result.status)' does not agree with exit code $ExpectedExitCode." }
    if ($Result.totalDiagnostics -ne $ExpectedDiagnostics) { throw "${Name}: $($Result.totalDiagnostics) diagnostics, expected $ExpectedDiagnostics." }
}

function New-Sarif([string]$Name, [object[]]$Results)
{
    $path = Join-Path $testRoot "$Name-net10.0-Debug.sarif"
    @{ runs = @(@{ results = $Results }) } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function New-SarifResult([string]$RuleId, [string]$Level, [Int32]$Line, [hashtable]$Properties, [object[]]$Suppressions)
{
    $result = @{
        ruleId = $RuleId
        level = $Level
        message = @{ text = "$RuleId message" }
        locations = @(@{ physicalLocation = @{ artifactLocation = @{ uri = ([Uri]$sourceFile).AbsoluteUri }; region = @{ startLine = $Line; startColumn = 1 } } })
    }
    if ($Properties) { $result.properties = $Properties }
    if ($Suppressions) { $result.suppressions = $Suppressions }
    return $result
}

try
{
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $errorLine = "$sourceFile(1,2): error HBCS001: Public field 'Value' must be replaced"
    $warningLine = "$sourceFile(2,3): warning HBCS002: Boolean property 'Ready' must start with Is"
    $infoLine = "$sourceFile(3,1): info HBCS008: Private modifier on field '_x' should be omitted"
    $trailingLine = "$sourceFile({0},20): warning HBCS009: Trailing comment must be moved to its own line"
    $configurationLine = "$sourceFile(1,1): warning HBCS900: Option 'personal_csharp_rules.max_line_length' has invalid value 'wide'"

    # The JSON status and the exit code always agree, whatever the severity mix.
    Assert-Verdict "clean" (Invoke-Report "clean" @()) 0 0
    Assert-Verdict "warning-only" (Invoke-Report "warning-only" @($warningLine)) 1 1
    Assert-Verdict "info-only" (Invoke-Report "info-only" @($infoLine)) 0 1
    Assert-Verdict "info-only-fail-on-info" (Invoke-Report "info-only-fail-on-info" @($infoLine) @{ FailOn = "info" }) 1 1
    Assert-Verdict "warning-fail-on-error" (Invoke-Report "warning-fail-on-error" @($warningLine) @{ FailOn = "error" }) 0 1
    Assert-Verdict "error" (Invoke-Report "error" @($errorLine) @{ BuildExitCode = 1 }) 1 1
    Assert-Verdict "configuration-only" (Invoke-Report "configuration-only" @($configurationLine)) 0 1
    Assert-Verdict "build-failure-no-hbcs" (Invoke-Report "build-failure-no-hbcs" @("MSBuild failed") @{ BuildExitCode = 1; AnalysisStatus = "failed"; ExecutionErrors = @("CS0246: missing type") }) 2 0
    Assert-Verdict "format-tool-error" (Invoke-Report "format-tool-error" @() @{ FormatStatus = "failed"; FormatFailureKind = "toolError" }) 2 0
    Assert-Verdict "format-differences" (Invoke-Report "format-differences" @() @{ FormatStatus = "failed"; FormatFailureKind = "differences" }) 1 0
    $belowThreshold = Invoke-Report "below-threshold" @($errorLine, $infoLine)
    if (@($belowThreshold.diagnostics | Where-Object { $_.ruleId -eq "HBCS008" -and -not $_.affectsVerdict }).Count -ne 1) { throw "A diagnostic below -FailOn is not marked as not affecting the verdict." }
    if ((Get-Content -LiteralPath (Join-Path $testRoot "below-threshold.md") -Raw -Encoding UTF8) -notmatch "below -FailOn warning") { throw "The Markdown report does not mark diagnostics below -FailOn." }

    # Baselines are a multiset: one stored trailing comment does not cover a second identical one.
    $baselinePath = Join-Path $testRoot "baseline.json"
    $created = Invoke-Report "baseline-create" @($errorLine, ($trailingLine -f 5)) @{ BaselinePath = $baselinePath; CreateBaseline = $true }
    Assert-Verdict "baseline-create" $created 0 2
    $shiftedErrorLine = "$sourceFile(20,2): error HBCS001: Public field 'Value' must be replaced"
    Assert-Verdict "baseline-existing-only" (Invoke-Report "baseline-existing" @($shiftedErrorLine, ($trailingLine -f 9)) @{ BaselinePath = $baselinePath }) 0 2
    $withNew = Invoke-Report "baseline-new" @($shiftedErrorLine, ($trailingLine -f 9), ($trailingLine -f 12)) @{ BaselinePath = $baselinePath }
    Assert-Verdict "baseline-with-new" $withNew 1 3
    if ($withNew.baseline.new -ne 1 -or $withNew.baseline.existing -ne 2) { throw "Baseline counts differ: new $($withNew.baseline.new), existing $($withNew.baseline.existing)." }
    if (@($withNew.diagnostics | Where-Object { $_.isNew }).Count -ne 1) { throw "Exactly one diagnostic must be marked new." }

    # Baseline files written by the previous format (one fingerprint per diagnostic) are still read.
    $legacyPath = Join-Path $testRoot "legacy-baseline.json"
    $legacyFingerprint = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes("HBCS001|File.cs|Public field 'Value' must be replaced"))).Replace("-", "").ToLowerInvariant()
    @{ schemaVersion = 1; fingerprints = @($legacyFingerprint) } | ConvertTo-Json | Set-Content -LiteralPath $legacyPath -Encoding UTF8
    Assert-Verdict "legacy-baseline" (Invoke-Report "legacy-baseline" @($errorLine) @{ BaselinePath = $legacyPath }) 0 1

    # A baseline created on Windows (path hashed as Sub\File.cs) matches the same finding on every OS, where the
    # report path is Sub/File.cs on Linux and macOS.
    $portablePath = Join-Path $testRoot "portable-baseline.json"
    $portableFingerprint = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes("HBCS001|Sub\File.cs|Public field 'Value' must be replaced"))).Replace("-", "").ToLowerInvariant()
    @{ schemaVersion = 2; entries = @(@{ fingerprint = $portableFingerprint; count = 1 }) } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $portablePath -Encoding UTF8
    $subFileLine = "$([IO.Path]::Combine($sourceRoot, 'Sub', 'File.cs'))(1,2): error HBCS001: Public field 'Value' must be replaced"
    Assert-Verdict "portable-baseline" (Invoke-Report "portable-baseline" @($subFileLine) @{ BaselinePath = $portablePath }) 0 1

    # SARIF: the policy severity carried by a downgraded finding wins, "note" is info, suppressed results are skipped,
    # and errors sort before infos.
    $sarifPath = New-Sarif "Fixture" @(
        (New-SarifResult "HBCS008" "note" 3 $null $null),
        (New-SarifResult "HBCS001" "warning" 1 @{ customProperties = @{ policySeverity = "error" } } $null),
        (New-SarifResult "HBCS002" "warning" 2 $null @(@{ kind = "inSource" }))
    )
    $sarifResult = Invoke-Report "sarif" @($errorLine) @{ SarifPaths = @($sarifPath) }
    Assert-Verdict "sarif" $sarifResult 1 2
    if ($sarifResult.diagnostics[0].ruleId -ne "HBCS001" -or $sarifResult.diagnostics[0].severity -ne "error") { throw "The SARIF policy severity was not restored or errors do not sort first." }
    if ($sarifResult.diagnostics[1].severity -ne "info") { throw "SARIF level 'note' was reported as '$($sarifResult.diagnostics[1].severity)', expected info." }

    $blockedParent = Join-Path $testRoot "blocked-parent"
    Set-Content -LiteralPath $blockedParent -Value "file" -Encoding UTF8
    $ErrorActionPreference = "Continue"
    & $powerShellPath -NoProfile -ExecutionPolicy Bypass -File $reportScript -OutputPath (Join-Path $blockedParent "report.md") -JsonOutputPath (Join-Path $testRoot "blocked.json") -Target "Fixture.csproj" -BuildExitCode 0 -FormatStatus passed -AnalysisStatus passed 2>$null | Out-Null
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
