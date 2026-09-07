# CSharpRuleKeeper

[English README](README.md) · [초보자 안내](docs/BEGINNER_GUIDE.html) · [참조 안내](docs/REFERENCE_GUIDE.html)

CSharpRuleKeeper는 대상 프로젝트에 `ProjectReference`나 `PackageReference`를 추가하지 않고 C# 코드를 검사한다. whitespace를 검증하고 현재 빌드에만 Roslyn Analyzer를 주입한 뒤 사람이 읽는 Markdown과 구조화 JSON을 함께 만든다.

## 바로 체험하기

대상 프로젝트 자체의 .NET SDK와 Windows PowerShell 5.1이 필요하다. 이 저장소 개발은 .NET SDK 10.0.400 feature band와 `latestFeature` roll-forward를 사용한다. 먼저 읽기 전용 환경 진단을 실행한다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeper.ps1" -Doctor -Solution ".\MySolution.sln"
```

솔루션 또는 프로젝트를 검사한다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\tools\CSharpRuleKeeper\build\Invoke-CSharpRuleKeeper.ps1" -Solution ".\MySolution.sln" -OutputPath ".\coding-agent-change-report.md" -JsonOutputPath ".\coding-agent-change-report.json"
```

종료 코드는 검사 완료·정책 통과 `0`, 완료했지만 정책 위반 `1`, 실행·설정·서식·분석 완료 실패 `2`다. HBCS 진단 0개만으로 분석 완료를 뜻하지 않으므로 JSON의 `analysisCompleted`와 `executionErrors`를 확인한다.

기본 명령은 `dotnet format whitespace --verify-no-changes`를 실행하며 소스·프로젝트·설정을 바꾸지 않는다. `-Fix`도 `dotnet format whitespace`만 적용한다. 이름 변경, 외부 Analyzer Code Fix, 의미 변경은 실행하지 않는다. 한 줄 조건문의 중괄호처럼 whitespace만으로 해결되지 않는 규칙은 검사 대상일 수 있지만 `-Fix` 지원을 약속하지 않는다.

## 샘플로 안전하게 연습하기

편집 전 저장소나 샘플 복사본을 만든다. 다음 명령은 HBCS001·002를 의도적으로 켜므로 일반적으로 비정상 종료한다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\build\Invoke-CSharpRuleKeeper.ps1" -Solution ".\samples\SampleConsumer\SampleConsumer.csproj" -DefineConstants "DEMONSTRATE_RULES" -OutputPath ".\sample-practice-report.md"
```

직렬화·API 호환성을 검토한 뒤 `Count`를 캡슐화하고 `Ready`를 `IsReady`로 바꾸며, 테스트 후 재검사한다. HBCS004 IDE Code Fix는 구현돼 있지만 명령줄의 임시 Analyzer 주입만으로 IDE에 설치되지는 않는다.

## 옵션과 점진적 도입

`-ExplainEditorConfig`는 대상을 바꾸지 않고 옵션 카탈로그를 보여 준다. 길이 한계 쌍은 양수이면서 `warning < error`여야 하며 음수·0·overflow·역전이면 두 값을 모두 기본값으로 복원한다. `analyze_test_projects`는 현재 HBCS005에만 적용되고 어셈블리 이름 접미사로 테스트를 판단한다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\build\Invoke-CSharpRuleKeeper.ps1" -ExplainEditorConfig -OptionsDocumentationPath ".\options.md"
```

[personal/team-starter preset](config/presets)과 [참조 안내](docs/REFERENCE_GUIDE.html#adoption)를 검토한다. preset은 예제일 뿐 사용자 설정에 자동 복사되지 않는다. 대상에 `TreatWarningsAsErrors`가 있으면 warning도 빌드를 실패시킬 수 있다.

```powershell
.\build\Invoke-CSharpRuleKeeper.ps1 -Solution .\MySolution.sln -BaselinePath .\csharprulekeeper-baseline.json -CreateBaseline
.\build\Invoke-CSharpRuleKeeper.ps1 -Solution .\MySolution.sln -BaselinePath .\csharprulekeeper-baseline.json
```

## 규칙

| ID | 검사 | 기본값 |
| --- | --- | --- |
| [HBCS001](docs/REFERENCE_GUIDE.html#HBCS001) | public 필드 | error |
| [HBCS002](docs/REFERENCE_GUIDE.html#HBCS002) | boolean 상태 이름 | warning |
| [HBCS003](docs/REFERENCE_GUIDE.html#HBCS003) | 컬렉션 복수형 | warning |
| [HBCS004](docs/REFERENCE_GUIDE.html#HBCS004) | 확인 가능한 문맥의 `nameof` | warning |
| [HBCS005](docs/REFERENCE_GUIDE.html#HBCS005) | 매직 넘버 | warning |
| [HBCS006](docs/REFERENCE_GUIDE.html#HBCS006) | 메서드 물리 줄 | >30 warning, >100 error |
| [HBCS007](docs/REFERENCE_GUIDE.html#HBCS007) | 타입 물리 줄 | >300 warning, >500 error |
| [HBCS008](docs/REFERENCE_GUIDE.html#HBCS008) | 중복 `private` | info |
| [HBCS009](docs/REFERENCE_GUIDE.html#HBCS009) | 줄 끝 주석 | warning |
| [HBCS010](docs/REFERENCE_GUIDE.html#HBCS010) | 연속 빈 줄 | warning |
| [HBCS011](docs/REFERENCE_GUIDE.html#HBCS011) | 명시적 비트폭 정수 이름 | warning |
| [HBCS012](docs/REFERENCE_GUIDE.html#HBCS012) | 줄 길이 | >120 warning |
| [HBCS013](docs/REFERENCE_GUIDE.html#HBCS013) | 필수 명명 패턴 | warning |
| [HBCS014](docs/REFERENCE_GUIDE.html#HBCS014) | 필드 접두사 | error |
| [HBCS015](docs/REFERENCE_GUIDE.html#HBCS015) | 파일 물리 줄 | >500 warning, >1000 error |

생성된 `*.g.cs`, `*.Designer.cs`는 분석하지 않는다. 예외·경계·자동 수정·계약 위험은 각 규칙 문서에 있다.

## 보고서·배포·저장소 개발

SARIF 2.1 컴파일러 로그가 주 진단 자료원이며 콘솔 정규식은 호환 모드로 남는다. 결과는 안정적으로 정렬하고 `-MaxDiagnostics`는 Markdown 표시만 제한하며 전체 JSON의 필수 필드는 [참조 안내](docs/REFERENCE_GUIDE.html#reports)에 정리했다.

소스 빌드가 필요 없는 로컬 ZIP과 SHA-256을 만든다.

```powershell
.\build\Publish-CSharpRuleKeeperBundle.ps1 -Version 1.1.0
```

번들은 Release Analyzer DLL을 재사용하지만 대상 SDK는 계속 필요하다. 공개 게시가 확인되지 않았으므로 존재하지 않는 NuGet/.NET tool 설치 명령은 제공하지 않는다. [참조 안내](docs/REFERENCE_GUIDE.html#distribution), [문제 해결](docs/REFERENCE_GUIDE.html#support), [기여](CONTRIBUTING.md)를 참고한다.

저장소 개발 검증은 외부 검사보다 넓다.

```powershell
dotnet format --verify-no-changes
dotnet build
dotnet test
.\build\run-quality-gate.ps1
```

품질 게이트는 격리된 외부 프로젝트 통합 테스트도 수행하며 CI 설정은 만들지 않는다. 설계 근거는 [구현 안내](docs/IMPLEMENTATION_GUIDE.html)에 있다.
