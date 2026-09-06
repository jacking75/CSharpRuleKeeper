[CmdletBinding()]
param(
    [string]$Solution,
    [string]$BuildLogPath,
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
    [string]$ToolVersion = "1.1.0",
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
    $ruleGuidance = @{
        HBCS001 = "외부 API·직렬화·상호 운용 계약을 검토하고 안전할 때만 캡슐화한다."
        HBCS002 = "외부 계약이 아닌지 확인한 뒤 상태 접두사를 사용한다."
        HBCS003 = "자연어 판정의 한계를 고려해 복수 대상을 나타내는 이름을 사용한다."
        HBCS004 = "외부 프로토콜 문자열이 아닌지 확인한 뒤 nameof를 사용한다."
        HBCS005 = "숫자의 도메인 의미를 이름 있는 상수·열거형·변수로 표현한다."
        HBCS006 = "공개 계약과 흐름을 보존하며 책임 단위로 메서드를 분리한다."
        HBCS007 = "공개 계약과 직렬화를 보존하며 타입의 책임을 분리한다."
        HBCS008 = "실제로 private인 멤버의 접근 제한자만 제거한다."
        HBCS009 = "주석 내용을 유지하며 독립된 이전 줄로 옮긴다."
        HBCS010 = "연속 빈 줄을 한 줄로 줄인다."
        HBCS011 = "진단이 제시한 명시적 비트폭 정수 타입을 사용한다."
        HBCS012 = "의미를 보존해 식·인수·조건을 여러 줄로 나눈다."
        HBCS013 = "외부 계약 여부를 먼저 검토하고 요구된 명명 패턴을 적용한다."
        HBCS014 = "저장 방식에 맞는 필드 접두사로 모든 참조를 함께 바꾼다."
        HBCS015 = "API와 동작을 보존하며 파일의 책임을 나눈다."
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
            helpUri = "https://github.com/jacking75/CSharpRuleKeeper/blob/main/docs/rules/$RuleId.md"
            requiresContractReview = $RuleId -in @("HBCS001", "HBCS002", "HBCS003", "HBCS004", "HBCS013", "HBCS014")
        })
    }

    foreach ($sarifPath in @($SarifPaths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }))
    {
        if (-not (Test-Path -LiteralPath $sarifPath)) { continue }
        $sarif = Get-Content -LiteralPath $sarifPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $sarifName = [IO.Path]::GetFileNameWithoutExtension($sarifPath)
        $sarifMatch = [regex]::Match($sarifName, "^(?<project>.+?)-(?<framework>net[^-]+)-(?<configuration>[^-]+)$")
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

    $lines = if (-not [string]::IsNullOrWhiteSpace($BuildLogPath)) {
        @(Get-Content -LiteralPath $BuildLogPath -Encoding UTF8)
    } elseif (-not [string]::IsNullOrWhiteSpace($Solution)) {
        $output = @(& dotnet build $Solution --no-restore --configuration Debug 2>&1 | ForEach-Object { $_.ToString() })
        $BuildExitCode = $LASTEXITCODE
        $output
    } else {
        $pipelineLines.ToArray()
    }
    $pattern = [regex]"^(?<path>.+?)\((?<line>\d+),(?<column>\d+)\):\s*(?<severity>error|warning|info)\s+(?<id>HBCS\d{3}):\s*(?<message>.*?)(?:\s+\[.*\])?$"
    foreach ($line in $lines)
    {
        $match = $pattern.Match($line)
        if ($match.Success)
        {
            Add-Diagnostic $match.Groups["id"].Value $match.Groups["severity"].Value $null $null $match.Groups["path"].Value ([Int32]$match.Groups["line"].Value) ([Int32]$match.Groups["column"].Value) $match.Groups["message"].Value
        }
    }

    $normalized = @($diagnostics | Sort-Object @{ Expression = { $severityOrder[$_.severity] } }, project, targetFramework, path, line, column, ruleId, message -Unique)
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
            if ($AnalysisStatus -ne "passed") { throw "분석이 완료된 경우에만 기준선을 만들 수 있다." }
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
            throw "기준선 파일을 찾을 수 없다: $BaselinePath"
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
    $report.Add("# CSharpRuleKeeper 실행 보고서")
    $report.Add("")
    $report.Add("- 실행 ID: ``$RunId``")
    $report.Add("- 도구 버전: $ToolVersion")
    $report.Add("- 대상: ``$Target``")
    $report.Add("- 시작: $StartedAt")
    $report.Add("- 종료: $($resultObject.finishedAt)")
    $report.Add("- 전체 상태: **$status**")
    $report.Add("- 서식 상태: **$FormatStatus**")
    $report.Add("- 빌드 종료 코드: **$BuildExitCode**")
    $report.Add("- 분석 상태: **$AnalysisStatus** (완료: $analysisCompleted)")
    $report.Add("- HBCS 진단: $($normalized.Count)개 (표시 $($displayed.Count)개, 생략 $($resultObject.omittedDiagnostics)개)")
    $report.Add("- 전체 JSON: ``$JsonOutputPath``")
    $report.Add("")
    $report.Add("HBCS 진단 0개와 분석 완료는 서로 다른 상태다. analysisCompleted가 false이면 검사가 끝난 것으로 판단하지 않는다.")
    if ($ExecutionErrors.Count -gt 0)
    {
        $report.Add("")
        $report.Add("## 실행 오류")
        $report.Add("")
        foreach ($executionError in $ExecutionErrors) { $report.Add("- $executionError") }
    }
    foreach ($diagnostic in $displayed)
    {
        $report.Add("")
        $report.Add("## $($diagnostic.ruleId) · $($diagnostic.severity)")
        $report.Add("")
        $report.Add("- 위치: ``$($diagnostic.path):$($diagnostic.line):$($diagnostic.column)``")
        if ($diagnostic.project) { $report.Add("- 프로젝트/TFM: ``$($diagnostic.project)`` / ``$($diagnostic.targetFramework)``") }
        $report.Add("- 진단: $($diagnostic.message -replace '\|', '\\|')")
        $report.Add("- 도움말: $($diagnostic.helpUri)")
        $report.Add("- 수정 주의: $($ruleGuidance[$diagnostic.ruleId])")
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
        Write-Host "보고서를 생성했다: $OutputPath"
        Write-Host "구조화 결과를 생성했다: $JsonOutputPath"
    }
    catch
    {
        [Console]::Error.WriteLine("보고서 저장에 실패했다: $_")
        exit 2
    }
}
