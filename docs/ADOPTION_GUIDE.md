# 팀 도입 안내

`config/presets/personal.editorconfig`는 현재 개인 기본 정책을 명시한다. `team-starter.editorconfig`는 계약 안전 규칙부터 켜고 취향이 강한 HBCS003·008·011·013을 suggestion 또는 none으로 시작하는 검토용 예제다. 어느 preset도 자동 복사하거나 기존 설정을 덮어쓰지 않는다.

`dotnet_diagnostic.HBCSxxx.severity`는 Roslyn severity를 바꾼다. HBCS006·007·015는 같은 ID가 warning/error descriptor에 사용되므로 ID severity override는 두 단계 모두 같은 severity로 표시한다. 원래 두 단계의 의미를 유지하려면 `personal_csharp_rules.*_warning`과 `*_error`만 조정한다.

`TreatWarningsAsErrors=true`인 대상에서는 warning도 빌드를 실패시킬 수 있다. 기준선은 명시적으로 생성하고 자동 갱신하지 않는다. Unity나 직렬화 필드는 완전한 특성 이름을 최소 디렉터리 범위에 설정하며, 이는 Unity 전체 지원 선언이 아니다.
