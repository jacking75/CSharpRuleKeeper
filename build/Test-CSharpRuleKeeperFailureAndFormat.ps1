[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$toolRoot = Split-Path -Parent $PSScriptRoot
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) "CSharpRuleKeeper-format-$([Guid]::NewGuid().ToString('N'))"
$analyzerPath = Join-Path $toolRoot "src\CSharpRuleKeeper.Analyzers\bin\Release\netstandard2.0\CSharpRuleKeeper.Analyzers.dll"

function Invoke-CheckerProcess([string[]]$Arguments)
{
    $allArguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "$PSScriptRoot\Invoke-CSharpRuleKeeper.ps1") + $Arguments
    $quotedArguments = @($allArguments | ForEach-Object { if ($_ -notmatch '[\s"]') { $_ } else { '"' + ($_ -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"' } }) -join " "
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = "powershell"
    $startInfo.Arguments = $quotedArguments
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
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

try
{
    New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
    "root = true`r`n`r`n[*.cs]`r`nindent_style = space`r`nindent_size = 4" | Set-Content -LiteralPath (Join-Path $fixtureRoot ".editorconfig") -Encoding UTF8
    "<Project Sdk=`"Microsoft.NET.Sdk`"><PropertyGroup><TargetFramework>net10.0</TargetFramework></PropertyGroup></Project>" | Set-Content -LiteralPath (Join-Path $fixtureRoot "Fixture.csproj") -Encoding UTF8
    & dotnet restore (Join-Path $fixtureRoot "Fixture.csproj") | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "fixture restore failed" }

    "sealed class Example`r`n{`r`n    MissingType Read() => null;`r`n}" | Set-Content -LiteralPath (Join-Path $fixtureRoot "Program.cs") -Encoding UTF8
    $compileExitCode = Invoke-CheckerProcess @("-Solution", (Join-Path $fixtureRoot "Fixture.csproj"), "-AnalyzerPath", $analyzerPath, "-OutputPath", (Join-Path $fixtureRoot "compile-error.md"), "-JsonOutputPath", (Join-Path $fixtureRoot "compile-error.json"))
    if ($compileExitCode -ne 2) { throw "Compile error exit code was $compileExitCode, expected 2." }
    $compileError = Get-Content -LiteralPath (Join-Path $fixtureRoot "compile-error.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($compileError.analysisCompleted -or @($compileError.executionErrors | Where-Object { $_ -match "CS0246" }).Count -eq 0) { throw "Compile errors were not classified as an execution failure." }

    "sealed class Example{void Run(){}}" | Set-Content -LiteralPath (Join-Path $fixtureRoot "Program.cs") -Encoding UTF8
    $unformattedHash = (Get-FileHash -LiteralPath (Join-Path $fixtureRoot "Program.cs")).Hash
    $formatExitCode = Invoke-CheckerProcess @("-Solution", (Join-Path $fixtureRoot "Fixture.csproj"), "-AnalyzerPath", $analyzerPath, "-OutputPath", (Join-Path $fixtureRoot "format-error.md"), "-JsonOutputPath", (Join-Path $fixtureRoot "format-error.json"))
    if ($formatExitCode -ne 2) { throw "Format error exit code was $formatExitCode, expected 2." }
    if ((Get-FileHash -LiteralPath (Join-Path $fixtureRoot "Program.cs")).Hash -ne $unformattedHash) { throw "The default check modified the source." }
    $fixExitCode = Invoke-CheckerProcess @("-Solution", (Join-Path $fixtureRoot "Fixture.csproj"), "-AnalyzerPath", $analyzerPath, "-OutputPath", (Join-Path $fixtureRoot "format-fix.md"), "-JsonOutputPath", (Join-Path $fixtureRoot "format-fix.json"), "-Fix")
    if ($fixExitCode -ne 0) { throw "The -Fix check failed with exit code $fixExitCode." }
    if ((Get-FileHash -LiteralPath (Join-Path $fixtureRoot "Program.cs")).Hash -eq $unformattedHash) { throw "-Fix did not apply whitespace changes." }

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
