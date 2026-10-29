# 문제 해결

[English](../TROUBLESHOOTING.md) | [시작하기](GETTING_STARTED.md) | [보고서](REPORT.md)

먼저 `-Doctor`를 실행한다. 빌드 실패나 분석 누락을 "진단 0개"로 오해하지 않는다. JSON의 `analysisCompleted`와 `executionErrors`를 확인한다.

## `-Doctor` 읽기

| 줄 | 의미 |
| --- | --- |
| Installed SDKs | `dotnet --list-sdks`의 출력. |
| Target global.json | 대상에 적용되는 `global.json`, 그 버전과 `rollForward`, 설치된 SDK가 이를 만족하는지 여부. `NOT satisfied`는 종료 코드 2를 낸다. 맞는 SDK를 설치한다. |
| Analyzer | 릴리스 번들에는 Analyzer DLL이 들어 있어 도구 쪽 SDK가 필요 없다. 소스 체크아웃은 직접 빌드하므로 10.0.4xx SDK가 필요하다. |

## 증상

| 보이는 현상 | 먼저 할 일 |
| --- | --- |
| SDK 또는 `dotnet`을 찾을 수 없음 | `-Doctor`를 읽고 대상이 요구하는 SDK를 설치한 뒤 다시 실행한다. |
| HBCS 진단은 0개인데 실행이 실패함(종료 코드 2) | `analysisCompleted`와 `executionErrors`를 읽는다. 서식, 빌드, 보고서 쓰기 또는 완료 확인이 실패한 것이다. |
| `executionErrors`에 컴파일 오류 `CSxxxx`가 있음 | 대상이 스스로 빌드되지 않는다. 어떤 규칙보다 먼저 이를 고친다. |
| 공백 서식 검사 실패 | 변경 내용을 검토한 뒤 `dotnet format whitespace <target>`(또는 `-Fix`를 지정한 검사기)를 실행한다. |
| 경고가 빌드를 실패시킴 | 대상이 `TreatWarningsAsErrors`를 설정했다. 규칙을 고칠지 [옵션](CONFIGURATION.md)을 조정할지 결정한다. |
| 규칙이 외부 계약의 변경을 요구하는 것처럼 보임 | 자동으로 고치지 않는다. 호출자, 직렬화, 프로토콜을 확인하고 예외 설정이나 수동 설계를 사용한다. |
| 프로젝트 자체의 `CustomAfterMicrosoftCommonTargets`가 무시되는 것처럼 보임 | 검사기는 솔루션 안의 프로젝트를 포함해 프로젝트별로 이를 보존한다. 속성을 읽지 못했다는 경고가 나오면 그 프로젝트의 확장이 건너뛰어졌을 수 있다. |

## Windows PowerShell 전용

스크립트는 Windows의 Windows PowerShell 5.1에서 테스트되었다. PowerShell 7, macOS, Linux는 지원하지 않는다.

## 이슈 보고

도구 버전, OS, SDK, PowerShell 버전, 실행한 명령, 관련 `.editorconfig`, 재현하는 최소 코드 샘플, 기대한 진단과 실제 진단을 포함한다. 비공개 전체 소스, 토큰, 개인 경로가 들어 있는 로그는 공유하지 않는다. 응답 시간은 보장하지 않으며, 이슈는 유지보수자의 여건이 되는 대로 처리한다.
