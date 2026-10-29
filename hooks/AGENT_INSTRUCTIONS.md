# Agent instruction snippets

Paste the paragraph that matches your language into the `AGENTS.md` or `CLAUDE.md` of the C# project being checked.

## English

After completing a task, the Stop hook runs CSharpRuleKeeper. If it reports HBCS diagnostics, open the report path, fix each location, and finish again. Never change public APIs, serialization formats, protocol strings or exception behavior only to satisfy a rule. If the same diagnostic persists after three attempts, stop and explain.

## 한국어

작업을 마치면 Stop 훅이 CSharpRuleKeeper를 실행한다. HBCS 진단이 보고되면 보고서 경로를 열어 각 위치를 고친 뒤 다시 마무리한다. 규칙을 통과시키려는 목적만으로 public API, 직렬화 형식, 프로토콜 문자열, 예외 동작을 바꾸지 않는다. 같은 진단이 세 번 시도 후에도 남으면 멈추고 이유를 설명한다.
