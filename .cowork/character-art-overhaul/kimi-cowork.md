<!-- cowork:kimi | 2026-08-05 14:30:08 | exit=0 | 367s -->
# kimi 분석 — character-art-overhaul

> 요청: 남/녀 캐릭터가 너무 이쁘지 않습니다. 그냥 동그라미, 네모를 붙여 넣은 형태로 디자인이 너무 허접하고, 못생겼습니다.

참고 URL:
- https://github.com/RafaelBarbosatec/bonfire
- https://github.com/LiberatedPixelCup/Universal-LPC-Spritesheet-Character-Generator

위 두 URL 을 참고하여 정적 이미지 애셋 없이, 동적 코드/위젯/컴포넌트로 미리 캐릭터를 만들어 놓고 로직/동적 생성해서 사용할 수 있도록 해 주세요.

그래서 캐릭터/몬스터의 비주얼적 디자인을 아주 예쁘고, 멋지고, 화려하게 해 주세요.
> 생성: 2026-08-05 14:30:08 · 소요 367s · 읽기 전용 분석(작업공간 미수정)

---

• 핵심 렌더러를 확인했다. 이제 몬스터 쪽과 연결 지점을 본다.

• 이제 표면 연결 파일들과 줌/스냅샷 근거를 확인한다.

• 마지막으로 참고 자료(Bonfire LPC)가 작업공간에 실재하는지 확인한다.

• 

## 1. 결론 요약

  "동그라미·네모" 지적의 실체는 아키텍처가 아니라 **조형 품질** 이다. 스펙→렌더러→공유 표면 구조(`CyborgDesign`+`CyborgRenderer`, 세 표면이 이미 공유)는 사람이 제안한 LPC식 구조와 같은 골격이라 새로 만들 필요가 없다. 못생김의 원인은 네 가지로 좁혀진다: ① 명암이 `armorBase`/`armorLight` **2톤 평면 채색**뿐이고 `Gradient` 가 전무, ② 팔·다리가 **테이퍼 없는 4점 사각형**, 헬멧·어깨가 **단일 RRect**, 곡선은 허리 pinch 두 줄뿐, ③ 디테일(코어·갈비·포트)이 1~3px 라 최소 줌 59px 에서 전멸해 "평평한 색 덩어리"만 남음, ④ 몬스터는 200종이 정의돼 있는데 그림은 `MonsterBuild` 4종뿐이라 종 다양성이 색조·눈 개수로만 표현된다. 권고는: 렌더러에 **그라디언트 셰이딩 + 베지에 실루엣 + 파츠 슬롯 스키마** 를 얹고, 몬스터는 **계열(family) 단위 파츠 파라미터** 로 확장하며, 비용 주범인 `MaskFilter.blur`(캐릭터당 최대 7회/프레임)를 먼저 정리하는 것이다.

  

