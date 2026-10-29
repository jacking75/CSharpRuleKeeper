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
    [ValidatePattern('^[A-Za-z][A-Za-z0-9_]*$')]
    [string]$Configuration = "Debug",
    [ValidateRange(1, 10000)]
    [Int32]$MaxDiagnostics = 200,
    [ValidateRange(1, 86400)]
    [Int32]$TimeoutSeconds = 900
)

$ErrorActionPreference = "Stop"
$OutputEncoding = [Console]::OutputEncoding = [Text.UTF8Encoding]::new()
$originalLocation = Get-Location
$toolRoot = Split-Path -Parent $PSScriptRoot
$toolVersion = (Get-Content -LiteralPath (Join-Path $PSScriptRoot "version.txt") -Raw).Trim()
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
        if (-not $process.Start()) { throw "Could not start the dotnet process." }
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

function ConvertTo-SdkVersion([string]$Text)
{
    $match = [regex]::Match($Text, '^(\d+)\.(\d+)\.(\d+)')
    if (-not $match.Success) { return $null }
    $patch = [Int32]$match.Groups[3].Value
    return [PSCustomObject]@{
        Major = [Int32]$match.Groups[1].Value
        Minor = [Int32]$match.Groups[2].Value
        Patch = $patch
        Text = $Text
    }
}

function Compare-SdkVersion($Left, $Right)
{
    foreach ($part in @("Major", "Minor", "Patch"))
    {
        if ($Left.$part -ne $Right.$part) { return [Math]::Sign($Left.$part - $Right.$part) }
    }

    return 0
}

function Test-SdkRequirement([string[]]$InstalledVersions, [string]$RequestedVersion, [string]$RollForward)
{
    $requested = ConvertTo-SdkVersion $RequestedVersion
    if ($null -eq $requested) { return $true }
    $installed = @($InstalledVersions | ForEach-Object { ConvertTo-SdkVersion $_ } | Where-Object { $null -ne $_ })
    foreach ($candidate in $installed)
    {
        $isAtLeast = (Compare-SdkVersion $candidate $requested) -ge 0
        $isSameMinor = $candidate.Major -eq $requested.Major -and $candidate.Minor -eq $requested.Minor
        $isSameBand = $isSameMinor -and [Math]::Floor($candidate.Patch / 100) -eq [Math]::Floor($requested.Patch / 100)
        $isSatisfied = switch -Regex ($RollForward)
        {
            '^disable$' { (Compare-SdkVersion $candidate $requested) -eq 0 }
            '^(patch|latestPatch)$' { $isSameBand -and $isAtLeast }
            '^(feature|latestFeature)$' { $isSameMinor -and $isAtLeast }
            '^(minor|latestMinor)$' { $candidate.Major -eq $requested.Major -and $isAtLeast }
            '^(major|latestMajor)$' { $isAtLeast }
            default { $isSameBand -and $isAtLeast }
        }
        if ($isSatisfied) { return $true }
    }

    return $false
}

function Find-GlobalJson([string]$StartDirectory)
{
    $directory = $StartDirectory
    while (-not [string]::IsNullOrWhiteSpace($directory))
    {
        $candidate = Join-Path $directory "global.json"
        if (Test-Path -LiteralPath $candidate) { return $candidate }
        $parent = Split-Path -Parent $directory
        if ($parent -eq $directory) { break }
        $directory = $parent
    }

    return $null
}

