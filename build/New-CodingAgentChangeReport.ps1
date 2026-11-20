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
    [ValidateSet("none", "differences", "toolError", "timeout")]
    [string]$FormatFailureKind = "none",
    [object[]]$FormatFiles = @(),
    [ValidateSet("passed", "failed", "notRun", "unknown")]
    [string]$AnalysisStatus = "unknown",
    [object]$AnalysisCoverage,
    [object[]]$BuildErrors = @(),
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
    [switch]$CreateBaseline,
    [ValidateSet("error", "warning", "info")]
    [string]$FailOn = "warning"
)

# Writes the Markdown report and the JSON result, and returns the result object.
# The verdict is decided here and the checker's exit code is the result's exitCode:
#   2 the check could not run or complete, 1 violations to fix, 0 passed.
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
    $configurationRuleId = "HBCS900"
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
        HBCS900 = "Fix the option value in .editorconfig, not the source file it points to (that file only shows where the option applies). The default values are used until then."
    }
    $severityRank = @{ error = 0; warning = 1; info = 2; hidden = 3 }
    $failOnRank = $severityRank[$FailOn]
    $diagnostics = [Collections.Generic.List[object]]::new()
    $targetRoot = if ($Target -and [IO.Path]::HasExtension($Target)) { Split-Path -Parent $Target } else { $Target }
    # Windows PowerShell 5.1 runs only on Windows and has no $IsWindows; PowerShell 7 defines it on every OS.
    $isWindowsHost = $PSVersionTable.PSEdition -ne "Core" -or $IsWindows
    $isMacHost = $PSVersionTable.PSEdition -eq "Core" -and $IsMacOS
    $utf8 = [Text.UTF8Encoding]::new($false)

    # Same rules as the checker: relative to the target folder, in the separator of the OS that ran the check,
    # case-insensitive on Windows and macOS, and macOS /private/var and /private/tmp equal to /var and /tmp.
    function ConvertTo-RelativePath([string]$BasePath, [string]$Path)
    {
        $separators = [char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
        $baseText = [IO.Path]::GetFullPath($BasePath).TrimEnd($separators)
        $pathText = [IO.Path]::GetFullPath($Path)
        if ($isMacHost)
        {
            $baseText = $baseText -creplace '^/private(?=/(var|tmp)(/|$))', ''
            $pathText = $pathText -creplace '^/private(?=/(var|tmp)(/|$))', ''
        }
        $comparison = if ($isWindowsHost -or $isMacHost) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
        $baseParts = $baseText.Split($separators)
        $pathParts = $pathText.Split($separators)
        $common = 0
        while ($common -lt $baseParts.Count -and $common -lt $pathParts.Count -and [string]::Equals($baseParts[$common], $pathParts[$common], $comparison)) { $common++ }
        if ($common -eq 0) { return $Path }
        $parts = @(@("..") * ($baseParts.Count - $common)) + @($pathParts | Select-Object -Skip $common)
        return $parts -join [IO.Path]::DirectorySeparatorChar
    }

    # Windows PowerShell 5.1 writes ' < > & as \u0027 \u003c \u003e \u0026 and PowerShell 7 writes them as they
    # are. Both hosts write them as they are, so the JSON text differs only in indentation.
    function ConvertTo-PortableJson($Value, [Int32]$Depth)
    {
        $json = $Value | ConvertTo-Json -Depth $Depth
        return [regex]::Replace($json, '(?<!\\)((?:\\\\)*)\\u00(27|3c|3e|26)', { param($match) $match.Groups[1].Value + [string][char][Convert]::ToInt32($match.Groups[2].Value, 16) }, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }

    # UTF-8 without a byte order mark on every host; Set-Content -Encoding UTF8 adds one only in Windows PowerShell 5.1.
    # A relative path is resolved against the PowerShell location, as Set-Content and Move-Item do; .NET would use
    # the process directory.
    function Write-TextFile([string]$Path, [string]$Text)
    {
        $fullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
        [IO.File]::WriteAllText($fullPath, $Text + [Environment]::NewLine, $utf8)
    }

    function ConvertTo-Severity([string]$Level)
    {
        switch ($Level)
        {
            "error" { return "error" }
            "warning" { return "warning" }
            "note" { return "info" }
            "info" { return "info" }
            default { return "hidden" }
        }
    }

    function Add-Diagnostic($RuleId, $Severity, $Project, $Framework, $Path, $Line, $Column, $Message)
    {
        if ($RuleId -notmatch "^HBCS\d{3}$") { return }
        if ($Path -and $Path -match "^file:") { $Path = ([Uri]$Path).LocalPath }
        if ($Path -and $targetRoot -and [IO.Path]::IsPathRooted($Path)) { $Path = ConvertTo-RelativePath $targetRoot $Path }
        $diagnostics.Add([PSCustomObject][ordered]@{
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
            isNew = $true
            affectsVerdict = $false
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
                # Diagnostics suppressed in source (#pragma, SuppressMessage) are logged with a suppression.
                if (@($result.suppressions | Where-Object { $null -ne $_ }).Count -gt 0) { continue }
                $location = @($result.locations)[0].physicalLocation
                $region = $location.region
                $project = $result.properties.project
                $framework = $result.properties.targetFramework
                if (-not $project -and $sarifMatch.Success) { $project = $sarifMatch.Groups["project"].Value }
                if (-not $framework -and $sarifMatch.Success) { $framework = $sarifMatch.Groups["framework"].Value }
                # Under the standalone runner error-severity findings are logged as warnings that carry their policy severity.
                $policySeverity = $result.properties.customProperties.policySeverity
                $severity = if ($policySeverity) { ConvertTo-Severity $policySeverity } else { ConvertTo-Severity $result.level }
                Add-Diagnostic $result.ruleId $severity $project $framework $location.artifactLocation.uri $region.startLine $region.startColumn $result.message.text
            }
        }
    }

    # SARIF is the primary source. Console output is parsed only when SARIF yielded nothing,
    # otherwise every diagnostic would be counted twice.
    if ($diagnostics.Count -eq 0)
    {
        $pattern = [regex]"^(?<path>.+?)\((?<line>\d+),(?<column>\d+)\):\s*(?<severity>error|warning|info)\s+(?<id>HBCS\d{3}):\s*(?<message>.*?)(?:\s+\(https?://[^)]*\))?(?:\s+\[.*\])?$"
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
    $normalized = @($uniqueDiagnostics.Values | Sort-Object path, line, column, ruleId, message)

    # The path is hashed with '\' separators on every OS, the form Windows has always used, so a baseline created
    # on one OS matches the same findings on another and baselines written before this rule still match.
    function Get-Fingerprint($Diagnostic)
    {
        $portablePath = "$($Diagnostic.path)".Replace('/', '\')
        $bytes = [Text.Encoding]::UTF8.GetBytes("$($Diagnostic.ruleId)|$portablePath|$($Diagnostic.message)")
        return [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($bytes)).Replace("-", "").ToLowerInvariant()
    }

    # Baseline entries are a multiset: a fingerprint has no line, so two identical findings in one file share it
    # and only the occurrences beyond the stored count are new. Within one fingerprint the earliest lines are existing.
    $baselineSummary = [ordered]@{ new = $normalized.Count; existing = 0; resolved = 0; state = "notUsed" }
    $codeDiagnostics = @($normalized | Where-Object { $_.ruleId -ne $configurationRuleId })
    $currentCounts = [ordered]@{}
    foreach ($diagnostic in $codeDiagnostics)
    {
        $fingerprint = Get-Fingerprint $diagnostic
        if ($currentCounts.Contains($fingerprint)) { $currentCounts[$fingerprint]["count"] = $currentCounts[$fingerprint]["count"] + 1 }
        else { $currentCounts[$fingerprint] = [ordered]@{ fingerprint = $fingerprint; count = 1; ruleId = $diagnostic.ruleId; path = $diagnostic.path; message = $diagnostic.message } }
    }

    if (-not [string]::IsNullOrWhiteSpace($BaselinePath))
    {
        if ($CreateBaseline)
        {
            if ($AnalysisStatus -ne "passed" -or $ExecutionErrors.Count -gt 0) { throw "A baseline can only be created when the analysis completed without execution errors." }
            $baseline = [ordered]@{
                schemaVersion = 2
                toolVersion = $ToolVersion
                configurationHash = $ConfigurationHash
                target = $Target
                createdAt = [DateTimeOffset]::UtcNow.ToString("o")
                entries = @($currentCounts.Values)
            }
            $baselineTemp = "$BaselinePath.$RunId.tmp"
            Write-TextFile $baselineTemp (ConvertTo-PortableJson $baseline 8)
            Move-Item -LiteralPath $baselineTemp -Destination $BaselinePath -Force
            $storedCounts = @{}
            foreach ($entry in $currentCounts.Values) { $storedCounts[$entry["fingerprint"]] = $entry["count"] }
            $state = "created"
        }
        elseif (Test-Path -LiteralPath $BaselinePath)
        {
            $saved = Get-Content -LiteralPath $BaselinePath -Raw -Encoding UTF8 | ConvertFrom-Json
            $storedCounts = @{}
            # Schema 1 stored one fingerprint per diagnostic; repeated fingerprints are counted the same way.
            foreach ($fingerprint in @($saved.fingerprints)) { if ($fingerprint) { $storedCounts["$fingerprint"] = 1 + [Int32]$storedCounts["$fingerprint"] } }
            foreach ($entry in @($saved.entries)) { if ($entry.fingerprint) { $storedCounts["$($entry.fingerprint)"] = [Int32]$entry.count + [Int32]$storedCounts["$($entry.fingerprint)"] } }
            $state = if ($saved.toolVersion -eq $ToolVersion -and $saved.configurationHash -eq $ConfigurationHash) { "matched" } else { "reviewRequired" }
        }
        else
        {
            throw "Baseline file not found: $BaselinePath"
        }

        $remaining = @{}
        foreach ($key in $storedCounts.Keys) { $remaining[$key] = $storedCounts[$key] }
        foreach ($diagnostic in ($codeDiagnostics | Sort-Object line, column))
        {
            $fingerprint = Get-Fingerprint $diagnostic
            if ([Int32]$remaining[$fingerprint] -gt 0)
            {
                $remaining[$fingerprint] = [Int32]$remaining[$fingerprint] - 1
                $diagnostic.isNew = $false
            }
        }
        $existingCount = @($normalized | Where-Object { -not $_.isNew }).Count
        $resolvedCount = 0
        foreach ($value in $remaining.Values) { $resolvedCount += [Int32]$value }
        $baselineSummary = [ordered]@{ new = $normalized.Count - $existingCount; existing = $existingCount; resolved = $resolvedCount; state = $state }
    }

    foreach ($diagnostic in $normalized)
    {
        $diagnostic.affectsVerdict = $diagnostic.isNew -and $diagnostic.ruleId -ne $configurationRuleId -and $severityRank[$diagnostic.severity] -le $failOnRank
    }
    $normalized = @($normalized | Sort-Object @{ Expression = { -not $_.affectsVerdict } }, @{ Expression = { $severityRank[$_.severity] } }, project, targetFramework, path, line, column, ruleId, message)
    $verdictCount = @($normalized | Where-Object { $_.affectsVerdict }).Count

    if ($FormatStatus -eq "failed" -and $FormatFailureKind -eq "none") { $FormatFailureKind = "differences" }
    $analysisCompleted = $AnalysisStatus -eq "passed"
    $isCheckIncomplete = -not $analysisCompleted -or $FormatStatus -in @("notRun", "unknown") -or $FormatFailureKind -in @("toolError", "timeout") -or $ExecutionErrors.Count -gt 0
    $exitCode = if ($isCheckIncomplete) { 2 } elseif ($verdictCount -gt 0 -or $FormatFailureKind -eq "differences") { 1 } else { 0 }
    $status = if ($exitCode -eq 0) { "passed" } else { "failed" }
    $exitMeaning = @{ 0 = "passed"; 1 = "violations to fix"; 2 = "the check could not run or complete" }[$exitCode]
    $resultObject = [ordered]@{
        schemaVersion = 1
        toolVersion = $ToolVersion
        runId = $RunId
        target = $Target
        configurationHash = $ConfigurationHash
        status = $status
        exitCode = $exitCode
        failOn = $FailOn
        formatStatus = $FormatStatus
        formatFailureKind = $FormatFailureKind
        formatFiles = @($FormatFiles)
        buildExitCode = $BuildExitCode
        buildErrors = @($BuildErrors)
        analysisStatus = $AnalysisStatus
        analysisCompleted = $analysisCompleted
        analysisCoverage = $AnalysisCoverage
        startedAt = $StartedAt
        finishedAt = [DateTimeOffset]::UtcNow.ToString("o")
        timings = $Timings
        totalDiagnostics = $normalized.Count
        verdictDiagnostics = $verdictCount
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
    $report.Add("- Overall status: **$status** (exit code $exitCode`: $exitMeaning)")
    $report.Add("- Fails on: $FailOn and more severe$(if ($baselineSummary.state -ne 'notUsed') { ', new diagnostics only' })")
    $report.Add("- Format status: **$FormatStatus**$(if ($FormatFailureKind -ne 'none') { " ($FormatFailureKind)" })")
    $report.Add("- Build exit code: **$BuildExitCode**")
    $coverageText = if ($null -ne $AnalysisCoverage) { "; $($AnalysisCoverage.analyzed) of $($AnalysisCoverage.compilations) project builds analyzed" } else { "" }
    $report.Add("- Analysis status: **$AnalysisStatus** (completed: $analysisCompleted$coverageText)")
    $report.Add("- HBCS diagnostics: $($normalized.Count), $verdictCount affect the verdict (shown $($displayed.Count), omitted $($resultObject.omittedDiagnostics))")
    if ($baselineSummary.state -ne "notUsed") { $report.Add("- Baseline: $($baselineSummary.state), new $($baselineSummary.new), existing $($baselineSummary.existing), resolved $($baselineSummary.resolved)") }
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
    if ($FormatFailureKind -eq "differences" -or ($FormatStatus -eq "passed" -and @($FormatFiles).Count -gt 0))
    {
        $isFixed = $FormatFailureKind -ne "differences"
        $report.Add("")
        $report.Add($(if ($isFixed) { "## Whitespace formatting fixed" } else { "## Whitespace formatting differences" }))
        $report.Add("")
        foreach ($file in @($FormatFiles)) { $report.Add("- ``$($file.path)`` line(s) $(@($file.lines) -join ', ')") }
        if (-not $isFixed)
        {
            if (@($FormatFiles).Count -eq 0) { $report.Add("- The file list is not available; see the console output.") }
            $report.Add("")
            $report.Add("Run ``dotnet format whitespace `"$Target`"`` or the check with ``-Fix`` to apply the .editorconfig whitespace rules.")
        }
    }
    foreach ($diagnostic in $displayed)
    {
        $verdictText = if ($diagnostic.ruleId -eq $configurationRuleId) { "does not affect the verdict (configuration problem: fix .editorconfig)" }
            elseif (-not $diagnostic.isNew) { "does not affect the verdict (existing in the baseline)" }
            elseif (-not $diagnostic.affectsVerdict) { "does not affect the verdict (below -FailOn $FailOn)" }
            else { "affects the verdict" }
        $report.Add("")
        $report.Add("## $($diagnostic.ruleId) $([char]0x00B7) $($diagnostic.severity) $([char]0x00B7) $(if ($diagnostic.isNew) { 'new' } else { 'existing' })")
        $report.Add("")
        $report.Add("- Location: ``$($diagnostic.path):$($diagnostic.line):$($diagnostic.column)``")
        if ($diagnostic.project) { $report.Add("- Project/TFM: ``$($diagnostic.project)`` / ``$($diagnostic.targetFramework)``") }
        $report.Add("- Diagnostic: $($diagnostic.message -replace '\|', '\\|')")
        $report.Add("- Verdict: $verdictText")
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
        Write-TextFile $reportTemp ($report -join [Environment]::NewLine)
        Write-TextFile $jsonTemp (ConvertTo-PortableJson $resultObject 12)
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

    return [PSCustomObject]$resultObject
}
