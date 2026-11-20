[CmdletBinding()]
param(
    [string]$OutputDirectory = "artifacts",
    [string]$Version
)

# Builds the release ZIP and verifies it from a clean folder outside the repository.
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
if ([string]::IsNullOrWhiteSpace($Version)) { $Version = (Get-Content -LiteralPath (Join-Path $PSScriptRoot "version.txt") -Raw).Trim() }
$toolRoot = Split-Path -Parent $PSScriptRoot
# An absolute -OutputDirectory is used as given; a relative one is relative to the current location.
$outputRoot = if ([IO.Path]::IsPathRooted($OutputDirectory)) { [IO.Path]::GetFullPath($OutputDirectory) } else { [IO.Path]::GetFullPath((Join-Path (Get-Location).ProviderPath $OutputDirectory)) }
$bundleName = "CSharpRuleKeeper-$Version"
$stagingRoot = Join-Path $outputRoot $bundleName
$archivePath = Join-Path $outputRoot "$bundleName.zip"
$repositoryUrl = "https://github.com/jacking75/CSharpRuleKeeper/blob/main"
# Maintainer documents describe the source repository (quality gate, tests, release steps), whose scripts are
# not in the bundle. They stay on GitHub, and links to them are rewritten to their GitHub address.
$maintainerDocuments = @("MAINTAINERS.md", "RELEASE_CHECKLIST.md")

function Copy-Folder([string]$Source, [string]$Destination, [string[]]$ExcludedNames)
{
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    foreach ($item in Get-ChildItem -LiteralPath $Source -Force)
    {
        if ($ExcludedNames -contains $item.Name) { continue }
        if ($item.PSIsContainer) { Copy-Folder $item.FullName (Join-Path $Destination $item.Name) $ExcludedNames }
        else { Copy-Item -LiteralPath $item.FullName -Destination $Destination }
    }
}

function Get-RelativeLinks([string]$MarkdownPath)
{
    $isInsideFence = $false
    foreach ($line in [IO.File]::ReadAllLines($MarkdownPath, [Text.Encoding]::UTF8))
    {
        if ($line -match '^\s*```') { $isInsideFence = -not $isInsideFence; continue }
        if ($isInsideFence) { continue }
        foreach ($match in [regex]::Matches(($line -replace '`[^`]*`', ''), '\[[^\]]*\]\(([^)\s#]+)(#[^)\s]*)?\)'))
        {
            $target = $match.Groups[1].Value
            if ($target -notmatch '^(https?:|mailto:)') { $target }
        }
    }
}

# A link to a file that is not in the bundle points to the same file on GitHub instead.
function Update-ExternalLinks([string]$Root)
{
    foreach ($file in Get-ChildItem -LiteralPath $Root -Filter "*.md" -File -Recurse)
    {
        $text = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8)
        $updated = [regex]::Replace($text, '(\[[^\]]*\]\()([^)\s#]+)((?:#[^)\s]*)?\))', {
            param($match)
            $target = $match.Groups[2].Value
            if ($target -match '^(https?:|mailto:)') { return $match.Value }
            $resolved = [IO.Path]::GetFullPath((Join-Path $file.DirectoryName $target))
            if (Test-Path -LiteralPath $resolved) { return $match.Value }
            $repositoryPath = $resolved.Substring($Root.Length).Replace([IO.Path]::DirectorySeparatorChar, '/').TrimStart('/')
            return "$($match.Groups[1].Value)$repositoryUrl/$repositoryPath$($match.Groups[3].Value)"
        })
        if ($updated -ne $text) { [IO.File]::WriteAllText($file.FullName, $updated, [Text.UTF8Encoding]::new($false)) }
    }
}

# Compress-Archive in Windows PowerShell 5.1 writes '\' into entry names; ZIP entries must use '/'.
function New-ZipArchive([string]$SourceDirectory, [string]$DestinationPath)
{
    $stream = [IO.File]::Open($DestinationPath, [IO.FileMode]::CreateNew)
    $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create)
    try
    {
        $baseLength = (Split-Path -Parent $SourceDirectory).Length + 1
        foreach ($file in Get-ChildItem -LiteralPath $SourceDirectory -File -Recurse -Force)
        {
            $entryName = $file.FullName.Substring($baseLength).Replace([IO.Path]::DirectorySeparatorChar, '/')
            $null = [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $file.FullName, $entryName, [IO.Compression.CompressionLevel]::Optimal)
        }
    }
    finally
    {
        $archive.Dispose()
        $stream.Dispose()
    }
}

