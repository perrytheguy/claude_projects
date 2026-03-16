# AIWORKS.CODE — Product Requirements Document (PRD)

## 1. 제품 개요

**제품명:** AIWORKS.CODE
**버전:** 1.0
**플랫폼:** Windows PowerShell 5.1
**목적:** Windows 환경에서 자연어 명령으로 Office 애플리케이션, 브라우저, 파일 시스템을 제어하는 로컬 AI 에이전트 CLI 도구

---

## 2. 문제 정의

Windows 업무 환경에서 반복적인 Office 작업, 브라우저 조작, 파일 처리를 수행할 때:
- 매번 수동으로 GUI를 클릭해야 하는 비효율
- 비개발자도 자동화를 사용할 수 있는 도구의 부재
- 외부 인터넷 연결 없이 로컬에서 동작하는 AI 자동화 도구의 부재

---

## 3. 목표 사용자

| 사용자 유형 | 설명 |
|------------|------|
| 사무직 직원 | 한글(HWP), Excel, Word 반복 작업 자동화 필요 |
| IT 관리자 | 시스템 명령 및 파일 관리 자동화 |
| 업무 자동화 담당자 | AI 기반 RPA 대체 솔루션 필요 |

---

## 4. 핵심 기능 요구사항

### 4.1 AI 통신 모듈
- **지원 Provider:** Claude (Anthropic), OpenAI, Custom
- **Claude API 연동:** `https://api.anthropic.com/v1/messages`
- **대화 히스토리 유지:** 최대 20턴 (메모리 관리)
- **응답 포맷:** JSON (`action`, `params`, `message`, `requires_confirmation`)
- **타임아웃:** 설정 가능 (기본 60초)

### 4.2 액션 타입

| 액션 | 설명 |
|------|------|
| `answer` | 일반 텍스트 응답 |
| `office` | Excel / Word / PowerPoint COM 제어 |
| `hwp` | 한글(HWP) COM 제어 |
| `ie` | Internet Explorer 레거시 제어 |
| `chrome` | Chrome 브라우저 제어 (Playwright/Selenium) |
| `pdf` | PDF 텍스트 추출 및 처리 |
| `shell` | PowerShell 명령 실행 |

### 4.3 안전 시스템
- **위험 키워드 감지:** `delete`, `결제`, `payment`, `drop`, `format`, `remove`, `rm`, `shutdown`
- **사용자 확인 요구:** 위험 작업 전 Y/N 프롬프트
- **위험 작업 로깅:** 타임스탬프 포함 로그 파일 저장
- **경고 메시지:** 키워드별 커스텀 경고 메시지 표시

### 4.4 CLI Config 편집기 (`/config`)
AI 연결 없이 독립적으로 동작하는 설정 관리 도구

| 명령어 | 기능 |
|--------|------|
| `/config list [섹션]` | 설정 전체 또는 섹션별 출력 |
| `/config get <키>` | 특정 키 값 조회 |
| `/config set <섹션> <키> <값>` | 키 값 변경 |
| `/config remove <섹션> <키>` | 키 삭제 |
| `/config add-program <이름> <경로>` | 프로그램 등록 |
| `/config add-warning <키워드> <메시지>` | 경고 메시지 등록 |
| `/config reload` | 설정 파일 재로드 |
| `/config help` | 도움말 출력 |

### 4.5 슬래시 명령어

| 명령어 | 기능 |
|--------|------|
| `/help` | 전체 명령어 목록 |
| `/history` | 대화 히스토리 출력 |
| `/clear` | 히스토리 초기화 |
| `/exit` | 세션 종료 |

---

## 5. 비기능 요구사항

| 항목 | 요구사항 |
|------|---------|
| **호환성** | Windows PowerShell 5.1 이상 |
| **인코딩** | UTF-8 BOM (Korean Windows CP949 환경 대응) |
| **의존성** | 외부 모듈 없음 (순수 PS 5.1 + COM) |
| **응답 시간** | AI 응답 타임아웃 60초 이내 |
| **메모리** | 대화 히스토리 최대 20개 유지 |
| **로그** | 위험 작업 전용 로그 (`aiworks.log`) |

---

## 6. 설정 파일 구조 (`AIWORKS.code.config`)

```ini
[AI]        # AI 제공자 및 API 설정
[Browser]   # ChromeDriver, Playwright, IE 경로
[Office]    # HWP 보안경로, PDF 도구, COM 초기화 지연
[Safety]    # 위험 키워드, 로그 설정
[UI]        # 프롬프트, 스피너, 컬러, 히스토리 수
[Programs]  # 이름=실행파일 경로 매핑
[Warnings]  # 키워드=경고 메시지 매핑
```

---

## 7. 제약 사항

- PowerShell 5.1: `??` 연산자 미지원 → `Coalesce()` 헬퍼 사용
- 유니코드 특수문자 미지원 → ASCII 대체 (`[+]`, `[x]`, `|/-\`)
- Claude API: user/assistant 역할 교대 규칙 준수 필수
- COM 자동화: 대상 프로그램 설치 필요 (Excel, HWP 등)

---

## 8. 향후 개선 방향 (v2.0)

- [ ] GUI 설정 에디터 (WPF 기반)
- [ ] 멀티 에이전트 태스크 분기 처리
- [ ] 작업 스케줄링 (크론 형태)
- [ ] 로컬 LLM 연동 (Ollama)
- [ ] 플러그인 시스템 (외부 .ps1 모듈 로드)
