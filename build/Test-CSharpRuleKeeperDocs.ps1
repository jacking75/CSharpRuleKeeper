[CmdletBinding()]
param()

# Verifies that every relative Markdown link points to an existing file and heading,
# and that every rule ID has the heading the analyzers' help links point to.
$ErrorActionPreference = "Stop"
$toolRoot = Split-Path -Parent $PSScriptRoot
$errors = [Collections.Generic.List[string]]::new()

function Get-MarkdownLines([string]$Path)
{
    $isInsideFence = $false
    foreach ($line in [IO.File]::ReadAllLines($Path, [Text.Encoding]::UTF8))
    {
        if ($line -match '^\s*```') { $isInsideFence = -not $isInsideFence; continue }
        if (-not $isInsideFence) { $line }
    }
}

function ConvertTo-Anchor([string]$Heading)
{
    $text = $Heading -replace '\[([^\]]*)\]\([^)]*\)', '$1' -replace '`', ''
    $text = $text.Trim().ToLowerInvariant() -replace '[^\p{L}\p{N}\s_-]', ''
    return $text -replace '\s', '-'
}

function Get-Anchors([string]$Path)
{
    $anchors = [Collections.Generic.HashSet[string]]::new()
    foreach ($line in (Get-MarkdownLines $Path))
    {
        if ($line -match '^#{1,6}\s+(.+?)\s*$') { $null = $anchors.Add((ConvertTo-Anchor $Matches[1])) }
    }

    return , $anchors
}

$markdownFiles = @(
    Get-ChildItem -LiteralPath $toolRoot -File -Filter "*.md" |
        Where-Object { $_.Name -in @("README.md", "README_kr.md", "CONTRIBUTING.md", "CHANGELOG.md") }
    Get-ChildItem -LiteralPath (Join-Path $toolRoot "docs") -File -Filter "*.md" -Recurse
    Get-ChildItem -LiteralPath (Join-Path $toolRoot "hooks") -File -Filter "*.md" -Recurse
)

foreach ($file in $markdownFiles)
{
    foreach ($line in (Get-MarkdownLines $file.FullName))
    {
        $text = $line -replace '`[^`]*`', ''
        foreach ($match in [regex]::Matches($text, '\[[^\]]*\]\(([^)\s]+)\)'))
        {
            $target = $match.Groups[1].Value
            if ($target -match '^(https?:|mailto:)') { continue }
            $pathPart, $anchorPart = $target -split '#', 2
            $targetFile = if ($pathPart) { [IO.Path]::GetFullPath((Join-Path $file.DirectoryName $pathPart)) } else { $file.FullName }
            $relativeName = $file.FullName.Substring($toolRoot.Length + 1)
            if (-not (Test-Path -LiteralPath $targetFile))
            {
                $errors.Add("${relativeName}: missing file for link '$target'")
                continue
            }
            if ($anchorPart -and $targetFile -like "*.md" -and -not (Get-Anchors $targetFile).Contains($anchorPart))
            {
                $errors.Add("${relativeName}: missing heading '#$anchorPart' in link '$target'")
            }
        }
    }
}

$ruleIds = @(Select-String -LiteralPath (Join-Path $toolRoot "src\CSharpRuleKeeper.Analyzers\RuleIds.cs") -Pattern '"(HBCS\d{3})"' |
    ForEach-Object { $_.Matches[0].Groups[1].Value } | Sort-Object -Unique)
if ($ruleIds.Count -eq 0) { $errors.Add("No rule IDs found in RuleIds.cs.") }
foreach ($rulesFile in @("docs\RULES.md", "docs\ko\RULES.md"))
{
    $anchors = Get-Anchors (Join-Path $toolRoot $rulesFile)
    foreach ($ruleId in $ruleIds)
    {
        if (-not $anchors.Contains($ruleId.ToLowerInvariant())) { $errors.Add("${rulesFile}: no heading for $ruleId") }
    }
}

if ($errors.Count -gt 0)
{
    $errors | ForEach-Object { [Console]::Error.WriteLine($_) }
    throw "Documentation link check failed with $($errors.Count) problem(s)."
}

Write-Host "CSharpRuleKeeper documentation link tests passed ($($markdownFiles.Count) files, $($ruleIds.Count) rules)."
exit 0