function Show-Doctor
{
    $exitCode = 0
    $dotnetCommand = Get-Command dotnet -ErrorAction SilentlyContinue
    Write-Host "CSharpRuleKeeper doctor"
    Write-Host "- Tool version: $toolVersion"
    Write-Host "- Tool root: $toolRoot"
    Write-Host "- PowerShell: $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))"
    if ($null -eq $dotnetCommand)
    {
        Write-Host "- dotnet: not found"
        return 2
    }

    Write-Host "- dotnet: $($dotnetCommand.Source)"
    $sdks = @(& dotnet --list-sdks 2>&1)
    Write-Host "- Installed SDKs:"
    $sdks | ForEach-Object { Write-Host "  $_" }
    $installedVersions = @($sdks | ForEach-Object { ($_ -split "\s+")[0] })

    if (-not [string]::IsNullOrWhiteSpace($Solution))
    {
        $target = Resolve-FullPath $Solution $originalLocation.Path
        Write-Host "- Target: $target"
        $directory = if (Test-Path -LiteralPath $target -PathType Container) { $target } else { Split-Path -Parent $target }
        $globalJson = Find-GlobalJson $directory
        if ($null -eq $globalJson)
        {
            Write-Host "- Target global.json: none (the latest installed SDK is used)"
        }
        else
        {
            $sdkSection = (Get-Content -LiteralPath $globalJson -Raw -Encoding UTF8 | ConvertFrom-Json).sdk
            $requestedVersion = "$($sdkSection.version)"
            $rollForward = if ($sdkSection.rollForward) { "$($sdkSection.rollForward)" } else { "latestPatch" }
            Write-Host "- Target global.json: $globalJson (version=$(if ($requestedVersion) { $requestedVersion } else { 'any' }), rollForward=$rollForward)"
            $isSatisfied = [string]::IsNullOrWhiteSpace($requestedVersion) -or (Test-SdkRequirement $installedVersions $requestedVersion $rollForward)
            Write-Host "- Target SDK requirement: $(if ($isSatisfied) { 'satisfied' } else { 'NOT satisfied - install a matching SDK' })"
            if (-not $isSatisfied) { $exitCode = 2 }
        }
    }

    $bundledAnalyzer = Join-Path $toolRoot "analyzers\CSharpRuleKeeper.Analyzers.dll"
    if (Test-Path -LiteralPath $bundledAnalyzer)
    {
        Write-Host "- Analyzer: bundled DLL found, no tool-side SDK needed"
    }
    else
    {
        $hasToolSdk = @($installedVersions | Where-Object { $_ -match "^10\.0\.4\d{2}$" }).Count -gt 0
        Write-Host "- Analyzer: no bundled DLL; it is built from source and needs a 10.0.4xx SDK (rollForward=latestFeature)"
        Write-Host "- Tool build SDK: $(if ($hasToolSdk) { 'available' } else { 'MISSING' })"
        if (-not $hasToolSdk) { $exitCode = 2 }
    }

    Write-Host "Doctor did not restore, build or modify any file."
    return $exitCode
}

function Get-SolutionProjects([string]$SolutionPath)
{
    $listing = Invoke-DotNet @("sln", $SolutionPath, "list") (Split-Path -Parent $SolutionPath)
    if ($listing.ExitCode -ne 0) { return $null }
    $solutionDirectory = Split-Path -Parent $SolutionPath
    return @($listing.Output |
        Where-Object { $_ -match '\.(cs|vb|fs)proj$' } |
        ForEach-Object { Resolve-FullPath $_.Trim() $solutionDirectory })
}

