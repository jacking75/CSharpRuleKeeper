# Entry point for coding-agent Stop hooks (Claude Code, Codex CLI) and generic exit-code hooks.
# JSON protocol: a block is {"decision":"block"} on stdout, a notice for the human is {"systemMessage":...}; exit 0.
# Exit-code protocol: a block is exit 2 with the reason on stderr, a notice is exit 1 with the text on stderr.
# The hook blocks only for what the agent can fix (HBCS verdict, whitespace differences, compile errors in code).
# Everything else, including its own failures and bad arguments, becomes a visible notice and never a silent pass.
# Like the checker it has no [CmdletBinding()] and takes strings, so bad arguments reach the script body.
param(
    [string]$Solution,
    [string]$ReportPath,
    [string]$MaxRetries = "3",
    [string]$ChangeDetection = "auto",
    [string]$Protocol = "auto",
    [string]$TimeoutSeconds = "600",
    [string]$FailOn = "warning",
    [string]$BaselinePath
)

$ErrorActionPreference = "Stop"
$unboundArguments = @($args)
$maxReasonLength = 4000
$maxListedDiagnostics = 20
$maxListedCompileErrors = 10
$maxListedFormatFiles = 10
$timeoutGraceSeconds = 60
$relevantFilePattern = '\.(cs|csproj|props|targets|editorconfig|globalconfig)$'
$ignoredPathPattern = '(^|/)(bin|obj)/'
$script:useJsonProtocol = $Protocol -in @("claude", "codex")
$script:inputProblem = $null

try { [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false) } catch { }

function Complete-Hook([ValidateSet("allow", "notice", "block")][string]$Kind, [string]$Text)
{
    if ($script:inputProblem)
    {
        if ($Kind -eq "allow") { $Kind = "notice"; $Text = "CSharpRuleKeeper passed." }
        $Text = "$Text`n(CSharpRuleKeeper: $($script:inputProblem))"
    }

    if ($script:useJsonProtocol)
    {
        if ($Kind -eq "block") { [Console]::Out.Write((@{ decision = "block"; reason = $Text } | ConvertTo-Json -Compress)) }
        elseif ($Kind -eq "notice") { [Console]::Out.Write((@{ systemMessage = $Text } | ConvertTo-Json -Compress)) }
        [Console]::Out.Flush()
        exit 0
    }

    if ($Kind -eq "allow") { exit 0 }
    [Console]::Error.WriteLine($Text)
    exit $(if ($Kind -eq "block") { 2 } else { 1 })
}

# Agents send UTF-8 JSON. [Console]::In would decode it with the OEM code page and corrupt non-ASCII text,
# so the raw bytes are decoded as UTF-8; a byte order mark (UTF-8 or UTF-16) is honored and removed.
function Read-StandardInput
{
    if (-not [Console]::IsInputRedirected) { return "" }
    $reader = [IO.StreamReader]::new([Console]::OpenStandardInput(), [Text.UTF8Encoding]::new($false), $true)
    try { return $reader.ReadToEnd().TrimStart([char]0xFEFF) } finally { $reader.Dispose() }
}

function Get-ArgumentErrors
{
    $errors = [Collections.Generic.List[string]]::new()
    $number = 0
    if ($unboundArguments.Count -gt 0) { $errors.Add("unknown or extra argument(s): $($unboundArguments -join ' ')") }
    if (-not [Int32]::TryParse($MaxRetries, [ref]$number) -or $number -lt 1 -or $number -gt 20) { $errors.Add("-MaxRetries must be an integer from 1 to 20, got '$MaxRetries'") }
    if (-not [Int32]::TryParse($TimeoutSeconds, [ref]$number) -or $number -lt 1 -or $number -gt 86400) { $errors.Add("-TimeoutSeconds must be an integer from 1 to 86400, got '$TimeoutSeconds'") }
    if ($ChangeDetection -notin @("auto", "always", "never")) { $errors.Add("-ChangeDetection must be auto, always or never, got '$ChangeDetection'") }
    if ($Protocol -notin @("auto", "claude", "codex", "exitcode")) { $errors.Add("-Protocol must be auto, claude, codex or exitcode, got '$Protocol'") }
    if ($FailOn -notin @("error", "warning", "info")) { $errors.Add("-FailOn must be error, warning or info, got '$FailOn'") }
    return ,$errors.ToArray()
}

