# HBCS002: boolean 상태 이름

## 목적
boolean 값과 질문형 메서드의 의미를 이름에서 드러낸다.

## 기본 심각도
`warning`이다.

## 위반 예제
`Boolean Ready { get; }`

## 통과 예제
`Boolean IsReady { get; }`

## 예외
`Try` 메서드의 `out Boolean`, override, 명시적·암시적 인터페이스 구현은 외부 계약 보호를 위해 제외한다.

## 옵션
전용 옵션은 없고 `dotnet_diagnostic.HBCS002.severity`로 조정한다.

## 경계값
허용 접두사는 `is/has/can/should/needs`, 메서드는 해당 PascalCase와 `Exists/Contains`다.

## 자동 수정
제공하지 않는다.

## 계약 변경 위험
이름 변경은 소스·리플렉션·직렬화 계약에 영향을 줄 수 있다.
