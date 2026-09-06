[CmdletBinding()]
param(
    [string]$Solution,
    [string]$OutputPath = "coding-agent-change-report.md",
    [string]$JsonOutputPath,
    [switch]$Fix,
    [switch]$Doctor,
    [switch]$ExplainEditorConfig,
    [string]$OptionsDocumentationPath,
    [string]$DefineConstants,
    [string]$AnalyzerPath,
    [string]$BaselinePath,
    [switch]$CreateBaseline,
    [ValidateRange(1, 10000)]
    [Int32]$MaxDiagnostics = 200,
    [ValidateRange(1, 86400)]
    [Int32]$TimeoutSeconds = 900
)

$ErrorActionPreference = "Stop"
$OutputEncoding = [Console]::OutputEncoding = [Text.UTF8Encoding]::new()
$originalLocation = Get-Location
$toolRoot = Split-Path -Parent $PSScriptRoot
$toolVersion = "1.1.0"
$runId = [Guid]::NewGuid().ToString("N")
$startedAt = [DateTimeOffset]::UtcNow.ToString("o")
$resultsRoot = $null
$reportPath = $null
$configurationHash = $null
$formatStatus = "notRun"
$analysisStatus = "notRun"
$buildExitCode = -1
$executionErrors = [Collections.Generic.List[string]]::new()

function Resolve-FullPath([string]$Path, [string]$BasePath)
{
    if ([IO.Path]::IsPathRooted($Path))
    {
        return [IO.Path]::GetFullPath($Path)
    }

    return [IO.Path]::GetFullPath((Join-Path $BasePath $Path))
}

