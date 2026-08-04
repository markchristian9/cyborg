<!-- cowork:codex | 2026-08-04 21:20:23 | exit=0 | 464s -->
# codex 분석 — character-visual-upgrade

> 요청: 남성/여성 캐릭터를 더 멋있게 비주얼 적 디자인을 해 주세요.

1) 남성/여성 캐릭터 비주얼적 디자인을 더 예쁘고, 멋지고, 화려하게 해 주세요.
2) 클릭으로 이동할 수 있도록 해 주세요.
3) 정적 애셋이 아닌, 동적 캐릭터 생성이므로 방향은 256 방향으로 할 수 있나요? 최대한 방향을 많이 해 주세요.
> 생성: 2026-08-04 21:20:23 · 소요 464s · 읽기 전용 분석(작업공간 미수정)

---



## 1. 결론 요약

현재 구현은 `yaw`를 양자화하지 않으므로 수학적으로 256방향을 넘는 연속 회전을 지원하지만, 타원 폭 변화와 부위 앵커 투영만으로는 256개의 구분 가능한 자세를 만들지 못한다. `lib/game/iso.dart:108`, `lib/game/entities/cyborg_renderer.dart:793`  
비주얼은 림 라이트·다층 코어·바이저·밑창 발광까지 갖춰 “화려함”의 기반은 있으나, 32~64px에서는 미세 장식보다 관절 분리·비대칭 실루엣·큰 명암 덩어리가 부족하다. `lib/game/entities/cyborg_renderer.dart:260`, `lib/game/entities/cyborg_renderer.dart:305`  
클릭 이동은 열린 지형의 단거리 이동으로는 동작하지만, 경로 탐색·적/PC 탭 의도·위험 지형 비용이 없어 1km 공유 월드와 PK 조작으로는 불충분하다. `lib/game/entities/player.dart:307`, `lib/game/action_rpg_game.dart:683`  
가장 시급한 결함은 여성형 선택이 인게임으로 전달되지 않아 `Player`가 기본 남성형으로 생성되는 점이며, 30인 렌더링도 정상 상태는 경계선이고 다수 대시 시에는 프레임 예산을 넘길 가능성이 높다. `lib/main.dart:64`, `lib/game/action_rpg_game.dart:225`, `lib/game/entities/player.dart:26`

## 2. 근거

