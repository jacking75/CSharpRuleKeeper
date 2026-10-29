[CmdletBinding()]
param(
    [string]$Solution,
    [string]$ReportPath,
    [ValidateRange(1, 20)]
    [Int32]$MaxRetries = 3,
    [ValidateSet("auto", "always", "never")]
    [string]$ChangeDetection = "auto",
    [ValidateSet("auto", "claude", "codex", "exitcode")]
    [string]$Protocol = "auto",
    [ValidateRange(1, 86400)]
    [Int32]$TimeoutSeconds = 600
)

# Entry point for coding-agent Stop hooks (Claude Code, Codex CLI).
# Blocking is only ever expressed as {"decision":"block"} on stdout (exit 0) or exit code 2.
# Every unexpected failure ends with exit 0 so a broken environment never traps the agent in a loop.
$ErrorActionPreference = "Stop"
$maxReasonLength = 4000
$maxListedDiagnostics = 20
$maxListedCompileErrors = 10
$relevantFilePattern = '\.(cs|csproj|props|targets|editorconfig)$'
$script:useJsonProtocol = $false

try { [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false) } catch { }

function Complete-Hook([ValidateSet("allow", "notice", "block")][string]$Kind, [string]$Text)
{
    if ($script:useJsonProtocol)
    {
        if ($Kind -eq "block") { [Console]::Out.Write((@{ decision = "block"; reason = $Text } | ConvertTo-Json -Compress)) }
        elseif ($Kind -eq "notice") { [Console]::Out.Write((@{ systemMessage = $Text } | ConvertTo-Json -Compress)) }
        exit 0
    }

    if ($Kind -eq "allow") { exit 0 }
    [Console]::Error.WriteLine($Text)
    exit $(if ($Kind -eq "block") { 2 } else { 0 })
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
    $startInfo.Arguments = ConvertTo-ArgumentString (@("-C", $Directory) + $Arguments)
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = [Text.Encoding]::UTF8
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

function Get-RelevantGitChanges([string]$Directory)
{
    $status = Invoke-Git $Directory @("status", "--porcelain=v1", "-z", "-uall")
    if ($status.ExitCode -ne 0) { return $null }
    $entries = @($status.Output -split "`0" | Where-Object { $_ })
    $changes = [Collections.Generic.List[string]]::new()
    for ($index = 0; $index -lt $entries.Count; $index++)
    {
        $entry = $entries[$index]
        if ($entry.Length -lt 4) { continue }
        $code = $entry.Substring(0, 2)
        if ($code -match "[RC]") { $index++ }
        $path = $entry.Substring(3)
        if ($path -match $relevantFilePattern) { $changes.Add($path) }
    }

    return ,$changes.ToArray()
}

function Get-ChangeFingerprint([string]$Directory, [string[]]$Paths)
{
    $parts = foreach ($path in ($Paths | Sort-Object))
    {
        $item = Get-Item -LiteralPath (Join-Path $Directory $path) -ErrorAction SilentlyContinue
        if ($null -eq $item) { "$path|deleted" } else { "$path|$($item.Length)|$($item.LastWriteTimeUtc.Ticks)" }
    }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($parts -join "`n"))
    return [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($bytes)).Replace("-", "").ToLowerInvariant()
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
    foreach ($pattern in @("\.slnx?$", "\.csproj$"))
    {
        $candidates = @(Get-ChildItem -LiteralPath $ProjectDirectory -File | Where-Object { $_.Name -match $pattern })
        if ($candidates.Count -eq 1) { return $candidates[0].FullName }
        if ($candidates.Count -gt 1) { return $null }
    }

    return $null
}

function Invoke-Checker([string]$Target, [string]$MarkdownPath, [string]$JsonPath)
{
    $checkerArguments = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $PSScriptRoot "Invoke-CSharpRuleKeeper.ps1"),
        "-Solution", $Target, "-OutputPath", $MarkdownPath, "-JsonOutputPath", $JsonPath, "-TimeoutSeconds", $TimeoutSeconds
    )
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
    $process = [Diagnostics.Process]::Start($startInfo)
    # The checker prints the whole build log; drain it so stdout of this hook stays protocol-only.
    $null = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    $exitCode = $process.ExitCode
    $process.Dispose()
    return [PSCustomObject]@{ ExitCode = $exitCode; ErrorText = $stderr.Result }
}