## 2. 근거

  - `lib/game/entities/cyborg_renderer.dart:72-76` — 페인트가 `armorBase`·`armorLight`·`accent`·`_deepShade` 4종뿐. `Gradient` 는 파일 전체에 없음(grep 결과 0건).
  - `cyborg_renderer.dart:145-151` — 다리는 `moveTo`+`lineTo` 4점 사각형(`Path`에 곡선 없음). 팔도 동일 구조(`:566-571`, `:594-600`).
  - `cyborg_renderer.dart:655-662` — 헬멧은 `Rect.fromCenter` 하나의 RRect. 어깨 패드도 RRect(`:476-486`).
  - `cyborg_renderer.dart:247,256,802-813` — 베지에는 허리 `quadraticBezierTo` 2개와 포니테일 2개가 전부.
  - `cyborg_renderer.dart:266-279` — "흉갑 하이라이트"는 몸통 클립 안에 놓는 사다리꼴 1개. 입체감의 전부.
  - `cyborg_renderer.dart:337-365` — 코어는 원 4겹 + 링. `:374-381` 흡입구는 3.4×5.2px 타원. 59px 표시(`cyborg_render_snapshot_test.dart:17-19` 근거 주석)에서 소멸하는 크기.
  - `cyborg_renderer.dart:200,342,349,434,697` — 캐릭터 1인당 `MaskFilter.blur` 최대 7개소(부츠×2, 코어×2, 척추레일, 바이저).
  - `lib/game/entities/enemy.dart:620-629` — `switch (build)` 로 `_renderScout/Sentry/Heavy/Commander` 4개만. `:618` 방향은 `facesRight`+`scale(-1,1)` 좌우 2면뿐(연속 yaw 없음).
  - `lib/game/systems/monster_codex.dart:106-212` — `MonsterFamily.all` 은 20계열, `MonsterCodex.all`(`:307-309`)은 200종. 그런데 종 차이는 `hue`·`eyeCount`·`crestCount`·스탯뿐(`:379-399`).
  - `lib/game/entities/player.dart:1123`, `lib/game/entities/remote_player.dart:311`, `lib/auth/cyborg_portrait.dart:124`, `lib/game/ui/cyborg_preview.dart:53` — 인게임·원격 플레이어·선택 화면·프리뷰 네 표면이 이미 같은 `CyborgRenderer.drawBody` 를 호출.
  - `lib/game/action_rpg_game.dart:223,350-353` — 원격 플레이어 표시 상한 50명. 줌은 `screenSize.y/760` 을 `0.55~1.6` 으로 클램프.
  - `cyborg_renderer.dart:877-941` — `_View.project()` 가 타원기둥 둘레각→화면 x·깊이 투영을 제공(연속 yaw). 이 덕에 깊이 정렬·가림이 자동(`:84-97`).
  - `test/cyborg_render_snapshot_test.dart:28-47` — 16방향 × 1.9배/0.55배 PNG 검수 경로가 이미 존재.
  - 작업공간 내 `bonfire`/`lpc`/`rive` 는 `.cowork/` 프롬프트 문서와 무관 매치뿐 — 참고 자료는 URL 일 뿐 코드로 벤더링돼 있지 않다. `pubspec` 에도 `flame_rive` 없음(cowork 프롬프트 Tech stack 절).

  