- `lib/game/iso.dart:100` — `facingYaw()`는 2:1 투영의 세로 압축을 복원한 뒤 연속 `atan2` 각도를 반환한다.
- `lib/game/entities/player.dart:825` — 인게임 본체는 `quantizeYaw()` 없이 `facingYaw(dir)`를 그대로 `drawBody()`에 전달한다.
- `lib/game/entities/cyborg_renderer.dart:793` — `_View.project()`는 타원 둘레점을 회전해 화면 x와 깊이를 연속값으로 계산한다.
- `lib/game/entities/cyborg_renderer.dart:32` — 체형의 깊이비·관절 높이비가 렌더러에 하드코딩되어 있고, 코어 크기도 `frame` 분기로 결정된다(`lib/game/entities/cyborg_renderer.dart:305`). 이는 외형 수치가 모두 `CyborgDesign`에 있다는 선언(`lib/game/entities/cyborg_design.dart:18`)과 어긋난다.
- `lib/game/entities/cyborg_design.dart:143` — VULCAN은 108px 높이·34px 어깨, WRAITH는 102px 높이·25px 어깨와 13.5px 허리로 실루엣 차이를 둔다(`lib/game/entities/cyborg_design.dart:180`).
- `lib/game/entities/cyborg_renderer.dart:614` — 바이저는 깊이 부호 하나로 나타나고 사라지며, 측면에서도 폭을 최소 55% 유지한다. 포니테일 곡선은 항상 화면 왼쪽으로 휜다(`lib/game/entities/cyborg_renderer.dart:703`).
- `lib/game/entities/cyborg_renderer.dart:748` — 등에 멘 블레이드는 회전한 두 끝점이 아니라 3px 폭의 수직 사각형이며 `depth` 경계에서 즉시 나타나거나 사라진다.
- `lib/main.dart:64` — 서버 캐릭터의 이름·레벨·XP만 `ActionRpgGame`에 넘기고 `character.kind`는 사용하지 않는다. `_spawnPlayer()`도 `design` 없이 생성한다(`lib/game/action_rpg_game.dart:225`).
- `lib/auth/cyborg_portrait.dart:64` — 선택 화면과 프리뷰·플레이어는 모두 `CyborgRenderer` 자체는 공유한다(`lib/game/ui/cyborg_preview.dart:53`, `lib/game/entities/player.dart:833`).
- `lib/game/input/click_move.dart:19` — 최하위 탭 레이어, 0.55초 목적지 표식, 이동 중 점선 안내가 구현되어 있다.
- `lib/game/entities/player.dart:257` — 수동 입력이 클릭 목표보다 우선하고, 클릭 이동은 직선 조향·축 분리 충돌·0.35초 정체 시 취소 방식이다.
- `lib/game/level/level_map.dart:149` — `hazard`도 통행 가능으로 취급되며, `nearestWalkable()`은 경로가 아니라 목적지 한 칸만 보정한다(`lib/game/level/level_map.dart:195`).
- `lib/game/entities/enemy.dart:399` — 적은 탭 콜백이 없고 렌더링도 연속 회전이 아니라 좌우 반전만 사용한다. 근접·발사 대상에도 PC는 포함되지 않는다(`lib/game/action_rpg_game.dart:709`).
- `lib/game/entities/player.dart:735` — 정상 플레이어는 본체와 블러 그림자를 매 프레임 다시 그리고, 대시 중 최대 12개 잔상 각각을 `saveLayer`와 전체 본체 재렌더링으로 처리한다(`lib/game/entities/player.dart:798`).
- `test/cyborg_render_snapshot_test.dart:19` — 렌더 테스트는 예외 발생 여부와 수치 관계만 검사하고, 8방향 이미지는 저장 선택 기능일 뿐 픽셀 골든 비교가 아니다(`test/cyborg_render_snapshot_test.dart:56`).

## 3. 상세 분석

### 요구별 판정

| 요구 | 판정 | 이유 |
|---|---|---|
| 남성/여성 비주얼 강화 | 부분 충족 | 발광 장식은 충분하지만 큰 형태와 관절 마디가 약하며, 여성형 선택이 실제 게임에 전달되지 않는다. `lib/game/entities/cyborg_renderer.dart:260`, `lib/main.dart:64` |
| 클릭 이동 | 기초 기능 충족 | 빈 땅 탭·목표 표식·수동 입력 우선순위는 구현됐지만 직선 이동뿐이다. `lib/game/input/click_move.dart:12`, `lib/game/entities/player.dart:257` |
| 256방향 | 수학적으로 충족, 시각적으로 부분 충족 | 입력 각도는 연속이지만 몸통·머리 윤곽은 주로 타원 폭만 변하며 세부 부위는 이산적으로 출몰한다. `lib/game/entities/cyborg_renderer.dart:814`, `lib/game/entities/cyborg_renderer.dart:614` |
| 외형 SSOT | 불완전 | 동일 렌더러는 공유하지만 인게임 디자인 전달이 끊겼고 외형 상수가 렌더러에도 남아 있다. `lib/game/entities/player.dart:26`, `lib/game/entities/cyborg_renderer.dart:32` |

### “256방향”의 실제 의미

`quantizeYaw(…, 256)`은 1.40625° 간격이지만 현재 플레이어는 이 함수조차 호출하지 않으므로 각도 해상도에는 이론상 상한이 없다. 클릭 목표와 조이스틱은 연속 방향을 만들 수 있지만, WASD는 입력 조합상 최대 8방향만 만든다. `lib/game/iso.dart:114`, `lib/game/entities/player.dart:833`, `lib/game/action_rpg_game.dart:1287`