function Format-Diagnostic($Diagnostic)
{
    return "$($Diagnostic.ruleId) $($Diagnostic.path):$($Diagnostic.line) $($Diagnostic.message)"
}

function New-BlockReason($Result, [string]$MarkdownPath, [Int32]$Attempt)
{
    $lines = [Collections.Generic.List[string]]::new()
    $diagnostics = @($Result.diagnostics)
    $compileErrors = @($Result.executionErrors | Where-Object { $_ -match '^CS\d{4}:' })
    $lines.Add("CSharpRuleKeeper found problems (attempt $Attempt of $MaxRetries). Fix them and finish again. Full report: $MarkdownPath")
    if ($compileErrors.Count -gt 0)
    {
        $lines.Add("")
        $lines.Add("Compile errors ($($compileErrors.Count)):")
        $compileErrors | Select-Object -First $maxListedCompileErrors | ForEach-Object { $lines.Add("  $_") }
    }
    if ($Result.formatStatus -eq "failed")
    {
        $lines.Add("")
        $lines.Add("Whitespace formatting differs from .editorconfig. Run 'dotnet format whitespace <solution>' and finish again.")
    }
    if ($diagnostics.Count -gt 0)
    {
        $lines.Add("")
        $lines.Add("$($Result.totalDiagnostics) HBCS diagnostics (most severe first):")
        $diagnostics | Select-Object -First $maxListedDiagnostics | ForEach-Object { $lines.Add("  $(Format-Diagnostic $_)") }
        if ($diagnostics.Count -gt $maxListedDiagnostics) { $lines.Add("  ... and $($diagnostics.Count - $maxListedDiagnostics) more in the report") }
        $lines.Add("")
        $lines.Add("Fix cautions:")
        $diagnostics | Select-Object -ExpandProperty ruleId -Unique | ForEach-Object {
            $rule = $_
            $caution = ($diagnostics | Where-Object { $_.ruleId -eq $rule } | Select-Object -First 1).fixCaution
            if ($caution) { $lines.Add("  $rule - $caution") }
        }
    }
    $lines.Add("")
    $lines.Add("Do not change public APIs, serialization contracts or protocol strings only to satisfy a rule.")
    $text = $lines -join "`n"
    if ($text.Length -gt $maxReasonLength) { $text = $text.Substring(0, $maxReasonLength) + "`n... (truncated, see the full report)" }
    return $text
}