## 3. 상세 분석

  ### 3-1. 지금 그림이 왜 못생겼는가 — "동그라미·네모"의 조형 번역

  사람의 표현을 조형 언어로 옮기면 다섯 결함이다.

  1. **곡률의 단조로움.** 부위마다 곡률이 "RRect 의 코너 반경" 하나로 수렴한다. 헬멧(RRect, `cyborg_renderer.dart:655-662`), 어깨 패드(RRect, `:476-486`), 무릎·손목 마디(RRect, `:168-178`, `:574-587`)가 모두 같은 조형 문법이라, 눈은 이를 "둥근 네모를 붙였다"로 읽는다. 잘 그린 캐릭터는 부위마다 곡률의 크기·방향이 다르다(헬멧은 큰 반경의 완만한 곡 + 턱의 급격한 꺾임, 팔은 근육 볼륨의 S곡).
  2. **테이퍼 없는 사지.** 팔·다리가 어깨→손목, 엉덩이→발목까지 거의 같은 폭의 사각 스트립(`:145-151`, `:566-571`). 인체 실루엣의 리듬(두꺼움→좁아짐→관절 볼륨)이 없어 "막대 인형"이 된다. 무릎·손목 RRect 마디(`:165-178`)는 관절의 존재는 알리지만 볼륨의 방향성은 주지 못한다.
  3. **명암 단계 부족.** 몸 한 부위당 색이 최대 2개(base/light) + accent. 중간톤(mid)과 반사광(reflect)이 없어 형태가 평면으로 읽힌다. 빛 방향 개념은 흉갑 하이라이트 1곳(`:266-279`)과 림 스트로크(`:283-289`)뿐이고, 그림자 면은 yaw 와 무관하게 고정 색이다.
  4. **디테일 밀도의 배율 부적합.** 코어(반경 3.4~4.5px, `:334`), 갈비 선(strokeWidth 2, `:311-326`), 흡입구(3.4×5.2, `:374-381`)는 확대 프리뷰(1.9배)용 정보다. 최소 줌 0.55에서 키 59px(`action_rpg_game.dart:352-353`, 스냅샷 테스트 주석 `:17-19`)이면 이것들은 1~2px 점으로 죽고, 남는 것은 2톤 덩어리뿐 — 즉 **플레이 중 보이는 그림이 가장 빈약한 버전**이다. 화려함을 어디에 배치할지가 잘못돼 있다.
  5. **회전 시 머리의 정면 고정.** 헬멧 RRect 는 `Offset(0, cy)` 중심으로 yaw 에 무관하게 같은 형태(`:655-656`)이고 폭만 `headWidthScale` 로 준다(`:644`). 옆·뒤를 봐도 "정면 헬멧이 납작해진" 모습이라 회전할수록 인형감이 올라간다. `_View.project()` 로 정면 요소(바이저·턱)는 잘 돌아가는데(`:682-721`) 껍데기 형태가 안 따라간다.

  ### 3-2. 코드만으로 "예쁜" 캐릭터 — 쓸 수 있는 수단과 비용

  - **`LinearGradient`/`RadialGradient` 채색**: 부위당 fill 1회가 shader fill 로 바뀌는 것이라 즉시 모드에서 비용 증가가 거의 없다 [추측: 이 크기의 래스터에선 수 µs 수준]. 2톤→4톤(하이라이트/베이스/미드/셰이드) 전환의 실질 수단. `MaskFilter` 와 달리 오프스크린 패스가 없다.
  - **베지에 실루엣**: `_drawTorso` 가 이미 `quadraticBezierTo` 로 허리 곡률을 데이터화(`:244-262`)했다 — 이 패턴을 팔(상완/전완 볼륨), 헬멧(측후면 윤곽), 어깨 패드(장갑판 오버행)로 확장하면 된다. 비용은 Path 점 몇 개 증가분이라 무시할 수준.
  - **`MaskFilter.blur` 가 진짜 비용 주범**: blur 는 Skia/Impeller 에서 오프스크린 패스를 유발하며, 현재 캐릭터당 최대 7개소(§2 근거 7), 적은 눈·부스터·코어에 개당 1~3개(`enemy.dart:685,737,770,777,956,997,1094`). 원격 플레이어 상한 50명(`action_rpg_game.dart:223`) 기준, 캐릭터만 30명 화면이면 **프레임당 blur 패스 수십~200+ 회**다 [추측: 개당 수십~수백 µs로 프레임 예산 16.6ms 를 압박할 수준]. 글로우는 대부분 **미리 굽거나 `RadialGradient`(저렴)로 대체 가능**한 정적 형태다.
  - **`saveLayer`**: 선택 해제 초상 1곳(`cyborg_portrait.dart:115-119`)만 사용. 합성(림라이트를 블렌드로 얹기 등)을 늘리면 유혹이 생기지만, 캐릭터당 saveLayer 는 30명에서 드로우콜을 배로 늘리므로 인게임 경로에는 쓰지 않는 쪽이 맞다.
  - **`Picture`/`ui.Image` 베이크**: 정적 부위(헬멧·어깨·몸통 껍데기)는 yaw 당 1회 그려 캐시 가능. 다만 §7 문제(아래)로 연속 yaw 와 충돌한다 — 양자화 수와 메모리를 함께 정해야 한다(§3-6).

  ### 3-3. LPC 레이어 합성 → 코드 파츠 시스템

  LPC 의 본질은 "① 슬롯 체계(몸/머리/옷/갑옷/무기), ② 고정 레이어 순서, ③ 슬롯 단위 교체, ④ 스펙이 데이터" 다. 이 프로젝트에는 이미 절반이 있다: `drawBody` 의 호출 순서가 곧 레이어 순서(등 장비→뒤팔→다리→골반→몸통→어깨→앞팔→목→머리, `cyborg_renderer.dart:80-100`)이고, `CyborgImplant` 가 "장착 부품" 개념(`cyborg_design.dart:230-251`)이다.

  부족한 것은 **교체 단위**다. 지금 임플란트는 켜고 끄는 불리언 묶음이라 "같은 슬롯의 다른 디자인"을 표현 못 한다. 옮기는 방법:

  - 슬롯 열거 추가 [판단]: `PartSlot { helmet, torsoPlate, shoulderPad, armGuard, legGuard, backUnit, hair, visor }` — 각 슬롯에 2~4개 `PartVariant` (예: 헬멧 = `visorFull / halfDome / crested`).
  - `CyborgDesign` 에 `Map<PartSlot, PartVariant> parts` 를 추가하고, 기존 `CyborgImplant` 는 "발광/기믹 플래그"로 남긴다(이미 그림에 연결된 7종을 버리면 `:306-443` 의 렌더 코드가 전부 재작성이라 비용 대비 손해).
  - 각 variant 는 `void draw(Canvas, CyborgDesign, _Levels, _View)` 시그니처의 순수 함수 — LPC 의 "레이어 PNG" 자리에 "레이어 함수"가 온다. `_View` 투영을 그대로 쓰므로 연속 yaw 가 유지된다.
  - SSOT 유지: 스펙은 여전히 `CyborgDesign` 하나, 세 표면(player·portrait·preview)은 손댈 필요 없이 새 파츠가 자동 반영된다.

  ### 3-4. 몬스터 다양성

  현재 매트릭스: 200종(`monster_codex.dart:307`) = 20계열 × 10등급이지만, 그림은 `build` 4개(`enemy.dart:620-629`)라 **같은 계통(drone 5계열, walker 6계열, siege 7계열)은 색조와 눈 개수만 다르다**. `MonsterSpecies` 에 이미 `family`(hue)·`tier`·`eyeCount`·`crestCount` 가 있어 접속점은 충분하다.

  설계안 [판단]: 계통별 골격 템플릿(4개)은 유지하되, **계열별 파츠 테이블**을 둔다. 예: `walker` 계통에서 순찰병=둥근 흉갑+집게, 도끼병=각진 흉갑+블레이드 암, 창병=슬림 흉갑+랜스. 구체적으로는 `MonsterFamily` 에 `silhouette`(흉갑 형태 enum)·`weaponArm`(enum)·`headGear`(enum) 필드를 추가하고, `_renderSentry` 를 "골격 + 파츠 슬롯 그리기"로 분해한다. 등급(tier)은 지금처럼 문양·눈 개수(`:671-713`)에 더해 **장식 밀도**(숄더 스파이크 수, 패널 라인 수)로 드러낸다 — 59px 에서 읽히는 차이는 실루엣 덩어리뿐이므로, 계열 구분은 반드시 실루엣 파츠로 해야 한다.

  주의: 적 렌더는 현재 좌우 2면 플립(`enemy.dart:618`)이다. 파츠화를 플레이어식 `_View` 연속 yaw 로 올리면 더 입체적이지만, 방향 정보량이 늘어 "적이 어디를 보는지"라는 게임플레이 신호(`_renderTelegraph` 의 조준선, `:1128-1138`)와의 정합을 다시 맞춰야 한다. 1차 개선에서는 2면 유지 + 파츠화가 현실적이다.

  ### 3-5. 커스터마이저 UI

  공유 렌더러 문제는 이미 해결돼 있다(`CyborgPreviewPainter`, `cyborg_preview.dart:14-89`). 파츠 선택 UI 로 가는 데 필요한 것은 둘뿐이다.

  - `CyborgDesign` 이 `@immutable` const(`cyborg_design.dart:25-52`)이므로 슬롯 교체용 `copyWith` 또는 빌더가 필요하다. 지금은 `const` 인스턴스 2개(`assault`/`infiltrator`)만 존재해 커스터마이즈 개념 자체가 없다.
  - 선택 상태(파츠 조합)의 저장: `shared_preferences` 가 이미 의존성에 있고(cowork Tech stack), 캐릭터 선택(`CyborgKind`)이 어디에 저장되는지에 맞춰 파츠 조합도 같은 경로로 저장하면 된다 [미확인: 선택 저장 위치].
  - UI 는 슬롯별 칩/드롭다운 + 즉시 프리뷰(`CyborgPreviewPainter` 는 `design` 이 바뀌면 `shouldRepaint` 로 갱신, `:83-88`)로 충분하다. 확대 배율(프리뷰 기본 2.0, `:286`)이므로 여기서는 1~3px 디테일이 살아남는다 — **디테일 밀도는 커스터마이저용, 실루엣 대비는 인게임용**으로 이원 설계가 필요하다.

  ### 3-6. 어디까지가 현실적인가

  - **코드 드로잉으로 도달 가능**: 벡터 아트 풍의 깔끔한 스타일 — 그라디언트 메탈, 림라이트, 발광 포인트, 베지에 실루엣. 선택 화면(1.9~3.5배)에서는 "예쁘다"까지 충분히 간다.
  - **59px 인게임에서는**: 디테일이 아니라 실루엣+3~4 톤 덩어리+발광 점만 보인다. 즉 인게임 "화려함"의 한계는 조형이 아니라 물리적 픽셀 수다. 여기서 추가 화려함을 원하면 파츠 정밀도가 아니라 **이펙트 레이어**(트레일·오라 — 이미 dash ghost 등 존재, `player.dart:1076-1083`)가 정답이다.
  - **`ui.Image` 베이크 캐시 수치** [추측]: 캐릭터 1방향 1프레임을 108×1.3 ≈ 140×140px RGBA 로 굽으면 ≈ 78KB. yaw 16방향 × 보행 4프레임 × 2프레임 = 128장 ≈ 10MB. 몬스터는 200종이라 전종 베이크는 비현실적(16방향×4프레임×200종 ≈ 1GB) — 화면에 보이는 종만 LRU 로 굽는 방식만 성립한다. 워밍업은 종 첫 등장 시 수 ms [추측]. 단, 베이크는 `_View` 의 **연속 yaw 를 16방향 양자화로 퇴보**시킨다 — `quantizeYaw` 가 `iso.dart:132` 에 이미 있지만 현재 아무도 안 쓰는 이유(회전 계단)가 있다. 캐릭터 회전이 잦은 이 게임에서 이 퇴보는 눈에 보인다.
  - **`flame_rive` 가 필요해지는 지점**: 관절 리깅(무릎이 꺾이는 보행), 커스터마이저에서의 클로즈업 연출. 단, pubspec 에 없고 런타임/에셋 파이프라인이 새로 필요하므로, 코드 드로잉 개선(그라디언트+베지에)을 먼저 하고도 "팔다리 관절 애니메이션이 안 되면 안 되는" 판정이 나올 때 도입이 맞다. 59px 인게임에서는 Rive 도 실루엣 한계를 못 넘는다.

  

