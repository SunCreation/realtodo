# AIFFEL Campus Code Peer Review Template

- 코더(Coder) : SunCreation (조해창)  <!-- GitHub 핸들 / 실명 미확인 시 핸들 -->
- 리뷰어(Reviewer) : 김주영

> 리뷰 대상 레포 : https://github.com/SunCreation/realtodo
> 프로젝트 : RealTodo — macOS 메뉴바 할일 앱 (SwiftUI + GRDB/SQLite + Google Calendar + AI `agy` CLI)
> 리뷰 일자 : 2026-07-21

> **⚠️ 검토 환경 고지 (정직성):** 본 앱은 **macOS 14+ 전용(SwiftUI)** 이라 리뷰어의 Windows 환경에서
> **빌드·실행을 하지 못했습니다.** 따라서 아래 "실제 동작" 판정은 **코드 정독 기반 추정**이며,
> 실행 검증이 아닙니다. `[코드확인]` = 소스에서 직접 확인, `[미실행]` = 런타임 미검증 항목.

---

# PRT(Peer Review Template)

> 각 문항 앞 `[ ]`에 **O**(해당) / **X**(미해당) 표기.
> **모든 문항에 근거를 반드시 첨부** — 근거가 되는 코드 블록 또는 스크린샷.

- [O] **1. 주어진 문제를 해결하는 완성된 코드가 제출되었나요?**
  - PRD(24KB 상세 스펙)의 요구가 실제 코드로 구현됨 `[코드확인]` / 런타임 미검증 `[미실행]`
  - **근거:** 3-타깃 구조(`RealTodoKit` 로직 · `App` SwiftUI · `CLI` 19개 서브커맨드)로 완결.
    DB CRUD·마이그레이션(v1~v3), Google OAuth+Calendar REST, AI(`agy`) 연동까지 전부 존재.
    ```
    Sources/CLI/RealTodoCLI.swift : today/list/add/edit/done/schedule/delete/analyze/
      review/breakdown/suggestions/calendar/category/stats/config … 19개 커맨드 모두 서비스에 연결
    Package.swift : GRDB 7 + swift-argument-parser 의존, macOS(.v14) 타깃
    ```

- [O] **2. 핵심적이거나 복잡한 부분의 설명을 보고 코드가 잘 이해되었나요?**
  - 단순 나열 주석이 아니라 **"왜 이렇게 했는지"** 를 남긴 doc 주석이 강점.
  - **근거:**
    ```
    AIService.swift:155-159  agy 프로세스 재시도 정책 설명
      "Only *launch* failures are retried … A timeout is not retried: the process
       already consumed the full window, so retrying would silently double the wait."
    AIService.swift:175-177  파이프 데드락 회피 이유
      "agy can emit more than the OS pipe buffer (~64KB); reading only after exit
       would block the child on a full pipe and force a spurious timeout."
    DatabaseService.swift:297-300 / TaskBreakdownService.swift:88-92  파괴적 작업 범위 한정 근거
    ```

- [O] **3. 디버깅하여 "문제 해결 기록"을 남겼거나 "새로운 시도·추가 실험"을 했나요?**
  - 별도 트러블슈팅 문서는 없으나, **엔지니어링 판단이 코드 주석으로 기록**돼 있어 인정.
  - **근거:**
    ```
    · 파이프 동시 드레인(AIService.swift:178-206) — 순진한 "read-after-exit" 데드락을 겪고
      DispatchGroup 동시 드레인으로 해결한 흔적
    · launch만 재시도/timeout은 재시도 안 함(AIService.swift:160-206) — 실패 유형 구분 실험
    · OAuth 콜백을 위해 raw BSD 소켓 로컬 서버 직접 구현(SettingsViewModel.swift:239-334) — 추가 시도
    ```
  - **아쉬운 점:** 무엇이 실패했고 어떻게 고쳤는지의 **명시적 기록(README/회고)** 은 없음 → 4번과 연결.

- [X] **4. 회고를 잘 작성했나요?**
  - **미해당.** 레포에 README·회고·배운점/아쉬운점 문서가 **전혀 없음.**
  - **근거:**
    ```
    $ git ls-files | grep -iE 'readme|회고|retro'   → (없음)
    $ git grep -niE '회고|배운|아쉬|느낀' -- '*.md'  → (없음)
    추적 파일 34개 중 문서는 PRD.md(스펙) 1개뿐. 결과에 대한 성찰 기록 부재.
    ```
  - **이게 이번 리뷰에서 가장 명확한 개선점.** 코드 완성도에 비해 회고가 비어 감점 요인.