다만 사람 눈이 구분할 수 있는 방향 수는 고정된 숫자가 아니라 화면 크기와 비대칭 단서의 크기에 좌우된다. [분석 산술] 256단계에서 VULCAN 어깨 반폭 17px의 최대 위치 변화는 `17 × 2π/256 ≈ 0.42px`, WRAITH는 약 0.31px다. 최소 카메라 배율 0.55에서는 각각 약 0.23px·0.17px에 불과하다. `lib/game/entities/cyborg_design.dart:147`, `lib/game/entities/cyborg_design.dart:184`, `lib/game/action_rpg_game.dart:230`

따라서 현재 크기에서는 256개가 서로 구분되지는 않는다. [판단] 32방향은 큰 형상 변화가 읽히는 수준, 64방향은 회전이 부드러워 보이는 수준이며, 256은 입력·보간 정밀도로만 의미가 있다. 현재 연속각 방식을 유지하되 “256개의 고유 아트 방향이 완성됐다”고 판정해서는 안 된다.

### 회전이 무너지는 부위

- **몸통:** `halfWidth()`가 `cos²`와 `sin²`로 폭만 바꾸므로 정면과 후면의 외곽선이 같다. 가슴·허리·골반의 앞뒤 돌출이나 비대칭 장갑면은 회전하지 않는다. `lib/game/entities/cyborg_renderer.dart:203`, `lib/game/entities/cyborg_renderer.dart:814`
- **팔·어깨:** 팔 전체가 깊이 부호 하나로 몸통 앞/뒤를 전환해 정면·후면 경계에서 한 팔 전체가 순간적으로 레이어를 바꿀 수 있다. 어깨 패드는 깊이 정렬은 하지만 두 개 모두 몸통 뒤가 아니라 몸통 위에 그린다. `lib/game/entities/cyborg_renderer.dart:83`, `lib/game/entities/cyborg_renderer.dart:425`
- **다리:** 보행 위상은 `sin(yaw)`에 따른 화면 x 이동에만 쓰인다. 정면·후면에서는 `strideProjection`이 0이 되어 발이 거의 움직이지 않고, 무릎도 별도 관절이 아니라 힘줄 선의 기준점으로만 남는다. `lib/game/entities/cyborg_renderer.dart:119`, `lib/game/entities/cyborg_renderer.dart:132`
- **머리:** 바이저는 측면에서도 상당한 폭을 유지하다 `depth > 0` 경계에서 통째로 사라진다. 뒤통수 케이블과 관자놀이 모듈도 같은 이산 가시성 문제를 가진다. `lib/game/entities/cyborg_renderer.dart:614`, `lib/game/entities/cyborg_renderer.dart:656`
- **포니테일:** 회전 방향과 무관하게 제어점이 항상 `p.x - spread` 쪽으로 향한다. 좌측을 보는 측면과 우측을 보는 측면 중 하나에서는 머리 뒤가 아니라 같은 화면 방향으로 휘는 부자연스러운 결과가 난다. `lib/game/entities/cyborg_renderer.dart:720`
- **무기:** 홀스터 블레이드는 “비스듬히 걸린” 설명과 달리 수직 사각형이다. 근접 공격 중에도 본체가 기본 `showBlade: true`로 홀스터를 그리고, 이후 화면 최상단에 스윙 블레이드를 추가하므로 각도에 따라 두 자루처럼 보일 수 있다. `lib/game/entities/cyborg_renderer.dart:57`, `lib/game/entities/player.dart:756`
- **VULCAN 흉골:** 갈비선 y가 `y.chestTop - 3 - i×5`라 몸통 시작선보다 위에 그려진다. 흉갑 안이 아니라 목·머리 쪽으로 올라갈 가능성이 높은 명백한 좌표 문제다. `lib/game/entities/cyborg_renderer.dart:284`
- **설계값 미반영:** `neckLength`는 두 디자인에 정의돼 있으나 렌더러가 참조하지 않는다. 선언된 남녀 목 비율 차이가 실제 그림에는 반영되지 않는다. `lib/game/entities/cyborg_design.dart:86`, `lib/game/entities/cyborg_design.dart:154`

