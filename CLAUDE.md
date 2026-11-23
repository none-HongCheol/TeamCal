# Plait (플레잇) — 작업 안내

Windows 데스크톱 캘린더 위젯. PowerShell 5.1 + WinForms + WebView2.
위젯 화면(HTML/JS)은 각 `.ps1` 안에 문자열로 들어 있고, 호스트(PowerShell)와 `host({cmd})` 메시지로 주고받는다.
홈페이지: https://none-hongcheol.github.io/TeamCal/ (GitHub Pages, 이 저장소의 루트)

## 작업 규칙 (사용자와 합의)
- 답은 한국어로.
- UI를 바꿀 때는 목업 이미지를 먼저 보여 주고, 확인받은 뒤 만든다.
- 사용자가 요청하지 않은 파일이나 매뉴얼은 보내지 않는다. 목업 이미지는 괜찮다.
- **GitHub에 올리기 전에는 매번 "올릴까요?"라고 묻는다.** "바로 올려", "진행하고 업로드해"는 그 버전 한 번에만 해당한다.
- 새 버전을 올릴 때는 `version.json`의 version과 notes, 스크립트 안의 `$AppVersion`, 홈페이지 `index.html`의 업데이트 노트(`#updates`)를 함께 고친다.

## 보안 (꼭 지킬 것)
- `google_client.json`과 client_secret은 GitHub에 절대 올리지 않는다. 예외는 사용자가 직접 만든 설치 exe(`external/Plait_setup.exe`)뿐이다.
- Supabase의 secret 키나 service_role 키는 묻지도, 받지도 않는다. 위젯에는 anon 키만 들어간다.
- 사용자의 비밀번호는 대신 입력하지 않는다.
- 네이버 아이디와 앱 비밀번호는 PC에만 DPAPI로 암호화해 `naver.dat`에 저장하고, 서버로 보내지 않는다.
- Microsoft(Outlook) 앱을 등록할 때는 client secret을 만들지 않게 안내한다.

## 폴더와 판(edition)
| 폴더 | 판 | 버전 | 설치 폴더(AppData) | 비고 |
|---|---|---|---|---|
| `external/` | **Plait (외부용, 메인)** | 2.0.0 | `TeamCalExternal` | 베타 0.4.4 기능을 모두 옮겨 온 판 |
| `beta/` | TeamCal Beta | 0.4.4 | `TeamCalBeta` | 새 기능을 먼저 시험하는 판 |
| `widget/` | 사내용 TeamCal | 2.1.1 | `TeamLeaveWidget` | Plait과 따로 관리 |

- **Plait은 내부 식별자를 일부러 예전 이름 그대로 둔다.** 그래야 기존 사용자의 설정·로그인·자동 업데이트가 유지된다. 바꾸지 말아야 할 것:
  - 파일 이름 `TeamCalExternal.ps1`
  - AppData 폴더 `TeamCalExternal`
  - AppId `TeamCal.External`
  - 뮤텍스 `Local\TeamCalExternal`
  - 업데이트 주소 `.../TeamCal/external/version.json`
  - `MIR_PRE` 값과 PRODID
- 화면에 보이는 이름만 Plait이다. `$AppName = 'Plait'`이고, `$OldNames`에는 `'TEAM CAL(외부용)'`이 들어 있다. 업데이트하면 옛 바로가기를 지우고 새로 만든다.
- 앱 아이콘은 스크립트 안에 base64로 들어 있다(`$AppIconIco`, `$AppIconPng`). `make_exe.ps1`도 이 값을 읽어서 exe 아이콘으로 쓴다.
- 기능을 켜고 끄는 플래그는 위젯 JS의 `EDITION`이다. 외부판 Plait도 `EDITION="beta"` 코드 경로를 그대로 쓴다(`EXT`, `BETA` 모두 true).
- 베타에서 외부판으로 옮길 때는 `beta/TeamCalBeta.ps1`을 복사한 뒤 위 식별자와 이름, 아이콘, 버전, 업데이트 주소만 바꾼다.