## 4. 리스크 · 함정

  - **SSOT 분산 위험**: 파츠 variant 를 렌더러 바깥(예: 커스터마이저 전용 그림)에 두면 세 표면이 어긋난다. 반드시 `cyborg_design.dart`/`cyborg_renderer.dart` 안에서 확장해야 한다(cowork Instructions 2).
  - **팔레트 우회**: 몬스터 색은 `MonsterCodex._paletteFor`(`monster_codex.dart:498-515`)이 HSL 로 생성하므로 `GamePalette` 에 없는 색이 이미 존재한다. 새 몬스터 색을 `GamePalette` 에 넣으라는 규칙(cowork Instructions 4)과 현 구조가 충돌할 수 있다 — 계열 hue 대역(252°~347°) 제약(`monster_codex.dart:96-99`)을 유지하는 쪽이 우선.
  - **성능 회귀**: 화려함을 `MaskFilter` 로 추가하면 이미 과부하 후보인 블러 패스가 늘어난다. 50명 원격 상한 + 몹 수십 마리에서 프레임 드롭으로 직결. 반대로 베이크 캐시는 연속 yaw(§7 자산)를 잃는다 — 둘은 트레이드오프이며 섞어 쓸 수 없다.
  - **59px 착시**: 스냅샷은 1.9배와 0.55배를 둘 다 뽑으므로(`cyborg_render_snapshot_test.dart:32-38`), 1.9배만 보고 "예뻐졌다"고 판단하는 실수를 하기 쉽다. 인게임 개선의 합격선은 0.55배 시트다.
  - **적 방향 표현의 게임플레이 결합**: 적의 연속 yaw 화는 텔레그래프·조준선(`enemy.dart:1122-1153`)과 패리 능력(좌우 2면 → N면)을 바꾸므로 "그림만"의 변경이 아니다.
  - **동시 편집**: 다른 세션이 같은 저장소를 편집 중(cowork 검증 방법 절 경고). 특히 `enemy.dart`·`cyborg_renderer.dart` 는 근거 인용 시점 이후 바뀔 수 있다.
  - **`CyborgDesign` 의 const 불변성**: 커스터마이저 도입 시 `copyWith` 추가는 `CyborgDesign.all` 의 const 인스턴스와 공존해야 한다. 파츠 조합 직렬화(서버 전송 여부)는 SpacetimeDB 스키마(`spacetimedb/`)까지 번질 수 있는 영역 — 클라만 바꿔서 끝날지, 서버까지 갈지는 미확인.

  

