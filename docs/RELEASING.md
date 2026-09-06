# 로컬 배포물 만들기

`build/Publish-CSharpRuleKeeperBundle.ps1 -Version 1.1.0`을 실행하면 Release Analyzer DLL, targets, 스크립트, 옵션·보고서 스키마, 규칙 문서, README, LICENSE를 ZIP으로 묶고 SHA-256 파일을 만든다.

깨끗한 디렉터리에 압축을 풀어 `build/Invoke-CSharpRuleKeeper.ps1 -Doctor`와 정상/위반 샘플을 검사한다. 제거는 압축 해제 디렉터리 삭제이며, 되돌리기는 이전 ZIP을 별도 디렉터리에 풀어 사용한다. 대상 SDK는 별도로 필요하다. 실제 GitHub/NuGet 게시와 자격증명 사용은 자동화하지 않는다.