function ConvertTo-ArgumentString([string[]]$Arguments)
{
    return @($Arguments | ForEach-Object {
        if ($_ -notmatch '[\s"]') { $_ } else { '"' + ($_ -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"' }
    }) -join " "
}

function Invoke-Git([string]$Directory, [string[]]$Arguments)
{
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = "git"
    $startInfo.Arguments = ConvertTo-ArgumentString (@("-C", $Directory, "-c", "core.quotepath=false") + $Arguments)
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    try
    {
        $process = [Diagnostics.Process]::Start($startInfo)
    }
    catch
    {
        return [PSCustomObject]@{ ExitCode = -1; Output = "" }
    }

    $stdout = $process.StandardOutput.ReadToEndAsync()
    $null = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    $result = [PSCustomObject]@{ ExitCode = $process.ExitCode; Output = $stdout.Result }
    $process.Dispose()
    return $result
}

function Get-Hash([string]$Text)
{
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    return [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($bytes)).Replace("-", "").ToLowerInvariant()
}

# Identifies the state a check would see: HEAD, the content of every relevant changed file and the settings
# that change the verdict. Paths from "git status --porcelain" are relative to the repository top level.
# Returns $null outside git, where every Stop is checked.
function Get-StateFingerprint([string]$Directory, [string[]]$Settings)
{
    $topLevel = Invoke-Git $Directory @("rev-parse", "--show-toplevel")
    if ($topLevel.ExitCode -ne 0) { return $null }
    $repositoryRoot = [IO.Path]::GetFullPath($topLevel.Output.Trim())
    $status = Invoke-Git $Directory @("status", "--porcelain=v1", "-z", "-uall")
    if ($status.ExitCode -ne 0) { return $null }
    $head = Invoke-Git $Directory @("rev-parse", "HEAD")
    $parts = [Collections.Generic.List[string]]::new()
    $parts.Add("head=$(if ($head.ExitCode -eq 0) { $head.Output.Trim() } else { 'none' })")
    foreach ($setting in $Settings) { $parts.Add($setting) }
    $entries = @($status.Output -split "`0" | Where-Object { $_ })
    $paths = [Collections.Generic.List[string]]::new()
    for ($index = 0; $index -lt $entries.Count; $index++)
    {
        $entry = $entries[$index]
        if ($entry.Length -lt 4) { continue }
        if ($entry.Substring(0, 2) -match "[RC]") { $index++ }
        $path = $entry.Substring(3)
        if ($path -match $relevantFilePattern -and $path -notmatch $ignoredPathPattern) { $paths.Add($path) }
    }
    foreach ($path in ($paths | Sort-Object -Unique))
    {
        $fullPath = Join-Path $repositoryRoot $path
        $content = if (Test-Path -LiteralPath $fullPath -PathType Leaf) { (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash } else { "deleted" }
        $parts.Add("$path|$content")
    }
    return Get-Hash ($parts -join "`n")
}

function Read-JsonFile([string]$Path)
{
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return $null }
}

function Write-JsonFile([string]$Path, $Value)
{
    $Value | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Resolve-FullPath([string]$Path, [string]$BasePath)
{
    if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
    return [IO.Path]::GetFullPath((Join-Path $BasePath $Path))
}

function Find-SolutionPath([string]$ProjectDirectory)
{
    if (-not [string]::IsNullOrWhiteSpace($Solution)) { return (Resolve-FullPath $Solution $ProjectDirectory) }
    if (-not [string]::IsNullOrWhiteSpace($env:CSHARPRULEKEEPER_SOLUTION)) { return (Resolve-FullPath $env:CSHARPRULEKEEPER_SOLUTION $ProjectDirectory) }
    if (-not (Test-Path -LiteralPath $ProjectDirectory -PathType Container)) { return $null }
    foreach ($pattern in @("\.slnx?$", "\.csproj$"))
    {
        $candidates = @(Get-ChildItem -LiteralPath $ProjectDirectory -File | Where-Object { $_.Name -match $pattern })
        if ($candidates.Count -eq 1) { return $candidates[0].FullName }
        if ($candidates.Count -gt 1) { return $null }
    }

    return $null
}

function Invoke-Checker([string]$Target, [string]$MarkdownPath, [string]$JsonPath, [string]$Baseline)
{
    $checkerArguments = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $PSScriptRoot "Invoke-CSharpRuleKeeper.ps1"),
        "-Solution", $Target, "-OutputPath", $MarkdownPath, "-JsonOutputPath", $JsonPath,
        "-TimeoutSeconds", $TimeoutSeconds, "-FailOn", $FailOn
    )
    if ($Baseline) { $checkerArguments += @("-BaselinePath", $Baseline) }
    if (-not [string]::IsNullOrWhiteSpace($env:CSHARPRULEKEEPER_ANALYZER_PATH))
    {
        $checkerArguments += @("-AnalyzerPath", $env:CSHARPRULEKEEPER_ANALYZER_PATH)
    }

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = (Get-Process -Id $PID).Path
    $startInfo.Arguments = ConvertTo-ArgumentString $checkerArguments
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $startInfo.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    $process = [Diagnostics.Process]::Start($startInfo)
    # The checker prints the whole build log; drain it so stdout of this hook stays protocol-only.
    $null = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    # The checker stops its own dotnet steps at -TimeoutSeconds in total; the grace period is a safety net.
    $isCompleted = $process.WaitForExit(([Int32]$TimeoutSeconds + $timeoutGraceSeconds) * 1000)
    if (-not $isCompleted)
    {
        & taskkill /PID $process.Id /T /F 2>$null | Out-Null
        $process.WaitForExit()
    }
    $exitCode = if ($isCompleted) { $process.ExitCode } else { -1 }
    $process.Dispose()
    return [PSCustomObject]@{ ExitCode = $exitCode; ErrorText = $stderr.Result; TimedOut = -not $isCompleted }
}

function Format-Diagnostic($Diagnostic)
{
    return "$($Diagnostic.ruleId) $($Diagnostic.severity) $($Diagnostic.path):$($Diagnostic.line) $($Diagnostic.message)"
}

function Get-CodeErrors($Result)
{
    return @($Result.buildErrors | Where-Object { "$($_.code)" -match '^CS\d{4}$' -and "$($_.path)" -match '\.cs$' })
}

function New-BlockReason($Result, [string]$MarkdownPath, [Int32]$Attempt, [string]$Target)
{
    $lines = [Collections.Generic.List[string]]::new()
    $verdictDiagnostics = @($Result.diagnostics | Where-Object { $_.affectsVerdict })
    $otherDiagnostics = @($Result.diagnostics | Where-Object { -not $_.affectsVerdict -and $_.ruleId -ne "HBCS900" })
    $configurationDiagnostics = @($Result.diagnostics | Where-Object { $_.ruleId -eq "HBCS900" })
    $compileErrors = Get-CodeErrors $Result
    $lines.Add("CSharpRuleKeeper found problems (attempt $Attempt of $MaxRetries). Fix them and finish again. Full report: $MarkdownPath")
    if ($compileErrors.Count -gt 0)
    {
        $lines.Add("")
        $lines.Add("Compile errors ($($compileErrors.Count)):")
        $compileErrors | Select-Object -First $maxListedCompileErrors | ForEach-Object { $lines.Add("  $($_.code) $($_.path):$($_.line) $($_.message)") }
    }
    if ($Result.formatFailureKind -eq "differences")
    {
        $files = @($Result.formatFiles)
        $lines.Add("")
        $lines.Add("Whitespace formatting differs from .editorconfig in $($files.Count) file(s). Run 'dotnet format whitespace `"$Target`"' and finish again.")
        $files | Select-Object -First $maxListedFormatFiles | ForEach-Object { $lines.Add("  $($_.path) line(s) $(@($_.lines) -join ', ')") }
    }
    if ($verdictDiagnostics.Count -gt 0)
    {
        $lines.Add("")
        $lines.Add("$($verdictDiagnostics.Count) HBCS diagnostics to fix (most severe first):")
        $verdictDiagnostics | Select-Object -First $maxListedDiagnostics | ForEach-Object { $lines.Add("  $(Format-Diagnostic $_)") }
        if ($verdictDiagnostics.Count -gt $maxListedDiagnostics) { $lines.Add("  ... and $($verdictDiagnostics.Count - $maxListedDiagnostics) more in the report") }
        $lines.Add("")
        $lines.Add("Fix cautions:")
        $verdictDiagnostics | Select-Object -ExpandProperty ruleId -Unique | ForEach-Object {
            $rule = $_
            $caution = ($verdictDiagnostics | Where-Object { $_.ruleId -eq $rule } | Select-Object -First 1).fixCaution
            if ($caution) { $lines.Add("  $rule - $caution") }
        }
    }
    if ($otherDiagnostics.Count -gt 0)
    {
        $lines.Add("")
        $lines.Add("$($otherDiagnostics.Count) more HBCS diagnostics do not affect the verdict (below -FailOn $($Result.failOn) or existing in the baseline); they are listed in the report.")
    }
    if ($configurationDiagnostics.Count -gt 0)
    {
        $lines.Add("")
        $lines.Add("Configuration problem for the user, not for you: $($configurationDiagnostics[0].message). Do not edit .editorconfig to make a rule pass; mention it to the user.")
    }
    if (@($Result.executionErrors).Count -gt $compileErrors.Count -and $Result.exitCode -eq 2)
    {
        $lines.Add("")
        $lines.Add("The check did not fully complete: $(@($Result.executionErrors)[0])")
    }
    $lines.Add("")
    $lines.Add("Do not change public APIs, serialization contracts or protocol strings only to satisfy a rule.")
    $text = $lines -join "`n"
    if ($text.Length -gt $maxReasonLength) { $text = $text.Substring(0, $maxReasonLength) + "`n... (truncated, see the full report)" }
    return $text
}

try
{
    $inputText = Read-StandardInput
    $payload = $null
    if (-not [string]::IsNullOrWhiteSpace($inputText))
    {
        try
        {
            $payload = $inputText | ConvertFrom-Json
        }
        catch
        {
            # Most likely an agent whose payload is damaged. Skipping silently would look like a pass, so the
            # check still runs on the current directory and the problem is reported to the human.
            $preview = ($inputText -replace '\s+', ' ')
            if ($preview.Length -gt 80) { $preview = $preview.Substring(0, 80) + "..." }
            $script:inputProblem = "Hook input is not valid JSON ($preview); checked the current directory instead."
        }
    }

    if ($Protocol -eq "exitcode") { $script:useJsonProtocol = $false }
    elseif ($Protocol -eq "auto") { $script:useJsonProtocol = ($null -ne $payload -and $null -ne $payload.hook_event_name) -or $null -ne $script:inputProblem }

    $argumentErrors = Get-ArgumentErrors
    if ($argumentErrors.Count -gt 0)
    {
        Complete-Hook "notice" "CSharpRuleKeeper hook is misconfigured, so nothing was checked: $($argumentErrors -join '; '). Fix the hook arguments in the agent settings."
    }

    if ($ChangeDetection -eq "never") { Complete-Hook "allow" "" }
    if ($null -ne $payload -and $payload.hook_event_name -and $payload.hook_event_name -notin @("Stop", "SubagentStop")) { Complete-Hook "allow" "" }

    $projectDirectory = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR }
        elseif ($payload -and $payload.cwd) { "$($payload.cwd)" }
        else { (Get-Location).Path }
    # Without a readable payload the loop flag is unknown; counting every attempt keeps the retry limit effective.
    $isStopHookActive = ($null -ne $payload -and $payload.stop_hook_active -eq $true) -or $null -ne $script:inputProblem
    $sessionId = if ($payload -and $payload.session_id) { "$($payload.session_id)" } else { "default" }
    $sessionId = [regex]::Replace($sessionId, "[^A-Za-z0-9_-]", "_")

    $stateDirectory = if ($env:CSHARPRULEKEEPER_STATE_DIR) { $env:CSHARPRULEKEEPER_STATE_DIR } else { Join-Path $env:LOCALAPPDATA "CSharpRuleKeeper\hook-state" }
    New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
    Get-ChildItem -LiteralPath $stateDirectory -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTimeUtc -lt [DateTime]::UtcNow.AddDays(-14) } |
        Remove-Item -Force -ErrorAction SilentlyContinue
    $statePath = Join-Path $stateDirectory "$sessionId.json"
    $passedPath = Join-Path $stateDirectory "passed-$((Get-Hash ([IO.Path]::GetFullPath($projectDirectory).TrimEnd('\').ToLowerInvariant())).Substring(0, 16)).json"

    $target = Find-SolutionPath $projectDirectory
    if ($null -eq $target -or -not (Test-Path -LiteralPath $target))
    {
        Complete-Hook "notice" "CSharpRuleKeeper: no unique .sln/.slnx/.csproj found in $projectDirectory. Pass -Solution or set CSHARPRULEKEEPER_SOLUTION."
    }

    $baseline = if ($BaselinePath) { $BaselinePath } elseif ($env:CSHARPRULEKEEPER_BASELINE) { $env:CSHARPRULEKEEPER_BASELINE } else { $null }
    if ($baseline) { $baseline = Resolve-FullPath $baseline $projectDirectory }

    $state = Read-JsonFile $statePath
    $attempts = if (-not $isStopHookActive -or $null -eq $state) { 0 } else { [Int32]$state.attempts }
    $markdownPath = if ($ReportPath) { (Resolve-FullPath $ReportPath $projectDirectory) } else { Join-Path $projectDirectory ".csharprulekeeper\last-report.md" }
    $jsonPath = [IO.Path]::ChangeExtension($markdownPath, ".json")
    if ($isStopHookActive -and $attempts -ge [Int32]$MaxRetries)
    {
        Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
        Complete-Hook "notice" "CSharpRuleKeeper: retry limit ($MaxRetries) reached. Stopping without blocking. See $markdownPath"
    }

    # A state that already passed is not checked again; any other state, including the first Stop in a
    # project, is checked so that violations committed before the session are not missed.
    $fingerprint = $null
    if ($ChangeDetection -eq "auto")
    {
        $toolVersion = (Get-Content -LiteralPath (Join-Path $PSScriptRoot "version.txt") -Raw).Trim()
        $baselineHash = if ($baseline -and (Test-Path -LiteralPath $baseline -PathType Leaf)) { (Get-FileHash -LiteralPath $baseline -Algorithm SHA256).Hash } else { "none" }
        $fingerprint = Get-StateFingerprint $projectDirectory @("target=$($target.ToLowerInvariant())", "failOn=$FailOn", "baseline=$baseline|$baselineHash", "tool=$toolVersion")
        $passed = Read-JsonFile $passedPath
        if ($null -ne $fingerprint -and $null -ne $passed -and $passed.fingerprint -eq $fingerprint)
        {
            Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
            Complete-Hook "allow" ""
        }
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $markdownPath) -Force | Out-Null
    $ignoreFile = Join-Path (Split-Path -Parent $markdownPath) ".gitignore"
    if (-not (Test-Path -LiteralPath $ignoreFile)) { Set-Content -LiteralPath $ignoreFile -Value "*" -Encoding ASCII }
    Remove-Item -LiteralPath $jsonPath -Force -ErrorAction SilentlyContinue

    $checker = Invoke-Checker $target $markdownPath $jsonPath $baseline
    if ($checker.TimedOut)
    {
        Complete-Hook "notice" "CSharpRuleKeeper: the check did not finish within $TimeoutSeconds seconds and was stopped; nothing was verified. Raise -TimeoutSeconds (and the hook timeout) or check the build."
    }

    $result = Read-JsonFile $jsonPath
    if ($null -eq $result)
    {
        $errorText = "$($checker.ErrorText)".Trim()
        if ($errorText.Length -gt 1000) { $errorText = $errorText.Substring(0, 1000) + "..." }
        Complete-Hook "notice" "CSharpRuleKeeper: the check exited with code $($checker.ExitCode) and produced no result, so nothing was verified. $errorText"
    }

    $configurationDiagnostics = @($result.diagnostics | Where-Object { $_.ruleId -eq "HBCS900" })
    if ($checker.ExitCode -eq 0)
    {
        Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
        if ($null -ne $fingerprint) { Write-JsonFile $passedPath ([ordered]@{ projectDirectory = $projectDirectory; fingerprint = $fingerprint; passedAt = [DateTimeOffset]::UtcNow.ToString("o") }) }
        if ($configurationDiagnostics.Count -gt 0)
        {
            Complete-Hook "notice" "CSharpRuleKeeper passed, but .editorconfig has an invalid option value and defaults are used: $($configurationDiagnostics[0].message). See $markdownPath"
        }
        Complete-Hook "allow" ""
    }

    $isBlocking = @($result.diagnostics | Where-Object { $_.affectsVerdict }).Count -gt 0 -or
        $result.formatFailureKind -eq "differences" -or
        (Get-CodeErrors $result).Count -gt 0
    if (-not $isBlocking)
    {
        $reasons = @($result.executionErrors | Select-Object -First 3) -join " | "
        Complete-Hook "notice" "CSharpRuleKeeper could not complete the check (exit code $($checker.ExitCode)), so nothing was verified: $reasons See $markdownPath"
    }

    Write-JsonFile $statePath ([ordered]@{ attempts = $attempts + 1; lastRunId = "$($result.runId)"; lastStatus = "$($result.status)" })
    Complete-Hook "block" (New-BlockReason $result $markdownPath ($attempts + 1) $target)
}
catch
{
    Complete-Hook "notice" "CSharpRuleKeeper hook error, nothing was verified: $($_.Exception.Message)"
}
