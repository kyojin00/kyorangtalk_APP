# 교랑톡 (KyorangTalk)

> 교랑(Kyorang) 패밀리의 실시간 채팅 애플리케이션

교랑톡은 텍스트 채팅뿐 아니라 음성·영상 통화, 프로필 갤러리, 메시지 백업까지 지원하는 Flutter 기반 모바일 메신저입니다. Supabase Realtime을 백본으로 사용하며, 저사양 기기에서도 안정적으로 동작하도록 렌더링·실시간 처리를 최적화한 것이 특징입니다.

- **패키지명**: `com.kyorang.kyorang_talk`
- **플랫폼**: Android (Play Store 내부 테스트 트랙 배포 중)
- **백엔드**: Supabase (`taohtzdmqsvhbxfqfvmq`)
- **테스트 기기**: Galaxy SM-A136S (Android 14, MediaTek 저사양)

---

## 목차

1. [주요 기능](#주요-기능)
2. [기술 스택](#기술-스택)
3. [아키텍처](#아키텍처)
4. [프로젝트 구조](#프로젝트-구조)
5. [시작하기](#시작하기)
6. [환경 설정](#환경-설정)
7. [빌드 & 실행](#빌드--실행)
8. [디자인 시스템](#디자인-시스템)
9. [주요 기술 노트 / 트러블슈팅](#주요-기술-노트--트러블슈팅)
10. [로드맵](#로드맵)

---

## 주요 기능

### 채팅
- **실시간 1:1 채팅** — Supabase Realtime broadcast 채널 기반 메시지 송수신
- **채팅방 목록 실시간 갱신** — 새 메시지·읽음 상태가 목록에 즉시 반영
- **다중 이미지 전송** — 여러 장의 이미지를 한 번에 묶어 전송 (DB·Provider 계층 완료, UI 컴포넌트 작업 중)

### 음성 / 영상 통화
- **Agora 기반 음성·영상 통화** — SDK 6.5.0 사용
- **통화 알림 생명주기 관리** — 수신/응답/종료 상태에 따른 알림 정확한 처리
- **포그라운드 알림 서비스** — 통화·메시지 수신을 위한 백그라운드 상시 동작

### 프로필 & 미디어
- **프로필 사진 갤러리 시스템** — 여러 장의 프로필 사진 등록·열람
- **풀스크린 이미지 뷰어** — `InteractiveViewer` 기반 확대/축소 지원

### 안전 & 데이터 관리
- **차단 / 신고 시스템** — 사용자 차단 및 신고 기능
- **메시지 백업 v3** — 미디어 포함 `.zip` 형식으로 대화 내보내기/복원

---

## 기술 스택

### 프레임워크 & 상태관리
| 항목 | 기술 |
|------|------|
| UI 프레임워크 | Flutter |
| 상태관리 | Riverpod 3.x |
| 라우팅 | go_router |
| 로컬 저장소 | Hive CE |

### 백엔드 & 인프라
| 항목 | 기술 |
|------|------|
| 데이터베이스 / 인증 / 실시간 | Supabase (DB, Auth, Realtime, Edge Functions, Storage) |
| 푸시 알림 / 인증 | Firebase (Auth, FCM) |
| 음성·영상 통화 | Agora SDK 6.5.0 |
| 인앱 결제 | RevenueCat |

### 주요 패키지
- `flutter_foreground_task ^8.17.0` — 포그라운드 서비스
- `flutter_local_notifications ^17.2.3` — 로컬 알림
- `cached_network_image` — 이미지 캐싱
- `go_router` — 선언적 라우팅

### 모니터링
- **Sentry** — 크래시 리포팅
- **pg_cron** — DB 정리 작업 스케줄링

---

## 아키텍처

교랑톡은 **Feature-first** 구조를 기반으로 하며, Riverpod을 통한 단방향 데이터 흐름을 따릅니다.

```
UI (Widgets)
   │  ref.watch / ref.read
   ▼
Provider (Riverpod 3.x)
   │  비즈니스 로직 / 상태 관리
   ▼
Repository / Service
   │  데이터 접근 추상화
   ▼
Supabase / Firebase / Agora / Hive
```

### 실시간 처리 전략
RLS 환경에서 필터 없는 `postgres_changes` 구독은 동작하지 않으므로, **broadcast 채널**을 사용하여 목록 갱신과 알림을 처리합니다. 이는 RLS 정책과 충돌 없이 안정적인 실시간 동기화를 보장합니다.

### RLS 순환 참조 해결
채팅방 멤버십·사진 열람 권한 등에서 발생하는 RLS 순환 참조는 `SECURITY DEFINER` 헬퍼 함수로 분리합니다.

- `is_room_member()` — 채팅방 멤버 여부 확인
- `is_photo_viewer()` — 사진 열람 권한 확인

---

## 프로젝트 구조

```
kyorang_talk/
├── android/                  # Android 네이티브 설정 (google-services.json 등)
├── lib/
│   ├── main.dart             # 앱 진입점 (Firebase 초기화 포함)
│   ├── core/
│   │   ├── theme/            # AppTheme (디자인 토큰)
│   │   ├── router/           # go_router 설정
│   │   └── services/         # 포그라운드 알림, 백업 등 공통 서비스
│   ├── features/
│   │   ├── chat/             # 채팅방, 메시지, 다중 이미지 전송
│   │   ├── call/             # Agora 음성·영상 통화
│   │   ├── profile/          # 프로필 / 갤러리 (my_profile_screen.dart)
│   │   ├── auth/             # 로그인 / 회원가입
│   │   └── block_report/     # 차단 / 신고
│   └── shared/
│       └── widgets/          # 재사용 위젯
├── assets/
├── pubspec.yaml
└── README.md
```

---

## 시작하기

### 사전 요구사항
- Flutter SDK (stable 채널 권장)
- Android SDK / Android Studio
- Supabase 프로젝트 접근 권한
- Firebase 프로젝트 접근 권한
- Agora 앱 ID

### 설치
```bash
# 1. 의존성 설치
flutter pub get

# 2. 코드 생성 (Riverpod / Hive 등)
dart run build_runner build --delete-conflicting-outputs
```

---

## 환경 설정

### 1. Supabase
- 프로젝트 ref: `taohtzdmqsvhbxfqfvmq`
- URL: `https://taohtzdmqsvhbxfqfvmq.supabase.co`
- **anon key** 등 민감 정보는 코드에 직접 넣지 말고 환경 변수 또는 `--dart-define`으로 주입

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://taohtzdmqsvhbxfqfvmq.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<your-anon-key>
```

### 2. Firebase
- Android: `android/app/google-services.json` 배치
- FCM(푸시 알림) 및 Firebase Auth 사용
- ⚠️ Android는 네이티브 설정 파일을 자동으로 읽지만, 웹 빌드 시에는 `DefaultFirebaseOptions.currentPlatform`을 `Firebase.initializeApp()`에 명시적으로 전달해야 함

### 3. Agora
- Agora App ID 및 토큰 서버 설정 필요
- SDK 버전: 6.5.0

---

## 빌드 & 실행

### 디버그 실행
```bash
flutter run
```

### 릴리스 빌드 (App Bundle)
```bash
flutter build appbundle --release
```

### 로그 확인 (logcat)
대상 앱의 PID에 한정하여 Flutter 태그 로그만 필터링합니다.

```powershell
# adb 전체 경로 사용 (PowerShell 환경)
$adb = "C:\Users\Administrator\AppData\Local\Android\Sdk\platform-tools\adb.exe"
& $adb logcat --pid (& $adb shell pidof com.kyorang.kyorang_talk) *:V | Select-String "flutter"
```

---

## 디자인 시스템

다크 퍼플 테마를 기반으로 하며, 모든 색상은 `AppTheme`를 통해 관리합니다. **하드코딩된 색상값은 사용하지 않습니다.**

| 항목 | 값 |
|------|-----|
| 기본 배경 | `#060610` |
| 보조 배경 | `#080810` |
| 액센트 | `#7c3aed` |

- UI에서 이모지는 최소한으로 사용
- 아이콘은 가급적 PNG 에셋 사용

---

## 주요 기술 노트 / 트러블슈팅

프로젝트 진행 중 축적된 핵심 교훈입니다.

### BackdropFilter는 삼성/MediaTek 기기에서 위험
Impeller를 비활성화해도, 여러 개의 `BackdropFilter(ImageFilter.blur(...))`가 동시에 렌더링되면 GPU 렌더 행(hang)이 발생합니다. 반투명 `Material`로 대체하세요. (릴리스 빌드 안정화 과정에서 실제 제거 완료)

### Supabase Realtime
- RLS 하에서 **필터 없는 `postgres_changes` 구독은 실패** → broadcast 채널 사용
- 무료 티어 프로젝트는 자동 일시정지됨 → OAuth/쿼리가 갑자기 502·CORS 에러를 내면 프로젝트 상태부터 확인

### RLS 순환 참조
`SECURITY DEFINER` 헬퍼 함수로 분리 (`is_room_member()`, `is_photo_viewer()`)

### 풀스크린 이미지
`InteractiveViewer` 내부에서는 `Center` 래퍼 대신 **`SizedBox.expand` + `BoxFit.contain`** 조합이 올바른 패턴

### 진단 우선 원칙
코드를 작성하기 전에 `[A]`–`[G]` 스타일의 print 로깅, 최소 빌드, 순차적 제거(sequential elimination)로 근본 원인을 먼저 격리합니다.

---

## 로드맵

### 진행 중 / 예정
- [ ] **다중 이미지 UI 컴포넌트**
  - 미리보기 시트 (preview sheet)
  - 업로드 진행률 표시
  - 이미지 그리드 버블
  - 풀스크린 뷰어
  - 채팅방 화면 통합
- [ ] **보이스룸 차단 필터링** — Agora UID 매핑을 통해 차단한 사용자의 오디오 음소거

### 완료
- [x] 통화 알림 생명주기 관리
- [x] Agora error -17 수정
- [x] 채팅방 목록 실시간 갱신
- [x] 프로필 사진 갤러리 시스템
- [x] 포그라운드 알림 서비스
- [x] 차단 / 신고 시스템
- [x] 메시지 백업 v3 (미디어 포함 `.zip`)
- [x] 다중 이미지 전송 (DB + Provider 계층)
- [x] 릴리스 빌드 안정화 (BackdropFilter 제거, CachedNetworkImage, `my_profile_screen` 리팩터링)

---

## 교랑 패밀리

교랑톡은 교랑 패밀리 생태계의 일부입니다.

| 앱 | 설명 |
|-----|------|
| **교랑톡** | 실시간 채팅 앱 (본 프로젝트) |
| 교랑빌리지 | 커뮤니티 플랫폼 앱 |
| 교랑무드 | 감정 웰니스/다이어리 앱 |
| 교랑 스토리 | 익명 감정 SNS (web) |
| 교랑샵 | 굿즈 샵 (web) |
| 교랑AI | AI 상담 플랫폼 (web) |

---

## 라이선스 / 문의

- GitHub: [`kyojin00`](https://github.com/kyojin00)
- 본 프로젝트는 교랑 패밀리 전용 비공개 프로젝트입니다.