function Get-CustomAfterTargets([string]$ProjectPath)
{
    $query = Invoke-DotNet @("msbuild", $ProjectPath, "-getProperty:CustomAfterMicrosoftCommonTargets", "-nologo") (Split-Path -Parent $ProjectPath)
    if ($query.ExitCode -ne 0)
    {
        Write-Host "WARNING: could not read CustomAfterMicrosoftCommonTargets of $ProjectPath; its own build extension may be skipped."
        return @()
    }

    $value = $query.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Last 1
    if ([string]::IsNullOrWhiteSpace($value)) { return @() }
    return @($value -split ";" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function New-CombinedTargets([string]$TargetPath, [string]$RuleKeeperTargets, [string]$DestinationPath)
{
    $isSolution = [IO.Path]::GetExtension($TargetPath) -in @(".sln", ".slnx")
    $isDirectory = Test-Path -LiteralPath $TargetPath -PathType Container
    $projects = if ($isSolution) { Get-SolutionProjects $TargetPath } elseif ($isDirectory) { @() } else { @($TargetPath) }
    if ($null -eq $projects)
    {
        Write-Host "WARNING: could not list the projects of $TargetPath; per-project build extensions are not preserved."
        $projects = @()
    }

    $imports = [Collections.Generic.List[string]]::new()
    $imports.Add("<Project>")
    if ($isDirectory)
    {
        foreach ($existingTarget in (Get-CustomAfterTargets $TargetPath))
        {
            $escapedTarget = [Security.SecurityElement]::Escape($existingTarget)
            $imports.Add("  <Import Project=`"$escapedTarget`" Condition=`"Exists('$escapedTarget')`" />")
        }
    }

    foreach ($project in $projects)
    {
        $escapedProject = [Security.SecurityElement]::Escape($project)
        foreach ($existingTarget in (Get-CustomAfterTargets $project))
        {
            $escapedTarget = [Security.SecurityElement]::Escape($existingTarget)
            $imports.Add("  <Import Project=`"$escapedTarget`" Condition=`"'`$(MSBuildProjectFullPath)' == '$escapedProject' And Exists('$escapedTarget')`" />")
        }
    }

    $imports.Add("  <Import Project=`"$([Security.SecurityElement]::Escape($RuleKeeperTargets))`" />")
    $imports.Add("</Project>")
    $imports | Set-Content -LiteralPath $DestinationPath -Encoding UTF8
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
        throw "-Solution is required to run a check. Use -Doctor for environment diagnostics or -ExplainEditorConfig for option help."
    }

    $targetPath = Resolve-FullPath $Solution $originalLocation.Path
    if (-not (Test-Path -LiteralPath $targetPath))
    {
        throw "Solution or project to check was not found: $targetPath"
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
            throw "The report output must not use a protected source, project or configuration path: $candidatePath"
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
                throw "The analyzer build failed."
            }
        }
    }
    else
    {
        $AnalyzerPath = Resolve-FullPath $AnalyzerPath $originalLocation.Path
    }

    if (-not (Test-Path -LiteralPath $AnalyzerPath))
    {
        throw "Analyzer DLL not found: $AnalyzerPath"
    }
    $analyzerWatch.Stop()

    $formatWatch = [Diagnostics.Stopwatch]::StartNew()
    $formatArguments = @("format", "whitespace", $targetPath)
    if (-not $Fix) { $formatArguments += "--verify-no-changes" }
    $format = Invoke-DotNet $formatArguments $targetDirectory
    $format.Output | ForEach-Object { Write-Host $_ }
    if ($format.TimedOut) { $executionErrors.Add("The format check exceeded the $TimeoutSeconds second limit and was stopped.") }
    $formatStatus = if ($format.ExitCode -eq 0) { "passed" } else { "failed" }
    $formatWatch.Stop()

    $buildWatch = [Diagnostics.Stopwatch]::StartNew()
    $combinedTargets = Join-Path $resultsRoot "CSharpRuleKeeper.combined.targets"
    New-CombinedTargets $targetPath (Join-Path $PSScriptRoot "CSharpRuleKeeper.targets") $combinedTargets
    $buildArguments = @(
        "build", $targetPath, "--configuration", $Configuration, "--no-incremental",
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
    if ($build.TimedOut) { $executionErrors.Add("The target build exceeded the $TimeoutSeconds second limit and was stopped together with its child processes.") }
    $sarifPaths = @(Get-ChildItem -LiteralPath $resultsRoot -Filter "*.sarif" -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
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
        $executionErrors.Add("The target build or analysis failed with exit code $buildExitCode.")
    }
    else
    {
        $analysisStatus = "unknown"
        $executionErrors.Add("Could not confirm an analysis completion marker or SARIF output.")
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
            [Console]::Error.WriteLine("Failed to save the failure report: $($_.Exception.Message)")
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
