# HBCS004: 확인 가능한 식별자에 nameof 사용

## 목적
식별자 문자열을 컴파일러가 추적하게 한다.
## 기본 심각도
`warning`이다.
## 위반 예제
`new ArgumentNullException("value")`
## 통과 예제
`new ArgumentNullException(nameof(value))`
## 예외
외부 프로토콜, JSON 키, 확인할 수 없는 문자열은 제외한다.
## 옵션
전용 옵션은 없다.
## 경계값
예외의 `paramName`, `PropertyChangedEventArgs`, 현재 타입 reflection만 검사한다.
## 자동 수정
IDE Code Fix와 Fix All을 제공하지만 빌드 주입만으로 IDE에 설치되지는 않는다.
## 계약 변경 위험
문맥을 확인하고 문자열 상수 값이 동일한 경우만 적용한다.
