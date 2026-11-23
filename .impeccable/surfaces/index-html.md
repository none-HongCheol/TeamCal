---
version: 1
slug: "index-html"
primary_target: "index.html"
related_targets: []
---

# Surface: Plait 홈페이지 (새로 만들기)

Mode: Persuade. 정석 제품 랜딩 페이지(사용자 선택). 완성도 기준: Notion Calendar 홈페이지.

## Job and audience
Plait에 관심이 생겨 들어온 Windows PC 사용자. 무엇을 하는 앱인지 한 줄로 이해하고, 기능을 둘러본 뒤 받을지 정한다.

## Outcome
- 주 행동: 기능 둘러보기(같은 페이지의 기능 영역으로 이동).
- 보조 행동: Plait 받기(Windows .exe). 첫 화면에서 보이되 주 버튼보다 약하게.
- 첫 화면에서 증명할 것: 구글·네이버·함께 쓰는 캘린더가 위젯 하나에 겹쳐 보인다는 것.
- 핵심 포인트(사용자 지정): 캘린더 칩마다 연동할 곳(구글·네이버, Outlook 준비 중)을 하나씩 골라 양방향으로 맞춘다는 것. 기능 셋째 줄에서 칩 설정 창을 직접 켜고 끄며 보여 준다.

## Content (기존 index.html의 사실을 그대로 옮김, 새로 지어내지 않음)
상단 업데이트 알림 줄, 머리글(로고·메뉴·밝게/어둡게), 히어로, 기능 3가지(한 화면 / 함께 쓰기 / 양방향), 화면(일정 추가·휴가 등록), 더 보기 9가지, 시작하기 4단계, 다운로드(환경·SmartScreen 안내·팀 담당자), 업데이트 노트(최근 2~3개 + 전체 보기), 자주 묻는 질문 10개, 바닥글(개인정보처리방침).

## Boundaries
- 유지: 로고(`assets/plait_icon.png`, `plait_favicon.png`), 코랄 계열(#f4835f, #c4462a, 강조 #e0592a / 다크 #ff8a4c), 인디고 금지, 해요체, 다운로드 링크 `external/Plait_setup.exe`, `privacy.html` 링크, 업데이트 노트 앵커 `#updates`, 기존 앵커(#features #start #download #faq).
- 반드시 할 것: 밝게/어둡게/시스템 따라가기, 모바일 대응(모바일 방문자에게는 "Windows용" 안내), 키보드 탐색, 본문 바로가기.
- 하지 않을 것: 사용자 수·후기·평점 같은 지어낸 근거, Mac·Outlook 지원처럼 보이는 표현, 기존 사실 문구 임의 변경.

## Open decisions (빌더가 임의로 정하지 않음)
- 위젯 스크린샷: 현재 이미지는 2.0 이전 화면. 사용자가 2.0 스크린샷을 주기 전까지 기존 이미지를 쓰고 교체 목록에 올린다.
- 업데이트 노트를 홈에 몇 개까지 둘지(기본 최근 3개 + 나머지 접기).
- GitHub 업로드는 매번 사용자에게 "올릴까요?"라고 묻고 진행.

## Direction contract
THESIS: 흩어진 캘린더가 위젯 하나로 모이는 순간을 직접 켜고 끄며 보여 준다. 기능을 같은 크기 카드 세 장으로 나열하는 앱 소개 페이지의 기본형을 거부한다.
OWN-WORLD: 브랜드 종이색 #fbfaf7 바탕, 흰 면, 잉크 #1b1b1d, 강조는 코랄 #e0592a 하나. 캘린더 출처색은 구글 파랑·네이버 초록·함께 코랄로 데모에서만 쓴다. Pretendard 한 가족, 굵기 대비로 위계를 세우고 숫자는 tabular. 얇은 선과 부드러운 그림자, 10–14px 모서리. 다크 모드는 #121214 바탕과 #ff8a4c 강조.
STORY: 한 줄 문구로 무엇인지 알고, 바탕화면 위 위젯을 보고, 기능 영역에서 출처를 직접 켜고 끄며 "한 달력에 모인다"를 체감한 뒤, 다운로드로 간다.
FIRST VIEWPORT: 얇은 업데이트 줄, 고정 머리글(로고·메뉴·테마·작은 받기 버튼). 가운데 정렬 큰 제목 두 줄, 설명 한 단락, [기능 둘러보기](잉크 채움) [Windows용 받기](테두리). 그 아래 화면 폭 가까이 넓은 바탕화면 장면: 코랄 계열 배경 위 오른쪽에 실제 위젯 스크린샷, 아래 작업 표시줄. 장면 윗부분이 첫 화면 아래 끝에 걸친다.
FORM: canon(정석 랜딩, 사용자 선택), seed:542dac8e733881a8. 시그니처: 기능 첫 줄의 출처 칩을 켜고 끄면 해당 색 일정이 달력에서 엮이듯 들어오고 빠진다.
FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
