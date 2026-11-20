# Standalone CSharpRuleKeeper check. Exit codes: 0 passed, 1 violations, 2 the check could not run or complete.
# There is deliberately no [CmdletBinding()] and every value parameter is a string: PowerShell rejects a bad
# typed value or an unknown parameter before the script body runs, which "powershell -File" reports as
# exit code 1 ("violations"). This way unknown arguments land in $args and all values are validated below,
# so argument problems exit with 2 and a message. Not coverable: an ambiguous abbreviation (-C) and a
# parameter name given without its value are still rejected by PowerShell itself with exit code 1.
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
    [string]$FailOn = "warning",
    [string]$Configuration = "Debug",
    [string]$MaxDiagnostics = "200",
    [string]$TimeoutSeconds = "900"
)

$ErrorActionPreference = "Stop"
$unboundArguments = @($args)
$originalConsoleEncoding = [Console]::OutputEncoding
$originalLocation = Get-Location
$toolRoot = Split-Path -Parent $PSScriptRoot
$toolVersion = (Get-Content -LiteralPath (Join-Path $PSScriptRoot "version.txt") -Raw).Trim()
$runId = [Guid]::NewGuid().ToString("N")
$startedAt = [DateTimeOffset]::UtcNow.ToString("o")
$minimumSdk = "8.0.100"
$resultsRoot = $null
$reportPath = $null
$targetPath = $null
$configurationHash = $null
$formatStatus = "notRun"
$formatFailureKind = "none"
$formatFiles = @()
$analysisStatus = "notRun"
$buildExitCode = -1
$deadline = $null
$executionErrors = [Collections.Generic.List[string]]::new()
$buildErrors = [Collections.Generic.List[object]]::new()
$analysisCoverage = $null

# Child dotnet processes write in the console code page; UTF-8 keeps non-ASCII messages intact.
# The original encoding is restored in the finally block so an in-process caller is not affected.
try { [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false) } catch { }

function Resolve-FullPath([string]$Path, [string]$BasePath)
{
    if ([IO.Path]::IsPathRooted($Path))
    {
        return [IO.Path]::GetFullPath($Path)
    }

    return [IO.Path]::GetFullPath((Join-Path $BasePath $Path))
}

function Get-ArgumentErrors
{
    $errors = [Collections.Generic.List[string]]::new()
    if ($unboundArguments.Count -gt 0) { $errors.Add("Unknown or extra argument(s): $($unboundArguments -join ' '). Check the parameter names.") }
    if ($FailOn -notin @("error", "warning", "info")) { $errors.Add("-FailOn must be error, warning or info, got '$FailOn'.") }
    if ($Configuration -notmatch '^[A-Za-z][A-Za-z0-9_]*$') { $errors.Add("-Configuration must be a configuration name such as Debug or Release, got '$Configuration'.") }
    $number = 0
    if (-not [Int32]::TryParse($MaxDiagnostics, [ref]$number) -or $number -lt 1 -or $number -gt 10000) { $errors.Add("-MaxDiagnostics must be an integer from 1 to 10000, got '$MaxDiagnostics'.") }
    if (-not [Int32]::TryParse($TimeoutSeconds, [ref]$number) -or $number -lt 1 -or $number -gt 86400) { $errors.Add("-TimeoutSeconds must be an integer from 1 to 86400, got '$TimeoutSeconds'.") }
    if ($CreateBaseline -and [string]::IsNullOrWhiteSpace($BaselinePath)) { $errors.Add("-CreateBaseline needs -BaselinePath to know where to write the baseline.") }
    if (-not $Doctor -and -not $ExplainEditorConfig -and [string]::IsNullOrWhiteSpace($Solution)) { $errors.Add("-Solution is required to run a check. Use -Doctor for environment diagnostics or -ExplainEditorConfig for option help.") }
    return ,$errors.ToArray()
}