### 비주얼 읽힘

현재 팔레트는 밝은 바닥 위에 짙은 장갑과 청록 발광을 두어 진영 식별과 기본 실루엣 대비는 올바르다. `lib/game/palette.dart:79` 코어도 후광·본체·흰 심지·방열 링으로 구성되어 확대 화면에서는 충분히 화려하다. `lib/game/entities/cyborg_renderer.dart:305`

문제는 월드 최소 배율에서 102~108px 몸체가 약 56~59px 높이로 축소된다는 점이다. [분석 산술] 1.1~1.8px 림·스캔선·밑창선은 약 0.6~1.0px가 되고, WRAITH 코어 반경 3.4px도 약 1.9px가 된다. `lib/game/entities/cyborg_renderer.dart:170`, `lib/game/entities/cyborg_renderer.dart:305`, `lib/game/action_rpg_game.dart:230`

따라서 더 많은 글로우보다 다음이 효과적이다. [판단]

- VULCAN은 한쪽이 더 큰 견갑, 넓은 흉곽 쐐기, 대형 전완·척추팩처럼 4~8px 이상 차지하는 질량으로 “강습”을 읽혀야 한다.
- WRAITH는 회전하는 포니테일 리본, 골반 핀, 분리된 종아리·뒤꿈치 형태처럼 좁고 긴 음영 덩어리로 “침투”를 읽혀야 한다.
- 어깨–몸통, 팔꿈치, 골반–허벅지, 무릎에 짙은 2~3px 음각 간격을 두어 축소 후에도 최소 1px의 마디가 남아야 한다.
- `armorBase`·`armorLight`·`deepShade`를 큰 면 단위로 배치하고 청록은 코어·바이저·한두 개의 방향 단서에 집중해야 한다. 색 추가가 필요하면 `GamePalette`와 `CyborgDesign`을 통해서만 공급해야 한다. `lib/game/entities/cyborg_design.dart:101`, `lib/game/palette.dart:79`

### 클릭 이동과 MMORPG/PK 경계

UI 우선 구조는 합리적이다. 탭 레이어가 가장 아래에 있고 액션 버튼과 열린 패널은 이벤트를 처리 완료 상태로 만든다. `lib/game/input/click_move.dart:12`, `lib/game/ui/touch_controls.dart:54`, `lib/game/ui/inventory_ui.dart:453` 수동 입력이 들어오면 클릭 목표를 지우는 우선순위도 올바르다. `lib/game/entities/player.dart:266`

그러나 실전 문제는 다음과 같다.

- 적은 탭 대상이 아니므로 적을 누르면 그 화면 픽셀이 지면 좌표로 역변환되어 이동 목표가 된다. 캐릭터 몸통처럼 지면보다 위에 그려진 픽셀은 실제 발밑과 다른 좌표를 만든다. `lib/game/input/click_move.dart:28`, `lib/game/iso.dart:59`
- 적/PC 선택, 공격 이동, 상호작용 의도가 없다. 현재 피해 대상도 적과 파괴물뿐이라 PK용 PC 탭 의미가 정의되지 않았다. `lib/game/action_rpg_game.dart:709`
- 목적지가 통행 가능해도 중간의 타워·공백을 우회하지 않는다. 0.35초 정체 후 취소할 뿐이라 사용자는 “왜 멈췄는지” 알기 어렵다. `lib/game/entities/player.dart:293`, `lib/game/level/level_map.dart:327`
- 정체 판단은 목표까지 남은 거리 감소가 아니라 이번 프레임의 이동량을 잰다. 벽을 따라 옆으로 움직이기만 해도 정체 시간이 초기화된다. `lib/game/entities/player.dart:290`
- `nearestWalkable()`은 한 칸만 검사하지만 실제 플레이어 충돌은 몸 반경 네 모서리를 검사한다. 목적지 보정에는 성공하고 실제 이동은 실패할 수 있다. `lib/game/level/level_map.dart:195`, `lib/game/entities/player.dart:345`
- 방화벽은 통행 가능 타일이어서 비용 개념이 없는 직선 이동은 위험 구역도 그대로 가로지른다. `lib/game/level/level_map.dart:149`
- 키보드와 조이스틱은 서로 더한 뒤 정규화한다. 두 입력이 정확히 반대로 상쇄되면 수동 조작이 클릭 목표를 취소하지 못하고 자동 이동이 계속될 수 있다. `lib/game/action_rpg_game.dart:391`

