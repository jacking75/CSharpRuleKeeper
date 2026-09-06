# HBCS001: public 필드 금지

## 목적
외부 API와 직렬화 계약이 의도 없이 필드에 고정되는 일을 막는다.

## 기본 심각도
`error`다.

## 위반 예제
`public Int32 Count;`

## 통과 예제
`public Int32 Count { get; set; }`

## 예외
`const`와 `public_field_allowed_attributes`에 완전한 이름으로 등록한 상호 운용·직렬화 특성은 제외한다.

## 옵션
`personal_csharp_rules.public_field_allowed_attributes`

## 경계값
줄 수 경계가 없다.

## 자동 수정
제공하지 않는다.

## 계약 변경 위험
필드를 속성으로 바꾸면 바이너리·직렬화 계약이 달라질 수 있어 수동 검토가 필수다.
