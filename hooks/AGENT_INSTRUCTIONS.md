# Agent instruction snippets

Paste the paragraph that matches your language into the `AGENTS.md` or `CLAUDE.md` of the C# project being checked.

## English

After completing a task, the Stop hook runs CSharpRuleKeeper on the whole solution. If it reports HBCS diagnostics, compile errors or whitespace differences, open the report path, fix each location, and finish again. Never change public APIs, serialization formats, protocol strings or exception behavior only to satisfy a rule, and do not add suppressions or edit `.editorconfig` to make a rule pass. If a finding cannot be fixed safely, or the same finding remains after three attempts, stop and explain it to the user.

## 한국어

작업을 마치면 Stop 훅이 솔루션 전체에 CSharpRuleKeeper를 실행한다. HBCS 진단, 컴파일 오류, 공백 서식 차이가 보고되면 보고서 경로를 열어 각 위치를 고친 뒤 다시 마무리한다. 규칙을 통과시키려는 목적만으로 public API, 직렬화 형식, 프로토콜 문자열, 예외 동작을 바꾸지 않으며, 규칙을 통과시키려고 억제를 추가하거나 `.editorconfig`를 고치지 않는다. 안전하게 고칠 수 없는 진단이 있거나 같은 진단이 세 번 시도 후에도 남으면 멈추고 사용자에게 설명한다.