# Report, JSON and baseline paths are checked before anything is written, so a refused path is never touched.
function Assert-WritablePath([string]$Path, [string]$Label)
{
    $protectedExtensions = @(".cs", ".csx", ".vb", ".fs", ".csproj", ".vbproj", ".fsproj", ".proj", ".sln", ".slnx", ".slnf", ".props", ".targets", ".editorconfig", ".globalconfig", ".ruleset", ".config", ".dll", ".exe", ".ps1")
    $protectedNames = @("global.json", "packages.lock.json", "nuget.config", ".gitignore", ".gitattributes")
    $name = [IO.Path]::GetFileName($Path)
    if ([string]::IsNullOrWhiteSpace($name)) { throw "$Label is not a file path: $Path" }
    if ($Path -eq $targetPath -or $protectedExtensions -contains [IO.Path]::GetExtension($Path).ToLowerInvariant() -or $protectedNames -contains $name.ToLowerInvariant())
    {
        throw "$Label must not use a protected source, project or configuration path: $Path"
    }
    if (Test-Path -LiteralPath $Path -PathType Container) { throw "$Label is an existing folder, not a file: $Path" }
}

function Get-RemainingMilliseconds
{
    if ($null -eq $deadline) { return [Int32]::MaxValue }
    return [Int32][Math]::Max(0, [Math]::Min([Int32]::MaxValue, ($deadline - [DateTime]::UtcNow).TotalMilliseconds))
}

function Invoke-DotNet([string[]]$Arguments, [string]$WorkingDirectory)
{
    $remaining = Get-RemainingMilliseconds
    if ($remaining -le 0)
    {
        return [PSCustomObject]@{ Output = @(); ErrorOutput = @(); ExitCode = 2; TimedOut = $true }
    }

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
    $startInfo.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $startInfo.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try
    {
        if (-not $process.Start()) { throw "Could not start the dotnet process." }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $completed = $process.WaitForExit($remaining)
        if (-not $completed)
        {
            & taskkill /PID $process.Id /T /F 2>$null | Out-Null
            $process.WaitForExit()
        }
        $process.Refresh()
        $output = @(($stdout.Result + [Environment]::NewLine + $stderr.Result) -split "`r?`n" | Where-Object { $_ -ne "" })
        $errorOutput = @($stderr.Result -split "`r?`n" | Where-Object { $_.Trim() -ne "" })
        $exitCode = if ($completed) { $process.ExitCode } else { 2 }
        return [PSCustomObject]@{ Output = $output; ErrorOutput = $errorOutput; ExitCode = $exitCode; TimedOut = -not $completed }
    }
    finally
    {
        $process.Dispose()
    }
}

# Keeps what a person needs from a failed dotnet step (for example hostfxr's "install SDK 8.0.100").
function Get-FailureSummary($Result)
{
    $lines = @($Result.ErrorOutput | Where-Object { $_ -notmatch '^\s+at ' })
    $keyLines = @($lines | Where-Object { $_ -match 'not found|Install |Requested SDK|global\.json|\berror\b' })
    if ($keyLines.Count -gt 0) { $lines = $keyLines }
    if ($lines.Count -eq 0) { $lines = @($Result.Output | Where-Object { $_ -match '\berror\b' -and $_ -notmatch '^\s+at ' }) }
    if ($lines.Count -eq 0) { $lines = @($Result.Output | Select-Object -Last 3) }
    return (@($lines | Select-Object -First 4 | ForEach-Object { $_.Trim() }) -join " | ")
}

