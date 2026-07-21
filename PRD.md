# RealTodo — macOS Menu Bar Todo App PRD

## 1. Overview

macOS 상태바(메뉴바)에 상주하는 네이티브 할일 관리 앱. 클릭 시 반투명 팝오버로 할일 목록을 보여주고, Google Calendar 연동 + AI(`agy` CLI)를 통해 오늘 해야 할 일을 자동 산정.

**핵심 워크플로우:**
```
[아침] AI가 캘린더+전체할일 분석 → 오늘 후보 할일 제안 (대기 상태)
  → 사용자가 우선순위 선택 → "오늘의 할일"로 승격
  → 작업 진행 중 30분 주기로 AI가 세부 태스크 업데이트
```

---

## 2. Core Requirements

### 2.1 Menu Bar 상주
- macOS 상태바에 아이콘 상주 (SF Symbols `checklist` 또는 커스텀)
- 클릭 → 반투명 흰색 팝오버(Popover) 표시
- 팝오버 바깥 클릭 시 자동 닫힘
- 앱 실행 시 Dock 아이콘 숨김 (LSUIElement = YES) → 메뉴바에만 존재

### 2.2 팝오버 UI

#### 2.2.1 메인 탭 구조
팝오버 상단에 2개 메인 탭:

| 탭 | 설명 |
|----|------|
| **오늘의 할일** | 오늘 작업할 항목. 사용자가 직접 승격한 항목 + 수동 추가 |
| **전체 할일** | 모든 할일. AI 추천(대기), 장기 할일, 완료 항목 포함 |

#### 2.2.2 공통 UI 요소
- 반투명 배경 (NSVisualEffectView, material: `.hudWindow`, blendingMode: `.behindWindow`)
- 창 모서리 둥글게 (rounded corners)
- 카테고리 필터 탭 (전체 / 업무 / 개인 / 커스텀...) — 다중 선택 가능
- 각 할일 항목:
  - 체크박스 (완료 토글)
  - 제목 텍스트 (클릭 시 편집 가능)
  - **카테고리 컬러 도트들** (복수 개 표시)
  - 출처 아이콘 (수동 입력 vs 캘린더 vs AI 추천)
  - 상태 뱃지: `대기` (AI 추천, 노란색) / `오늘` (파란색) / `완료` (회색)
  - 하위 태스크 접기/펼치기 (있다면)
  - 우클릭 컨텍스트 메뉴: 편집 / 삭제 / 복사 / 완료 / **"오늘로 이동"** / **"전체로 이동"**

#### 2.2.3 하단 입력 영역
- 빠른 추가 입력 필드 (+ 버튼)
- 카테고리 다중 선택 드롭다운

### 2.3 카테고리 시스템 (다중 지정)

- 기본 카테고리: **업무** 🔵, **개인** 🟢
- 사용자 정의 카테고리 추가 가능 (이름 + 색상 선택)
- **각 할일은 0개 이상의 카테고리에 속할 수 있음** (N:M 관계)
- 카테고리별 필터링: 다중 선택 → OR 조건 (업무 OR 개인 선택 시 둘 다 표시)
- 필터 미선택 시 전체 표시

### 2.4 할일 상태 시스템

```
                  ┌──────────────┐
     [수동 추가]──▶│   전체 할일   │◀──[AI 추천(대기)]
                  └──────┬───────┘
                         │ 사용자가 "오늘로 이동" 선택
                         ▼
                  ┌──────────────┐
                  │  오늘의 할일   │──▶ [체크 완료]
                  └──────────────┘
```

할일 상태 (`status`):
| 상태 | 설명 | UI |
|------|------|-----|
| `pending` | AI 추천, 아직 수락 안 함 | 노란색 뱃지 "대기", 전체 탭에만 |
| `scheduled` | 사용자가 수락/승격 → 오늘 작업 예정 | 파란색 뱃지, 양쪽 탭에 |
| `in_progress` | 작업 중 | 진행 표시줄 |
| `completed` | 완료 | 회색 취소선, 하단으로 |