## 5. 권고안

  | 순위 | 권고 | 범위 | 근거 | 리스크 |
  |---|---|---|---|---|
  | 1 | 셰이딩 2톤→4톤: 부위별 `LinearGradient`(수직 하이라이트→베이스→셰이드) + yaw 연동 명암 오프셋. `_View` 의 빛 방향(-0.6 앵커, `:266`)을 전 부위로 확장 | `cyborg_renderer.dart` 전 `_draw*` | `cyborg_renderer.dart:72-76,266-289` | 없음에 가까움(셰이더 fill, 즉시 모드) |
  | 2 | 실루엣 베지에화: 팔·다리 스트립에 상완/전완·허벅지/종아리 볼륨 곡선, 헬멧 측후면 윤곽을 `cubicTo` 로. `quadraticBezierTo` 패턴 재사용 | `cyborg_renderer.dart:145-151,566-600,655-662` | `:247,256`(기존 사례) | 곡선 수 증가로 Path 복잡도 미세 상승 |
  | 3 | `MaskFilter.blur` 다이어트: 정적 글로우(부츠·바이저·레일)는 `RadialGradient` 대체, 코어·눈만 blur 유지. 목표: 캐릭터당 blur 7→2, 적당 3~7→1~2 | `cyborg_renderer.dart:200,342,349,434,697`, `enemy.dart:685,737,770,777` | §3-2 비용 분석, `action_rpg_game.dart:223`(50명 상한) | 글로우 질감 미세 저하 |
  | 4 | 파츠 슬롯 스키마: `PartSlot`/`PartVariant` enum + `CyborgDesign.parts` 맵 + variant draw 함수(레이어 순서는 기존 `drawBody` 순서 고정). `CyborgImplant` 는 기믹 플래그로 유지 | `cyborg_design.dart`, `cyborg_renderer.dart` | `cyborg_design.dart:230-251`, `cyborg_renderer.dart:80-100` | `copyWith` 필요(const 불변 구조 변경) |
  | 5 | 몬스터 계열 파츠화: `MonsterFamily` 에 silhouette/weaponArm/headGear 추가, 4개 렌더 메서드를 "골격+슬롯"으로 분해. tier 는 장식 밀도로 | `monster_codex.dart:78-213`, `enemy.dart:620-1030` | 200종 vs 4그림 괴리(`monster_codex.dart:307`, `enemy.dart:620-629`) | 텔레그래프/조준선과 방향 표현 정합 필요 |
  | 6 | 커스터마이저: `CyborgPreviewPage` 에 슬롯 칩 UI + `copyWith` 기반 실시간 프리뷰. 저장은 기존 캐릭터 선택 경로에 합류 | `lib/game/ui/cyborg_preview.dart`, 선택 저장 경로 | `cyborg_preview.dart:83-88,286` | 파츠 조합의 서버 동기화 여부 결정 필요(미확인) |
  | 7 | (2단계 판정) 위 1~6 후에도 관절 애니메이션이 요구되면 `flame_rive` 도입 검토. 인게임 다수 표시용 베이크 캐시는 연속 yaw 퇴보와 메모리(≈10MB/캐릭터조합)를 감수할 때만 | pubspec, 렌더 파이프라인 | §3-6 수치, `cyborg_renderer.dart:877-941` | 의존성 추가, 연속 yaw 상실 |

  