1km 전체에 단일 A*를 돌릴 필요는 없다. [판단] 먼저 직선 가시성 검사를 하고 막힌 경우에만 제한된 로컬 격자에서 경로를 구하며, 장거리 입력이 추가되면 40타일 도로망이나 청크 그래프를 상위 경로로 쓰는 계층형 방식이 이 월드 구조에 맞다. 도로가 연결성을 보장한다는 설계 근거는 `GAME-DESIGN.md:228`에 있다.

### 30인 렌더링 성능

[분석 추산] 정상 방향 하나는 프레임별 조건에 따라 본체 약 25~40개 Canvas 도형과 그림자 1개를 그리고, 그림자를 포함해 약 3~6개의 `MaskFilter.blur`를 사용한다. `lib/game/entities/cyborg_renderer.dart:105`, `lib/game/entities/cyborg_renderer.dart:305`, `lib/game/entities/iso_entity.dart:55`

| 상황 | 본체 렌더 수 | 도형 명령 추산 | 블러 추산 | `saveLayer` |
|---|---:|---:|---:|---:|
| 정상 1명 | 1 | 26~41 | 3~6 | 0 |
| 정상 30명 | 30 | 780~1,230 | 90~180 | 0 |
| 최대 잔상 포함 1명 | 최대 13 | 325~520 | 39~78 | 최대 12 |
| 30명이 동시에 최대 잔상 | 최대 390 | 9,750~15,600 | 1,170~2,340 | 최대 360 |

[추측] 중급 모바일의 작은 캐릭터 기준 정상 1명은 약 0.1~0.4ms, 30명은 캐릭터만 약 3~12ms 범위일 가능성이 있다. 60fps의 16.6ms 중 지형·몬스터·UI까지 남겨야 하므로 30명은 안전 판정을 내릴 수 없고, 집단 대시는 30ms를 쉽게 넘을 가능성이 높다. 실제 `FrameTiming.rasterDuration` 측정값은 현재 자료에 없다.

전체 프레임을 `ui.Image`로 캐시하는 것도 그대로 채택하기 어렵다. [분석 가정: 64×128 RGBA, 보행 8프레임+대기 1프레임]

- 64방향 × 9프레임 × 2종 = 1,152장: 1x 약 36MiB, 2x 약 144MiB.
- 256방향 × 9프레임 × 2종 = 4,608장: 1x 약 144MiB, 2x 약 576MiB.
- [추측] `ui.Picture`가 장당 2~4KiB라면 각각 약 2.3~4.5MiB, 9~18MiB지만, 256방향 워밍업에 약 14만~18만 개 도형 명령을 기록해야 하고 재생 시 블러 래스터 비용은 남는다.

따라서 로컬 캐릭터는 연속각을 유지하고, 원격 캐릭터는 32~64방향의 정적 장갑 레이어만 `Picture`로 캐시하며 코어·바이저·보행 관절은 동적으로 그리는 분리가 적합하다. `quantizeYaw()`도 원래 캐시 적중을 위한 함수로 마련돼 있다. `lib/game/iso.dart:114`

## 4. 리스크 · 함정