### 2.5 할일 데이터 모델

```
Todo {
  id: UUID
  title: String
  description: String?
  categories: [Category]         // N:M — 다중 카테고리
  status: TodoStatus             // pending | scheduled | in_progress | completed
  priority: Priority?            // high | medium | low
  source: Source                 // .manual | .calendar(eventId) | .aiSuggested
  parentEventId: String?         // 원본 캘린더 이벤트 ID
  parentTodoId: String?          // 상위 할일 ID (세부 태스크인 경우)
  subtasks: [Todo]?              // 하위 세부 태스크들
  dueDate: Date?
  scheduledDate: Date?           // "오늘"로 지정된 날짜
  completedAt: Date?
  createdAt: Date
  updatedAt: Date
}
```

---

## 3. Google Calendar 연동

### 3.1 인증
- Google Calendar API v3 사용
- OAuth2 인증 (기존 `~/.config/mcp-google/credentials.json` 활용)
- 최초 실행 시 브라우저로 인증 플로우 → 토큰 로컬 저장
- 토큰 만료 시 자동 갱신

### 3.2 캘린더 수동 연동
- 설정 화면에서 Google 계정의 **캘린더 목록**을 불러옴
- 사용자가 **각 캘린더를 "업무" 또는 "개인" 카테고리에 직접 매핑**
  - 예: "company@work.com" 캘린더 → 업무 / "family@gmail.com" → 개인
- 매핑하지 않은 캘린더는 수집하지 않음
- 매핑은 언제든 변경 가능

### 3.3 캘린더 읽기 (읽기 전용)
- 매핑된 캘린더에서 오늘 ± 7일 범위의 이벤트 수집
- 각 이벤트: 제목, 시작/종료시간, 캘린더명, 설명
- 캘린더 매핑 기반으로 자동 카테고리 태그 부여

### 3.4 이벤트 → 할일 변환
- **이벤트 자체**도 할일로 자동 등록 (`source: .calendar`)
- **AI가 이벤트 기반으로 세부 할일도 추가 생성** (→ 4.2 참조)
- 원본 이벤트와 생성된 할일 간 연결 (`parentEventId`)

---

## 4. AI 할일 산정 (agy CLI)

### 4.1 두 가지 AI 실행 모드

#### 모드 A: 아침 루틴 (하루 시작 시 1회)
```
트리거: 앱 첫 실행 시 OR 매일 오전 설정 시간 (기본 08:00)

입력:
  - 오늘 + 향후 7일 캘린더 일정
  - 전체 할일 목록 (미완료)
  - 어제 완료한 할일

agy 프롬프트:
  "오늘 날짜: {today}
   캘린더 일정: {events_json}
   전체 할일 목록: {todos_json}
   
   위 정보를 분석해서:
   1. 각 큰 일정/할일을 실행 가능한 소규모 태스크로 분해
   2. 오늘 추천할 할일 목록을 우선순위와 함께 제안
   3. 각 추천의 이유를 간단히 설명
   
   JSON 형식으로 출력:
   [{
     \"title\": \"소규모 태스크 제목\",
     \"categories\": [\"work\"|\"personal\", ...],
     \"parent_event_id\": \"...\" 또는 null,
     \"parent_todo_id\": \"...\" 또는 null,
     \"reason\": \"추천 이유\",
     \"priority\": \"high\"|\"medium\"|\"low\"
   }]"

결과:
  → 모두 status=pending(대기)으로 저장
  → 시스템 알림: "오늘 추천 할일 N개가 준비되었습니다"
  → 사용자가 팝오버 열면 "대기" 탭에서 확인 후 수락/거절
```