## 설치 배포
- `external/Plait_setup.zip`에는 `TeamCalExternal.ps1`, `Plait 설치.cmd`, `exe 만들기.cmd`, `make_exe.ps1`, 안내 txt가 들어 있다. 스크립트를 고치면 zip도 다시 만든다.
- `external/Plait_setup.exe`는 **사용자가 Windows에서 직접 빌드**한다. zip 폴더에 google_client.json을 넣고 "exe 만들기.cmd"를 실행하면 된다. 현재 올라가 있는 파일은 1.0.8 exe를 이름만 바꾼 것이므로 다시 빌드해야 한다.
- `external/TeamCal_setup.exe`는 예전 링크용으로 남겨 두었다.

## 주요 기술 메모 (Plait 2.0 / 베타)
- **계정 우선**: 처음 켜면 Plait 계정(아이디·이름·비밀번호 8자 이상, 복구 코드)을 만들거나 로그인한다. 서버는 Supabase다.
  - 실행해 둔 SQL: `supabase_0.2.0_sync.sql`(mirror_cals, mirror_links), `supabase_0.4.0.sql`(origin 컬럼, new_recovery_code, delete_my_account)
- **공유 칩(함께 쓰는 캘린더)**: 원본은 서버에 있다. 권한은 owner / editor(편집 가능) / viewer(보기만).
  - 칩을 더블클릭하면 뜨는 창에서 연동, 사람(초대·권한·내보내기), 색상, 삭제·나가기를 다룬다. 삭제할 때는 연결된 구글·네이버 캘린더도 지울지 체크박스로 묻는다.
- **동기화 엔진 `bSync`**: 구글과 네이버로 양방향 미러링한다.
  - `mirror_cals.sync_token` 값은 `"off"`, `"pick"`, 또는 실제 토큰이다.
  - 구글은 syncToken을 쓰고, 네이버는 etag와 내용 비교로 판단한다.
  - `origin='own'`(구글·네이버 원본 캘린더를 공유 칩으로 바꾼 것)은 삭제하거나 이름을 바꾸지 않는다. 반복 일정과 62일보다 오래된 일정은 건너뛴다.
  - 미러 캘린더 이름은 칩 이름 그대로 쓴다(접두어 없음).
- **네이버 CalDAV**: 호스트를 거쳐 요청한다.
  - C# `[TLW]::DavSend`를 쓰고, 명령은 `nvreq`, `nvsave`, `nvclear`, `nvstate`, `nvclip`이다.
  - 저장된 기본 URL로만 요청을 허용한다.
  - 네이버는 MKCALENDAR를 막아 두었다. 그래서 칩에 빨간 "!"를 띄우고 [네이버 캘린더 열기 ↗] → [만들었어요 · 확인] 순서로 같은 이름의 캘린더에 자동으로 연결한다.
  - 네이버 웍스 주소는 caldav.worksmobile.com이고, 아직 실제로 검증하지 못했다.
- 위젯 설정 탭: 일반, 연동, 계정, 팀 휴가, 알림, 정보.

## 브랜드
- 이름: Plait (플레잇). 로고는 엮인 두 코랄 띠로 만든 캘린더 테두리와 숫자 31이다.
- 아이콘 색: 밝은 코랄 `#f4835f`(위·왼쪽 띠), 진한 코랄 `#c4462a`(아래·오른쪽 띠, 숫자 31, Inter ExtraBold)
- 앱 UI 색: 종이색 `#fbfaf7`, 잉크 `#1b1b1d`, 강조색 `#e0592a`(다크 모드 `#ff8a4c`). 인디고는 쓰지 않는다.
- 홈페이지 아이콘: `assets/plait_icon.png`(256), `assets/plait_favicon.png`(64)

## 남은 일
- 사용자가 `Plait_setup.exe`를 2.0.0으로 다시 빌드해 올리기
- 구글 클라우드 OAuth 동의 화면의 앱 이름을 Plait으로 바꾸기
- 구글 앱 인증 준비: 도메인 구매, 개인정보처리방침(`external/privacy.html`, 2.0.0 기준으로 개정됨), 스코프 사유, 데모 영상 대본. 구글 캘린더 스코프는 민감 등급이라 CASA는 필요 없다.
- Outlook 연결: 사용자가 Entra 앱 클라이언트 ID를 주면 진행한다.
- 홈페이지 첫 화면과 화면 소개의 위젯 스크린샷을 Plait 2.0 화면으로 바꾸기
- PowerShell이 없는 환경에서 만든 2.0.0이라, Windows에서 업데이트·계정 화면·아이콘·네이버 연결을 실제로 확인해야 한다.
