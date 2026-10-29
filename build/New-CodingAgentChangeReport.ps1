[CmdletBinding()]
param(
    [Parameter(ValueFromPipeline = $true)]
    [AllowEmptyString()]
    [string[]]$BuildOutput,
    [string[]]$SarifPaths,
    [string]$OutputPath = "coding-agent-change-report.md",
    [string]$JsonOutputPath,
    [string]$Target,
    [ValidateSet("passed", "failed", "notRun", "unknown")]
    [string]$FormatStatus = "unknown",
    [ValidateSet("passed", "failed", "notRun", "unknown")]
    [string]$AnalysisStatus = "unknown",
    [Int32]$BuildExitCode = -1,
    [string]$RunId = ([Guid]::NewGuid().ToString("N")),
    [string]$ToolVersion,
    [string]$ConfigurationHash,
    [object]$Timings,
    [string]$StartedAt = ([DateTimeOffset]::UtcNow.ToString("o")),
    [string[]]$ExecutionErrors = @(),
    [ValidateRange(1, 10000)]
    [Int32]$MaxDiagnostics = 200,
    [string]$BaselinePath,
    [switch]$CreateBaseline
)

begin
{
    $pipelineLines = [Collections.Generic.List[string]]::new()
}

process
{
    foreach ($line in $BuildOutput) { $pipelineLines.Add($line) }
}