#### 모드 B: 30분 주기 업데이트
```
트리거: 30분 타이머 (설정 변경 가능)

입력:
  - 현재 시간 기준 남은 캘린더 일정
  - "오늘의 할일" 중 미완료 항목
  - 새로 수집된 캘린더 변경사항

agy 프롬프트:
  "현재 시간: {now}
   남은 일정: {remaining_events}
   진행 중 할일: {active_todos}
   
   상황을 분석해서:
   1. 남은 일정에 필요한 준비 태스크가 있으면 추가
   2. 진행 중 할일의 하위 태스크를 더 세분화할 것이 있으면 제안
   3. 긴급히 처리해야 할 항목이 있으면 우선순위 상향 제안
   
   동일 JSON 형식."

결과:
  → 마찬가지로 status=pending(대기)으로 저장
  → 변경/추가 건이 있으면 시스템 알림 + 뱃지 업데이트
```

### 4.2 할일 분해 (Task Breakdown)

큰 작업을 소규모 태스크로 자동 분해하는 기능:
- **자동 분해**: AI가 아침 루틴에서 큰 할일 감지 시 자동으로 하위 태스크 생성
- **수동 분해**: 사용자가 할일 우클릭 → "태스크 분해" → agy 호출 → 하위 태스크 제안
- 분해된 하위 태스크는 `parentTodoId`로 원본에 연결
- 접기/펼치기 UI로 하위 태스크 표시
- 하위 태스크 개별 완료 가능, 진행률 프로그레스바 표시

예시:
```
📋 프로젝트A 미팅 (14:00-15:00)          [오늘] [업무]
  ├─ ✅ 참석자 확인                        [완료]
  ├─ ☐ 안건 정리                          [대기]
  └─ ☐ 발표 자료 준비                      [대기]
```

### 4.3 사용자 수락/거절 워크플로우

"전체 할일" 탭에서 AI 추천 항목(`status=pending`):
- 각 항목 우측에 **[수락 ▶ 오늘]** / **[거절 ✕]** 버튼
- 수락 → `status = scheduled`, `scheduledDate = today` → "오늘의 할일" 탭으로 이동
- 거절 → 항목 삭제 (또는 `status = dismissed` 로 숨김)
- 일괄 수락/거절 버튼 (상단)

### 4.4 agy CLI 호출 사양
- 명령어: `agy --print "{prompt}"`
- 타임아웃: 60초 (설정 가능)
- 백그라운드 스레드에서 실행 (UI 블로킹 방지)
- 실패 시 재시도 1회 → 그래도 실패하면 로깅 후 스킵
- 응답 파싱: JSON 추출 → Todo 모델 배열로 변환 → DB 저장

### 4.5 알림
- macOS 시스템 알림 (UserNotifications framework)
  - 아침 루틴 완료: "오늘 추천 할일 N개가 준비되었습니다. 확인해보세요."
  - 30분 업데이트: "새로운 제안 M개가 있습니다."
- 메뉴바 아이콘에 **대기 중 할일 개수** 뱃지 (노란색, 있을 때만)

### 4.6 타이머 설정
- 아침 루틴: 매일 설정 시간 (기본 08:00, 변경 가능)
- 30분 주기 타이머: 기본 30분 (15분 / 30분 / 1시간 / 수동 선택)
- 앱 시작 시 아침 루틴 즉시 실행 (오늘 아직 안 했으면)

---

## 5. CLI 인터페이스 (`real_todo`)

GUI 앱과 **동일한 SQLite DB + Service 레이어**를 공유하는 커맨드라인 툴.
터미널에서 빠르게 할일을 조회/추가/관리할 수 있으며, 다른 CLI 도구(agy 등)와 파이프라인 연동도 가능.

### 5.1 아키텍처

```
┌─────────────────────────────────────┐
│         Shared Service Layer         │
│  DatabaseService / CalendarService   │
│  AIService / TaskBreakdownService    │
├──────────────┬──────────────────────┤
│   GUI App    │   CLI (real_todo)     │
│  (SwiftUI)   │  (ArgumentParser)     │
└──────────────┴──────────────────────┘
         ↕ 같은 SQLite DB ↕
```