function ConvertTo-SdkVersion([string]$Text)
{
    $match = [regex]::Match($Text, '^(\d+)\.(\d+)\.(\d+)')
    if (-not $match.Success) { return $null }
    return [PSCustomObject]@{
        Major = [Int32]$match.Groups[1].Value
        Minor = [Int32]$match.Groups[2].Value
        Patch = [Int32]$match.Groups[3].Value
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

function Read-SdkRequirement([string]$GlobalJsonPath)
{
    $sdkSection = (Get-Content -LiteralPath $GlobalJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json).sdk
    $rollForward = if ($sdkSection.rollForward) { "$($sdkSection.rollForward)" } else { "latestPatch" }
    return [PSCustomObject]@{ Version = "$($sdkSection.version)"; RollForward = $rollForward }
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
        $isSatisfied = $true
        if ($null -eq $globalJson)
        {
            Write-Host "- Target global.json: none (the latest installed SDK is used)"
        }
        else
        {
            $requirement = Read-SdkRequirement $globalJson
            Write-Host "- Target global.json: $globalJson (version=$(if ($requirement.Version) { $requirement.Version } else { 'any' }), rollForward=$($requirement.RollForward))"
            $isSatisfied = [string]::IsNullOrWhiteSpace($requirement.Version) -or (Test-SdkRequirement $installedVersions $requirement.Version $requirement.RollForward)
            Write-Host "- Target SDK requirement: $(if ($isSatisfied) { 'satisfied' } else { 'NOT satisfied - install a matching SDK' })"
            if (-not $isSatisfied) { $exitCode = 2 }
        }

        if ($isSatisfied -and (Test-Path -LiteralPath $directory))
        {
            $targetSdk = $null
            Push-Location -LiteralPath $directory
            try { $targetSdk = ConvertTo-SdkVersion ("$(@(& dotnet --version 2>$null) | Select-Object -First 1)").Trim() } finally { Pop-Location }
            if ($null -eq $targetSdk)
            {
                Write-Host "- Compiler compatibility: unknown (could not read the SDK the target uses)"
            }
            else
            {
                $isCompatible = (Compare-SdkVersion $targetSdk (ConvertTo-SdkVersion $minimumSdk)) -ge 0
                Write-Host "- Compiler compatibility: the target builds with SDK $($targetSdk.Text); the analyzer needs Roslyn 4.8 (SDK $minimumSdk or later): $(if ($isCompatible) { 'compatible' } else { 'NOT compatible - the compiler would skip the analyzer (CS9057)' })"
                if (-not $isCompatible) { $exitCode = 2 }
            }
        }
    }

    $bundledAnalyzer = Join-Path $toolRoot "analyzers\CSharpRuleKeeper.Analyzers.dll"
    if (Test-Path -LiteralPath $bundledAnalyzer)
    {
        Write-Host "- Analyzer: bundled DLL found, no tool-side SDK needed"
    }
    else
    {
        $toolRequirement = Read-SdkRequirement (Join-Path $toolRoot "global.json")
        $hasToolSdk = Test-SdkRequirement $installedVersions $toolRequirement.Version $toolRequirement.RollForward
        Write-Host "- Analyzer: no bundled DLL; it is built from source and needs an SDK matching $($toolRequirement.Version) (rollForward=$($toolRequirement.RollForward))"
        Write-Host "- Tool build SDK: $(if ($hasToolSdk) { 'available' } else { 'MISSING' })"
        if (-not $hasToolSdk) { $exitCode = 2 }
    }

    Write-Host "Doctor did not restore, build or modify any file."
    return $exitCode
}

function Get-ProjectProperties([string]$ProjectPath)
{
    $names = @("CustomAfterMicrosoftCommonTargets", "TargetFramework", "TargetFrameworks", "Language")
    $arguments = @("msbuild", $ProjectPath, "-nologo", "-p:Configuration=$Configuration") + @($names | ForEach-Object { "-getProperty:$_" })
    $query = Invoke-DotNet $arguments (Split-Path -Parent $ProjectPath)
    if ($query.ExitCode -ne 0)
    {
        Write-Host "WARNING: could not evaluate $ProjectPath; its own build extension may be skipped."
        return $null
    }

    $text = ($query.Output -join "`n")
    $start = $text.IndexOf("{")
    if ($start -lt 0) { return $null }
    try { return ($text.Substring($start) | ConvertFrom-Json).Properties } catch { return $null }
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

function Split-TargetList([string]$Value)
{
    return @("$Value" -split ";" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

# Builds the import file for this run and returns the project/TFM pairs that are expected to be compiled.
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

    $expected = [Collections.Generic.List[object]]::new()
    $imports = [Collections.Generic.List[string]]::new()
    $imports.Add("<Project>")
    if ($isDirectory)
    {
        $properties = Get-ProjectProperties $TargetPath
        foreach ($existingTarget in (Split-TargetList $properties.CustomAfterMicrosoftCommonTargets))
        {
            $escapedTarget = [Security.SecurityElement]::Escape($existingTarget)
            $imports.Add("  <Import Project=`"$escapedTarget`" Condition=`"Exists('$escapedTarget')`" />")
        }
    }

    foreach ($project in $projects)
    {
        $properties = Get-ProjectProperties $project
        if ($null -eq $properties) { continue }
        $escapedProject = [Security.SecurityElement]::Escape($project)
        foreach ($existingTarget in (Split-TargetList $properties.CustomAfterMicrosoftCommonTargets))
        {
            $escapedTarget = [Security.SecurityElement]::Escape($existingTarget)
            $imports.Add("  <Import Project=`"$escapedTarget`" Condition=`"'`$(MSBuildProjectFullPath)' == '$escapedProject' And Exists('$escapedTarget')`" />")
        }
        if ($properties.Language -eq "C#")
        {
            $frameworks = @(Split-TargetList $properties.TargetFrameworks)
            if ($frameworks.Count -eq 0) { $frameworks = @("$($properties.TargetFramework)") }
            foreach ($framework in $frameworks) { $expected.Add([PSCustomObject]@{ Project = $project; Framework = $framework }) }
        }
    }

    $imports.Add("  <Import Project=`"$([Security.SecurityElement]::Escape($RuleKeeperTargets))`" />")
    $imports.Add("</Project>")
    $imports | Set-Content -LiteralPath $DestinationPath -Encoding UTF8
    return ,$expected.ToArray()
}

# Hashes everything that can change what the analyzers report, so a baseline knows when to ask for a review.
function Get-ConfigurationHash([string]$Directory)
{
    $names = @(".editorconfig", ".globalconfig", "Directory.Build.props", "Directory.Build.targets")
    $files = [Collections.Generic.List[string]]::new()
    $parent = Split-Path -Parent $Directory
    while (-not [string]::IsNullOrWhiteSpace($parent))
    {
        foreach ($name in $names)
        {
            $candidate = Join-Path $parent $name
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { $files.Add($candidate) }
        }
        $next = Split-Path -Parent $parent
        if ($next -eq $parent) { break }
        $parent = $next
    }
    Get-ChildItem -LiteralPath $Directory -File -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { ($names -contains $_.Name -or $_.Extension -eq ".globalconfig") -and $_.FullName.Substring($Directory.Length) -notmatch '\\(bin|obj|node_modules|\.git|\.vs)\\' } |
        ForEach-Object { $files.Add($_.FullName) }
    $text = @($files | Sort-Object -Unique | ForEach-Object { "$($_.ToLowerInvariant()):$((Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash)" }) -join "|"
    $bytes = [Text.Encoding]::UTF8.GetBytes($text)
    return [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($bytes)).Replace("-", "").ToLowerInvariant()
}

function Invoke-FormatCheck([string]$TargetPath, [string]$WorkingDirectory)
{
    $formatReport = Join-Path $resultsRoot "format"
    $arguments = @("format", "whitespace", $TargetPath, "--report", $formatReport)
    if (-not $Fix) { $arguments += "--verify-no-changes" }
    $result = Invoke-DotNet $arguments $WorkingDirectory
    $result.Output | ForEach-Object { Write-Host $_ }
    $files = @()
    $reportFile = Join-Path $formatReport "format-report.json"
    if (Test-Path -LiteralPath $reportFile)
    {
        $parsed = Read-JsonFile $reportFile
        $files = @(@($parsed) | Where-Object { $null -ne $_ -and $_.FilePath } | ForEach-Object {
            [PSCustomObject]@{ path = $_.FilePath; lines = @($_.FileChanges | ForEach-Object { [Int32]$_.LineNumber } | Sort-Object -Unique | Select-Object -First 20) }
        })
    }

    if ($result.TimedOut)
    {
        $executionErrors.Add("The format check exceeded the $TimeoutSeconds second limit and was stopped.")
        return [PSCustomObject]@{ Status = "failed"; Kind = "timeout"; Files = $files }
    }
    if ($result.ExitCode -eq 0) { return [PSCustomObject]@{ Status = "passed"; Kind = "none"; Files = $files } }
    # dotnet format returns 2 when --verify-no-changes found differences; anything else is a tool failure.
    if ($result.ExitCode -eq 2 -and -not $Fix) { return [PSCustomObject]@{ Status = "failed"; Kind = "differences"; Files = $files } }
    $executionErrors.Add("dotnet format failed with exit code $($result.ExitCode): $(Get-FailureSummary $result)")
    return [PSCustomObject]@{ Status = "failed"; Kind = "toolError"; Files = @() }
}

function Get-RelativePath([string]$Path)
{
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    if ($Path -match "^file:") { $Path = ([Uri]$Path).LocalPath }
    if (-not [IO.Path]::IsPathRooted($Path)) { return $Path }
    $rootUri = [Uri](($targetDirectory.TrimEnd('\') + '\'))
    return [Uri]::UnescapeDataString($rootUri.MakeRelativeUri([Uri]([IO.Path]::GetFullPath($Path))).ToString()).Replace('/', '\')
}

# The same error arrives from the console output and from the SARIF log, and once per target framework.
# The console message ends with " (help URL)" and the SARIF one does not, so an error is identified by its
# code and location; only an error without a line falls back to its message, without that suffix.
function Add-BuildError([string]$Code, [string]$Path, $Line, $Column, [string]$Message, [string]$Project)
{
    $relativePath = Get-RelativePath $Path
    $helpSuffix = '\s+\(https?://[^\s()]+\)$'
    foreach ($existing in $buildErrors)
    {
        if ($existing.code -ne $Code -or $existing.path -ne $relativePath -or "$($existing.line)" -ne "$Line") { continue }
        if ($null -ne $Line)
        {
            if ($null -eq $existing.column -or $null -eq $Column -or "$($existing.column)" -eq "$Column") { return }
        }
        elseif (($existing.message -replace $helpSuffix, '') -eq ($Message -replace $helpSuffix, '')) { return }
    }
    $buildErrors.Add([PSCustomObject]@{ code = $Code; path = $relativePath; line = $Line; column = $Column; message = $Message; project = $Project })
}

# MSBuild canonical error format: origin(line,column): error CODE: message [project]
function Read-BuildOutputErrors([string[]]$Lines)
{
    $pattern = [regex]'^\s*(?<path>.*?)(?:\((?<line>\d+)(?:,(?<column>\d+))?(?:,\d+,\d+)?\))?\s*:\s*(?:[^:]*\s)?error\s+(?<code>[A-Za-z]+\d+)\s*:\s*(?<message>.*?)(?:\s+\[(?<project>[^\]]+)\])?\s*$'
    foreach ($line in $Lines)
    {
        $match = $pattern.Match($line)
        if (-not $match.Success -or $match.Groups["code"].Value -match '^HBCS\d{3}$') { continue }
        $lineNumber = if ($match.Groups["line"].Success) { [Int32]$match.Groups["line"].Value } else { $null }
        $columnNumber = if ($match.Groups["column"].Success) { [Int32]$match.Groups["column"].Value } else { $null }
        $project = if ($match.Groups["project"].Success) { ($match.Groups["project"].Value -split '::')[0] } else { $null }
        Add-BuildError $match.Groups["code"].Value $match.Groups["path"].Value.Trim() $lineNumber $columnNumber $match.Groups["message"].Value $project
    }
}

function Read-JsonFile([string]$Path)
{
    try { return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return $null }
}

# Proves which project/TFM compilations really ran the analyzer and explains the ones that did not.
function Measure-AnalysisCoverage($Expected, $Build)
{
    $analyzerName = [regex]::Escape([IO.Path]::GetFileNameWithoutExtension($AnalyzerPath))
    $loadFailurePattern = '^(CS8032|CS8033|CS8034|CS9057|AD0001)$'
    $entries = [Collections.Generic.List[object]]::new()
    foreach ($marker in @(Get-ChildItem -LiteralPath $resultsRoot -Filter "*.started" -File -ErrorAction SilentlyContinue))
    {
        $lines = @([IO.File]::ReadAllLines($marker.FullName, [Text.Encoding]::UTF8))
        if ($lines.Count -lt 3) { continue }
        $completedMarker = [IO.Path]::ChangeExtension($marker.FullName, ".completed")
        $entries.Add([PSCustomObject]@{ Project = $lines[0]; Framework = $lines[1]; Sarif = $lines[2]; IsCompiled = (Test-Path -LiteralPath $completedMarker) })
    }

    $missing = [Collections.Generic.List[object]]::new()
    $sarifPaths = [Collections.Generic.List[string]]::new()
    $analyzedCount = 0
    foreach ($entry in $entries)
    {
        $sarif = if (Test-Path -LiteralPath $entry.Sarif) { Read-JsonFile $entry.Sarif } else { $null }
        $hasRules = $false
        $loadFailures = @()
        if ($null -ne $sarif)
        {
            $sarifPaths.Add($entry.Sarif)
            foreach ($run in @($sarif.runs))
            {
                if (@($run.tool.driver.rules | Where-Object { "$($_.id)" -match '^HBCS\d{3}$' }).Count -gt 0) { $hasRules = $true }
                foreach ($result in @($run.results))
                {
                    if ("$($result.ruleId)" -match '^HBCS\d{3}$') { $hasRules = $true }
                    elseif ("$($result.ruleId)" -match $loadFailurePattern -and "$($result.message.text)" -match "CSharpRuleKeeper|$analyzerName")
                    {
                        # The first line is the useful part; the rest is usually a stack trace.
                        $firstLine = ("$($result.message.text)" -split "`r?`n")[0]
                        if ($firstLine.Length -gt 400) { $firstLine = $firstLine.Substring(0, 400) + "..." }
                        $loadFailures += "$($result.ruleId): $firstLine"
                    }
                    elseif ($result.level -eq "error")
                    {
                        $location = @($result.locations)[0].physicalLocation
                        Add-BuildError "$($result.ruleId)" $location.artifactLocation.uri $location.region.startLine $location.region.startColumn "$($result.message.text)" $entry.Project
                    }
                }
            }
        }

        foreach ($failure in $loadFailures) { $executionErrors.Add("The analyzer failed in $([IO.Path]::GetFileName($entry.Project)) ($($entry.Framework)): $failure") }
        if ($hasRules -and $loadFailures.Count -eq 0)
        {
            $analyzedCount++
            continue
        }

        $projectErrors = @($buildErrors | Where-Object { $_.project -eq $entry.Project })
        $reason = if ($Build.TimedOut) { "the build was stopped by the time limit" }
            elseif ($loadFailures.Count -gt 0) { "the analyzer could not run: $($loadFailures[0])" }
            elseif ($projectErrors.Count -gt 0) { "compilation failed with $($projectErrors.Count) error(s), first $($projectErrors[0].code) at $($projectErrors[0].path):$($projectErrors[0].line)" }
            elseif ($null -ne $sarif) { "the compiler ran without the CSharpRuleKeeper analyzer (no HBCS rule in its log)" }
            else { "it was not compiled; most likely a project it references failed to build" }
        $missing.Add([PSCustomObject]@{ project = $entry.Project; targetFramework = $entry.Framework; reason = $reason })
    }

    # Projects the solution lists but MSBuild never started count only when the build failed;
    # with a successful build they are excluded by the solution configuration.
    if ($Build.ExitCode -ne 0)
    {
        foreach ($item in $Expected)
        {
            $isStarted = @($entries | Where-Object { $_.Project -eq $item.Project -and ($_.Framework -eq $item.Framework -or -not $item.Framework) }).Count -gt 0
            if (-not $isStarted) { $missing.Add([PSCustomObject]@{ project = $item.Project; targetFramework = $item.Framework; reason = "the build stopped before reaching it" }) }
        }
    }

    foreach ($item in $missing) { $executionErrors.Add("Not analyzed: $(Get-RelativePath $item.project) ($($item.targetFramework)) - $($item.reason.TrimEnd('.')).") }
    if ($entries.Count -eq 0 -and $missing.Count -eq 0 -and $Build.ExitCode -eq 0) { $executionErrors.Add("No C# project was compiled, so nothing was analyzed. Check that the target contains C# projects.") }
    return [PSCustomObject]@{
        SarifPaths = $sarifPaths.ToArray()
        Coverage = [ordered]@{
            compilations = $analyzedCount + $missing.Count
            analyzed = $analyzedCount
            missing = @($missing | ForEach-Object { [ordered]@{ project = (Get-RelativePath $_.project); targetFramework = $_.targetFramework; reason = $_.reason } })
        }
    }
}

function Write-Report([string[]]$BuildOutput, [string[]]$SarifPaths, $Timings, [bool]$IsFailureReport)
{
    $reportArguments = @{
        BuildOutput = $BuildOutput
        OutputPath = $reportPath
        JsonOutputPath = $JsonOutputPath
        Target = $targetPath
        BuildExitCode = $buildExitCode
        FormatStatus = $formatStatus
        FormatFailureKind = $formatFailureKind
        FormatFiles = $formatFiles
        AnalysisStatus = $analysisStatus
        AnalysisCoverage = $analysisCoverage
        BuildErrors = $buildErrors.ToArray()
        RunId = $runId
        ToolVersion = $toolVersion
        ConfigurationHash = $configurationHash
        Timings = $Timings
        StartedAt = $startedAt
        SarifPaths = $SarifPaths
        ExecutionErrors = $executionErrors.ToArray()
        MaxDiagnostics = [Int32]$MaxDiagnostics
        FailOn = $FailOn
    }
    if (-not $IsFailureReport -and -not [string]::IsNullOrWhiteSpace($BaselinePath)) { $reportArguments.BaselinePath = $BaselinePath }
    if (-not $IsFailureReport -and $CreateBaseline) { $reportArguments.CreateBaseline = $true }
    $result = & "$PSScriptRoot\New-CodingAgentChangeReport.ps1" @reportArguments
    return $result
}

try
{
    $argumentErrors = Get-ArgumentErrors
    if ($argumentErrors.Count -gt 0)
    {
        $argumentErrors | ForEach-Object { [Console]::Error.WriteLine("Argument error: $_") }
        exit 2
    }

    if ($Doctor)
    {
        exit (Show-Doctor)
    }

    if ($ExplainEditorConfig)
    {
        & "$PSScriptRoot\Show-CSharpRuleKeeperOptions.ps1" -OutputPath $OptionsDocumentationPath
        exit $LASTEXITCODE
    }

    $deadline = [DateTime]::UtcNow.AddSeconds([Int32]$TimeoutSeconds)
    $targetPath = Resolve-FullPath $Solution $originalLocation.Path
    $candidateReportPath = Resolve-FullPath $OutputPath $originalLocation.Path
    $JsonOutputPath = if ([string]::IsNullOrWhiteSpace($JsonOutputPath)) { [IO.Path]::ChangeExtension($candidateReportPath, ".json") } else { Resolve-FullPath $JsonOutputPath $originalLocation.Path }
    Assert-WritablePath $candidateReportPath "-OutputPath"
    Assert-WritablePath $JsonOutputPath "-JsonOutputPath"
    if ($candidateReportPath -eq $JsonOutputPath) { throw "-OutputPath and -JsonOutputPath must be different files: $JsonOutputPath" }
    if ($CreateBaseline) { Assert-WritablePath (Resolve-FullPath $BaselinePath $originalLocation.Path) "-BaselinePath" }
    $reportPath = $candidateReportPath
    if (-not [string]::IsNullOrWhiteSpace($BaselinePath))
    {
        $BaselinePath = Resolve-FullPath $BaselinePath $originalLocation.Path
        if ($BaselinePath -in @($candidateReportPath, $JsonOutputPath)) { throw "-BaselinePath must not be the report or JSON path: $BaselinePath" }
        if (-not $CreateBaseline -and -not (Test-Path -LiteralPath $BaselinePath -PathType Leaf)) { throw "Baseline file not found: $BaselinePath. Create it first with -CreateBaseline." }
    }

    if (-not (Test-Path -LiteralPath $targetPath))
    {
        throw "Solution or project to check was not found: $targetPath"
    }

    $targetDirectory = if (Test-Path -LiteralPath $targetPath -PathType Container) { $targetPath } else { Split-Path -Parent $targetPath }
    $configurationHash = Get-ConfigurationHash $targetDirectory
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
            $buildAnalyzer = Invoke-DotNet @("build", $analyzerProject, "--configuration", "Release", "-nodeReuse:false") $toolRoot
            $buildAnalyzer.Output | ForEach-Object { Write-Host $_ }
            if ($buildAnalyzer.ExitCode -ne 0)
            {
                $executionErrors.Add("The analyzer build failed with exit code $($buildAnalyzer.ExitCode): $(Get-FailureSummary $buildAnalyzer)")
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
    $format = Invoke-FormatCheck $targetPath $targetDirectory
    $formatStatus = $format.Status
    $formatFailureKind = $format.Kind
    $formatFiles = @($format.Files | ForEach-Object { [PSCustomObject]@{ path = (Get-RelativePath $_.path); lines = $_.lines } })
    $formatWatch.Stop()

    $buildWatch = [Diagnostics.Stopwatch]::StartNew()
    $combinedTargets = Join-Path $resultsRoot "CSharpRuleKeeper.combined.targets"
    $expected = New-CombinedTargets $targetPath (Join-Path $PSScriptRoot "CSharpRuleKeeper.targets") $combinedTargets
    $buildArguments = @(
        "build", $targetPath, "--configuration", $Configuration, "--no-incremental", "-nodeReuse:false",
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
    Read-BuildOutputErrors $buildOutput
    $measurement = Measure-AnalysisCoverage $expected $build
    $analysisCoverage = $measurement.Coverage
    foreach ($buildError in $buildErrors)
    {
        $location = if ($buildError.path) { " at $($buildError.path)$(if ($buildError.line) { "($($buildError.line),$($buildError.column))" })" } else { "" }
        $executionErrors.Add("$($buildError.code): $($buildError.message)$location")
    }
    if ($buildExitCode -ne 0 -and -not $build.TimedOut -and $buildErrors.Count -eq 0 -and ($analysisCoverage.missing.Count -gt 0 -or $analysisCoverage.analyzed -eq 0))
    {
        $executionErrors.Add("The target build failed with exit code ${buildExitCode}: $(Get-FailureSummary $build)")
    }
    $analysisStatus = if ($analysisCoverage.analyzed -gt 0 -and $analysisCoverage.missing.Count -eq 0 -and -not $build.TimedOut -and @($executionErrors | Where-Object { $_ -like "The analyzer failed*" }).Count -eq 0) { "passed" } else { "failed" }
    $buildWatch.Stop()

    $timings = [ordered]@{
        analyzerPreparationMilliseconds = $analyzerWatch.ElapsedMilliseconds
        formatMilliseconds = $formatWatch.ElapsedMilliseconds
        buildAndAnalysisMilliseconds = $buildWatch.ElapsedMilliseconds
    }
    $result = Write-Report $buildOutput $measurement.SarifPaths $timings $false
    if ($null -eq $result) { exit 2 }
    exit ([Int32]$result.exitCode)
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
            $analysisStatus = "failed"
            $null = Write-Report @() @() $null $true
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
        Remove-Item -LiteralPath $resultsRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    try { [Console]::OutputEncoding = $originalConsoleEncoding } catch { }
}
