# 기존 진단 기준선

`-BaselinePath .\csharprulekeeper-baseline.json -CreateBaseline`으로 현재 분석 완료 결과를 명시적으로 저장한다. 이후 같은 `-BaselinePath`로 검사하면 새 진단·기존 진단·해결된 진단 수를 JSON에 기록한다. 검사 중 기준선을 자동 갱신하지 않는다.

fingerprint는 규칙 ID, 상대 또는 보고된 파일 경로, 메시지를 SHA-256으로 결합하며 줄 번호에만 의존하지 않는다. 앞부분 줄 삽입은 기존 진단으로 남을 수 있다. 첫 버전에서는 파일 rename, 같은 문맥의 중복 진단, 도구 버전 변경을 보수적으로 재검토 대상으로 취급한다. 컴파일·restore·분석 미완료는 기준선으로 통과시킬 수 없다.