- CLI는 GUI 앱의 타겟에 포함된 Service 레이어를 Framework로 분리하여 공유
- 또는 CLI를 독립 실행 파일로 빌드 → 같은 DB 경로 참조
- Swift ArgumentParser 사용

### 5.2 명령어 사양

```bash
# ── 조회 ──

# 오늘의 할일 목록
real_todo today
real_todo today --category work
real_todo today --status pending
real_todo today --format json          # JSON 출력 (파이프라인용)
real_todo today --format table         # 테이블 출력 (기본값)

# 전체 할일 목록
real_todo list
real_todo list --category work,personal  # 다중 카테고리 필터 (OR)
real_todo list --status scheduled
real_todo list --source ai_suggested
real_todo list --date 2026-06-08

# 단일 할일 상세
real_todo show <id>
real_todo show <id> --with-subtasks    # 하위 태스크 포함

# ── 추가 ──

# 기본 추가 (기본: 오늘의 할일, scheduled 상태)
real_todo add "프레젠테이션 자료 준비"
real_todo add "팀 미팅" --category work
real_todo add "운동하기" --category work,personal   # 다중 카테고리
real_todo add "장기 프로젝트" --status pending       # 전체 할일에만
real_todo add "긴급 버그 수정" --priority high
real_todo add "문서 검토" --due 2026-06-10

# 파이프 입력 지원
echo "할일 제목" | real_todo add -
cat tasks.txt | real_todo add --batch  # 한 줄씩 여러 항목 추가

# ── 수정 ──

real_todo edit <id> --title "새 제목"
real_todo edit <id> --category work,personal
real_todo edit <id> --priority high
real_todo edit <id> --due 2026-06-15

# ── 상태 변경 ──

real_todo done <id>                    # 완료 처리
real_todo done <id1> <id2> <id3>       # 다중 완료
real_todo schedule <id>                # → 오늘의 할일로 승격
real_todo schedule <id> --date 2026-06-10  # 특정 날짜로
real_todo unschedule <id>              # → 전체 할일로
real_todo dismiss <id>                 # AI 추천 거절

# ── 삭제 ──

real_todo delete <id>
real_todo delete <id> --force          # 확인 없이

# ── AI 기능 ──

real_todo analyze                      # 아침 루틴 수동 실행
real_todo analyze --full               # 전체 재분석
real_todo breakdown <id>               # 특정 할일을 하위 태스크로 분해
real_todo breakdown <id> --accept-all  # 분해 결과 자동 수락
real_todo suggestions                  # 대기 중 AI 추천 목록
real_todo suggestions --accept <id>    # 특정 추천 수락
real_todo suggestions --accept-all     # 전체 수락
real_todo suggestions --reject <id>    # 특정 추천 거절
real_todo suggestions --reject-all     # 전체 거절

# ── 캘린더 ──

real_todo calendar sync                # Google Calendar 수동 동기화
real_todo calendar list                # 연동된 캘린더 목록
real_todo calendar map <calendar_id> --category work  # 캘린더↔카테고리 매핑
real_todo calendar unmap <calendar_id> # 매핑 해제
real_todo calendar events              # 오늘 캘린더 이벤트

# ── 카테고리 ──

real_todo category list                # 카테고리 목록
real_todo category add "사이드프로젝트" --color "#F59E0B"
real_todo category delete <id>

# ── 통계 ──

real_todo stats                        # 오늘/이번주 완료율 등
real_todo stats --format json

# ── 설정 ──

real_todo config get <key>
real_todo config set <key> <value>
real_todo config list                  # 전체 설정
```

### 5.3 출력 포맷

기본: 터미널 친화적 테이블
```
$ real_todo today

오늘의 할일 (2026-06-08) — 5건

  ☐ 1. 프로젝트A 미팅 자료 준비          [업무] 🔵    high
  ☐ 2. 코드 리뷰                         [업무] 🔵    medium
  ☐ 3. 팀 스탠드업                        [업무] 🔵    low
  ☐ 4. 운동하기                          [개인] 🟢    medium
  ✅ 5. 아침 스탠드업 참석                [업무] 🔵    —

  진행률: 1/5 (20%)
```

