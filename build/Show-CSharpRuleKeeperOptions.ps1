[CmdletBinding()]
param(
    [string]$OutputPath,
    [string]$Target
)

$ErrorActionPreference = "Stop"
$catalog = @(
    [PSCustomObject]@{ name = "method_lines_warning"; type = "positiveInteger"; default = "30"; diagnostics = @("HBCS006"); descriptionKo = "메서드가 초과하면 경고한다." }
    [PSCustomObject]@{ name = "method_lines_error"; type = "integerGreaterThanWarning"; default = "100"; diagnostics = @("HBCS006"); descriptionKo = "메서드가 초과하면 오류로 진단한다." }
    [PSCustomObject]@{ name = "type_lines_warning"; type = "positiveInteger"; default = "300"; diagnostics = @("HBCS007"); descriptionKo = "타입이 초과하면 경고한다." }
    [PSCustomObject]@{ name = "type_lines_error"; type = "integerGreaterThanWarning"; default = "500"; diagnostics = @("HBCS007"); descriptionKo = "타입이 초과하면 오류로 진단한다." }
    [PSCustomObject]@{ name = "file_lines_warning"; type = "positiveInteger"; default = "500"; diagnostics = @("HBCS015"); descriptionKo = "파일이 초과하면 경고한다." }
    [PSCustomObject]@{ name = "file_lines_error"; type = "integerGreaterThanWarning"; default = "1000"; diagnostics = @("HBCS015"); descriptionKo = "파일이 초과하면 오류로 진단한다." }
    [PSCustomObject]@{ name = "max_line_length"; type = "positiveInteger"; default = "120"; diagnostics = @("HBCS012"); descriptionKo = "물리 줄의 최대 문자 수다." }
    [PSCustomObject]@{ name = "allow_magic_numbers"; type = "commaSeparatedNumbers"; default = "-1,0,1,2"; diagnostics = @("HBCS005"); descriptionKo = "매직 넘버 검사 예외 목록이다." }
    [PSCustomObject]@{ name = "analyze_test_projects"; type = "boolean"; default = "false"; diagnostics = @("HBCS005"); descriptionKo = "어셈블리 이름 접미사로 판단한 테스트 프로젝트도 검사한다." }
    [PSCustomObject]@{ name = "public_field_allowed_attributes"; type = "commaSeparatedTypeNames"; default = ""; diagnostics = @("HBCS001"); descriptionKo = "public 필드 허용 특성 이름이다." }
    [PSCustomObject]@{ name = "type_length_excluded_suffixes"; type = "commaSeparatedSuffixes"; default = ""; diagnostics = @("HBCS007"); descriptionKo = "타입 길이 검사 제외 접미사다." }
)
Write-Host "CSharpRuleKeeper .editorconfig 옵션 안내"
Write-Host ""
Write-Host "이 출력은 기본값 카탈로그다. 실제 파일별 값은 Roslyn의 .editorconfig 우선순위로 결정된다."
if ($Target)
{
    Write-Host "대상: $([IO.Path]::GetFullPath($Target))"
    Write-Host "특정 대상의 최종 적용값은 검사 JSON의 진단과 대상 빌드 결과로 확인한다."
}
Write-Host ""
foreach ($option in $catalog)
{
    Write-Host "$($option.name): 형식 $($option.type), 기본값 '$($option.default)', 진단 $($option.diagnostics -join ', '). $($option.descriptionKo)"
}

if (-not [string]::IsNullOrWhiteSpace($OutputPath))
{
    $markdown = [Collections.Generic.List[string]]::new()
    $markdown.Add("# CSharpRuleKeeper .editorconfig 옵션 안내")
    $markdown.Add("")
    $markdown.Add("이 표는 기본값 카탈로그다. 하위 `.editorconfig`가 더 가까운 파일 범위에서 값을 덮어쓰며, 실제 해석은 Roslyn이 수행한다.")
    $markdown.Add("")
    $markdown.Add("| 옵션 | 형식 | 기본값 | 진단 | 설명 |")
    $markdown.Add("| --- | --- | --- | --- | --- |")
    foreach ($option in $catalog)
    {
        $markdown.Add("| ``$($option.name)`` | ``$($option.type)`` | ``$($option.default)`` | $($option.diagnostics -join ', ') | $($option.descriptionKo) |")
    }
    $markdown.Add("")
    $markdown.Add("길이 warning/error는 모두 양수이며 warning < error여야 한다. 쌍이 잘못되면 Analyzer는 그 쌍 전체를 기본값으로 복원한다. 잘못된 정수·bool과 알 수 없는 키는 파일을 자동 수정하지 않는다.")
    $parentPath = Split-Path -Parent $OutputPath
    if ($parentPath -and -not (Test-Path -LiteralPath $parentPath)) { New-Item -ItemType Directory -Path $parentPath -Force | Out-Null }
    $markdown | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    Write-Host "옵션 설명 문서를 생성했다: $OutputPath"
}