- [O] **5. 코드가 간결하고 효율적인가요? (단, 효율성에 실제 지적 있음)**
  - 구조·모듈화는 우수. 다만 **N+1 쿼리** 등 효율성 결함이 실재 → 무조건 O는 아님.
  - **근거(좋은 점):**
    ```
    · actor 격리(DatabaseService/AuthService/CalendarService/AIService)로 동시성 안전
    · SQL 전부 파라미터 바인딩(arguments:) — 중복 없는 헬퍼화
    · Array.uniqued() 확장 등 재사용 유틸(TaskBreakdownService.swift:251)
    ```
  - **근거(효율 지적):**
    ```
    · N+1 쿼리: fetchAllTodos/fetchTodayTodos/fetchSubtasks가 todo마다 카테고리 SELECT를
      개별 실행(DatabaseService.swift:203-211, 235-243, 257-266). JOIN 1회로 접을 수 있음.
    · show 커맨드가 단일 항목 카테고리 얻으려 fetchAllTodos() 전체 재조회
      (RealTodoCLI.swift:135), 게다가 parent_todo_id==nil 필터라 서브태스크 카테고리는 누락.
    ```

---

# 프로젝트 제출 루브릭 평가 (본 프로젝트 채점 기준)

> 파트너 프로젝트를 아래 3개 학습목표/평가기준으로 실제 평가한다.
> 각 항목 `[ ]`에 **O**(충족) / **X**(미충족) 표기 + 근거 필수.

- [△] **1. 보안을 스스로 점검할 수 있습니다.**  → **대체로 충족, 단 자가점검이 놓친 실보안 이슈 2건**
  - 평가기준: 보안 문제가 없는지 잘 검토되어 있고, **실제로 문제가 없어야** 합니다.
  - **잘 된 자가점검(충족 근거):**
    ```
    · 하드코딩 시크릿 0건 — git grep(api_key|secret|token|AIza|sk-|BEGIN…) 결과 변수명/에러문자열뿐
    · 자격증명 파일 커밋 0건 — credentials.json/.env/.pem/.key 미추적
    · .gitignore가 시크릿·로컬DB를 의도적으로 광범위 차단(*.env, credentials.json, *.pem, *.key, *.sqlite, *.db)
    · SQL 전부 파라미터 바인딩 → SQL 인젝션 불가 (DatabaseService 전 메서드 arguments: 사용)
    · AI 실행이 Process(arguments 배열) → 셸 인젝션 불가 (AIService.swift:164-165)
    · AI CRUD id 검증 → AI 환각으로도 사용자 소유 할일 삭제/수정 불가
      (TaskBreakdownService.swift:106 editableIds 게이트 + :120 source/status 재확인)
    · Google 스코프 calendar.readonly — 최소권한 (Constants.swift:24-28)
    ```
  - **자가점검이 놓친 실제 이슈 (여기가 "실제로 문제 없어야"에 걸리는 부분):**
    ```
    ① [보안-중] OAuth 콜백 CSRF 방어 부재 (state/PKCE 없음)
       - buildAuthURL에 state·code_challenge 파라미터 없음 (AuthService.swift:94-105)
       - 콜백 서버가 첫 요청의 ?code= 를 검증 없이 수락 (SettingsViewModel.swift:205-211)
       - 결과: localhost:9876 인증창 열린 180초 동안, 로컬 악성 프로세스나
         "http://localhost:9876/?code=..." 를 부르는 크래프팅 링크로 code 주입 가능
         (OAuth login-CSRF / code-injection). 심각도는 로컬·시간창 한정이라 낮음~중이나,
         "보안 자가점검"을 학습목표로 삼은 프로젝트가 놓치면 안 되는 교과서적 항목.
       - 개선: buildAuthURL에 state(랜덤) + PKCE 추가, 콜백에서 state 일치 검증.
    ② [보안-저~중] OAuth 토큰 평문 저장 (Keychain 미사용)
       - access_token·refresh_token을 로컬 SQLite에 평문 저장
         (DatabaseService.swift:81-91 google_accounts 테이블)
       - DB는 gitignore·유저 스코프 경로라 실유출 위험은 낮으나, macOS 정석은 Keychain.
         특히 refresh_token은 장기 토큰이라 평문 보관이 바람직하지 않음.
    ```
  - **판정 근거:** 시크릿/인젝션/인가 등 "터지는" 구멍은 없음(양호). 다만 인증 플로우에
    state/PKCE 누락이라는 실이슈가 있어 **깨끗한 O가 아니라 △(조건부 충족)** 로 매김.

