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
    if ($compileExitCode -ne 2) { throw "컴파일 오류 종료 코드가 $compileExitCode 다." }
    $compileError = Get-Content -LiteralPath (Join-Path $fixtureRoot "compile-error.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($compileError.analysisCompleted -or @($compileError.executionErrors | Where-Object { $_ -match "CS0246" }).Count -eq 0) { throw "컴파일 오류 분류가 올바르지 않다." }

    "sealed class Example{void Run(){}}" | Set-Content -LiteralPath (Join-Path $fixtureRoot "Program.cs") -Encoding UTF8
    $unformattedHash = (Get-FileHash -LiteralPath (Join-Path $fixtureRoot "Program.cs")).Hash
    $formatExitCode = Invoke-CheckerProcess @("-Solution", (Join-Path $fixtureRoot "Fixture.csproj"), "-AnalyzerPath", $analyzerPath, "-OutputPath", (Join-Path $fixtureRoot "format-error.md"), "-JsonOutputPath", (Join-Path $fixtureRoot "format-error.json"))
    if ($formatExitCode -ne 2) { throw "서식 오류 종료 코드가 $formatExitCode 다." }
    if ((Get-FileHash -LiteralPath (Join-Path $fixtureRoot "Program.cs")).Hash -ne $unformattedHash) { throw "기본 검사에서 소스가 변경됐다." }
    $fixExitCode = Invoke-CheckerProcess @("-Solution", (Join-Path $fixtureRoot "Fixture.csproj"), "-AnalyzerPath", $analyzerPath, "-OutputPath", (Join-Path $fixtureRoot "format-fix.md"), "-JsonOutputPath", (Join-Path $fixtureRoot "format-fix.json"), "-Fix")
    if ($fixExitCode -ne 0) { throw "-Fix 검사에 실패했다: $fixExitCode" }
    if ((Get-FileHash -LiteralPath (Join-Path $fixtureRoot "Program.cs")).Hash -eq $unformattedHash) { throw "-Fix가 whitespace를 적용하지 않았다." }
    Write-Host "실행 실패·서식 범위 테스트가 통과했다."
}
finally
{
    if (Test-Path -LiteralPath $fixtureRoot) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }
}

exit 0
