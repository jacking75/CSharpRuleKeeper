[CmdletBinding()]
param(
    [string]$OutputPath,
    [string]$Target
)

$ErrorActionPreference = "Stop"
$catalog = @(
    [PSCustomObject]@{ name = "method_lines_warning"; type = "positiveInteger"; default = "30"; diagnostics = @("HBCS006"); description = "Warn when a method exceeds this many physical lines." }
    [PSCustomObject]@{ name = "method_lines_error"; type = "integerGreaterThanWarning"; default = "100"; diagnostics = @("HBCS006"); description = "Report an error when a method exceeds this many physical lines." }
    [PSCustomObject]@{ name = "type_lines_warning"; type = "positiveInteger"; default = "300"; diagnostics = @("HBCS007"); description = "Warn when a type exceeds this many physical lines." }
    [PSCustomObject]@{ name = "type_lines_error"; type = "integerGreaterThanWarning"; default = "500"; diagnostics = @("HBCS007"); description = "Report an error when a type exceeds this many physical lines." }
    [PSCustomObject]@{ name = "file_lines_warning"; type = "positiveInteger"; default = "500"; diagnostics = @("HBCS015"); description = "Warn when a source file exceeds this many physical lines." }
    [PSCustomObject]@{ name = "file_lines_error"; type = "integerGreaterThanWarning"; default = "1000"; diagnostics = @("HBCS015"); description = "Report an error when a source file exceeds this many physical lines." }
    [PSCustomObject]@{ name = "max_line_length"; type = "positiveInteger"; default = "120"; diagnostics = @("HBCS012"); description = "Maximum number of characters in a physical line." }
    [PSCustomObject]@{ name = "allow_magic_numbers"; type = "commaSeparatedNumbers"; default = "-1,0,1,2"; diagnostics = @("HBCS005"); description = "Numeric literals exempt from the magic number check." }
    [PSCustomObject]@{ name = "analyze_test_projects"; type = "boolean"; default = "false"; diagnostics = @("HBCS005"); description = "Also check test projects. A project is a test project when MSBuild sets IsTestProject=true or the last dot-separated segment of its assembly name is Test(s), UnitTest(s), IntegrationTest(s), Specs or Benchmark(s) (or the name ends with Tests)." }
    [PSCustomObject]@{ name = "public_field_allowed_attributes"; type = "commaSeparatedTypeNames"; default = ""; diagnostics = @("HBCS001"); description = "Attribute names that allow a public field." }
    [PSCustomObject]@{ name = "type_length_excluded_suffixes"; type = "commaSeparatedSuffixes"; default = ""; diagnostics = @("HBCS007"); description = "Type name suffixes excluded from the type length check." }
)
Write-Host "CSharpRuleKeeper .editorconfig option guide"
Write-Host ""
Write-Host "This output is a catalog of default values. The value used for each file is decided by Roslyn's .editorconfig precedence."
if ($Target)
{
    Write-Host "Target: $([IO.Path]::GetFullPath($Target))"
    Write-Host "The final value for a specific target is confirmed through the check JSON diagnostics and the target build result."
}
Write-Host ""
foreach ($option in $catalog)
{
    Write-Host "$($option.name): type $($option.type), default '$($option.default)', diagnostics $($option.diagnostics -join ', '). $($option.description)"
}

if (-not [string]::IsNullOrWhiteSpace($OutputPath))
{
    $markdown = [Collections.Generic.List[string]]::new()
    $markdown.Add("# CSharpRuleKeeper .editorconfig option guide")
    $markdown.Add("")
    $markdown.Add("This table is a catalog of default values. A nearer `.editorconfig` overrides a value for its own file scope, and Roslyn performs the actual resolution.")
    $markdown.Add("")
    $markdown.Add("| Option | Type | Default | Diagnostics | Description |")
    $markdown.Add("| --- | --- | --- | --- | --- |")
    foreach ($option in $catalog)
    {
        $markdown.Add("| ``$($option.name)`` | ``$($option.type)`` | ``$($option.default)`` | $($option.diagnostics -join ', ') | $($option.description) |")
    }
    $markdown.Add("")
    $markdown.Add("Length warning and error limits must both be positive, and warning must be lower than error. If a pair is invalid, the analyzer restores the whole pair to its defaults. An invalid integer or boolean value is replaced by its default and reported as HBCS900; unknown keys are ignored.")
    $parentPath = Split-Path -Parent $OutputPath
    if ($parentPath -and -not (Test-Path -LiteralPath $parentPath)) { New-Item -ItemType Directory -Path $parentPath -Force | Out-Null }
    $markdown | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    Write-Host "Option guide written: $OutputPath"
}
