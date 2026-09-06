# 성능 측정

`build/Measure-CSharpRuleKeeperPerformance.ps1`는 같은 대상을 최소 5회 실행하고 원시 시간과 중앙값을 JSON으로 기록한다. 장비, SDK, 프로젝트 수, TFM, 코드량, restore 포함 첫 실행과 restore 후 반복 실행을 함께 해석해야 한다.

Release Analyzer DLL은 `-AnalyzerPath` 또는 배포 번들로 재사용한다. 증분 빌드가 분석을 건너뛴 결과는 향상으로 계산하지 않는다. 측정하지 않은 목표는 지원 약속이 아니다. `-TimeoutSeconds`가 지나면 Windows 프로세스 트리를 종료하고 보고서를 미완료 상태로 남긴다.

## 2026-09-06 로컬 반복 측정

- 대상: `samples/SampleConsumer/SampleConsumer.csproj`, 1개 프로젝트, `net10.0`
- 환경: Windows, .NET SDK 10.0.400, Release Analyzer DLL 재사용, restore 완료 상태
- 범위: 파일 탐색·whitespace 검증·비증분 대상 빌드·Analyzer·보고서 생성 전체
- 원시 시간: 6,793ms, 6,366ms, 6,413ms, 6,413ms, 6,985ms
- 중앙값: 6,413ms
- 결과: 5회 모두 `analysisCompleted=true`, 진단과 상태가 동일했다.

이 값은 현재 장비의 작은 샘플 결과이며 소·중·대 프로젝트 전체 성능을 대표하지 않는다. 단계별 세분화와 다른 규모 측정은 후속 실측 항목이다.
