# 설정

[English](../CONFIGURATION.md) | [규칙](RULES.md) | [시작하기](GETTING_STARTED.md)

서식과 표준 명명 규칙은 `.editorconfig`에 두며 `dotnet format`이 적용한다. 코드의 의미가 필요한 규칙은 Analyzer가 가장 가까운 `.editorconfig`에서 읽는 `personal_csharp_rules.*` 옵션을 사용한다. 검사를 실행하지 않고 옵션을 나열하려면 다음을 실행한다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build\Invoke-CSharpRuleKeeper.ps1 -ExplainEditorConfig
```

## 옵션

모든 옵션은 `[*.cs]` 아래에 둔다. 알 수 없는 키는 무시된다.

| 옵션 | 기본값 | 사용처 |
| --- | --- | --- |
| `method_lines_warning` | 30 | [HBCS006](RULES.md#hbcs006) 경고 한계 |
| `method_lines_error` | 100 | HBCS006 오류 한계 |
| `type_lines_warning` | 300 | [HBCS007](RULES.md#hbcs007) 경고 한계 |
| `type_lines_error` | 500 | HBCS007 오류 한계 |
| `file_lines_warning` | 500 | [HBCS015](RULES.md#hbcs015) 경고 한계 |
| `file_lines_error` | 1000 | HBCS015 오류 한계 |
| `max_line_length` | 120 | [HBCS012](RULES.md#hbcs012) |
| `allow_magic_numbers` | `-1,0,1,2` | [HBCS005](RULES.md#hbcs005) 허용 값 |
| `analyze_test_projects` | `false` | HBCS005가 테스트 프로젝트(어셈블리 이름이 `.Test`, `.Tests`, `.Benchmark`, `.Benchmarks`로 끝나는 프로젝트)도 검사한다 |
| `public_field_allowed_attributes` | 비어 있음 | [HBCS001](RULES.md#hbcs001)에서 public 필드를 허용하는 특성 이름 |
| `type_length_excluded_suffixes` | 비어 있음 | HBCS007에서 제외할 타입 이름 접미사. 예: `Dto,Migration` |

경고 한계와 오류 한계는 한 쌍이다. 둘 다 양수여야 하고 경고 값이 오류 값보다 작아야 한다. 올바르지 않은 쌍은 그 쌍의 두 값을 모두 기본값으로 되돌린다. 목록은 쉼표로 구분하며 공백을 포함할 수 있다.

줄 수는 선언의 첫 토큰부터 마지막 토큰까지의 물리 줄 수이며(HBCS015는 파일 전체), 주석과 빈 줄을 포함한다.

## 최소 예시

```ini
[*.cs]
personal_csharp_rules.method_lines_warning = 40
personal_csharp_rules.method_lines_error = 120
personal_csharp_rules.max_line_length = 140
personal_csharp_rules.allow_magic_numbers = -1,0,1,2,100,404
personal_csharp_rules.public_field_allowed_attributes = StructLayout,DataMember
personal_csharp_rules.type_length_excluded_suffixes = Dto,Migration
```

필요한 줄만 프로젝트의 기존 `.editorconfig`에 추가한다. 먼저 팀의 서식 설정과 충돌하지 않는지 확인한다.

## 폴더별 설정

더 가까운 `.editorconfig`가 자기 폴더의 값을 덮어쓴다. 예를 들어 이 저장소의 `tests/.editorconfig`는 테스트 메서드가 C# 소스 전체를 문자열 리터럴로 담고 있으므로 메서드와 타입 한계를 높인다.

## 프리셋

- `config/presets/personal.editorconfig`: 유지보수자의 개인 정책.
- `config/presets/team-starter.editorconfig`: 계약에 안전한 규칙부터 켜는, 검토 우선 시작용 프리셋.

프리셋은 자동으로 복사되거나 적용되지 않는다.

## 심각도와 `TreatWarningsAsErrors`

대상이 `TreatWarningsAsErrors=true`를 설정하면 경고도 빌드를 실패시킨다. HBCS006, HBCS007, HBCS015는 진단 심각도를 바꾸는 대신 경고 한계와 오류 한계를 조정해야 두 수준이 각자의 의미를 유지한다.

## 기존 코드에 도입

1. 읽기 전용 검사를 실행하고 진단 수를 센다.
2. 계약에 안전한 규칙(public 필드, 매우 긴 메서드)부터 시작하고, 취향에 가까운 규칙은 경고나 정보 수준으로 유지한다.
3. 새 진단이 눈에 띄도록 기준선([REPORT.md](REPORT.md#기준선))을 기록한다.
4. 새 진단이 나타났다고 기준선을 덮어쓰지 않는다. 의도한 정리를 마친 뒤에만 새로 만든다.
5. 주석으로 코드를 무시하지 말고 이유와 함께 `.editorconfig` 예외를 추가한다.