end
{
    $ErrorActionPreference = "Stop"
    $reportWatch = [Diagnostics.Stopwatch]::StartNew()
    if ([string]::IsNullOrWhiteSpace($ToolVersion)) { $ToolVersion = (Get-Content -LiteralPath (Join-Path $PSScriptRoot "version.txt") -Raw).Trim() }
    $ruleGuidance = @{
        HBCS001 = "Review external API, serialization and interop contracts, and encapsulate only when it is safe."
        HBCS002 = "Confirm the name is not an external contract, then use a state prefix. Try-prefixed methods with an out parameter are exempt."
        HBCS003 = "Natural-language detection has limits; use a name that clearly denotes multiple items."
        HBCS004 = "Confirm the string is not an external protocol string, then use nameof."
        HBCS005 = "Express the domain meaning of the number as a named constant, enum or variable."
        HBCS006 = "Split the method by responsibility while preserving the public contract and control flow."
        HBCS007 = "Split the type by responsibility while preserving the public contract and serialization."
        HBCS008 = "Remove the access modifier only from members that are actually private."
        HBCS009 = "Keep the comment text and move it to its own preceding line."
        HBCS010 = "Reduce consecutive blank lines to one."
        HBCS011 = "Use the explicit-width integer type named in the diagnostic."
        HBCS012 = "Split the expression, arguments or condition across lines without changing its meaning."
        HBCS013 = "Check for an external contract first, then apply the required naming pattern."
        HBCS014 = "Use the field prefix that matches the storage kind and rename every reference together."
        HBCS015 = "Split the file by responsibility while preserving the API and behavior."
    }
    $severityOrder = @{ error = 0; warning = 1; info = 2; hidden = 3 }
    $diagnostics = [Collections.Generic.List[object]]::new()
    $targetRoot = if ($Target -and [IO.Path]::HasExtension($Target)) { Split-Path -Parent $Target } else { $Target }

    function Add-Diagnostic($RuleId, $Severity, $Project, $Framework, $Path, $Line, $Column, $Message)
    {
        if ($RuleId -notmatch "^HBCS\d{3}$") { return }
        if ($Path -and $Path -match "^file:") { $Path = ([Uri]$Path).LocalPath }
        if ($Path -and $targetRoot -and [IO.Path]::IsPathRooted($Path))
        {
            $rootUri = [Uri](([IO.Path]::GetFullPath($targetRoot).TrimEnd('\') + '\'))
            $pathUri = [Uri]([IO.Path]::GetFullPath($Path))
            $Path = [Uri]::UnescapeDataString($rootUri.MakeRelativeUri($pathUri).ToString()).Replace('/', '\')
        }
        $diagnostics.Add([PSCustomObject]@{
            ruleId = $RuleId
            severity = $Severity
            project = $Project
            targetFramework = $Framework
            path = $Path
            line = $Line
            column = $Column
            message = $Message
            helpUri = "https://github.com/jacking75/CSharpRuleKeeper/blob/main/docs/RULES.md#$($RuleId.ToLowerInvariant())"
            fixCaution = $ruleGuidance[$RuleId]
            requiresContractReview = $RuleId -in @("HBCS001", "HBCS002", "HBCS003", "HBCS004", "HBCS013", "HBCS014")
        })
    }

    foreach ($sarifPath in @($SarifPaths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }))
    {
        if (-not (Test-Path -LiteralPath $sarifPath)) { continue }
        $sarif = Get-Content -LiteralPath $sarifPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $sarifName = [IO.Path]::GetFileNameWithoutExtension($sarifPath)
        $sarifMatch = [regex]::Match($sarifName, "^(?<project>.+?)-(?<framework>net[^-]+)-(?<configuration>[^-]+)(-+[0-9]+)?$")
        foreach ($run in @($sarif.runs))
        {
            foreach ($result in @($run.results))
            {
                $location = @($result.locations)[0].physicalLocation
                $region = $location.region
                $path = $location.artifactLocation.uri
                $project = $result.properties.project
                $framework = $result.properties.targetFramework
                if (-not $project -and $sarifMatch.Success) { $project = $sarifMatch.Groups["project"].Value }
                if (-not $framework -and $sarifMatch.Success) { $framework = $sarifMatch.Groups["framework"].Value }
                Add-Diagnostic $result.ruleId $result.level $project $framework $path $region.startLine $region.startColumn $result.message.text
            }
        }
    }

    # SARIF is the primary source. Console output is parsed only when SARIF yielded nothing,
    # otherwise every diagnostic would be counted twice.
    if ($diagnostics.Count -eq 0)
    {
        $pattern = [regex]"^(?<path>.+?)\((?<line>\d+),(?<column>\d+)\):\s*(?<severity>error|warning|info)\s+(?<id>HBCS\d{3}):\s*(?<message>.*?)(?:\s+\[.*\])?$"
        foreach ($line in $pipelineLines.ToArray())
        {
            $match = $pattern.Match($line)
            if ($match.Success)
            {
                Add-Diagnostic $match.Groups["id"].Value $match.Groups["severity"].Value $null $null $match.Groups["path"].Value ([Int32]$match.Groups["line"].Value) ([Int32]$match.Groups["column"].Value) $match.Groups["message"].Value
            }
        }
    }

    # The same location reported once per target framework is a single fix point.
    $uniqueDiagnostics = [Collections.Generic.Dictionary[string, object]]::new()
    foreach ($diagnostic in $diagnostics)
    {
        $key = "$($diagnostic.ruleId)|$($diagnostic.path)|$($diagnostic.line)|$($diagnostic.column)|$($diagnostic.message)"
        if (-not $uniqueDiagnostics.ContainsKey($key))
        {
            $uniqueDiagnostics[$key] = $diagnostic
            continue
        }
        $kept = $uniqueDiagnostics[$key]
        $frameworks = @(@("$($kept.targetFramework)" -split ";") + @("$($diagnostic.targetFramework)" -split ";") | Where-Object { $_ } | Select-Object -Unique)
        if ($frameworks.Count -gt 0) { $kept.targetFramework = $frameworks -join ";" }
    }
    $normalized = @($uniqueDiagnostics.Values | Sort-Object @{ Expression = { $severityOrder[$_.severity] } }, project, targetFramework, path, line, column, ruleId, message)
    $baselineSummary = [ordered]@{ new = $normalized.Count; existing = 0; resolved = 0; state = "notUsed" }
    $fingerprints = @($normalized | ForEach-Object {
        $value = "$($_.ruleId)|$($_.path)|$($_.message)"
        $bytes = [Text.Encoding]::UTF8.GetBytes($value)
        $hash = [Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
        [BitConverter]::ToString($hash).Replace("-", "").ToLowerInvariant()
    })
    if (-not [string]::IsNullOrWhiteSpace($BaselinePath))
    {
        if ($CreateBaseline)
        {
            if ($AnalysisStatus -ne "passed") { throw "A baseline can only be created when the analysis completed." }
            $baseline = [ordered]@{
                schemaVersion = 1
                toolVersion = $ToolVersion
                configurationHash = $ConfigurationHash
                target = $Target
                createdAt = [DateTimeOffset]::UtcNow.ToString("o")
                fingerprints = $fingerprints
            }
            $baseline | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $BaselinePath -Encoding UTF8
            $baselineSummary = [ordered]@{ new = 0; existing = $normalized.Count; resolved = 0; state = "created" }
        }
        elseif (Test-Path -LiteralPath $BaselinePath)
        {
            $saved = Get-Content -LiteralPath $BaselinePath -Raw -Encoding UTF8 | ConvertFrom-Json
            $savedFingerprints = @($saved.fingerprints)
            $existingCount = @($fingerprints | Where-Object { $_ -in $savedFingerprints }).Count
            $baselineSummary = [ordered]@{
                new = $normalized.Count - $existingCount
                existing = $existingCount
                resolved = @($savedFingerprints | Where-Object { $_ -notin $fingerprints }).Count
                state = if ($saved.toolVersion -eq $ToolVersion -and $saved.configurationHash -eq $ConfigurationHash) { "matched" } else { "reviewRequired" }
            }
        }
        else
        {
            throw "Baseline file not found: $BaselinePath"
        }
    }

    $analysisCompleted = $AnalysisStatus -eq "passed"
    $status = if ($FormatStatus -eq "failed" -or $BuildExitCode -ne 0 -or -not $analysisCompleted) { "failed" } elseif ($baselineSummary.new -gt 0) { "failed" } else { "passed" }
    $resultObject = [ordered]@{
        schemaVersion = 1
        toolVersion = $ToolVersion
        runId = $RunId
        target = $Target
        configurationHash = $ConfigurationHash
        status = $status
        formatStatus = $FormatStatus
        buildExitCode = $BuildExitCode
        analysisStatus = $AnalysisStatus
        analysisCompleted = $analysisCompleted
        startedAt = $StartedAt
        finishedAt = [DateTimeOffset]::UtcNow.ToString("o")
        timings = $Timings
        totalDiagnostics = $normalized.Count
        omittedDiagnostics = [Math]::Max(0, $normalized.Count - $MaxDiagnostics)
        baseline = $baselineSummary
        diagnostics = $normalized
        executionErrors = @($ExecutionErrors)
    }

    if ([string]::IsNullOrWhiteSpace($JsonOutputPath)) { $JsonOutputPath = [IO.Path]::ChangeExtension($OutputPath, ".json") }
    $displayed = @($normalized | Select-Object -First $MaxDiagnostics)
    $report = [Collections.Generic.List[string]]::new()
    $report.Add("# CSharpRuleKeeper Run Report")
    $report.Add("")
    $report.Add("- Run ID: ``$RunId``")
    $report.Add("- Tool version: $ToolVersion")
    $report.Add("- Target: ``$Target``")
    $report.Add("- Started: $StartedAt")
    $report.Add("- Finished: $($resultObject.finishedAt)")
    $report.Add("- Overall status: **$status**")
    $report.Add("- Format status: **$FormatStatus**")
    $report.Add("- Build exit code: **$BuildExitCode**")
    $report.Add("- Analysis status: **$AnalysisStatus** (completed: $analysisCompleted)")
    $report.Add("- HBCS diagnostics: $($normalized.Count) (shown $($displayed.Count), omitted $($resultObject.omittedDiagnostics))")
    $report.Add("- Full JSON: ``$JsonOutputPath``")
    $report.Add("")
    $report.Add("Zero HBCS diagnostics and a completed analysis are different things. If analysisCompleted is false, do not treat the check as finished.")
    if ($ExecutionErrors.Count -gt 0)
    {
        $report.Add("")
        $report.Add("## Execution errors")
        $report.Add("")
        foreach ($executionError in $ExecutionErrors) { $report.Add("- $executionError") }
    }
    foreach ($diagnostic in $displayed)
    {
        $report.Add("")
        $report.Add("## $($diagnostic.ruleId) $([char]0x00B7) $($diagnostic.severity)")
        $report.Add("")
        $report.Add("- Location: ``$($diagnostic.path):$($diagnostic.line):$($diagnostic.column)``")
        if ($diagnostic.project) { $report.Add("- Project/TFM: ``$($diagnostic.project)`` / ``$($diagnostic.targetFramework)``") }
        $report.Add("- Diagnostic: $($diagnostic.message -replace '\|', '\\|')")
        $report.Add("- Help: $($diagnostic.helpUri)")
        $report.Add("- Fix caution: $($diagnostic.fixCaution)")
    }

    try
    {
        $reportWatch.Stop()
        if ($null -eq $Timings)
        {
            $Timings = [ordered]@{}
            $resultObject["timings"] = $Timings
        }
        $Timings["reportPreparationMilliseconds"] = $reportWatch.ElapsedMilliseconds
        foreach ($path in @($OutputPath, $JsonOutputPath))
        {
            $parent = Split-Path -Parent $path
            if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        }
        $reportTemp = "$OutputPath.$RunId.tmp"
        $jsonTemp = "$JsonOutputPath.$RunId.tmp"
        $report | Set-Content -LiteralPath $reportTemp -Encoding UTF8
        $resultObject | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonTemp -Encoding UTF8
        Move-Item -LiteralPath $reportTemp -Destination $OutputPath -Force
        Move-Item -LiteralPath $jsonTemp -Destination $JsonOutputPath -Force
        Write-Host "Report written: $OutputPath"
        Write-Host "Structured result written: $JsonOutputPath"
    }
    catch
    {
        [Console]::Error.WriteLine("Failed to save the report: $_")
        exit 2
    }
}