# The bundle is verified with the PowerShell that runs this script: pwsh starts pwsh, Windows PowerShell powershell.exe.
function Get-PowerShellPath
{
    $path = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    if ([IO.Path]::GetFileNameWithoutExtension($path) -in @("pwsh", "powershell")) { return $path }
    if ($PSVersionTable.PSEdition -eq "Core") { return "pwsh" }
    return "powershell"
}

function Invoke-BundleChecker([string]$Checker, [string[]]$Arguments)
{
    & (Get-PowerShellPath) -NoProfile -ExecutionPolicy Bypass -File $Checker @Arguments | Out-Host
    return $LASTEXITCODE
}

& dotnet build (Join-Path $toolRoot "src\CSharpRuleKeeper.Analyzers\CSharpRuleKeeper.Analyzers.csproj") --configuration Release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if (Test-Path -LiteralPath $stagingRoot) { Remove-Item -LiteralPath $stagingRoot -Recurse -Force }
New-Item -ItemType Directory -Path (Join-Path $stagingRoot "build") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stagingRoot "analyzers") -Force | Out-Null

Copy-Item -LiteralPath (Join-Path $toolRoot "src\CSharpRuleKeeper.Analyzers\bin\Release\netstandard2.0\CSharpRuleKeeper.Analyzers.dll") -Destination (Join-Path $stagingRoot "analyzers")
foreach ($buildFile in @("Invoke-CSharpRuleKeeper.ps1", "Invoke-CSharpRuleKeeperHook.ps1", "New-CodingAgentChangeReport.ps1", "Show-CSharpRuleKeeperOptions.ps1", "CSharpRuleKeeper.targets", "version.txt"))
{
    Copy-Item -LiteralPath (Join-Path $toolRoot "build\$buildFile") -Destination (Join-Path $stagingRoot "build")
}
Copy-Folder (Join-Path $toolRoot "hooks") (Join-Path $stagingRoot "hooks") @()
Copy-Folder (Join-Path $toolRoot "docs") (Join-Path $stagingRoot "docs") $maintainerDocuments
Copy-Folder (Join-Path $toolRoot "config\presets") (Join-Path $stagingRoot "config\presets") @()
Copy-Folder (Join-Path $toolRoot "samples\SampleConsumer") (Join-Path $stagingRoot "samples\SampleConsumer") @("bin", "obj")
foreach ($rootFile in @("README.md", "README_kr.md", "LICENSE", "CHANGELOG.md"))
{
    Copy-Item -LiteralPath (Join-Path $toolRoot $rootFile) -Destination $stagingRoot
}
Update-ExternalLinks $stagingRoot

$manifest = [ordered]@{
    name = "CSharpRuleKeeper"
    version = $Version
    analyzer = "analyzers/CSharpRuleKeeper.Analyzers.dll"
    entrypoint = "build/Invoke-CSharpRuleKeeper.ps1"
    hookEntrypoint = "build/Invoke-CSharpRuleKeeperHook.ps1"
    sample = "samples/SampleConsumer/SampleConsumer.csproj"
    createdAt = [DateTimeOffset]::UtcNow.ToString("o")
}
$manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $stagingRoot "manifest.json") -Encoding UTF8
if (Test-Path -LiteralPath $archivePath) { Remove-Item -LiteralPath $archivePath -Force }
New-ZipArchive $stagingRoot $archivePath