`--format json`:
```json
{
  "date": "2026-06-08",
  "todos": [
    {
      "id": "abc-123",
      "title": "프로젝트A 미팅 자료 준비",
      "categories": ["work"],
      "status": "scheduled",
      "priority": "high",
      "source": "ai_suggested",
      "subtasks": [
        {"id": "def-456", "title": "발표 자료 작성", "status": "pending"},
        {"id": "ghi-789", "title": "참석자 확인", "status": "completed"}
      ]
    }
  ],
  "stats": {"total": 5, "completed": 1}
}
```

### 5.4 CLI와 GUI 동시 사용
- GUI 앱이 실행 중이어도 CLI 사용 가능 (같은 DB 접근)
- SQLite WAL 모드로 동시 읽기/쓰기 지원
- CLI에서 변경 시 → DB 업데이트 → GUI는 다음 폴링 주기에 반영
- GUI에서 변경 시 → CLI가 즉시 반영 (같은 DB 읽기)

### 5.5 설치 및 경로
- CLI 바이너리: `/usr/local/bin/real_todo` (심볼릭 링크) 또는 `~/.local/bin/real_todo`
- GUI 앱 번들 내부에 CLI 포함 → 설치 스크립트로 심볼릭 링크 생성
- 또는 `make install-cli` 로 별도 설치
- DB 경로: `~/Library/Application Support/RealTodo/realtodo.db` (GUI/CLI 공통)

---

## 6. 사용자 인터랙션 (GUI)

### 6.1 할일 추가
- 하단 입력 필드에 직접 타이핑 + Enter
- 카테고리 다중 선택 (기본: 현재 필터된 카테고리)
- 추가 위치: 현재 탭 ("오늘" 탭이면 scheduled, "전체" 탭이면 pending)
- AI 추천 항목은 수락/거절 버튼으로 관리

### 6.2 할일 관리
- 체크박스로 완료 토글
- 완료된 항목: 회색 취소선, 하단으로 정렬
- 드래그앤드롭으로 순서 변경 (오늘 탭 내에서)
- 우클릭 컨텍스트 메뉴:
  - 편집 (제목, 카테고리, 우선순위)
  - 삭제
  - 복사 (제목 클립보드)
  - 완료 처리
  - **"오늘로 이동"** (전체 탭 → 오늘 탭)
  - **"전체로 이동"** (오늘 탭 → 전체 탭, scheduledDate 제거)
  - **"태스크 분해"** (agy로 하위 태스크 생성)

### 6.3 글로벌 단축키
- **`⌥⌘⇧T`** (Option + Command + Shift + T): 팝오버 토글
- **`⌥⌘⇧N`** (Option + Command + Shift + N): 새 할일 빠른 추가 다이얼로그
- 단축키 충돌 방지: 모든 단축키에 Option 포함
- 설정에서 단축키 변경 가능

---

## 7. 데이터 영속성

### 7.1 SQLite (로컬)
- 경로: `~/Library/Application Support/RealTodo/realtodo.db`
- 라이브러리: GRDB.swift
- 마이그레이션: GRDB 마이그레이션으로 스키마 버전 관리

### 7.2 스키마

