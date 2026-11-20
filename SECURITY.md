# Security policy / 보안 정책

## English

### Reporting a vulnerability

Please do not report security problems in public issues. Use GitHub's private vulnerability reporting instead: on the repository page open **Security**, then **Report a vulnerability** (https://github.com/jacking75/CSharpRuleKeeper/security/advisories/new). Describe the problem, the affected version, and the steps to reproduce it. You will get an answer as maintainer time allows; there is no guaranteed response time.

Security fixes are made on the latest version only.

### What the tool runs

The checker and the Stop hook run `dotnet format` and `dotnet build` on the target. A build executes the target repository's MSBuild logic: its project files, `Directory.Build.props`/`.targets`, imported targets, source generators, analyzers and NuGet package build scripts. Checking a repository therefore runs code from that repository with your user rights. Only check code you trust, and treat an agent hook on an untrusted repository like running its build yourself.

The tool itself sends nothing over the network. `dotnet build` restores NuGet packages as configured by the target.

## 한국어

### 취약점 보고

보안 문제는 공개 이슈로 올리지 않는다. GitHub의 비공개 취약점 보고를 사용한다. 저장소 페이지에서 **Security** → **Report a vulnerability**(https://github.com/jacking75/CSharpRuleKeeper/security/advisories/new)를 연다. 문제, 영향을 받는 버전, 재현 절차를 적는다. 답변은 유지보수자의 여건이 되는 대로 하며 응답 시간은 보장하지 않는다.

보안 수정은 최신 버전에만 적용한다.

### 도구가 실행하는 것

검사기와 Stop 훅은 대상에 `dotnet format`과 `dotnet build`를 실행한다. 빌드는 대상 저장소의 MSBuild 로직, 즉 프로젝트 파일, `Directory.Build.props`/`.targets`, 가져온 target, 소스 생성기, Analyzer, NuGet 패키지의 빌드 스크립트를 실행한다. 따라서 저장소를 검사하면 그 저장소의 코드가 사용자 권한으로 실행된다. 신뢰하는 코드만 검사하고, 신뢰할 수 없는 저장소에서 에이전트 훅을 쓰는 것은 그 빌드를 직접 실행하는 것과 같다고 본다.

도구 자체는 네트워크로 아무것도 보내지 않는다. `dotnet build`는 대상의 설정대로 NuGet 패키지를 복원한다.