try
{
    $inputText = if ([Console]::IsInputRedirected) { [Console]::In.ReadToEnd() } else { "" }
    $payload = $null
    if (-not [string]::IsNullOrWhiteSpace($inputText))
    {
        try { $payload = $inputText | ConvertFrom-Json }
        catch
        {
            [Console]::Error.WriteLine("CSharpRuleKeeper hook: stdin is not valid JSON, skipping the check.")
            exit 0
        }
    }

    $script:useJsonProtocol = switch ($Protocol)
    {
        "exitcode" { $false }
        "auto" { $null -ne $payload -and $null -ne $payload.hook_event_name }
        default { $true }
    }
    if ($ChangeDetection -eq "never") { Complete-Hook "allow" "" }
    if ($null -ne $payload -and $payload.hook_event_name -and $payload.hook_event_name -notin @("Stop", "SubagentStop")) { Complete-Hook "allow" "" }

    $projectDirectory = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR }
        elseif ($payload -and $payload.cwd) { "$($payload.cwd)" }
        else { (Get-Location).Path }
    $isStopHookActive = $null -ne $payload -and $payload.stop_hook_active -eq $true
    $sessionId = if ($payload -and $payload.session_id) { "$($payload.session_id)" } else { "default" }
    $sessionId = [regex]::Replace($sessionId, "[^A-Za-z0-9_-]", "_")

    $stateDirectory = if ($env:CSHARPRULEKEEPER_STATE_DIR) { $env:CSHARPRULEKEEPER_STATE_DIR } else { Join-Path $env:LOCALAPPDATA "CSharpRuleKeeper\hook-state" }
    New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
    Get-ChildItem -LiteralPath $stateDirectory -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTimeUtc -lt [DateTime]::UtcNow.AddDays(-14) } |
        Remove-Item -Force -ErrorAction SilentlyContinue
    $statePath = Join-Path $stateDirectory "$sessionId.json"
    $seenPath = Join-Path $stateDirectory "$sessionId.seen.json"

    $target = Find-SolutionPath $projectDirectory
    if ($null -eq $target -or -not (Test-Path -LiteralPath $target))
    {
        Complete-Hook "notice" "CSharpRuleKeeper: no unique .sln/.slnx/.csproj found in $projectDirectory. Pass -Solution or set CSHARPRULEKEEPER_SOLUTION."
    }

    $state = Read-JsonFile $statePath
    $attempts = if (-not $isStopHookActive -or $null -eq $state) { 0 } else { [Int32]$state.attempts }
    $markdownPath = if ($ReportPath) { (Resolve-FullPath $ReportPath $projectDirectory) } else { Join-Path $projectDirectory ".csharprulekeeper\last-report.md" }
    $jsonPath = [IO.Path]::ChangeExtension($markdownPath, ".json")
    if ($isStopHookActive -and $attempts -ge $MaxRetries)
    {
        Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
        Complete-Hook "notice" "CSharpRuleKeeper: retry limit ($MaxRetries) reached. Stopping without blocking. See $markdownPath"
    }

    $head = ""
    $fingerprint = $null
    $seen = Read-JsonFile $seenPath
    if ($ChangeDetection -eq "auto")
    {
        $changes = Get-RelevantGitChanges $projectDirectory
        if ($null -ne $changes)
        {
            $head = (Invoke-Git $projectDirectory @("rev-parse", "HEAD")).Output.Trim()
            if ($null -eq $seen) { $seen = [PSCustomObject]@{ head = $head; passedFingerprint = "" } }
            $fingerprint = Get-ChangeFingerprint $projectDirectory $changes
            $isHeadChanged = $seen.head -ne $head
            if (($changes.Count -eq 0 -and -not $isHeadChanged) -or $seen.passedFingerprint -eq $fingerprint)
            {
                Write-JsonFile $seenPath ([ordered]@{ head = $seen.head; passedFingerprint = $seen.passedFingerprint })
                Complete-Hook "allow" ""
            }
        }
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $markdownPath) -Force | Out-Null
    $ignoreFile = Join-Path (Split-Path -Parent $markdownPath) ".gitignore"
    if (-not (Test-Path -LiteralPath $ignoreFile)) { Set-Content -LiteralPath $ignoreFile -Value "*" -Encoding ASCII }

    $checker = Invoke-Checker $target $markdownPath $jsonPath
    $result = Read-JsonFile $jsonPath
    if ($checker.ExitCode -eq 0)
    {
        Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
        if ($ChangeDetection -eq "auto") { Write-JsonFile $seenPath ([ordered]@{ head = $head; passedFingerprint = "$fingerprint" }) }
        Complete-Hook "allow" ""
    }

    if ($null -eq $result)
    {
        Complete-Hook "notice" "CSharpRuleKeeper: the check exited with code $($checker.ExitCode) and produced no result. $($checker.ErrorText.Trim())"
    }

    $hasCompileErrors = @($result.executionErrors | Where-Object { $_ -match '^CS\d{4}:' }).Count -gt 0
    $isBlocking = $checker.ExitCode -eq 1 -or ($checker.ExitCode -eq 2 -and ($hasCompileErrors -or $result.formatStatus -eq "failed" -or $result.totalDiagnostics -gt 0))
    if (-not $isBlocking)
    {
        Complete-Hook "notice" "CSharpRuleKeeper: the check could not run (exit code $($checker.ExitCode)). See $markdownPath"
    }

    Write-JsonFile $statePath ([ordered]@{ attempts = $attempts + 1; lastRunId = "$($result.runId)"; lastStatus = "$($result.status)" })
    Complete-Hook "block" (New-BlockReason $result $markdownPath ($attempts + 1))
}
catch
{
    [Console]::Error.WriteLine("CSharpRuleKeeper hook error: $($_.Exception.Message)")
    exit 0
}