- 여성형을 선택해도 `ActionRpgGame`이 `character.kind`를 전달하지 않아 인게임은 기본 `CyborgDesign.assault`가 된다. 현재 “같은 그림”이라는 주석과 실제 데이터 흐름이 충돌한다. `lib/main.dart:64`, `lib/game/entities/player.dart:26`
- 렌더러의 깊이비·관절비·코어 크기·공통 색이 `CyborgDesign` 밖에 있어 프레임 추가 시 렌더러 분기가 계속 늘어날 위험이 있다. `lib/game/entities/cyborg_renderer.dart:26`, `lib/game/entities/cyborg_renderer.dart:305`
- 연속 수학식이 회전의 부드러움은 주지만, 바이저·등 장비의 이산 가시성 때문에 오히려 정면/측면/후면 경계에서 팝이 발생할 수 있다. `lib/game/entities/cyborg_renderer.dart:373`, `lib/game/entities/cyborg_renderer.dart:614`
- 적/PC 탭을 바닥 탭과 구분하지 않으면 향후 PK에서 공격하려던 탭이 적 앞으로 이동하거나 상대를 통과하는 명령이 된다. `lib/game/input/click_move.dart:28`, `lib/game/action_rpg_game.dart:709`
- 원격 플레이어를 현재 `Player` 렌더 구조로 그대로 복제하면 대시 잔상 `saveLayer`가 동시 전투에서 가장 큰 성능 폭탄이 된다. `lib/game/entities/player.dart:257`, `lib/game/entities/player.dart:798`
- 스냅샷 테스트는 시각 회귀를 자동 판정하지 않으며 8방향만 확대 배율 1.9로 본다. 실제 32~64px 읽힘과 측면 경계 팝을 검출하지 못한다. `test/cyborg_render_snapshot_test.dart:56`
- 저장소의 `.cowork/cowork-prompt.md:25`는 현재 비주얼 요청이 아니라 이전 HP 재설계 과제를 담고 있다. `GAME-DESIGN.md:169`도 아직 8방향 불리언 방식으로 설명하고 조작표에서 클릭 이동을 누락한다(`GAME-DESIGN.md:501`). 코드와 지침의 동시 편집 불일치가 다음 분석을 잘못 유도할 수 있다.

## 5. 권고안