function Invoke-DotNet([string[]]$Arguments, [string]$WorkingDirectory)
{
    $quotedArguments = @($Arguments | ForEach-Object {
        if ($_ -notmatch '[\s"]') { $_ } else { '"' + ($_ -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"' }
    }) -join " "
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = "dotnet"
    $startInfo.Arguments = $quotedArguments
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try
    {
        if (-not $process.Start()) { throw "dotnet 프로세스를 시작하지 못했다." }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $completed = $process.WaitForExit($TimeoutSeconds * 1000)
        if (-not $completed)
        {
            & taskkill /PID $process.Id /T /F 2>$null | Out-Null
            $process.WaitForExit()
        }
        $process.Refresh()
        $output = @(($stdout.Result + [Environment]::NewLine + $stderr.Result) -split "`r?`n" | Where-Object { $_ -ne "" })
        $exitCode = if ($completed) { $process.ExitCode } else { 2 }
        return [PSCustomObject]@{ Output = $output; ExitCode = $exitCode; TimedOut = -not $completed }
    }
    finally
    {
        $process.Dispose()
    }
}

function Show-Doctor
{
    $dotnetCommand = Get-Command dotnet -ErrorAction SilentlyContinue
    Write-Host "CSharpRuleKeeper doctor"
    Write-Host "- 도구 버전: $toolVersion"
    Write-Host "- 도구 루트: $toolRoot"
    Write-Host "- PowerShell: $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))"
    if ($null -eq $dotnetCommand)
    {
        Write-Host "- dotnet: 찾을 수 없음"
        return 2
    }

    Write-Host "- dotnet: $($dotnetCommand.Source)"
    $sdks = @(& dotnet --list-sdks 2>&1)
    Write-Host "- 설치 SDK:"
    $sdks | ForEach-Object { Write-Host "  $_" }
    $hasRequiredSdk = @($sdks | Where-Object { $_ -match "^10\.0\.4\d{2}\s" }).Count -gt 0
    Write-Host "- 개발 SDK 정책: 10.0.400 feature band, rollForward=latestFeature"
    Write-Host "- 개발 SDK 상태: $(if ($hasRequiredSdk) { '사용 가능' } else { '요구 feature band 없음' })"

    if (-not [string]::IsNullOrWhiteSpace($Solution))
    {
        $target = Resolve-FullPath $Solution $originalLocation.Path
        Write-Host "- 대상: $target"
        $directory = if (Test-Path -LiteralPath $target -PathType Container) { $target } else { Split-Path -Parent $target }
        $globalJson = $null
        while (-not [string]::IsNullOrWhiteSpace($directory))
        {
            $candidate = Join-Path $directory "global.json"
            if (Test-Path -LiteralPath $candidate)
            {
                $globalJson = $candidate
                break
            }

            $parent = Split-Path -Parent $directory
            if ($parent -eq $directory) { break }
            $directory = $parent
        }

        Write-Host "- 대상에 적용되는 global.json: $(if ($globalJson) { $globalJson } else { '없음(dotnet 기본 탐색 정책)' })"
    }

    Write-Host "Doctor는 restore, build 또는 파일 변경을 수행하지 않았다."
    return $(if ($hasRequiredSdk) { 0 } else { 2 })
}

try
{
    if ($Doctor)
    {
        exit (Show-Doctor)
    }

    if ($ExplainEditorConfig)
    {
        & "$PSScriptRoot\Show-CSharpRuleKeeperOptions.ps1" -OutputPath $OptionsDocumentationPath
        exit $LASTEXITCODE
    }

    if ([string]::IsNullOrWhiteSpace($Solution))
    {
        throw "-Solution은 검사 실행 시 필수다. 환경 진단은 -Doctor, 옵션 설명은 -ExplainEditorConfig를 사용한다."
    }

    $targetPath = Resolve-FullPath $Solution $originalLocation.Path
    if (-not (Test-Path -LiteralPath $targetPath))
    {
        throw "검사할 솔루션 또는 프로젝트를 찾을 수 없다: $targetPath"
    }

    $targetDirectory = if (Test-Path -LiteralPath $targetPath -PathType Container) { $targetPath } else { Split-Path -Parent $targetPath }
    $configurationFiles = @(Get-ChildItem -LiteralPath $targetDirectory -Filter ".editorconfig" -File -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName)
    $configurationText = @($configurationFiles | ForEach-Object { "$(($_.FullName).Substring($targetDirectory.Length)):$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)" }) -join "|"
    $configurationBytes = [Text.Encoding]::UTF8.GetBytes($configurationText)
    $configurationHash = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($configurationBytes)).Replace("-", "").ToLowerInvariant()
    $reportPath = Resolve-FullPath $OutputPath $originalLocation.Path
    if ([string]::IsNullOrWhiteSpace($JsonOutputPath))
    {
        $JsonOutputPath = [IO.Path]::ChangeExtension($reportPath, ".json")
    }
    else
    {
        $JsonOutputPath = Resolve-FullPath $JsonOutputPath $originalLocation.Path
    }

    $protectedExtensions = @(".cs", ".csproj", ".sln", ".slnx", ".props", ".targets", ".editorconfig")
    foreach ($candidatePath in @($reportPath, $JsonOutputPath))
    {
        if ($candidatePath -eq $targetPath -or $protectedExtensions -contains [IO.Path]::GetExtension($candidatePath))
        {
            throw "보고서 출력은 보호 대상 소스/프로젝트/설정 경로를 사용할 수 없다: $candidatePath"
        }
    }

    $buildOutput = @()
    $resultsRoot = Join-Path ([IO.Path]::GetTempPath()) "CSharpRuleKeeper-$runId"
    New-Item -ItemType Directory -Path $resultsRoot | Out-Null

    $analyzerWatch = [Diagnostics.Stopwatch]::StartNew()
    if ([string]::IsNullOrWhiteSpace($AnalyzerPath))
    {
        $bundledAnalyzer = Join-Path $toolRoot "analyzers\CSharpRuleKeeper.Analyzers.dll"
        if (Test-Path -LiteralPath $bundledAnalyzer)
        {
            $AnalyzerPath = $bundledAnalyzer
        }
        else
        {
            $analyzerProject = Join-Path $toolRoot "src\CSharpRuleKeeper.Analyzers\CSharpRuleKeeper.Analyzers.csproj"
            $AnalyzerPath = Join-Path $toolRoot "src\CSharpRuleKeeper.Analyzers\bin\Release\netstandard2.0\CSharpRuleKeeper.Analyzers.dll"
            $buildAnalyzer = Invoke-DotNet @("build", $analyzerProject, "--configuration", "Release") $toolRoot
            $buildAnalyzer.Output | ForEach-Object { Write-Host $_ }
            if ($buildAnalyzer.ExitCode -ne 0)
            {
                $executionErrors.Add("Analyzer build failed with exit code $($buildAnalyzer.ExitCode).")
                $buildExitCode = $buildAnalyzer.ExitCode
                throw "Analyzer 빌드에 실패했다."
            }
        }
    }
    else
    {
        $AnalyzerPath = Resolve-FullPath $AnalyzerPath $originalLocation.Path
    }

    if (-not (Test-Path -LiteralPath $AnalyzerPath))
    {
        throw "Analyzer DLL을 찾을 수 없다: $AnalyzerPath"
    }
    $analyzerWatch.Stop()

    $formatWatch = [Diagnostics.Stopwatch]::StartNew()
    $formatArguments = @("format", "whitespace", $targetPath)
    if (-not $Fix) { $formatArguments += "--verify-no-changes" }
    $format = Invoke-DotNet $formatArguments $targetDirectory
    $format.Output | ForEach-Object { Write-Host $_ }
    if ($format.TimedOut) { $executionErrors.Add("서식 검사가 제한 시간 $TimeoutSeconds 초를 초과해 중단됐다.") }
    $formatStatus = if ($format.ExitCode -eq 0) { "passed" } else { "failed" }
    $formatWatch.Stop()

    $buildWatch = [Diagnostics.Stopwatch]::StartNew()
    $existingTargets = @(& dotnet msbuild $targetPath -getProperty:CustomAfterMicrosoftCommonTargets -nologo 2>$null) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Last 1
    $targetsPath = Join-Path $PSScriptRoot "CSharpRuleKeeper.targets"
    $combinedTargets = Join-Path $resultsRoot "CSharpRuleKeeper.combined.targets"
    $imports = [Collections.Generic.List[string]]::new()
    $imports.Add("<Project>")
    if (-not [string]::IsNullOrWhiteSpace($existingTargets))
    {
        foreach ($existingTarget in $existingTargets -split ";")
        {
            $escapedTarget = [Security.SecurityElement]::Escape($existingTarget.Trim())
            if ($escapedTarget) { $imports.Add("  <Import Project=`"$escapedTarget`" Condition=`"Exists('$escapedTarget')`" />") }
        }
    }
    $escapedRuleKeeperTargets = [Security.SecurityElement]::Escape($targetsPath)
    $imports.Add("  <Import Project=`"$escapedRuleKeeperTargets`" />")
    $imports.Add("</Project>")
    $imports | Set-Content -LiteralPath $combinedTargets -Encoding UTF8
    $buildArguments = @(
        "build", $targetPath, "--configuration", "Debug", "--no-incremental",
        "/p:CustomAfterMicrosoftCommonTargets=$combinedTargets",
        "/p:CSharpRuleKeeperAnalyzerPath=$AnalyzerPath",
        "/p:CSharpRuleKeeperResultsRoot=$resultsRoot",
        "/p:RunAnalyzersDuringBuild=true",
        "/p:RunAnalyzers=true",
        "/p:UseSharedCompilation=false"
    )
    if (-not [string]::IsNullOrWhiteSpace($DefineConstants))
    {
        $buildArguments += "/p:DefineConstants=$($DefineConstants.Replace(';', '%3B'))"
    }

    $build = Invoke-DotNet $buildArguments $targetDirectory
    $buildOutput = $build.Output
    $buildExitCode = $build.ExitCode
    $buildOutput | ForEach-Object { Write-Host $_ }
    if ($build.TimedOut) { $executionErrors.Add("대상 빌드가 제한 시간 $TimeoutSeconds 초를 초과해 자식 프로세스와 함께 중단됐다.") }
    $sarifPaths = @(Get-ChildItem -LiteralPath $resultsRoot -Filter "*.sarif" -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
    $completionMarkers = @(Get-ChildItem -LiteralPath $resultsRoot -Filter "*.completed" -File -ErrorAction SilentlyContinue)
    if ($sarifPaths.Count -gt 0)
    {
        $analysisStatus = "passed"
        foreach ($sarifPath in $sarifPaths)
        {
            $sarif = Get-Content -LiteralPath $sarifPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($sarifRun in @($sarif.runs))
            {
                foreach ($sarifResult in @($sarifRun.results))
                {
                    if ($sarifResult.level -eq "error" -and $sarifResult.ruleId -notmatch "^HBCS\d{3}$")
                    {
                        $executionErrors.Add("$($sarifResult.ruleId): $($sarifResult.message.text)")
                    }
                }
            }
        }
        if ($executionErrors.Count -gt 0) { $analysisStatus = "failed" }
    }
    elseif ($buildExitCode -ne 0)
    {
        $analysisStatus = "failed"
        $executionErrors.Add("대상 빌드 또는 분석이 종료 코드 $buildExitCode 로 실패했다.")
    }
    else
    {
        $analysisStatus = "unknown"
        $executionErrors.Add("분석 완료 marker 또는 SARIF를 확인하지 못했다.")
    }
    $buildWatch.Stop()

    $timings = [ordered]@{
        analyzerPreparationMilliseconds = $analyzerWatch.ElapsedMilliseconds
        formatMilliseconds = $formatWatch.ElapsedMilliseconds
        buildAndAnalysisMilliseconds = $buildWatch.ElapsedMilliseconds
    }

    $reportArguments = @{
        BuildOutput = $buildOutput
        OutputPath = $reportPath
        JsonOutputPath = $JsonOutputPath
        Target = $targetPath
        BuildExitCode = $buildExitCode
        FormatStatus = $formatStatus
        AnalysisStatus = $analysisStatus
        RunId = $runId
        ToolVersion = $toolVersion
        ConfigurationHash = $configurationHash
        Timings = $timings
        StartedAt = $startedAt
        SarifPaths = $sarifPaths
        ExecutionErrors = $executionErrors.ToArray()
        MaxDiagnostics = $MaxDiagnostics
    }
    if (-not [string]::IsNullOrWhiteSpace($BaselinePath)) { $reportArguments.BaselinePath = Resolve-FullPath $BaselinePath $originalLocation.Path }
    if ($CreateBaseline) { $reportArguments.CreateBaseline = $true }
    & "$PSScriptRoot\New-CodingAgentChangeReport.ps1" @reportArguments
    if (-not $?) { exit 2 }

    if ($formatStatus -ne "passed" -or $analysisStatus -ne "passed") { exit 2 }
    if ($buildExitCode -ne 0) { exit 1 }
    exit 0
}
catch
{
    $failureMessage = $_.Exception.Message
    if ($executionErrors.Count -eq 0 -or $executionErrors[$executionErrors.Count - 1] -ne $failureMessage)
    {
        $executionErrors.Add($failureMessage)
    }
    if ($reportPath)
    {
        try
        {
            & "$PSScriptRoot\New-CodingAgentChangeReport.ps1" -BuildOutput @() -OutputPath $reportPath -JsonOutputPath $JsonOutputPath -Target $targetPath -BuildExitCode $buildExitCode -FormatStatus $formatStatus -AnalysisStatus $analysisStatus -RunId $runId -ToolVersion $toolVersion -StartedAt $startedAt -ConfigurationHash $configurationHash -ExecutionErrors $executionErrors.ToArray() -MaxDiagnostics $MaxDiagnostics
        }
        catch
        {
            [Console]::Error.WriteLine("실패 보고서를 저장하지 못했다: $($_.Exception.Message)")
        }
    }
    [Console]::Error.WriteLine($failureMessage)
    exit 2
}
finally
{
    Set-Location -LiteralPath $originalLocation
    if ($null -ne $resultsRoot -and (Test-Path -LiteralPath $resultsRoot))
    {
        Remove-Item -LiteralPath $resultsRoot -Recurse -Force
    }
}
