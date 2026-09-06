# HBCS005: 매직 넘버

## 목적
숫자의 도메인 의미를 이름으로 남긴다.
## 기본 심각도
`warning`이다.
## 위반 예제
`return value * 30;`
## 통과 예제
`const Int32 RetrySeconds = 30;`
## 예외
`const`, enum, 특성 인수, bit flag, 허용값과 기본적으로 테스트 어셈블리를 제외한다.
## 옵션
`allow_magic_numbers`, `analyze_test_projects`다. 테스트는 어셈블리 이름 접미사로 판단한다.
## 경계값
기본 허용값은 `-1,0,1,2`다.
## 자동 수정
제공하지 않는다.
## 계약 변경 위험
값을 바꾸지 않고 이름만 추출해야 한다.