- [O] **2. 실제 동작하는 백엔드 동작을 포함시킬 수 있습니다.**  → **충족 (단 런타임 미검증 + 소버그)**
  - 평가기준: 실제로 동작하는 백엔드가 **의도(PRD)와 일치**합니다.
  - **근거(충족):**
    ```
    · 진짜 백엔드 3종: GRDB/SQLite(WAL·FK·마이그레이션 v1~v3, 완전 CRUD),
      Google OAuth+Calendar REST(토큰 교환/갱신/userinfo/calendarList/events),
      AI 서브프로세스(agy --print, 타임아웃/재시도/JSON 추출) — 전부 실제 I/O 코드.
    · PRD의 "아침 AI 산정 → 사용자 승격 → 30분 주기 리뷰" 워크플로가 코드로 존재
      (TaskBreakdownService.runReview morning/periodic).
    ```
  - **실제 지적(의도 불일치 버그) — 동작 로직 재점검분:**
    ```
    · [동작-상] 아침 AI 루틴이 "하루 1회"만 실행되고 다음날부터 안 뜸 (핵심기능 정지):
      scheduleMorningRoutine이 일회성 타이머 — schedule(deadline:)에 repeating: 없음
      (TimerService.swift:113). 핸들러(:114-116)가 다음날 타이머를 재예약하지 않음.
      → 앱을 켜둬도 아침 루틴 최초 1회뿐. PRD "매일 아침 자동 산정" 워크플로 깨짐.
      (참고: 주기 업데이트 schedulePeriodicUpdate는 repeating:로 정상 반복 — 대조적)
    · [동작-중] 카테고리 필터 이중 적용 + 상태 오염:
      loadAllTodos가 필터 결과를 todos에 덮어쓰고(TodoListViewModel.swift:29-34),
      filteredTodos가 다시 필터(:139). toggleCategoryFilter(:131)는 reload 미호출 →
      필터 해제해도 걸러진 항목이 reload 전까지 안 돌아옴(비일관 동작).
    · [동작-소] "오늘 일정" 조회가 현재시각 기준이라 오전 시작 일정이 오후엔 사라짐:
      fetchCalendarEvents(from: Date(), …) (RealTodoCLI.swift:577) → startOfDay() 여야 함.
    · [동작-하] 고정포맷 DateFormatter에 en_US_POSIX 로케일/timeZone 미지정
      (DateHelpers.swift:34-38 isoDateFormatter). 비그레고리력 로케일에서 yyyy-MM-dd
      파싱/생성 오류 가능(Apple 공식 권고 위반). last_morning_date·--due·--date에 영향.
    · [엣지] 캘린더→할일 id 키 불일치: 이벤트는 "account_cal_ev"로 저장하나
      할일 확인/생성은 "cal_\(ev.id)" (CalendarService.swift:100 vs 118·123) →
      같은 ev.id가 여러 캘린더/계정에 있으면 할일 1개만 생성(충돌).
    · [다듬기] shouldRunMorningRoutineNow가 분 무시하고 hour만 비교(TimerService.swift:141);
      deduplicate 부분문자열 매칭이 유사 제목을 과제거 가능(TaskBreakdownService.swift:238).
    ```
  - **한계 고지:** 위는 코드 판독 결과이며 `[미실행]` — Mac에서 `swift build && swift run` 로
    실제 응답을 봐야 최종 확정. 단 [동작-상] 아침 타이머 건은 코드상 일회성이 명백해 확신도 높음.

