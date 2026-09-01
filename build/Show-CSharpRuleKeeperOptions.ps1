[CmdletBinding()]
param(
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"

$consoleLines = @(
    "CSharpRuleKeeper .editorconfig 옵션 안내",
    "",
    "아래 설정은 [*.cs] 또는 [*.{cs,csx}] 구역에 작성한다.",
    "하위 폴더의 .editorconfig는 더 가까운 범위의 설정으로 값을 덮어쓴다.",
    "",
    "method_lines_warning: 양의 정수, 기본값 30. 메서드가 이 줄 수를 초과하면 HBCS006 경고를 표시한다.",
    "method_lines_error: warning보다 큰 양의 정수, 기본값 100. 초과하면 HBCS006 오류를 표시한다.",
    "type_lines_warning: 양의 정수, 기본값 300. 타입이 이 줄 수를 초과하면 HBCS007 경고를 표시한다.",
    "type_lines_error: warning보다 큰 양의 정수, 기본값 500. 초과하면 HBCS007 오류를 표시한다.",
    "file_lines_warning: 양의 정수, 기본값 500. 주석과 빈 줄을 포함한 .cs 파일 전체가 초과하면 HBCS015 경고를 표시한다.",
    "file_lines_error: warning보다 큰 양의 정수, 기본값 1000. 초과하면 HBCS015 오류를 표시한다.",
    "max_line_length: 양의 정수, 기본값 120. 한 물리 줄의 문자 수가 초과하면 HBCS012 경고를 표시한다.",
    "allow_magic_numbers: 쉼표로 구분한 숫자 목록, 기본값 -1,0,1,2. 목록의 숫자는 HBCS005 검사에서 예외로 처리한다.",
    "analyze_test_projects: true 또는 false, 기본값 false. true이면 테스트 프로젝트에서도 HBCS005를 검사한다.",
    "public_field_allowed_attributes: 쉼표로 구분한 특성 이름 목록, 기본값 빈 값. 해당 특성이 붙은 public 필드는 HBCS001 검사에서 예외로 처리한다.",
    "type_length_excluded_suffixes: 쉼표로 구분한 타입 이름 접미사 목록, 기본값 빈 값. 해당 접미사의 타입은 HBCS007 길이 검사에서 제외한다.",
    "",
    "설정 예시:",
    "[*.cs]",
    "personal_csharp_rules.method_lines_warning = 40",
    "personal_csharp_rules.method_lines_error = 120",
    "personal_csharp_rules.file_lines_warning = 600",
    "personal_csharp_rules.file_lines_error = 1200"
)

$consoleLines | ForEach-Object {
    Write-Host $_
}

if (-not [string]::IsNullOrWhiteSpace($OutputPath))
{
    $markdown = @'
# CSharpRuleKeeper .editorconfig 옵션 안내

각 옵션은 대상 프로젝트의 `.editorconfig`에서 `[*.cs]` 또는 `[*.{cs,csx}]` 구역에 작성한다. 하위 폴더의 `.editorconfig`는 더 가까운 범위의 설정으로 값을 덮어쓴다.

| 옵션 | 값 형식과 기본값 | 동작 |
| --- | --- | --- |
| `method_lines_warning` | 양의 정수, `30` | 메서드가 초과하면 HBCS006 경고를 표시한다. |
| `method_lines_error` | warning보다 큰 양의 정수, `100` | 메서드가 초과하면 HBCS006 오류를 표시한다. |
| `type_lines_warning` | 양의 정수, `300` | 타입이 초과하면 HBCS007 경고를 표시한다. |
| `type_lines_error` | warning보다 큰 양의 정수, `500` | 타입이 초과하면 HBCS007 오류를 표시한다. |
| `file_lines_warning` | 양의 정수, `500` | 주석과 빈 줄을 포함한 `.cs` 파일 전체가 초과하면 HBCS015 경고를 표시한다. |
| `file_lines_error` | warning보다 큰 양의 정수, `1000` | `.cs` 파일 전체가 초과하면 HBCS015 오류를 표시한다. |
| `max_line_length` | 양의 정수, `120` | 한 물리 줄의 문자 수가 초과하면 HBCS012 경고를 표시한다. |
| `allow_magic_numbers` | 쉼표로 구분한 숫자, `-1,0,1,2` | 목록의 숫자를 HBCS005 검사에서 예외로 처리한다. |
| `analyze_test_projects` | `true` 또는 `false`, `false` | `true`이면 테스트 프로젝트에서도 HBCS005를 검사한다. |
| `public_field_allowed_attributes` | 쉼표로 구분한 특성 이름, 빈 값 | 해당 특성이 붙은 public 필드를 HBCS001 검사에서 예외로 처리한다. |
| `type_length_excluded_suffixes` | 쉼표로 구분한 타입 접미사, 빈 값 | 해당 접미사의 타입을 HBCS007 길이 검사에서 제외한다. |

## 설정 예시

```ini
[*.cs]
personal_csharp_rules.method_lines_warning = 40
personal_csharp_rules.method_lines_error = 120
personal_csharp_rules.file_lines_warning = 600
personal_csharp_rules.file_lines_error = 1200
```
'@

    $parentPath = Split-Path -Parent $OutputPath
    if (-not [string]::IsNullOrWhiteSpace($parentPath))
    {
        New-Item -ItemType Directory -Path $parentPath -Force | Out-Null
    }

    Set-Content -LiteralPath $OutputPath -Value $markdown -Encoding utf8
    Write-Host "옵션 설명 문서를 생성했다: $OutputPath"
}
