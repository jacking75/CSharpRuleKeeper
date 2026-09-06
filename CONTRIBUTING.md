# 기여 안내

.NET SDK 10.0.400 feature band와 Windows PowerShell 5.1이 현재 검증 환경이다. 변경 전 관련 README, 구현 가이드, `.editorconfig`, Analyzer와 테스트를 읽는다.

완료 전 `dotnet format --verify-no-changes`, `dotnet build`, `dotnet test`, `build/run-quality-gate.ps1`을 실행한다. 규칙에는 통과·위반·예외·경계 테스트를 추가한다. 공개 HBCS ID의 의미와 severity를 호환성 검토 없이 바꾸지 않으며 사용자 동작 변경 시 한·영 README와 안내서를 갱신한다. `working_log.md`에는 실제 KST 시각을 기록한다. 명시적 요청 없이 CI 워크플로를 추가하지 않는다.

외부 프로젝트에 Analyzer 참조를 추가하지 않고, 계약 변경 가능성이 있는 Code Fix를 만들지 않는다.
