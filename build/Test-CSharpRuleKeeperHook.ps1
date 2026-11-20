[CmdletBinding()]
param()

# Drives the hook the way agents do: UTF-8 bytes on stdin, protocol output on stdout. Nothing here depends on
# the code page of the console that launched the test.
$ErrorActionPreference = "Stop"
$toolRoot = Split-Path -Parent $PSScriptRoot
$hookScript = Join-Path $PSScriptRoot "Invoke-CSharpRuleKeeperHook.ps1"
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) "CSharpRuleKeeper-hook-$([Guid]::NewGuid().ToString('N'))"
$stateRoot = Join-Path $fixtureRoot "state"
$repositoryRoot = Join-Path $fixtureRoot "repo"
# A project folder with Korean names inside the repository, written with code points to keep this file ASCII.
$koreanWork = -join @([char]0xC791, [char]0xC5C5)
$koreanOne = [string][char]0xD55C
$projectRoot = Join-Path (Join-Path $repositoryRoot $koreanWork) $koreanOne
$analyzerPath = Join-Path $toolRoot "src\CSharpRuleKeeper.Analyzers\bin\Release\netstandard2.0\CSharpRuleKeeper.Analyzers.dll"
$cleanSource = "using System;`r`n`r`nsealed class Example`r`n{`r`n    public Int32 Count { get; set; }`r`n}`r`n"
$violatingSource = "using System;`r`n`r`nsealed class Example`r`n{`r`n    public Int32 Count;`r`n}`r`n"
$utf8 = [Text.UTF8Encoding]::new($false)
# Child scripts run under the PowerShell that runs this test (pwsh or Windows PowerShell).
$powerShellPath = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName

function Assert-True([bool]$Condition, [string]$Message)
{
    if (-not $Condition) { throw $Message }
}

