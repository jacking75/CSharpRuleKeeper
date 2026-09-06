# HBCS014: 필드 저장 방식별 접두사

## 목적
인스턴스·static·thread static 저장 방식을 이름에 드러낸다.
## 기본 심각도
`error`다.
## 위반 예제
`static Int32 _count;`
## 통과 예제
`static Int32 s_count;`
## 예외
생성 코드를 제외한다.
## 옵션
전용 옵션은 없다.
## 경계값
인스턴스 `_`, static `s_`, `[ThreadStatic]` `t_` 뒤에 camelCase를 요구한다.
## 자동 수정
제공하지 않는다.
## 계약 변경 위험
reflection·직렬화가 비공개 이름을 사용하는지 확인해야 한다.
