[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$toolRoot = Split-Path -Parent $PSScriptRoot
$hookScript = Join-Path $PSScriptRoot "Invoke-CSharpRuleKeeperHook.ps1"
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) "CSharpRuleKeeper-hook-$([Guid]::NewGuid().ToString('N'))"
$stateRoot = Join-Path $fixtureRoot "state"
$projectRoot = Join-Path $fixtureRoot "project"
$analyzerPath = Join-Path $toolRoot "src\CSharpRuleKeeper.Analyzers\bin\Release\netstandard2.0\CSharpRuleKeeper.Analyzers.dll"
$cleanSource = "using System;`r`n`r`nsealed class Example`r`n{`r`n    public Int32 Count { get; set; }`r`n}`r`n"
$violatingSource = "using System;`r`n`r`nsealed class Example`r`n{`r`n    public Int32 Count;`r`n}`r`n"

function Assert-True([bool]$Condition, [string]$Message)
{
    if (-not $Condition) { throw $Message }
}

function Invoke-Hook([string]$InputText, [string[]]$HookArguments)
{
    $allArguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $hookScript) + $HookArguments
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = "powershell"
    $startInfo.Arguments = @($allArguments | ForEach-Object {
        if ($_ -notmatch '[\s"]') { $_ } else { '"' + ($_ -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"' }
    }) -join " "
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $process = [Diagnostics.Process]::Start($startInfo)
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    if ($InputText) { $process.StandardInput.Write($InputText) }
    $process.StandardInput.Close()
    $process.WaitForExit()
    $watch.Stop()
    $result = [PSCustomObject]@{ ExitCode = $process.ExitCode; Output = $stdout.Result; ErrorText = $stderr.Result; Seconds = $watch.Elapsed.TotalSeconds }
    $process.Dispose()
    return $result
}

function New-StopPayload([string]$SessionId, [bool]$IsStopHookActive)
{
    return (@{ hook_event_name = "Stop"; session_id = $SessionId; cwd = $projectRoot; stop_hook_active = $IsStopHookActive } | ConvertTo-Json -Compress)
}

try
{
    Remove-Item Env:\CLAUDE_PROJECT_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:\CSHARPRULEKEEPER_SOLUTION -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $projectRoot -Force | Out-Null
    $env:CSHARPRULEKEEPER_STATE_DIR = $stateRoot
    $env:CSHARPRULEKEEPER_ANALYZER_PATH = $analyzerPath
    "root = true`r`n`r`n[*.cs]`r`nindent_style = space`r`nindent_size = 4" | Set-Content -LiteralPath (Join-Path $projectRoot ".editorconfig") -Encoding UTF8
    "<Project Sdk=`"Microsoft.NET.Sdk`"><PropertyGroup><TargetFramework>net10.0</TargetFramework></PropertyGroup></Project>" | Set-Content -LiteralPath (Join-Path $projectRoot "Fixture.csproj") -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $projectRoot "Program.cs") -Value $violatingSource -Encoding UTF8 -NoNewline
    & dotnet restore (Join-Path $projectRoot "Fixture.csproj") | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "fixture restore failed" }
    & dotnet build (Join-Path $toolRoot "src\CSharpRuleKeeper.Analyzers\CSharpRuleKeeper.Analyzers.csproj") --configuration Release | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "analyzer release build failed" }

    # A violation is returned to the agent as a block decision that names the rule and the report.
    $first = Invoke-Hook (New-StopPayload "loop" $false) @("-MaxRetries", "2")
    $firstDecision = $first.Output | ConvertFrom-Json
    Assert-True ($first.ExitCode -eq 0) "A blocking hook must exit 0 and block through JSON, got exit code $($first.ExitCode). $($first.ErrorText)"
    Assert-True ($firstDecision.decision -eq "block") "A violation did not produce a block decision. Output: $($first.Output) $($first.ErrorText)"
    Assert-True ($firstDecision.reason -match "HBCS001" -and $firstDecision.reason -match "last-report\.md") "The block reason lacks the rule ID or the report path."

    # The retry limit must release the agent instead of looping forever.
    $second = Invoke-Hook (New-StopPayload "loop" $true) @("-MaxRetries", "2")
    Assert-True (($second.Output | ConvertFrom-Json).decision -eq "block") "The second attempt should still block."
    $third = Invoke-Hook (New-StopPayload "loop" $true) @("-MaxRetries", "2")
    $thirdMessage = $third.Output | ConvertFrom-Json
    Assert-True ($third.ExitCode -eq 0 -and -not $thirdMessage.decision -and $thirdMessage.systemMessage -match "retry limit") "The retry limit did not release the agent. Output: $($third.Output)"

    # A general CLI hook gets exit code 2 for a violation.
    $cli = Invoke-Hook "" @("-Protocol", "exitcode", "-ChangeDetection", "always", "-Solution", (Join-Path $projectRoot "Fixture.csproj"))
    Assert-True ($cli.ExitCode -eq 2 -and $cli.ErrorText -match "HBCS001") "The exitcode protocol did not return 2 for a violation. Exit code: $($cli.ExitCode)"

    # A passing check allows the stop and must not leave retry state behind.
    $null = Invoke-Hook (New-StopPayload "recovered" $false) @()
    Assert-True (Test-Path -LiteralPath (Join-Path $stateRoot "recovered.json")) "The blocked run did not record retry state."
    Set-Content -LiteralPath (Join-Path $projectRoot "Program.cs") -Value $cleanSource -Encoding UTF8 -NoNewline
    $clean = Invoke-Hook (New-StopPayload "recovered" $true) @()
    Assert-True ($clean.ExitCode -eq 0 -and [string]::IsNullOrWhiteSpace($clean.Output)) "A clean project must produce no output. Output: $($clean.Output) $($clean.ErrorText)"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $stateRoot "recovered.json"))) "Retry state leaked after a passing check."

    # Without relevant file changes the hook must not run the 15+ second check.
    "bin/`r`nobj/`r`n" | Set-Content -LiteralPath (Join-Path $projectRoot ".gitignore") -Encoding ASCII
    & git -C $projectRoot init --quiet
    & git -C $projectRoot add -A
    & git -C $projectRoot -c user.name=test -c user.email=test@example.com commit --quiet -m initial
    $skipped = Invoke-Hook (New-StopPayload "quiet" $false) @()
    Assert-True ($skipped.ExitCode -eq 0 -and [string]::IsNullOrWhiteSpace($skipped.Output)) "An unchanged repository should produce no output."
    Assert-True ($skipped.Seconds -lt 8) "An unchanged repository took $($skipped.Seconds) seconds; the check was probably run."
    Set-Content -LiteralPath (Join-Path $projectRoot "Program.cs") -Value $violatingSource -Encoding UTF8 -NoNewline
    $changed = Invoke-Hook (New-StopPayload "quiet" $false) @()
    Assert-True (($changed.Output | ConvertFrom-Json).decision -eq "block") "A changed .cs file in a git repository did not trigger the check."

    Write-Host "CSharpRuleKeeper hook adapter tests passed."
}
finally
{
    Remove-Item Env:\CSHARPRULEKEEPER_STATE_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:\CSHARPRULEKEEPER_ANALYZER_PATH -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $fixtureRoot) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }
}

exit 0