```sql
-- 카테고리
CREATE TABLE categories (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  color TEXT NOT NULL,          -- hex color "#RRGGBB"
  sort_order INTEGER DEFAULT 0,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 할일
CREATE TABLE todos (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  description TEXT,
  status TEXT NOT NULL DEFAULT 'pending',
    -- pending | scheduled | in_progress | completed | dismissed
  priority TEXT,
    -- high | medium | low | NULL
  source TEXT NOT NULL DEFAULT 'manual',
    -- manual | calendar | ai_suggested
  parent_event_id TEXT,         -- 원본 캘린더 이벤트
  parent_todo_id TEXT,          -- 상위 할일 (세부 태스크)
  calendar_id TEXT,             -- 출처 캘린더
  due_date DATETIME,
  scheduled_date DATE,          -- "오늘"로 지정된 날짜
  completed_at DATETIME,
  sort_order INTEGER DEFAULT 0,
  ai_reason TEXT,               -- AI 추천 이유
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 할일-카테고리 N:M (다중 지정)
CREATE TABLE todo_categories (
  todo_id TEXT NOT NULL REFERENCES todos(id) ON DELETE CASCADE,
  category_id TEXT NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
  PRIMARY KEY (todo_id, category_id)
);

-- 캘린더 이벤트 캐시
CREATE TABLE calendar_events (
  id TEXT PRIMARY KEY,
  calendar_id TEXT NOT NULL,
  calendar_name TEXT,
  title TEXT,
  start_time DATETIME,
  end_time DATETIME,
  description TEXT,
  synced_at DATETIME
);

-- 캘린더-카테고리 매핑 (사용자 직접 지정)
CREATE TABLE calendar_mappings (
  calendar_id TEXT PRIMARY KEY,
  calendar_name TEXT NOT NULL,
  category_id TEXT NOT NULL REFERENCES categories(id)
);

-- 설정
CREATE TABLE settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

-- 인덱스
CREATE INDEX idx_todos_status ON todos(status);
CREATE INDEX idx_todos_scheduled_date ON todos(scheduled_date);
CREATE INDEX idx_todos_parent_todo ON todos(parent_todo_id);
CREATE INDEX idx_todos_parent_event ON todos(parent_event_id);
CREATE INDEX idx_todo_categories_todo ON todo_categories(todo_id);
CREATE INDEX idx_todo_categories_category ON todo_categories(category_id);
```

### 7.3 기본 데이터
```sql
INSERT INTO categories (id, name, color, sort_order) VALUES
  ('work', '업무', '#3B82F6', 0),
  ('personal', '개인', '#22C55E', 1);
```

---

## 8. 기술 스택

| Layer | Technology |
|-------|-----------|
| Language | Swift 6.2 |
| UI Framework | SwiftUI (macOS 14+) |
| Menu Bar | `MenuBarExtra` (SwiftUI) |
| Popover | `NSPopover` + `NSVisualEffectView` |
| Database | SQLite via GRDB.swift (WAL 모드) |
| Calendar API | Google Calendar API v3 (REST, URLSession) |
| Auth | OAuth2 (ASWebAuthenticationSession + GTMAppAuth) |
| AI | `agy` CLI (`--print` 모드, Process) |
| Notifications | UserNotifications.framework |
| Shortcuts | MASShortcut (GitHub) |
| CLI | Swift ArgumentParser |
| Min macOS | macOS 14.0 (Sonoma) |
| Architecture | MVVM + Services (GUI/CLI 공유) |

---

## 9. 프로젝트 구조