function Invoke-Hook([string]$InputText, [string[]]$HookArguments, [switch]$WithByteOrderMark)
{
    $allArguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $hookScript) + $HookArguments
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $powerShellPath
    $startInfo.Arguments = @($allArguments | ForEach-Object {
        if ($_ -notmatch '[\s"]') { $_ } else { '"' + ($_ -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"' }
    }) -join " "
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = $utf8
    $startInfo.StandardErrorEncoding = $utf8
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $process = [Diagnostics.Process]::Start($startInfo)
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    if ($InputText)
    {
        $bytes = $utf8.GetBytes($InputText)
        if ($WithByteOrderMark) { $bytes = [byte[]](0xEF, 0xBB, 0xBF) + $bytes }
        $process.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
    }
    $process.StandardInput.Close()
    $process.WaitForExit()
    $watch.Stop()
    $result = [PSCustomObject]@{ ExitCode = $process.ExitCode; Output = $stdout.Result; ErrorText = $stderr.Result; Seconds = $watch.Elapsed.TotalSeconds }
    $process.Dispose()
    return $result
}

function New-StopPayload([string]$SessionId, [bool]$IsStopHookActive, [string]$Message = "done")
{
    return (@{ hook_event_name = "Stop"; session_id = $SessionId; cwd = $projectRoot; stop_hook_active = $IsStopHookActive; last_assistant_message = $Message } | ConvertTo-Json -Compress)
}

function Get-Decision($Run)
{
    try { return $Run.Output | ConvertFrom-Json } catch { throw "The hook did not print JSON. Output: $($Run.Output) Error: $($Run.ErrorText)" }
}

function Initialize-Project([string]$Directory)
{
    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    "root = true`r`n`r`n[*.cs]`r`nindent_style = space`r`nindent_size = 4" | Set-Content -LiteralPath (Join-Path $Directory ".editorconfig") -Encoding UTF8
    "<Project Sdk=`"Microsoft.NET.Sdk`"><PropertyGroup><TargetFramework>net10.0</TargetFramework></PropertyGroup></Project>" | Set-Content -LiteralPath (Join-Path $Directory "Fixture.csproj") -Encoding UTF8
}

try
{
    Remove-Item Env:\CLAUDE_PROJECT_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:\CSHARPRULEKEEPER_SOLUTION -ErrorAction SilentlyContinue
    Remove-Item Env:\CSHARPRULEKEEPER_BASELINE -ErrorAction SilentlyContinue
    $env:CSHARPRULEKEEPER_STATE_DIR = $stateRoot
    $env:CSHARPRULEKEEPER_ANALYZER_PATH = $analyzerPath
    Initialize-Project $projectRoot
    [IO.File]::WriteAllText((Join-Path $projectRoot "Program.cs"), $violatingSource, $utf8)
    [IO.File]::WriteAllText((Join-Path $repositoryRoot ".gitignore"), "bin/`r`nobj/`r`n", $utf8)
    & dotnet restore (Join-Path $projectRoot "Fixture.csproj") | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "fixture restore failed" }
    & dotnet build (Join-Path $toolRoot "src\CSharpRuleKeeper.Analyzers\CSharpRuleKeeper.Analyzers.csproj") --configuration Release | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "analyzer release build failed" }
    & git -C $repositoryRoot init --quiet
    & git -C $repositoryRoot add -A
    & git -C $repositoryRoot -c user.name=test -c user.email=test@example.com commit --quiet -m initial
    if ($LASTEXITCODE -ne 0) { throw "fixture commit failed" }

    # The violation was committed before the session's first Stop, and the payload carries Korean text in
    # last_assistant_message and cwd. The hook must decode it as UTF-8, check, and block.
    $koreanMessage = -join @([char]0xC791, [char]0xC5C5, [char]0xC744, [char]0x0020, [char]0xB05D, [char]0xB0C8, [char]0xB2E4)
    $first = Invoke-Hook (New-StopPayload "loop" $false $koreanMessage) @("-MaxRetries", "2")
    $firstDecision = Get-Decision $first
    Assert-True ($first.ExitCode -eq 0) "A blocking hook must exit 0 and block through JSON, got exit code $($first.ExitCode). $($first.ErrorText)"
    Assert-True ($firstDecision.decision -eq "block") "A committed violation with a Korean payload did not block. Output: $($first.Output) $($first.ErrorText)"
    Assert-True ($firstDecision.reason -match "HBCS001" -and $firstDecision.reason -match "last-report\.md") "The block reason lacks the rule ID or the report path."

    # A UTF-8 byte order mark, as sent by a PowerShell parent with a UTF-8 console, must not break parsing.
    $second = Invoke-Hook (New-StopPayload "loop" $true) @("-MaxRetries", "2") -WithByteOrderMark
    Assert-True ((Get-Decision $second).decision -eq "block") "A BOM-prefixed payload did not block. Output: $($second.Output) $($second.ErrorText)"

    # The retry limit must release the agent instead of looping forever.
    $third = Invoke-Hook (New-StopPayload "loop" $true) @("-MaxRetries", "2")
    $thirdMessage = Get-Decision $third
    Assert-True ($third.ExitCode -eq 0 -and -not $thirdMessage.decision -and $thirdMessage.systemMessage -match "retry limit") "The retry limit did not release the agent. Output: $($third.Output)"

    # A general CLI hook gets exit code 2 for a violation.
    $cli = Invoke-Hook "" @("-Protocol", "exitcode", "-ChangeDetection", "always", "-Solution", (Join-Path $projectRoot "Fixture.csproj"))
    Assert-True ($cli.ExitCode -eq 2 -and $cli.ErrorText -match "HBCS001") "The exitcode protocol did not return 2 for a violation. Exit code: $($cli.ExitCode)"

    # A passing check allows the stop without output and removes the retry state.
    $null = Invoke-Hook (New-StopPayload "recovered" $false) @()
    Assert-True (Test-Path -LiteralPath (Join-Path $stateRoot "recovered.json")) "The blocked run did not record retry state."
    [IO.File]::WriteAllText((Join-Path $projectRoot "Program.cs"), $cleanSource, $utf8)
    $clean = Invoke-Hook (New-StopPayload "recovered" $true) @()
    Assert-True ($clean.ExitCode -eq 0 -and [string]::IsNullOrWhiteSpace($clean.Output)) "A clean project must produce no output. Output: $($clean.Output) $($clean.ErrorText)"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $stateRoot "recovered.json"))) "Retry state leaked after a passing check."

    # A state that already passed is not checked again, in any session.
    $skipped = Invoke-Hook (New-StopPayload "quiet" $false) @()
    Assert-True ($skipped.ExitCode -eq 0 -and [string]::IsNullOrWhiteSpace($skipped.Output)) "An unchanged passed state should produce no output."
    Assert-True ($skipped.Seconds -lt 8) "An unchanged passed state took $($skipped.Seconds) seconds; the check was probably run."

    # Unreadable stdin is reported to the human instead of passing silently.
    $env:CLAUDE_PROJECT_DIR = $projectRoot
    $garbled = Invoke-Hook '{"hook_event_name":"Stop","cwd":"C:\broken' @()
    Remove-Item Env:\CLAUDE_PROJECT_DIR
    Assert-True ((Get-Decision $garbled).systemMessage -match "not valid JSON") "Invalid stdin JSON was not reported. Output: $($garbled.Output) $($garbled.ErrorText)"

    # The project is a subfolder of the repository: editing the same file into a violation must be seen.
    [IO.File]::WriteAllText((Join-Path $projectRoot "Program.cs"), $violatingSource, $utf8)
    $changed = Invoke-Hook (New-StopPayload "quiet" $false) @()
    Assert-True ((Get-Decision $changed).decision -eq "block") "A changed .cs file in a repository subfolder did not trigger the check. Output: $($changed.Output) $($changed.ErrorText)"

    # Invalid hook arguments are a visible notice, never a silent pass.
    $misconfigured = Invoke-Hook (New-StopPayload "args" $false) @("-MaxRetries", "50")
    Assert-True ($misconfigured.ExitCode -eq 0 -and (Get-Decision $misconfigured).systemMessage -match "MaxRetries") "An invalid -MaxRetries was not reported. Output: $($misconfigured.Output) $($misconfigured.ErrorText)"

    # An environment problem (the target pins an SDK that is not installed) is reported to the human, not the agent.
    $environmentRoot = Join-Path $fixtureRoot "environment"
    Initialize-Project $environmentRoot
    [IO.File]::WriteAllText((Join-Path $environmentRoot "Program.cs"), $cleanSource, $utf8)
    '{ "sdk": { "version": "1.0.100", "rollForward": "disable" } }' | Set-Content -LiteralPath (Join-Path $environmentRoot "global.json") -Encoding ASCII
    $environment = Invoke-Hook (@{ hook_event_name = "Stop"; session_id = "environment"; cwd = $environmentRoot; stop_hook_active = $false } | ConvertTo-Json -Compress) @("-ChangeDetection", "always")
    $environmentDecision = Get-Decision $environment
    Assert-True (-not $environmentDecision.decision -and $environmentDecision.systemMessage -match "could not complete") "A missing SDK must produce a notice, not a block. Output: $($environment.Output)"

    Write-Host "CSharpRuleKeeper hook adapter tests passed."
}
finally
{
    Remove-Item Env:\CSHARPRULEKEEPER_STATE_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:\CSHARPRULEKEEPER_ANALYZER_PATH -ErrorAction SilentlyContinue
    Remove-Item Env:\CLAUDE_PROJECT_DIR -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $fixtureRoot) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }
}

exit 0