| 순위 | 권고 | 범위 | 근거 | 리스크 |
|---|---|---|---|---|
| 1 | `character.kind → CyborgKind.fromId() → CyborgDesign → ActionRpgGame → Player` 전달을 복구하고, 재시작 시에도 같은 디자인을 보존한다. 외형 상수·공통 색·코어 크기·깊이비도 `CyborgDesign` 프로필로 이동한다. | `main.dart`, `action_rpg_game.dart`, `cyborg_design.dart`, `cyborg_renderer.dart` | `lib/main.dart:64`, `lib/game/action_rpg_game.dart:225`, `lib/game/entities/cyborg_renderer.dart:32` | 생성자·캐시 키·오프라인 기본값을 함께 갱신해야 한다. |
| 2 | 팔·다리를 어깨/팔꿈치/손, 골반/무릎/발의 3D 로컬 관절점으로 정의하고 yaw 회전 후 각 세그먼트를 깊이 정렬한다. 몸통은 가슴·허리·골반의 타원 단면 여러 개로 앞/옆/뒤 면을 만든다. | 절차적 캐릭터 리그·회전 | `lib/game/entities/cyborg_renderer.dart:83`, `lib/game/entities/cyborg_renderer.dart:119`, `lib/game/entities/cyborg_renderer.dart:793` | 도형 수가 늘 수 있으므로 성능 권고와 함께 적용해야 한다. |
| 3 | VULCAN은 비대칭 대형 견갑·전완·척추팩, WRAITH는 회전 가능한 포니테일·골반 핀·가느다란 분절 하체를 큰 실루엣으로 강화한다. 관절마다 2~3px 짙은 간격을 두고 흉골 y 좌표와 미사용 `neckLength`를 바로잡는다. | 아트 디렉션·`CyborgDesign` | `lib/game/entities/cyborg_design.dart:138`, `lib/game/entities/cyborg_design.dart:175`, `lib/game/entities/cyborg_renderer.dart:284` | 과장된 비율이 선택 화면에서 지나치게 커 보이지 않도록 두 배율을 함께 검수해야 한다. |
| 4 | 탭 라우터를 UI → 적/PC/상호작용 객체 → 빈 지면 순으로 명시한다. 적 탭은 이동 목표가 아니라 사거리 진입 후 공격하는 `attack-move`, PC 탭은 PK 규칙과 안전지대 판정을 따르게 한다. | 입력·전투 의도·PK | `lib/game/input/click_move.dart:12`, `lib/game/entities/enemy.dart:399`, `lib/game/action_rpg_game.dart:709` | 모바일에서 작은 대상의 탭 허용 반경이 과하면 오조작이 늘어난다. |
| 5 | 직선 가시성 성공 시 현재 이동을 유지하고, 실패할 때만 몸 반경과 방화벽 비용을 반영한 제한 영역 A*를 실행한다. 정체는 이동량 대신 목표까지 남은 거리로 판정하고 취소 전에 재탐색한다. | `Player`, `LevelMap`, 클릭 경로 | `lib/game/entities/player.dart:293`, `lib/game/level/level_map.dart:149`, `lib/game/level/level_map.dart:195` | 100만 타일 전역 탐색은 금지하고 로컬/청크 계층으로 예산을 제한해야 한다. |
| 6 | 로컬 본체는 연속각·전체 효과, 원격 본체는 32~64방향 정적 `Picture` 캐시와 축소된 동적 발광을 사용한다. 대시 잔상은 2~4개 단순 실루엣으로 제한하고 잔상마다 전체 본체와 `saveLayer`를 재실행하지 않는다. | 렌더링 성능 | `lib/game/entities/player.dart:739`, `lib/game/entities/player.dart:798`, `lib/game/iso.dart:114` | 캐시 무효화 키에 디자인·방향·포즈가 빠지면 잘못된 몸체가 재사용된다. |
| 7 | 16~32방향 경계 스냅샷, 최소 카메라 배율 32~64px 골든, 여성형 선택→인게임 전달, 적/UI 탭 우선순위, 1명/30명/집단 대시 프레임 벤치마크를 검수 기준으로 둔다. | 테스트·성능 검증 | `test/cyborg_render_snapshot_test.dart:19`, `lib/game/action_rpg_game.dart:230` | 플랫폼별 안티앨리어싱 차이로 골든 허용 오차가 필요하다. |

## 6. 불확실 · 미확인

- 읽기 전용 규칙에 따라 `flutter analyze`, 테스트, 스냅샷 생성, 프리뷰 실행은 수행하지 않았다. 현재 코드의 컴파일 성공 여부는 미확인이다.
- 저장된 캐릭터 PNG나 실제 실행 프레임이 없으므로 회전·실루엣 평가는 Canvas 수식과 도형 좌표에 근거한 정적 판정이다.
- 프레임당 ms는 대상 기기·Flutter 렌더 백엔드·DPR 자료가 없어 `[추측]` 범위로만 제시했다. 최종 성능 판정에는 최소 사양 기기의 UI/raster 타임라인이 필요하다.
- 사람 눈이 구분하는 방향 수에는 단일 보편값이 없다. 본 보고서의 32~64방향 판단은 현재 25~34px 폭과 최소 0.55 배율에서 생기는 픽셀 이동량에 근거한 프로젝트 한정 판단이다.
- 실시간 원격 플레이어와 PK가 아직 클라이언트에 연결되지 않아, 30인 렌더링·PC 탭·동적 충돌 정책은 실제 네트워크 컴포넌트가 생긴 뒤 다시 확인해야 한다. `GAME-DESIGN.md:678`
- 분석 중 다른 세션이 같은 파일을 수정하는 상태였으며, 저장소의 `.cowork/cowork-prompt.md`와 `GAME-DESIGN.md`도 현재 요청·코드보다 뒤처져 있다. 최종 구현 직전 최신 파일 기준 재검증이 필요하다.