```
RealTodo/
├── App/                            # GUI 앱 타겟
│   ├── RealTodoApp.swift           # App entry, MenuBarExtra, LSUIElement
│   └── AppDelegate.swift
├── CLI/                            # CLI 타겟 (real_todo)
│   └── RealTodoCLI.swift           # ArgumentParser 메인
├── Shared/                         # GUI + CLI 공유 레이어
│   ├── Views/
│   │   ├── PopoverContainerView.swift
│   │   ├── TodayTodoView.swift
│   │   ├── AllTodoView.swift
│   │   ├── TodoRowView.swift
│   │   ├── SubtaskView.swift
│   │   ├── AddTodoView.swift
│   │   ├── CategoryFilterView.swift
│   │   ├── AISuggestionView.swift
│   │   └── SettingsView.swift
│   ├── Models/
│   │   ├── Todo.swift
│   │   ├── Category.swift
│   │   ├── CalendarEvent.swift
│   │   └── AISuggestion.swift
│   ├── ViewModels/
│   │   ├── TodoListViewModel.swift
│   │   ├── TodayViewModel.swift
│   │   └── SettingsViewModel.swift
│   ├── Services/
│   │   ├── DatabaseService.swift   # GRDB SQLite CRUD (WAL 모드)
│   │   ├── CalendarService.swift   # Google Calendar API
│   │   ├── AuthService.swift       # OAuth2
│   │   ├── AIService.swift         # agy CLI 호출
│   │   ├── TaskBreakdownService.swift
│   │   ├── NotificationService.swift
│   │   └── TimerService.swift
│   └── Helpers/
│       ├── HotkeyManager.swift
│       ├── Constants.swift
│       ├── DateHelpers.swift
│       └── OutputFormatter.swift   # CLI 테이블/JSON 포매터
├── Resources/
│   └── Assets.xcassets
└── Package.swift                    # SPM (GRDB, ArgumentParser, MASShortcut)
```

---

## 10. Milestones

### Phase 1 — 기본 메뉴바 앱 + CLI (MVP)
- [ ] Xcode 프로젝트 + SPM 설정 (GRDB, ArgumentParser)
- [ ] Shared Service 레이어 구조 설계
- [ ] GRDB SQLite 설정 + 마이그레이션 + WAL 모드
- [ ] MenuBarExtra + NSPopover 반투명 UI
- [ ] 할일 CRUD (추가/완료/삭제/편집)
- [ ] 카테고리 다중 지정 + 필터
- [ ] "오늘의 할일" / "전체 할일" 탭 분리
- [ ] CLI 기본 명령어: `add`, `list`, `today`, `done`, `delete`, `show`

### Phase 2 — 카테고리 + UX 고도화
- [ ] 커스텀 카테고리 추가/편집/삭제
- [ ] 할일 복사 (클립보드)
- [ ] 컨텍스트 메뉴 (편집/삭제/복사/이동/분해)
- [ ] 드래그앤드롭 순서 변경
- [ ] 글로벌 단축키 (⌥⌘⇧T, ⌥⌘⇧N)
- [ ] CLI: `edit`, `schedule`, `unschedule`, `stats`, `category` 명령어

### Phase 3 — Google Calendar 연동
- [ ] OAuth2 인증 플로우 (ASWebAuthenticationSession)
- [ ] 캘린더 목록 조회 → 설정 화면에서 매핑
- [ ] 이벤트 수집 + 캐시 저장
- [ ] 이벤트 → 할일 자동 등록 (카테고리 자동 태그)
- [ ] CLI: `calendar sync/list/map/events` 명령어

### Phase 4 — AI 자동 산정
- [ ] agy CLI 연동 서비스 (Process + JSON 파싱)
- [ ] 아침 루틴: 전체 일정 분석 → 대기 상태 할일 생성
- [ ] 할일 분해: 큰 작업 → 소규모 태스크
- [ ] AI 추천 수락/거절 UI
- [ ] 30분 주기 업데이트 타이머
- [ ] 시스템 알림 + 뱃지 카운트
- [ ] CLI: `analyze`, `breakdown`, `suggestions` 명령어

### Phase 5 — 폴리싱
- [ ] 애니메이션 (항목 추가/제거/상태 변경)
- [ ] 설정 창 완성 (알림 시간, 간격, 캘린더, 단축키)
- [ ] Launch at Login (SMAppService)
- [ ] 앱 아이콘 (커스텀)
- [ ] 다크 모드 대응
- [ ] CLI 설치 스크립트 (`make install-cli`)
- [ ] `--format json` 파이프라인 출력 안정화

---

## 10. Non-Goals (v1 제외)
- iOS/iPadOS 지원
- 할일 공동 편집
- 클라우드 동기화
- 서드파티 캘린더 (Apple Calendar은 v2 고려)
- 타임트래킹 기능
- 할일 반복 설정
