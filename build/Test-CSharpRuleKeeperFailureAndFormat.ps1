[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$toolRoot = Split-Path -Parent $PSScriptRoot
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) "CSharpRuleKeeper-format-$([Guid]::NewGuid().ToString('N'))"
$analyzerPath = Join-Path $toolRoot "src\CSharpRuleKeeper.Analyzers\bin\Release\netstandard2.0\CSharpRuleKeeper.Analyzers.dll"
# Child scripts run under the PowerShell that runs this test (pwsh or Windows PowerShell).
$powerShellPath = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName

function Invoke-CheckerProcess([string[]]$Arguments)
{
    $allArguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $PSScriptRoot "Invoke-CSharpRuleKeeper.ps1")) + $Arguments
    $quotedArguments = @($allArguments | ForEach-Object { if ($_ -notmatch '[\s"]') { $_ } else { '"' + ($_ -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"' } }) -join " "
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $powerShellPath
    $startInfo.Arguments = $quotedArguments
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
        $null = $process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        Write-Host $stdout.Result
        if ($stderr.Result) { Write-Host $stderr.Result }
        return $process.ExitCode
    }
    finally
    {
        $process.Dispose()
    }
}

function Read-Result([string]$Name)
{
    return Get-Content -LiteralPath (Join-Path $fixtureRoot "$Name.json") -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-CheckArguments([string]$Target, [string]$Name)
{
    return @("-Solution", $Target, "-AnalyzerPath", $analyzerPath, "-OutputPath", (Join-Path $fixtureRoot "$Name.md"), "-JsonOutputPath", (Join-Path $fixtureRoot "$Name.json"))
}

try
{
    $singleRoot = Join-Path $fixtureRoot "single"
    New-Item -ItemType Directory -Path $singleRoot -Force | Out-Null
    $project = Join-Path $singleRoot "Fixture.csproj"
    "root = true`r`n`r`n[*.cs]`r`nindent_style = space`r`nindent_size = 4" | Set-Content -LiteralPath (Join-Path $fixtureRoot ".editorconfig") -Encoding UTF8
    "<Project Sdk=`"Microsoft.NET.Sdk`"><PropertyGroup><TargetFramework>net10.0</TargetFramework></PropertyGroup></Project>" | Set-Content -LiteralPath $project -Encoding UTF8
    & dotnet restore $project | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "fixture restore failed" }

    # Argument problems exit with 2, not with the "violations" code 1, and nothing is written.
    $argumentCases = @(
        @("-Solution", $project, "-MaxDiagnostics", "0"),
        @("-Solution", $project, "-Configuration", "Rel ease"),
        @("-Solution", $project, "-Bogus", "value"),
        @("-Solution", $project, "-CreateBaseline")
    )
    foreach ($case in $argumentCases)
    {
        $argumentExitCode = Invoke-CheckerProcess $case
        if ($argumentExitCode -ne 2) { throw "Arguments '$($case -join ' ')' exited with $argumentExitCode, expected 2." }
    }

    # A refused output path is never written, not even by the failure report.
    $sourcePath = Join-Path $singleRoot "Program.cs"
    "sealed class Example`r`n{`r`n}`r`n" | Set-Content -LiteralPath $sourcePath -Encoding UTF8
    $sourceHash = (Get-FileHash -LiteralPath $sourcePath).Hash
    $protectedExitCode = Invoke-CheckerProcess @("-Solution", $project, "-AnalyzerPath", $analyzerPath, "-OutputPath", $sourcePath)
    if ($protectedExitCode -ne 2 -or (Get-FileHash -LiteralPath $sourcePath).Hash -ne $sourceHash) { throw "A protected -OutputPath was written or not refused (exit code $protectedExitCode)." }

    # An analyzer that never runs must not be reported as a passed check.
    $bogusAnalyzer = Join-Path $fixtureRoot "NotAnAnalyzer.dll"
    "not an assembly" | Set-Content -LiteralPath $bogusAnalyzer -Encoding ASCII
    $bogusArguments = Get-CheckArguments $project "no-analyzer"
    $bogusArguments[3] = $bogusAnalyzer
    $bogusExitCode = Invoke-CheckerProcess $bogusArguments
    $bogus = Read-Result "no-analyzer"
    if ($bogusExitCode -ne 2 -or $bogus.analysisCompleted -or $bogus.status -ne "failed") { throw "A run without the analyzer exited with $bogusExitCode (completed: $($bogus.analysisCompleted))." }

    # A compile error in a referenced project: the error is reported with its location, and the dependent
    # project that could not be compiled is listed instead of being silently left out.
    $brokenRoot = Join-Path $fixtureRoot "broken"
    New-Item -ItemType Directory -Path (Join-Path $brokenRoot "Lib"), (Join-Path $brokenRoot "App") -Force | Out-Null
    "<Project Sdk=`"Microsoft.NET.Sdk`"><PropertyGroup><TargetFramework>net10.0</TargetFramework></PropertyGroup></Project>" | Set-Content -LiteralPath (Join-Path $brokenRoot "Lib\Lib.csproj") -Encoding UTF8
    "<Project Sdk=`"Microsoft.NET.Sdk`"><PropertyGroup><TargetFramework>net10.0</TargetFramework></PropertyGroup><ItemGroup><ProjectReference Include=`"..\Lib\Lib.csproj`" /></ItemGroup></Project>" | Set-Content -LiteralPath (Join-Path $brokenRoot "App\App.csproj") -Encoding UTF8
    "namespace Lib;`r`n`r`npublic sealed class Holder`r`n{`r`n    MissingType Read() => null;`r`n}`r`n" | Set-Content -LiteralPath (Join-Path $brokenRoot "Lib\Holder.cs") -Encoding UTF8
    "namespace App;`r`n`r`nsealed class Worker`r`n{`r`n}`r`n" | Set-Content -LiteralPath (Join-Path $brokenRoot "App\Worker.cs") -Encoding UTF8
    & dotnet restore (Join-Path $brokenRoot "App\App.csproj") | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "broken fixture restore failed" }
    $compileExitCode = Invoke-CheckerProcess (Get-CheckArguments (Join-Path $brokenRoot "App\App.csproj") "compile-error")
    $compileError = Read-Result "compile-error"
    if ($compileExitCode -ne 2 -or $compileError.analysisCompleted) { throw "Compile error exit code was $compileExitCode, expected 2 with an incomplete analysis." }
    if (@($compileError.buildErrors | Where-Object { $_.code -eq "CS0246" -and $_.path -match 'Holder\.cs$' -and $_.line -eq 5 }).Count -eq 0) { throw "The compile error lacks its file and line: $($compileError.buildErrors | ConvertTo-Json -Compress)" }
    if (@($compileError.executionErrors | Where-Object { $_ -match '^Not analyzed: .*App\.csproj' }).Count -eq 0) { throw "The project that could not be compiled was not listed: $($compileError.executionErrors -join '; ')" }

    # A non-HBCS analyzer error comes from the console (message with a help URL) and from SARIF (without it):
    # each location is reported once, and two locations stay two errors.
    $analyzerErrorRoot = Join-Path $fixtureRoot "analyzer-error"
    New-Item -ItemType Directory -Path $analyzerErrorRoot | Out-Null
    "[*.cs]`r`ndotnet_diagnostic.CA1822.severity = error" | Set-Content -LiteralPath (Join-Path $analyzerErrorRoot ".editorconfig") -Encoding UTF8
    "<Project Sdk=`"Microsoft.NET.Sdk`"><PropertyGroup><TargetFramework>net10.0</TargetFramework></PropertyGroup></Project>" | Set-Content -LiteralPath (Join-Path $analyzerErrorRoot "Fixture.csproj") -Encoding UTF8
    "namespace Fixture;`r`n`r`npublic sealed class Holder`r`n{`r`n    public System.Int32 First() { return 3; }`r`n`r`n    public System.Int32 Second() { return 4; }`r`n}`r`n" | Set-Content -LiteralPath (Join-Path $analyzerErrorRoot "Holder.cs") -Encoding UTF8
    & dotnet restore (Join-Path $analyzerErrorRoot "Fixture.csproj") | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "analyzer error fixture restore failed" }
    $null = Invoke-CheckerProcess (Get-CheckArguments (Join-Path $analyzerErrorRoot "Fixture.csproj") "analyzer-error")
    $analyzerErrorLines = @((Read-Result "analyzer-error").buildErrors | Where-Object { $_.code -eq "CA1822" } | ForEach-Object { [Int32]$_.line })
    if ((($analyzerErrorLines | Sort-Object) -join ",") -ne "5,7") { throw "CA1822 errors were not reported once per location (lines: $($analyzerErrorLines -join ','))." }

    # Whitespace differences are violations (exit 1) and name the files; -Fix applies them.
    "sealed class Example{void Run(){}}" | Set-Content -LiteralPath $sourcePath -Encoding UTF8
    $unformattedHash = (Get-FileHash -LiteralPath $sourcePath).Hash
    $formatExitCode = Invoke-CheckerProcess (Get-CheckArguments $project "format-error")
    $formatError = Read-Result "format-error"
    if ($formatExitCode -ne 1 -or $formatError.formatFailureKind -ne "differences" -or @($formatError.formatFiles | Where-Object { $_.path -eq "Program.cs" }).Count -ne 1) { throw "Whitespace differences gave exit code $formatExitCode, kind $($formatError.formatFailureKind), files $($formatError.formatFiles | ConvertTo-Json -Compress)." }
    if ((Get-FileHash -LiteralPath $sourcePath).Hash -ne $unformattedHash) { throw "The default check modified the source." }
    $fixExitCode = Invoke-CheckerProcess ((Get-CheckArguments $project "format-fix") + "-Fix")
    if ($fixExitCode -ne 0) { throw "The -Fix check failed with exit code $fixExitCode." }
    if ((Get-FileHash -LiteralPath $sourcePath).Hash -eq $unformattedHash) { throw "-Fix did not apply whitespace changes." }

    # Doctor judges the target's SDK requirement, not the SDK needed to develop this tool.
    $doctorRoot = Join-Path $fixtureRoot "doctor"
    New-Item -ItemType Directory -Path $doctorRoot | Out-Null
    $doctorSatisfiedExitCode = Invoke-CheckerProcess @("-Doctor", "-Solution", $doctorRoot)
    if ($doctorSatisfiedExitCode -ne 0) { throw "Doctor exit code was $doctorSatisfiedExitCode for a target without global.json, expected 0." }
    '{ "sdk": { "version": "99.0.100", "rollForward": "disable" } }' | Set-Content -LiteralPath (Join-Path $doctorRoot "global.json") -Encoding UTF8
    $doctorUnsatisfiedExitCode = Invoke-CheckerProcess @("-Doctor", "-Solution", $doctorRoot)
    if ($doctorUnsatisfiedExitCode -ne 2) { throw "Doctor exit code was $doctorUnsatisfiedExitCode for an unsatisfiable target SDK, expected 2." }

    Write-Host "CSharpRuleKeeper failure classification, format and doctor tests passed."
}
finally
{
    if (Test-Path -LiteralPath $fixtureRoot) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }
}

exit 0
