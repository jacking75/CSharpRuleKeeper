# 호환성

| 구분 | 지원·검증 상태 |
| --- | --- |
| 도구 개발 SDK | `global.json`의 .NET SDK 10.0.400 feature band, `latestFeature` roll-forward |
| Analyzer 대상 | `netstandard2.0`; 이것만으로 모든 구형 Roslyn 호스트 호환을 보장하지 않음 |
| 테스트 호스트 | `net10.0` |
| 대상 프로젝트 | 대상 자체 SDK/TFM으로 빌드되며 해당 SDK가 설치되어야 함 |
| PowerShell | Windows PowerShell 5.1에서 구문 및 통합 테스트, PowerShell 7은 실제 검증 후 표에 추가 |
| 운영체제 | Windows 검증. macOS/Linux는 아직 지원을 선언하지 않음 |
| IDE Code Fix | HBCS004가 패키지에 포함되지만 외부 빌드 주입만으로 IDE에 설치되지는 않음 |
| Unity | 전면 지원을 선언하지 않음. 허용 특성 preset은 계약 보존용 설정 예시임 |

`-Doctor`는 설치 SDK, PowerShell, 도구 버전, 대상에 적용되는 `global.json`을 읽기 전용으로 표시한다. SDK가 없으면 dotnet 미발견, 10.0.400 feature band가 없으면 요구 버전 없음, 있으면 사용 가능으로 구분한다.