# Verify the archive from a clean folder: entry names, links, doctor, a clean fixture (exit 0),
# a violating fixture (exit 1) and the Getting started sample practice command (exit 1, HBCS001 and HBCS002).
$verifyRoot = Join-Path ([IO.Path]::GetTempPath()) "CSharpRuleKeeper-verify-$([Guid]::NewGuid().ToString('N'))"
$problems = [Collections.Generic.List[string]]::new()
try
{
    New-Item -ItemType Directory -Path $verifyRoot | Out-Null
    $zip = [IO.Compression.ZipFile]::OpenRead($archivePath)
    try { $badEntries = @($zip.Entries | Where-Object { $_.FullName.Contains('\') -or -not $_.FullName.StartsWith("$bundleName/") }) } finally { $zip.Dispose() }
    if ($badEntries.Count -gt 0) { $problems.Add("ZIP entries with '\' or outside $bundleName/: $($badEntries[0].FullName)") }
    [IO.Compression.ZipFile]::ExtractToDirectory($archivePath, (Join-Path $verifyRoot "bundle"))
    $bundleRoot = Join-Path $verifyRoot "bundle\$bundleName"
    foreach ($markdown in Get-ChildItem -LiteralPath $bundleRoot -Filter "*.md" -File -Recurse)
    {
        foreach ($target in @(Get-RelativeLinks $markdown.FullName))
        {
            if (-not (Test-Path -LiteralPath (Join-Path $markdown.DirectoryName $target))) { $problems.Add("Broken link in $($markdown.FullName.Substring($bundleRoot.Length + 1)): $target") }
        }
    }
    if (@(Get-ChildItem -LiteralPath (Join-Path $bundleRoot "samples") -Directory -Recurse | Where-Object { $_.Name -in @("bin", "obj") }).Count -gt 0) { $problems.Add("The sample contains bin or obj folders.") }

    $checker = Join-Path $bundleRoot "build\Invoke-CSharpRuleKeeper.ps1"
    $fixture = Join-Path $verifyRoot "fixture"
    New-Item -ItemType Directory -Path $fixture | Out-Null
    "<Project Sdk=`"Microsoft.NET.Sdk`"><PropertyGroup><TargetFramework>net10.0</TargetFramework></PropertyGroup></Project>" | Set-Content -LiteralPath (Join-Path $fixture "Fixture.csproj") -Encoding UTF8
    "root = true`r`n`r`n[*.cs]`r`nindent_style = space`r`nindent_size = 4" | Set-Content -LiteralPath (Join-Path $fixture ".editorconfig") -Encoding UTF8
    & dotnet restore (Join-Path $fixture "Fixture.csproj") | Out-Null

    $doctorExitCode = Invoke-BundleChecker $checker @("-Doctor", "-Solution", $fixture)
    "using System;`r`n`r`nsealed class Clean`r`n{`r`n    public Int32 Count { get; set; }`r`n}`r`n" | Set-Content -LiteralPath (Join-Path $fixture "Program.cs") -Encoding UTF8
    $cleanExitCode = Invoke-BundleChecker $checker @("-Solution", (Join-Path $fixture "Fixture.csproj"), "-OutputPath", (Join-Path $verifyRoot "clean.md"))
    "using System;`r`n`r`nsealed class Dirty`r`n{`r`n    public Int32 Count;`r`n}`r`n" | Set-Content -LiteralPath (Join-Path $fixture "Program.cs") -Encoding UTF8
    $dirtyExitCode = Invoke-BundleChecker $checker @("-Solution", (Join-Path $fixture "Fixture.csproj"), "-OutputPath", (Join-Path $verifyRoot "dirty.md"))
    if ($doctorExitCode -ne 0 -or $cleanExitCode -ne 0 -or $dirtyExitCode -ne 1) { $problems.Add("doctor=$doctorExitCode clean=$cleanExitCode violation=$dirtyExitCode (expected 0, 0, 1).") }

    # The command from docs/GETTING_STARTED.md section 4, run from the unpacked folder.
    Push-Location -LiteralPath $bundleRoot
    # Join-Path writes .\build\... on Windows and ./build/... on Linux and macOS, as the documentation does.
    try { $sampleExitCode = Invoke-BundleChecker (Join-Path "." "build\Invoke-CSharpRuleKeeper.ps1") @("-Solution", (Join-Path "." "samples\SampleConsumer\SampleConsumer.csproj"), "-DefineConstants", "DEMONSTRATE_RULES", "-OutputPath", (Join-Path $verifyRoot "sample-practice-report.md")) }
    finally { Pop-Location }
    $sample = Get-Content -LiteralPath (Join-Path $verifyRoot "sample-practice-report.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $sampleRules = @($sample.diagnostics | ForEach-Object { $_.ruleId } | Sort-Object -Unique)
    if ($sampleExitCode -ne 1 -or $sampleRules -notcontains "HBCS001" -or $sampleRules -notcontains "HBCS002") { $problems.Add("Sample practice: exit $sampleExitCode, rules $($sampleRules -join ',') (expected exit 1 with HBCS001 and HBCS002). Errors: $($sample.executionErrors -join '; ')") }
}
catch
{
    $problems.Add("Verification error: $($_.Exception.Message)")
}
finally
{
    if (Test-Path -LiteralPath $verifyRoot) { Remove-Item -LiteralPath $verifyRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

if ($problems.Count -gt 0)
{
    $problems | ForEach-Object { [Console]::Error.WriteLine("Bundle verification failed: $_") }
    Remove-Item -LiteralPath $archivePath -Force
    exit 2
}

$checksum = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath "$archivePath.sha256" -Value "$checksum  $([IO.Path]::GetFileName($archivePath))" -Encoding ASCII
Write-Host "Bundle: $archivePath"
Write-Host "SHA256: $checksum"
