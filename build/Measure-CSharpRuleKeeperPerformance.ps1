[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Solution,
    [ValidateRange(5, 100)]
    [Int32]$Iterations = 5,
    [string]$OutputPath = "artifacts/performance.json"
)

$ErrorActionPreference = "Stop"
$toolRoot = Split-Path -Parent $PSScriptRoot
$analyzerProject = Join-Path $toolRoot "src\CSharpRuleKeeper.Analyzers\CSharpRuleKeeper.Analyzers.csproj"
$analyzerPath = Join-Path $toolRoot "src\CSharpRuleKeeper.Analyzers\bin\Release\netstandard2.0\CSharpRuleKeeper.Analyzers.dll"
& dotnet build $analyzerProject --configuration Release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$measurements = [Collections.Generic.List[object]]::new()
for ($index = 1; $index -le $Iterations; $index++)
{
    $watch = [Diagnostics.Stopwatch]::StartNew()
    & "$PSScriptRoot\Invoke-CSharpRuleKeeper.ps1" -Solution $Solution -AnalyzerPath $analyzerPath -OutputPath "artifacts/performance-$index.md" -JsonOutputPath "artifacts/performance-$index.json"
    $exitCode = $LASTEXITCODE
    $watch.Stop()
    $measurements.Add([PSCustomObject]@{ iteration = $index; elapsedMilliseconds = $watch.ElapsedMilliseconds; exitCode = $exitCode })
}

$ordered = @($measurements.elapsedMilliseconds | Sort-Object)
$median = $ordered[[Math]::Floor($ordered.Count / 2)]
$result = [ordered]@{
    measuredAt = [DateTimeOffset]::UtcNow.ToString("o")
    machine = $env:COMPUTERNAME
    sdk = (& dotnet --version)
    target = [IO.Path]::GetFullPath($Solution)
    iterations = $Iterations
    medianMilliseconds = $median
    measurements = $measurements
    note = "restore 상태와 증분 빌드 여부를 함께 해석해야 하며, 분석 생략을 성능 향상으로 계산하지 않는다."
}
$parent = Split-Path -Parent $OutputPath
if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Host "성능 측정 결과: $OutputPath"
