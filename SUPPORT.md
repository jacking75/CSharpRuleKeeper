# 지원과 문제 해결

먼저 `Invoke-CSharpRuleKeeper.ps1 -Doctor -Solution <대상>`과 [호환성 표](docs/COMPATIBILITY.md)를 확인한다. 빌드 실패와 HBCS 진단 0개는 분석 완료를 뜻하지 않으므로 JSON의 `analysisCompleted`와 `executionErrors`를 확인한다.

제보에는 도구 버전, OS, SDK, PowerShell, 실행 명령, 관련 `.editorconfig`, 최소 재현 코드, 예상/실제 진단을 포함한다. 전체 비공개 소스, 토큰, 사용자 경로가 포함된 불필요한 로그를 올리지 않는다. 응답 시간 SLA는 약속하지 않으며 재현 가능한 범위에서 유지보수한다.