- [O] **3. 프론트엔드와 백엔드가 적절하게 만들어져 동작합니다.**  → **충족 (구조 기준, 런타임 미검증)**
  - 평가기준: 서비스가 **직관적**이고 **의도대로 동작**합니다.
  - **근거(충족):**
    ```
    · 깔끔한 MVVM: SwiftUI View(10개) ↔ @MainActor @Observable ViewModel ↔ actor 서비스
      (TodayViewModel/SettingsViewModel이 db·서비스 호출을 loading/error 상태로 감쌈).
    · GUI(메뉴바 팝오버) + CLI(real_todo) 이중 프론트 — 같은 백엔드 공유.
    · 견고성: OAuth 콜백용 로컬 소켓 서버까지 직접 구현해 실제 로그인 흐름 완성.
    ```
  - **지적:**
    ```
    · [견고성-중] DB 초기화 실패 시 fatalError로 앱 즉시 크래시(DatabaseService.swift:20).
      마이그레이션/디스크 문제에 복구 여지 없음 — 프로덕션엔 과함.
    · UI 직관성/반응은 `[미실행]` 이라 화면으로 확인 못 함. Mac 실행 스크린샷 필요.
    ```

---

# 참고 링크 및 코드 개선

## 총평 (직언)

전반적으로 **1기 초반 과제 수준을 크게 넘는 완성도**다. 3-타깃 아키텍처, actor 동시성,
파라미터 바인딩, AI CRUD를 자기 추천으로만 한정한 방어 설계는 특히 인상적이다.
아첨 빼고 보면 **핵심 약점 세 가지**: (a) **아침 AI 루틴 타이머가 일회성**이라 다음날부터
안 도는 실동작 버그(핵심 워크플로 정지), (b) 보안을 학습목표로 내걸었는데 정작
OAuth 플로우의 state/PKCE를 빠뜨린 점, (c) 회고·README가 통째로 비어 "무엇을 배웠나"가
안 보이는 점. 코드 설계는 A인데 **"진짜 매일 돌려봤나"** 와 기록에서 감점되는 케이스.

## 우선순위 개선 제안

1. **[동작·상] 아침 루틴 타이머를 매일 반복되게 수정** ← 이번 재점검 최대 발견
   - 방법 A: `scheduleMorningRoutine` 핸들러 끝에서 자기 자신을 재예약(다음 8시 재계산).
   - 방법 B: 매 24h `repeating:`으로 예약하되, 첫 발화까지의 초기 지연만 다음 8시로 계산.
   - `runMorningRoutine` 완료 후 `scheduleMorningRoutine()` 재호출만 넣어도 즉시 해결.
2. **[보안·필수] OAuth state + PKCE 추가**
   - `buildAuthURL`에 `state`(랜덤 nonce)와 `code_challenge`(PKCE S256) 추가,
     콜백에서 `state` 일치 검증 후 code 교환. 로컬 서버는 예상 state 아니면 거부.
3. **[보안·권장] 토큰을 Keychain으로 이전**
   - access/refresh 토큰을 SQLite 평문 대신 `Security` 프레임워크(Keychain)에 저장.
4. **[동작·중] 카테고리 필터 로직 단일화**
   - `loadAllTodos`는 항상 전체를 `todos`에 담고, 필터는 `filteredTodos`(computed)만 담당.
     `toggleCategoryFilter`는 reload 없이 즉시 반영. 이중 필터 제거.
5. **[동작·하] 날짜 포맷터 로케일 고정 + "오늘 일정" 하한 수정**
   - `isoDateFormatter.locale = Locale(identifier:"en_US_POSIX")` 지정.
   - `RealTodoCLI.swift:577` `from: Date()` → `from: DateHelpers.startOfDay()`.
6. **[효율] 카테고리 N+1 → JOIN 1회**
   - `fetchAllTodos`/`fetchTodayTodos`의 per-todo SELECT를 단일 JOIN + 그룹핑으로.
7. **[기록·감점방지] 회고/README 추가**
   - 배운 점·막힌 점·해결 과정(특히 파이프 데드락·OAuth 소켓 서버 삽질)을 문서화.

## 참고 링크
- Google OAuth for Native Apps (PKCE, loopback): RFC 8252
  https://datatracker.ietf.org/doc/html/rfc8252
- OAuth 2.0 state parameter (CSRF 방어): https://datatracker.ietf.org/doc/html/rfc6749#section-10.12