## 6. 불확실 · 미확인

  - `MaskFilter.blur` 의 실제 프레임 비용: 저장소에 프로파일링 데이터가 없다. §3-2 의 수치는 [추측]이며, `flutter run --profile` + performance overlay 또는 DevTools 로 실측이 필요하다.
  - 캐릭터 선택(`CyborgKind`)의 저장 위치와 서버 전송 여부: 파츠 커스터마이즈가 클라 로컬에서 끝날지, SpacetimeDB 캐릭터 테이블까지 갈지가 권고 6의 범위를 결정한다. `spacetimedb/src/` 의 캐릭터 스키마를 추가 확인해야 한다.
  - Bonfire LPC 예제 코드: 참고 URL 이 작업공간에 벤더링돼 있지 않아(grep 결과 `.cowork/` 문서뿐) `lpc_sprite_sheet_loader.dart` 의 구체 구현은 확인하지 못했다. 위 §3-3 은 LPC 의 공개된 레이어 개념과 cowork 프롬프트의 요약에 근거한 [판단]이다.
  - `world_tree.dart` 는 328줄 중 80줄만 읽었다. "같은 방식의 사례"로서 `Picture` 캐싱 여부 등 최적화 패턴이 있는지는 미확인.
  - 적의 2면 플립(`enemy.dart:618`)을 유지한 채 파츠화할 때 좌우 비대칭 파츠(캐논 어깨, `:936-946`)가 플립과 충돌하는지 — 설계 단계에서 검토 필요.
  - `test/cyborg_render_snapshot_test.dart` 를 실행해 실제 PNG 를 눈으로 보지 못했다(읽기 전용 규칙). "못생김"의 5가지 진단은 코드 구조에서 도출한 것이며, 스냅샷으로 육안 교차검증하면 우선순위가 조정될 수 있다.
