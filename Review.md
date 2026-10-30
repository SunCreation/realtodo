# AIFFEL Campus Agent Code Review Templete
- 개발자 : 조해창 (SunCreation)
- 리뷰어 : nihao72-netizen

# ART(Agent Review Template)
[O]  **1. 원하는 기능이 의도한 대로 동작하나요?**
- 요청(프롬프트)한 기능이 정상적으로 구현되었는지?
- 실제 실행 화면/결과물을 캡처하여 근거로 첨부
- macOS 메뉴바 앱(Swift)이라 리뷰어 환경(Windows)에서는 빌드할 수 없었다. 그래서 PRD의 요구사항과 코드를 하나씩 대조해 확인했다.
- 구현 확인:
  - 메뉴바 상주와 팝오버: Dock 아이콘 숨김, 바깥을 클릭하면 닫힘 ([AppDelegate.swift:13](Sources/App/AppDelegate.swift#L13), [AppDelegate.swift:69](Sources/App/AppDelegate.swift#L69))
  - 오늘/전체 탭, 카테고리 필터, 우클릭 메뉴, 드래그 순서 변경, 클립보드 복사, 하위 태스크 진행률 표시
  - PRD 5.2의 CLI 명령어 전체: `today`, `list`, `show`, `add`(파이프 입력·`--batch` 포함), `edit`, `done`, `schedule`, `unschedule`, `delete`, `analyze`, `breakdown`, `suggestions`, `calendar`, `category`, `stats`, `config`. PRD에 없는 `time`, `rollover`, `review`도 추가되어 있다 ([RealTodoCLI.swift](Sources/CLI/RealTodoCLI.swift)).
  - Google Calendar 연동(여러 계정, 캘린더별 카테고리 매핑), agy로 AI 추천과 할 일 분해, 시스템 알림
- 구현되지 않은 PRD 항목: 전역 단축키(⌥⌘⇧T/N), 로그인 시 자동 실행(SMAppService), `make install-cli`
- 동작이 PRD와 다를 것으로 보이는 부분: 아침 루틴이 첫날만 실행되는 문제와 대기 개수 뱃지가 보이지 않는 문제 (아래 개선 제안 5·6번)

[O]  **2. 에이전트에게 준 요청(프롬프트)이 적절했나요?**
- 기능 요청이 구체적이고 명확했는지?
- 모호한 요청을 어떻게 보완했는지 (예: 예시 제공, 조건 명시)
- [PRD.md](PRD.md)가 656줄 분량으로 구체적이다. 데이터 모델과 스키마(7.2), CLI 명령어와 출력 형식(5.2~5.3), agy 호출 방식(타임아웃 60초, 실패 시 1회 재시도, 4.4), 단계별 마일스톤(10)까지 적혀 있어 에이전트가 추측할 부분이 적다.
- Non-Goals(v1 제외 범위)를 따로 적어 에이전트가 범위를 넓히지 않도록 한 점이 좋았다.
- AI 기능에 쓰이는 프롬프트도 구체적이다. 출력 JSON 형식을 예시로 고정하고 "다른 텍스트 없이"라고 조건을 명시해, 파싱이 실패할 가능성을 줄였다 ([AIService.swift:57-72](Sources/RealTodoKit/Services/AIService.swift#L57-L72)).
- 아쉬운 점: 에이전트에게 실제로 보낸 요청 기록은 저장소에 없다. PRD와 구현이 다른 곳이 있다(예: PRD는 `ASWebAuthenticationSession`과 GTMAppAuth로 로그인한다고 했지만, 코드는 직접 만든 로컬 소켓 서버를 쓴다). 개발 중에 요청을 바꿨다면, 그 내용을 PRD에 반영해 두면 다음 요청의 기준으로 쓸 수 있다.

[O]  **3. 보안 검토를 수행했나요?**
- API 키, 비밀번호 등 민감 정보가 코드에 하드코딩되지 않았는지
- 사용자 입력값 검증 등 기본 보안 사항 확인
- 외부 데이터/의존성 사용 시 출처와 위험 검토했는지

잘 된 점
- **비밀값 하드코딩 없음:** Google OAuth의 `client_secret`은 저장소 밖 `~/.config/mcp-google/credentials.json`에서 읽는다 ([Constants.swift:18](Sources/RealTodoKit/Helpers/Constants.swift#L18)). 전체 커밋 이력을 검색했을 때 키·토큰은 없었다. `.gitignore`가 `.env*`, `credentials.json`, `*.pem`, `*.key`, `*.db`를 모두 막고 있다.
- **SQL 주입 방지:** GRDB에 값을 `?` 자리표시자로 넘긴다 (예: [DatabaseService.swift:166](Sources/RealTodoKit/Services/DatabaseService.swift#L166)). SQL 문자열에 값을 끼워 넣는 코드는 없다.
- **명령어 주입 방지:** agy를 셸을 거치지 않고 `Process.arguments` 배열로 실행해서, 할 일 제목에 특수문자가 있어도 명령어로 해석되지 않는다 ([AIService.swift:164-165](Sources/RealTodoKit/Services/AIService.swift#L164-L165)).
- **AI 출력 제한:** AI가 돌려준 delete/update는 AI가 만든, 아직 대기 중인 제안에만 적용된다 (`editableIds`, [TaskBreakdownService.swift:106-122](Sources/RealTodoKit/Services/TaskBreakdownService.swift#L106-L122)). 그래서 AI가 잘못 답하거나 캘린더 일정 내용에 조작된 지시가 들어 있어도, 사용자가 직접 만든 할 일은 지워지지 않는다.
- **의존성:** GRDB.swift와 apple/swift-argument-parser는 널리 쓰이는 오픈소스이고, `Package.resolved`로 버전이 고정되어 있다.

개선 제안 (아래 "코드 개선" 1~3번)
- OAuth 콜백 서버가 모든 네트워크 주소에서 접속을 받는다.
- OAuth 요청에 `state`와 PKCE가 없다.
- Google 토큰을 암호화하지 않고 SQLite에 저장한다.

[O]  **4. 에러가 난 부분을 디버깅하여 "문제를 해결한 기록"을 남겼나요?**
- 에이전트가 만든 코드의 오류를 어떻게 발견하고 수정했는지
- 새로운 시도 및 추가 실험이 기록되어 있는지
- 별도 문서는 없지만, 겪은 문제와 해결 이유가 코드 주석에 구체적으로 남아 있다.
  - agy 출력이 파이프 버퍼(약 64KB)를 넘으면 자식 프로세스가 멈춰 가짜 타임아웃이 났다. stdout/stderr를 동시에 읽도록 바꿔 해결했다 ([AIService.swift:175-177](Sources/RealTodoKit/Services/AIService.swift#L175-L177)).
  - 타임아웃은 이미 제한 시간을 다 쓴 뒤라 재시도하면 기다리는 시간이 두 배가 된다. 그래서 실행 실패만 재시도한다 ([AIService.swift:155-159](Sources/RealTodoKit/Services/AIService.swift#L155-L159)).
  - agy 실패가 모두 `nil` 하나로 묻히던 것을 stderr에 이유를 남기도록 고쳤다 ([AIService.swift:217-218](Sources/RealTodoKit/Services/AIService.swift#L217-L218)).
  - 메뉴바 아이콘이 실행할 때마다 노치 아래로 밀려나던 문제를 `autosaveName`으로 위치를 저장해 해결했다 ([AppDelegate.swift:54-57](Sources/App/AppDelegate.swift#L54-L57)).
  - 자정이 지나도 앱을 재시작하기 전까지 어제 할 일이 남아 있던 문제를 날짜 변경 알림으로 해결했다 ([AppDelegate.swift:27-35](Sources/App/AppDelegate.swift#L27-L35)).
- 제안: 커밋이 "Initial commit" 하나뿐이라 이런 수정 과정이 이력으로는 보이지 않는다. 기능이나 수정 단위로 커밋을 나누거나 디버깅 기록 문서를 두면, 무엇을 시도했고 왜 바꿨는지 더 잘 전달될 것 같다.

[X]  **5. 회고를 잘 작성했나요?**
- 에이전트 활용 과정에서 배운 점, 아쉬운 점, 느낀 점이 상세히 기록되어 있나요?
- 다음에 더 잘 요청하기 위한 개선점이 포함되어 있는지
- 저장소에서 회고 문서를 찾지 못했다. 저장소에는 PRD.md와 소스 코드만 있고 README도 없다.
- 제안: PRD를 이 정도로 구체적으로 쓴 경험 자체가 좋은 회고 소재다. "PRD에서 무엇을 정했더니 에이전트가 잘 따라왔고, 무엇은 구현하며 바뀌었는지"를 README에 짧게 남기면 다음 프로젝트에 바로 쓸 수 있을 것 같다.

# 참고 링크 및 코드 개선

## 1.리뷰 시 참고한 링크가 있다면 링크와 간략한 설명을 첨부합니다.
- [RFC 8252 - OAuth 2.0 for Native Apps](https://datatracker.ietf.org/doc/html/rfc8252): 데스크톱 앱은 루프백(127.0.0.1) 리디렉션과 PKCE를 쓰도록 권장한다.
- [Google: OAuth 2.0 for iOS & Desktop Apps](https://developers.google.com/identity/protocols/oauth2/native-app): Google도 데스크톱 앱에 `code_challenge`(PKCE)와 `state`를 권장한다.
- [Apple: Keychain Services](https://developer.apple.com/documentation/security/keychain-services): macOS에서 토큰 같은 비밀값을 저장하는 표준 방법이다.

## 2.리뷰를 통해 개선을 제안할 부분이 있다면 내용과 간략한 설명을 첨부합니다.
1. **OAuth 콜백 서버를 127.0.0.1에만 열기:** [SettingsViewModel.swift:249-253](Sources/RealTodoKit/ViewModels/SettingsViewModel.swift#L249-L253)에서 `getaddrinfo(nil, …)`과 `AI_PASSIVE`를 함께 써서 9876 포트가 모든 네트워크 주소에서 열린다. 로그인을 기다리는 최대 180초 동안 같은 와이파이의 다른 기기가 먼저 접속하면, 서버가 그 요청을 콜백으로 받아들이고 끝나 버린다. 첫 인자를 `"127.0.0.1"`로 주면 이 컴퓨터에서만 접속할 수 있다.
2. **OAuth에 `state`와 PKCE 추가:** [AuthService.swift:94](Sources/RealTodoKit/Services/AuthService.swift#L94)의 `buildAuthURL`에는 `state`와 `code_challenge`가 없다. `state`(무작위 값)를 보내고 콜백에서 같은 값인지 확인하면, 다른 사람이 만든 인증 코드가 섞여 들어오는 것을 막을 수 있다.
3. **Google 토큰은 Keychain에 저장:** `access_token`과 `refresh_token`이 `realtodo.db`에 평문으로 저장된다 ([DatabaseService.swift:86-87](Sources/RealTodoKit/Services/DatabaseService.swift#L86-L87)). DB 파일이 백업이나 공유로 밖에 나가면 캘린더 읽기 권한도 함께 나간다. refresh token만이라도 Keychain에 두는 것을 제안한다.
4. **(의견) 캘린더 내용이 외부 AI로 전달된다는 점을 문서에 적기:** 일정 제목과 설명이 agy 프롬프트에 들어간다. 회사 캘린더를 연결할 경우를 생각해, 어떤 데이터가 AI로 가는지 README나 설정 화면에 한 줄 적어 두면 좋겠다.
5. **아침 루틴 타이머가 한 번만 울린다:** [TimerService.swift:112-113](Sources/RealTodoKit/Services/TimerService.swift#L112-L113)의 타이머에 `repeating`이 없고, 실행 후 다시 예약하는 코드도 없다. 메뉴바 앱은 며칠씩 켜 두는 경우가 많은데, 그러면 둘째 날부터 08:00 아침 루틴이 돌지 않는다. 자정에 불리는 `dayChanged`([AppDelegate.swift:38-44](Sources/App/AppDelegate.swift#L38-L44))에서 `scheduleMorningRoutine()`을 다시 부르면 고칠 수 있다.
6. **대기 개수 뱃지가 화면에 보이지 않는다:** PRD 4.5는 메뉴바 아이콘에 대기 개수를 표시하도록 요구한다. 그런데 코드는 Dock 아이콘에 뱃지를 단다([NotificationService.swift:43](Sources/RealTodoKit/Services/NotificationService.swift#L43)). 앱이 `.accessory` 모드라 Dock 아이콘이 없으므로 뱃지가 어디에도 보이지 않는다. `statusItem.button.title`에 개수를 표시하는 방법을 제안한다.
7. **상위 할 일을 삭제하면 하위 태스크가 DB에 남는다:** `parent_todo_id`에 외래키가 없고([DatabaseService.swift:42](Sources/RealTodoKit/Services/DatabaseService.swift#L42)), `deleteTodo`도 해당 행만 지운다. 목록은 `parent_todo_id == nil`인 항목만 보여 주기 때문에, 남은 하위 태스크는 화면에 나오지 않는 쓰레기 데이터가 된다. `references("todos", onDelete: .cascade)`를 추가하는 마이그레이션을 제안한다.
8. **README와 테스트 추가:** 실행하려면 `~/.local/bin/agy`와 `~/.config/mcp-google/credentials.json`이 정해진 경로에 있어야 하는데, 이 내용이 문서에 없다. 다른 사람이 받아서 실행할 수 있도록 README에 준비 과정을 적고, AI 응답 파싱(`parseAIResponse`, `parseActions`)처럼 입력과 출력이 분명한 함수부터 테스트를 붙이면 좋겠다.

# 총평
656줄짜리 PRD 덕분에, 에이전트가 만든 코드의 구조가 설계와 거의 같다. 공통 코드(RealTodoKit)를 GUI와 CLI가 함께 쓰고, 서비스를 `actor`로 만들어 동시 접근을 안전하게 처리하고, DB 스키마를 버전별 마이그레이션으로 관리한다. 가장 배우고 싶은 점은 AI의 응답을 그대로 믿지 않은 설계다. AI가 돌려준 삭제·수정 요청은 AI 자신이 만든 대기 중 제안에만 적용해서, 사용자가 만든 할 일은 AI가 어떤 답을 내놓아도 안전하다.

보완하면 좋을 점은 두 가지다. 첫째, Google 로그인(OAuth 콜백 서버의 접속 주소, `state`/PKCE, 토큰 저장)을 보강하는 것이다. 둘째, 아침 루틴 타이머처럼 오래 켜 두어야 드러나는 버그를 테스트와 README로 잡을 수 있게 하는 것이다. 이 두 가지를 보완하면 매일 쓰는 도구로도 충분하다고 생각한다.
