<!-- cowork:claude | 2026-08-04 21:23:17 | exit=0 | 638s -->
# claude 분석 — character-visual-upgrade

> 요청: 남성/여성 캐릭터를 더 멋있게 비주얼 적 디자인을 해 주세요.

1) 남성/여성 캐릭터 비주얼적 디자인을 더 예쁘고, 멋지고, 화려하게 해 주세요.
2) 클릭으로 이동할 수 있도록 해 주세요.
3) 정적 애셋이 아닌, 동적 캐릭터 생성이므로 방향은 256 방향으로 할 수 있나요? 최대한 방향을 많이 해 주세요.
> 생성: 2026-08-04 21:23:17 · 소요 638s · 읽기 전용 분석(작업공간 미수정)

---



## 1. 결론 요약

세 요구 중 **2)·3)은 배선은 깔렸으나 목적을 달성하지 못했고, 1)은 아직 시작 단계다.** 방향은 `facingYaw()`가 연속 실수를 주므로 "256 방향"을 액면상 이미 초과하지만, 회전이 부드럽게 느껴지지 않는 진짜 원인은 방향 수가 아니라 세 가지다 — ① `facing`이 보간 없이 **즉시 스냅**하고(`player.dart:265`, `player.dart:313`), ② `_View.project()`가 계산한 깊이를 **화면 y에 전혀 반영하지 않아** 회전이 "폭만 줄었다 늘었다"로 보이며, ③ `strideProjection = sin(yaw)` 탓에 **정면·후면(yaw≈0, π)에서 보폭이 정확히 0**이 되어 걸음이 사라진다.

가장 시급한 것은 방향도 비주얼도 아니다. **캐릭터 선택 화면에서 고른 프레임이 게임으로 전달되는 경로가 아예 없다** — `action_rpg_game.dart:226`이 `Player(grid: …)`만 호출하므로 여성형(WRAITH)을 골라도 게임에서는 항상 남성형(VULCAN)이 나온다. 요구 1)의 전제가 무너진 상태다.

클릭 이동은 동작하지만 세 곳이 깨져 있다 — 안내선(`MovePathHint`)이 **지면 아래 우선순위**라 화면에 보이지 않고, 조이스틱은 `TapCallbacks`가 없어 **조이스틱을 탭하면 캐릭터가 화면 좌하단으로 걸어가며**, 적을 탭하면 공격이 아니라 이동만 된다.

---

## 2. 근거

- `lib/game/action_rpg_game.dart:226` — `return Player(grid: map.respawnPoint())..restoreProgress(…)`. `design:` 인자가 없다. `Player`의 기본값은 `player.dart:28`의 `CyborgDesign.assault`(남성형). 재시작 경로(`action_rpg_game.dart:1194`)도 같다.
- `lib/main.dart:74-82` — `ActionRpgGame(onLogout:…, sync:…, leaderboard:…, startLevel:…, startXp:…)`. 캐릭터 종류를 넘기는 인자가 없고, `action_rpg_game.dart:58-66`의 생성자에도 그런 파라미터가 정의돼 있지 않다. `character.kind`는 `character_select_screen.dart:212`에서만 쓰인다.
- `lib/game/entities/player.dart:265` — 키보드·조이스틱: `facing.setFrom(dir)`. `player.dart:313` — 클릭 이동: `facing.setFrom(dir)`. 둘 다 즉시 대입이라 각속도 제한이 없다. 대조적으로 `lib/game/entities/enemy.dart:187`은 `facing.lerp(toPlayer.normalized(), (dt * 4).clamp(0.0, 1.0))`로 **적만 부드럽게 돈다.**
- `lib/game/entities/cyborg_renderer.dart:833-840` — `project()`는 `(x, depth)`만 반환한다. 호출부 전체(`_drawLegs:124`, `_drawShoulders:443`, `_armsByDepth:485`, `_drawHead:615,672,690`, `_drawBackRig:374,400`)를 확인했으나 **`depth`를 화면 y 오프셋으로 쓰는 곳이 한 군데도 없다.** 정렬(`sort`)과 가시성 판정(`if (p.depth > 0)`)에만 쓰인다.
- `lib/game/entities/cyborg_renderer.dart:136` — `final stride = leg.phase * 5 * view.strideProjection;`, `cyborg_renderer.dart:808` — `double get strideProjection => _sin;`. `yaw = 0`이면 `sin(0) = 0` → **정면에서 stride = 0**. 보행 중 다리가 전혀 벌어지지 않는다. `yaw = π`(후면)도 동일.
- `lib/game/entities/cyborg_renderer.dart:441-446` — 어깨 패드를 `project(±π/2, radius, depth)`로 배치. `yaw = π/2`(완전 측면)를 대입하면 `x = radius·(±1)·cos(π/2) + depth·cos(±π/2)·sin(π/2) = 0` — **두 어깨의 화면 x가 정확히 같아진다.** 팔(`_armsByDepth:485`)·다리(`_drawLegs:124`)도 같은 구조라 측면에서 좌우 한 쌍이 완전히 겹친다.
- `lib/game/input/click_move.dart:94` — `MovePathHint() : super(priority: -999999);` vs `lib/game/level/ground_layer.dart:37` — `GroundLayer(this.map) : super(priority: -100000);`. Flame은 priority 오름차순으로 그리므로 안내선(-999999)이 먼저, 지면(-100000)이 나중에 그려진다. `ground_layer.dart:30-34` 주석대로 지면은 청크를 `ui.Picture`로 구워 칠하는 불투명 레이어다 → **안내선은 지면에 완전히 덮인다.**
- `~/.pub-cache/hosted/pub.dev/flame-1.38.0/lib/src/components/input/joystick_component.dart:19-20` — `class JoystickComponent extends PositionComponent with HasGameReference, ComponentViewportMargin, DragCallbacks`. **`TapCallbacks`가 없다.** 반면 `lib/game/ui/touch_controls.dart:17,63`의 `ActionButton`은 `TapCallbacks`를 쓰고 `event.handled = true`를 명시한다. 따라서 액션 버튼 탭은 막히지만 **조이스틱 위 탭은 `ClickMoveLayer`로 그대로 내려간다**(`click_move.dart:19-31`).
- `lib/game/entities/enemy.dart:26` — `class Enemy extends IsoEntity with Damageable`. `TapCallbacks`가 없다(`lib/game/` 전체 grep으로 확인). 적을 탭하면 `ClickMoveLayer`가 받아 그 지점으로 걸어간다.
- `lib/game/entities/enemy.dart:412` — `if (!facesRight(facing)) canvas.scale(-1, 1);`. 적은 **좌/우 2방향 플립**뿐이다. 플레이어만 연속 방향이라 같은 화면에서 방향 표현이 이원화돼 있다.
- `lib/game/iso.dart:118-123` — `quantizeYaw()`는 정의돼 있으나 저장소 전체 grep 결과 **`lib/` 안에 호출처가 없다.** `facingOctant()`(`iso.dart:126`)·`facesDown()`(`iso.dart:98`)도 미사용이며, `cyborg_renderer.dart:774`의 `drawPreview()`도 호출처가 없는 죽은 코드다.
- `lib/game/entities/cyborg_design.dart:159-163` vs `:199-203` — 남성형과 여성형의 `accent`·`accentSoft`·`armorBase`·`armorLight`·`visorColor`가 **다섯 개 모두 동일한 팔레트 상수**다. 주석(`:196-198`)이 의도적 선택임을 밝히고 있다.
- `lib/game/ui/cyborg_preview.dart:53-60`과 `lib/auth/cyborg_portrait.dart:121` — 둘 다 `drawBody(…)`에 **`time:`을 넘기지 않는다.** `cyborg_renderer.dart:70`의 `pulse = 0.72 + 0.28·sin(time·3.2)`가 0.72로 고정돼, 선택 화면·프리뷰에서는 코어가 맥동하지 않는다. `player.dart:830`만 `time: _animTime`을 넘긴다. 추가로 `cyborg_portrait.dart:121`은 `baseY: breath`(양수), `player.dart:827`은 `baseY: -bob`(음수)로 **호흡 부호가 반대**다.
- `lib/game/entities/cyborg_renderer.dart` 내 `MaskFilter.blur` 사용처 5곳(`:179` 부츠 밑창, `:317` 코어 후광, `:324` 코어 본체, `:409` 척추 레일, `:630` 바이저) + `lib/game/entities/iso_entity.dart:67`(그림자) — 캐릭터 1명당 실행 횟수는 **남성형 6회 / 여성형 7회**(부츠는 다리 2개라 2회).
- `lib/game/entities/player.dart:257-259, 788-806` — 대시 중 프레임마다 `_DashGhost`를 최대 12개까지 쌓고, `_renderGhost`가 고스트 하나마다 `canvas.saveLayer(…)` + `_drawFrame()` 전신 재드로잉을 한다. **대시 중인 캐릭터 1명 = 최대 13회 전신 드로잉 + 12회 오프스크린 레이어.**

---

## 3. 상세 분석

### 3.1 요구 3) "256 방향" — 액면 충족, 목적 미달

**액면상은 이미 충족을 넘어섰다.** `facingYaw()`(`iso.dart:108-112`)가 `atan2` 결과를 그대로 돌려주고, `player.dart:826`이 그 값을 양자화 없이 `drawBody(yaw:)`에 전달한다. `quantizeYaw()`는 호출되지 않는다. 렌더러 주석(`cyborg_renderer.dart:12-17`)의 주장은 사실이다.

**그런데 사람이 원한 것은 "방향 수"가 아니라 "부드럽게 도는 느낌"이다.** 그 관점에서 세 가지가 목적을 깎는다.

**(a) 회전 보간이 없다.** `facing.setFrom(dir)`은 각속도 무제한이다. 조이스틱을 반대로 홱 꺾으면 캐릭터는 한 프레임(16.6ms)에 180° 돈다. 방향 해상도가 무한이어도 **시간축 샘플이 1개**면 부드러움은 생기지 않는다. 적(`enemy.dart:187`)이 `lerp(…, dt*4)`로 도는 것과 대조적이라, 같은 화면에서 적이 플레이어보다 부드럽게 도는 역전이 일어난다.

**(b) 깊이가 화면 y로 내려오지 않는다.** 이것이 회전이 어색해 보이는 **핵심 원인**이다. `project()`는 타원기둥 위의 점을 회전시켜 `x`와 `depth`를 정확히 계산하지만(`cyborg_renderer.dart:833-840`), 반환된 `depth`는 그리는 순서와 가시성 판정에만 소비된다. 카메라가 위에서 내려다보는 아이소메트릭 씬에서 **앞에 있는 것은 화면에서 아래로 내려와야 한다.** 2:1 다이메트릭의 카메라 고각은 `atan(0.5) ≈ 26.57°`이므로, 깊이 `d`인 부위는 화면 y로 약 `-d·sin(26.57°) ≈ -0.447·d`만큼 이동해야 한다. 지금은 이 항이 0이다.

결과적으로 회전은 "각 부위가 좌우로 미끄러지고 폭이 줄어드는" 2D 변형으로만 읽힌다. 부위별로 무너지는 지점을 짚으면:

| 부위 | 무너지는 시선각 | 증상 | 근거 |
|---|---|---|---|
| **다리** | yaw ≈ 0, π (정면·후면) | 보폭이 **정확히 0**. 걷는데 다리가 붙어 있고 상하 반동(`bob`)만 남는다 | `cyborg_renderer.dart:136`, `:808` |
| **어깨·팔·다리(쌍)** | yaw ≈ ±π/2 (완전 측면) | 좌우 한 쌍의 화면 x가 **같아져 완전히 겹친다.** 실루엣이 한 짝 분량으로 좁아짐 | `cyborg_renderer.dart:441-446`, `:483-495`, `:122-128` |
| **팔(무기측)** | 전 구간 | `phase: 0` 고정이라 절대 흔들리지 않고, `armTop`·`armLength`가 yaw와 무관해 앞뒤 움직임이 없다 | `cyborg_renderer.dart:492`, `:510-511` |
| **팔(비무기측)** | 전 구간 | `armSwing`을 **y 오프셋**으로만 쓴다(`armTop + arm.phase`) — 팔이 앞뒤가 아니라 위아래로 펌프질한다 | `cyborg_renderer.dart:516` |
| **머리·목** | 전 구간 | 헬멧은 `Rect.fromCenter(center: Offset(0, cy))`, 목은 `Rect.fromLTRB(-w, …, w, …)` — **x가 0 고정.** 폭만 줄어들고 머리가 축을 따라 도는 느낌이 없다 | `cyborg_renderer.dart:589`, `:561` |
| **포니테일** | yaw ≈ ±π/2 | 길이·퍼짐이 `depth`의 선형 함수라(`:716-718`) 측면에서 중간 길이로 어정쩡하게 걸린다. 뒤통수에서 뻗는 곡선의 **방향**이 항상 화면 왼쪽 아래(`p.x - spread·1.4`)로 고정 | `cyborg_renderer.dart:714-734` |
| **안테나** | 전 구간 | 팁 오프셋이 `(-3, -10)` 하드코딩이라 뒤를 봐도 항상 화면 왼쪽으로 꺾인다 | `cyborg_renderer.dart:692` |
| **등 장비** | yaw ≈ ±π/2 | 동력팩 폭이 `facingAmount`(=`|cos yaw|`)에 비례해 측면에서 폭 4px까지 줄어든다. 등에서 튀어나온 **두께**로 보여야 할 것이 사라진다 | `cyborg_renderer.dart:376` |

**(c) 방향 해상도의 실효 상한.** 사람 눈의 한계는 픽셀로 따지는 게 정확하다. 캐릭터 폭이 화면 `W`px일 때 yaw가 `Δ`rad 변하면 부위의 화면 x는 최대 `(W/2)·Δ` 움직인다. 1px 미만은 안티에일리어싱에 흡수된다. 남성형 `shoulderWidth = 34`(`cyborg_design.dart:147`), 카메라 zoom은 `screenSize.y / 760`을 0.55~1.6로 clamp(`action_rpg_game.dart:230-234`)이므로 표준 화면(높이 800)에서 `W ≈ 36px`. 1px 이동에 필요한 `Δ = 2/36 = 0.056 rad = 3.2°` → **한 바퀴 약 113 방향**이 픽셀 단위 구분 한계다. 서브픽셀 밝기 변화까지 세면 2~3배(≈250~340)까지 감지 여지가 있으므로 **256은 "충분하고 낭비 없는" 숫자**다. 그 이상은 확실히 무의미하다. [추측] 서브픽셀 감지 배수는 이 프로젝트에서 측정된 값이 아니라 안티에일리어싱의 일반적 성질에 기댄 추정이다.

**판정: "256 방향" 요구는 입력 층위에서는 이미 충족됐다. 사람이 체감할 미달분은 전부 (a) 회전 보간 부재와 (b) 깊이→y 미반영에서 나온다. 방향 수를 더 늘리는 작업은 이득이 0이다.**

### 3.2 요구 1) 비주얼 — "화려함"보다 먼저 깨진 것

**전제가 무너져 있다.** §2 첫 두 항목대로, 선택한 프레임이 게임에 전달되지 않는다. 여성형을 아무리 다듬어도 플레이 중에는 보이지 않는다.

SSOT 자체는 지켜졌다 — `cyborg_portrait.dart:121`·`cyborg_preview.dart:53`·`player.dart:823`이 모두 `CyborgRenderer.drawBody`를 호출하고, `player.dart`에 남아 있던 자체 렌더링은 사라졌다. 다만 **호출 인자가 세 곳에서 제각각**이다: 게임만 `time:`을 넘기고, 초상화는 `baseY` 부호가 반대다. 결과적으로 선택 화면에서는 코어가 맥동하지 않고 호흡이 반대로 간다.

아트 디렉션 관점에서 지금 부족한 것은 **발광의 양이 아니라 읽힘(readability)**이다. 32~64px로 줄었을 때 살아남는 요소만 세면:

- **남녀 구분 단서가 실루엣 하나뿐.** 색 다섯 개가 전부 같다(`cyborg_design.dart:159-163` ≡ `:199-203`). 어깨 폭 34 vs 25, 키 108 vs 102 — 어깨/키 비율 0.315 vs 0.245가 유일한 구분점이다. 32px로 줄면 어깨 폭 차이는 약 2.6px. 포니테일(`_drawPonytail`)이 실질적으로 유일하게 남는 단서다.
- **실루엣에 마디가 없다.** 돌출부는 어깨 패드뿐인데 여성형은 `shoulderPadSize: 6.5`(`cyborg_design.dart:193`)라 거의 실루엣을 만들지 못한다. 나머지는 매끈한 원기둥의 조합이라 축소하면 막대 두 개로 뭉친다.
- **완전 좌우 대칭.** 비대칭 요소(한쪽 어깨 캐논, 한쪽 팔 대형 건틀릿, 흩날리는 천/케이블)가 하나도 없다. 대칭 실루엣은 축소 시 정보량이 절반이다.
- **여성형이 모래시계가 아니다.** `hipWidth: 18 == chestWidth: 18`(`cyborg_design.dart:184,187`). 허리만 13.5로 좁고 골반이 가슴과 같아, 실루엣이 "잘록한 원통"이지 모래시계가 아니다. `torsoTaper: -0.32`로 계산하면 베지에 제어점이 6.12, 허리 반폭이 6.75 — 곡률 차이가 0.63px에 불과해 정면에서 잘록함이 거의 보이지 않는다.
- **밝은 배경에 어두운 몸인데 밝은 림라이트를 둘렀다.** `cyborg_renderer.dart:262-268`이 실루엣 경계에 `accent`(#00E5FF, 밝음) stroke를 두른다. 어두운 배경에서는 몸을 배경에서 떼어내는 정석이지만, 배경이 #F7FCFF인 이 프로젝트에서는 **어두운 몸(#17364F)과 밝은 배경 사이에 중간 밝기의 띠를 끼워 넣어 경계 대비를 낮춘다.** 헬멧(`:597-603`)도 같다. 밝은 배경에서 실루엣을 세우는 정석은 반대 방향 — 바깥에 더 어두운 아웃라인, `accent`는 몸 **안쪽** 라인과 코어에만.
- **디테일이 축소에서 전멸한다.** 바이저 높이 `hh·0.3 = 5.7px`, 주사선 두께 1.2px, 안테나 팁 반지름 1.8px, 흉골 갈비 3줄 간격 5px. zoom 0.55에서 각각 3.1px / 0.66px / 1.0px / 2.75px — 절반이 서브픽셀로 사라진다. 지금의 "화려함"은 **프리뷰 배율(2.0x, `cyborg_preview.dart:285`)에서만 성립**한다.

### 3.3 요구 2) 클릭 이동 — 동작하되 세 곳이 깨짐

구조 자체는 견고하다. `ClickMoveLayer`를 월드 최하단(`priority: -1000000`)에 깔아 UI가 먼저 탭을 가져가게 한 설계(`click_move.dart:12-18`)는 옳고, 입력 우선순위도 정확하다 — `player.dart:260-263`이 `moveInput`이 들어오는 즉시 `clearMoveTarget()`을 부르므로 **키보드·조이스틱이 항상 클릭을 이긴다.** 요구사항 6(기존 조작 유지)은 지켜졌다.

깨진 곳:

1. **안내선이 보이지 않는다.** `MovePathHint`(-999999)가 `GroundLayer`(-100000)보다 먼저 그려져 지면이 통째로 덮는다. 코드는 정상 실행되지만 화면에는 아무것도 안 남는다.
2. **조이스틱 탭이 새어 나간다.** Flame의 `JoystickComponent`에 `TapCallbacks`가 없어, 조이스틱 배경을 짧게 누르면(드래그 없이) 탭이 `ClickMoveLayer`까지 내려간다. 조이스틱은 좌하단 여백 40px에 반경 62px(`action_rpg_game.dart:249-251`)이므로, 캐릭터가 화면 좌하단에 대응하는 월드 지점으로 걸어간다. **모바일에서 조이스틱을 잡으려다 놓칠 때마다 발생한다.**
3. **적을 탭하면 이동만 된다.** `Enemy`에 `TapCallbacks`가 없으므로 적 위 탭도 `ClickMoveLayer`가 받는다. 클릭 이동을 도입한 게임에서 사용자가 가장 먼저 시도하는 조작이 "적 클릭 = 공격"인데, 지금은 적에게 걸어가 멈춘다. PK 상황에서도 같아, 다른 플레이어를 탭하면 공격 의사가 이동으로 오인된다.

경로 탐색이 없는 점은 **1km 월드에서 치명적이지 않다.** 목표는 화면 안만 찍을 수 있고(월드 좌표는 뷰포트 안에서만 나온다), 화면 반경은 약 380px ÷ 64px/타일 ≈ 6타일이므로 한 번의 탭으로 가는 거리가 짧다. 장거리는 `teleport_sheet.dart`가 담당하는 구조다. 다만 이 때문에 **클릭 이동만으로 월드를 횡단하려면 탭을 수백 번 해야 한다** — 클릭 이동은 "근거리 정밀 이동", 이동은 조이스틱·텔레포트라는 역할 분담을 UI가 알려주지 않는다.

경계 조건 하나: `_stuckTime` 판정(`player.dart:291`)은 `progressed < speed·dt·0.25`인데, 도착 감속(`arrive`, `player.dart:316`)이 걸린 구간에서 벽에 한 축이 막히면 실제 이동량이 `0.317 × 0.707 ≈ 0.224 < 0.25`가 되어 조기 포기할 수 있다. [추측] 실제 재현 여부는 확인하지 못했다.

### 3.4 성능 — 30명 동시 표시

측정하지 않았으므로 드로우콜과 blur 호출 수만 세고, ms는 [추측]으로 표시한다.

**캐릭터 1명당 (평상시, 정면):**
- 드로우콜 약 **35~45회**(등 장비 2~5, 팔 3, 다리 6~8, 골반 1, 몸통 3, 몸통 디테일 3~7, 어깨 2~4, 목 1, 머리 약 12, 포니테일 2)
- `MaskFilter.blur` **6회(남성) / 7회(여성)** — 그림자 1 + 부츠 밑창 2 + 코어 2 + 바이저 1 (+ 여성 척추 레일 1)
- `clipPath`/`clipRRect` 2회(`:255`, `:635`)

**30명이면 드로우콜 1050~1350, blur 180~210회/프레임.** 이 중 원·라운드렉트에 걸린 blur(코어 2, 바이저 1)는 Skia의 analytic blur 경로를 타 상대적으로 싸지만, **`drawLine` + blur(부츠 밑창 2회, 척추 레일 1회)는 일반 경로**라 오프스크린 마스크를 만든다. 캐릭터당 2~3회 × 30명 = **60~90회의 오프스크린 왕복**이 가장 비싼 항목이다. [추측] 16.6ms 예산 대비 실제 소모량은 측정 없이 단정할 수 없다.

**대시가 최악의 경우다.** 캐릭터 1명이 대시하면 고스트 12개 × (`saveLayer` + 전신 드로잉)이 추가돼 **드로우콜 500+, `saveLayer` 12회**로 뛴다. `saveLayer`는 전체 크기 140×160 오프스크린을 할당하고 `ColorFilter`를 적용한 뒤 합성한다(`player.dart:793-802`). PK 난전에서 여러 명이 동시에 대시하면 이 비용이 선형으로 쌓인다. **현재 코드에서 30명 동시 표시를 가정하면 가장 먼저 터질 지점이다.**

**런타임 이미지 캐시는 권하지 않는다** — 수치가 성립하지 않는다. 캐릭터 렌더 영역 약 60×130px, devicePixelRatio 2 기준 120×260 RGBA = **124.8 KB/장**:

| 방향 × 보행프레임 × 프레임종류 | 장수 | 메모리 (dpr 2) | 워밍업 |
|---|---|---|---|
| 256 × 8 × 2 | 4096 | **511 MB** | 불가 |
| 64 × 8 × 2 | 1024 | **128 MB** | 약 4만 드로우콜 |
| 32 × 4 × 2 | 256 | **32 MB** | 약 1만 드로우콜, 프레임당 3장씩 구우면 ≈1.4초 |

32방향으로 떨어뜨려야 메모리가 감당되는데, 그 순간 §3.1에서 확인한 "연속 방향"이라는 이 프로젝트의 유일한 우위를 버리게 된다. `ui.Picture` 캐시(벡터 명령 기록)는 래스터화를 피하지 못하므로 blur 비용이 그대로 남아 이득이 거의 없다.

**대신 값이 있는 캐싱은 "blur 결과만 굽는 것"이다.** 코어 후광, 부츠 밑창 발광, 바이저 글로우는 **모양이 고정이고 색·알파만 변한다.** 각각 64×64 RGBA 한 장(16 KB)으로 앱 시작 시 코드로 구워 두고 `drawImageNine`/`drawImage` + `ColorFilter`로 찍으면, 캐릭터당 blur 호출을 **6~7회 → 0회**로 줄이면서 총 메모리는 **약 50 KB**다. 이는 "에셋 없는 프로그래매틱 렌더링" 원칙을 깨지 않는다 — 스프라이트 시트를 도입하는 게 아니라, 같은 코드가 그린 결과를 런타임에 한 번 굽는 것이다.

---

## 4. 리스크 · 함정

- **`project()`에 y 항을 더하는 변경은 렌더러 전역에 영향을 준다.** `_Limb`가 `x`·`depth`만 들고 있어(`cyborg_renderer.dart:844-863`) 시그니처가 바뀌고, `_drawLegs`·`_drawShoulders`·`_drawArm`·`_drawHead`·`_drawBackRig` 호출부 전부를 손대야 한다. 잘못하면 지면 접지(발이 땅에 닿는 y)가 어긋나 캐릭터가 떠 보인다 — **발은 항상 `y.foot`에 고정하고 상체 부위에만 y 오프셋을 주는 방식이 안전하다.**
- **`facing`에 각속도 제한을 걸면 근접 공격 판정 방향이 바뀐다.** `_resolveMeleeHit`(`player.dart:373-380`)이 `facing`으로 전방 120° 부채꼴을 판정하므로, 회전 보간을 넣으면 홱 돌아서 때릴 때 판정이 뒤늦게 따라온다. **판정용 방향(즉시)과 렌더용 방향(보간)을 분리**해야 조작감이 유지된다. `tryDash`(`player.dart:178-180`)와 `tryShoot`(`player.dart:156`)도 `facing`을 직접 읽는다.
- **`MovePathHint`의 priority를 올리면 캐릭터·구조물보다 위로 갈 수 있다.** 지면(-100000)보다 위, 엔티티(월드 중앙 기준 약 +100000)보다 아래인 구간에 놓아야 한다. 엔티티 priority가 `(gx+gy)*100`(`iso.dart:70-72`)이라 **위치에 따라 값이 변하므로 고정 상수로는 항상 아래에 둘 수 없다** — 안내선을 지면 직후로만 올리거나, `MoveMarker`처럼 `IsoEntity`로 만들어 깊이 정렬에 참여시켜야 한다.
- **적에 `TapCallbacks`를 붙이면 클릭 이동이 적 뒤의 땅에 닿지 않는다.** 적이 밀집한 곳에서는 "적 사이 빈 땅으로 이동"이 불가능해진다. 탭을 소비하지 말고 `event.handled`를 두지 않은 채 게임에 "적이 탭됐다"만 알리는 방식이거나, 사거리 밖이면 이동으로 폴백하는 처리가 필요하다.
- **조이스틱 탭 누출을 막으려고 `ClickMoveLayer`에서 화면 좌표를 검사하면 좌표계가 꼬인다.** `ClickMoveLayer`는 월드 컴포넌트라 `event.localPosition`이 월드 좌표다(`click_move.dart:29-30`). 조이스틱 영역은 뷰포트 좌표라 직접 비교할 수 없다. 조이스틱을 감싸는 `TapCallbacks` 래퍼를 두는 쪽이 좌표 변환 없이 끝난다.
- **`Player`에 `design`을 배선할 때 서버 상태와 어긋날 수 있다.** `character.kind`는 서버가 들고 있고(`character_select_screen.dart:212`), `CyborgKind.fromId`는 모르는 값이면 `male`로 떨어진다(`cyborg_kind.dart:47-53`). 게임 안에서 프레임을 바꿀 수 있게 되면 서버 값과의 동기화 규칙을 먼저 정해야 한다.
- **남녀 색을 분리하자는 제안은 `cyborg_design.dart:196-198`의 명시적 설계 결정과 충돌한다.** "두 프레임은 색이 아니라 실루엣·임플란트·헤어로 구분한다 — 팔레트가 바뀌어도 아군 식별색이 흐트러지지 않는다"는 이유가 적혀 있다. MMORPG에서 아군/적 식별색은 실제로 색보다 우선하는 정보다. **색 대신 명도 단계와 형태로 차별화하는 것이 이 제약 안의 정답**이다.
- **림라이트를 어두운 아웃라인으로 바꾸면 어두운 지형(방화벽 `floorHazard` #FFE1EC는 밝지만, 데이터 타워 그늘면 `wallLeft` #BFE2F2 위)에서 대비가 달라진다.** 배경 명도가 구역마다 다르므로 한 방향으로만 최적화하면 다른 구역에서 손해다. 안쪽 어두운 아웃라인 + 얇은 밝은 하이라이트를 **위쪽 가장자리에만** 두는 절충이 안전하다.
- **`.cowork/character-visual-upgrade/` 에 다른 AI의 1차 분석이 이미 존재한다**(`.grok-pass1.md`). 이 보고서는 그 결론에 의존하지 않고 원본 코드를 직접 열어 작성했으나, 최종 종합 시 중복·상충 여부를 오케스트레이터가 확인해야 한다.
- **다른 세션이 같은 저장소를 편집 중이다.** 위 인용은 이 분석 시점의 내용이며, 특히 `cyborg_renderer.dart`·`player.dart`는 활발히 바뀔 수 있다.

---

## 5. 권고안

| 순위 | 권고 | 범위 | 근거 | 리스크 |
|---|---|---|---|---|
| 1 | **선택한 프레임을 게임까지 배선한다.** `ActionRpgGame` 생성자에 `CyborgDesign`(또는 `CyborgKind`)을 받고 `_spawnPlayer()`가 `Player(grid:…, design: …)`로 넘기게 한다. `main.dart`가 `widget.character.kind`를 `CyborgKind.fromId`로 변환해 주입 | 게임 초기화 · 앱 셸 | `action_rpg_game.dart:226`, `action_rpg_game.dart:1194`, `main.dart:74-82`, `character_select_screen.dart:212` | 재시작 경로(`:1194`)도 함께 고쳐야 재시작 시 남성형으로 되돌아가지 않는다. 서버 `kind` 값과의 동기화 규칙 필요 |
| 2 | **`facing`에 각속도 제한(회전 보간)을 넣는다.** 렌더 전용 `renderFacing`(또는 `renderYaw`)을 별도로 두고 목표 각으로 `lerpAngle`, 각속도 상한 약 12~16 rad/s. 판정용 `facing`은 지금처럼 즉시 유지 | 플레이어 엔티티 | `player.dart:265`, `:313` vs `enemy.dart:187`(적은 이미 `lerp(…, dt*4)`) | 판정과 렌더가 분리되므로 "보이는 방향으로 안 때린다"는 인상이 생길 수 있다. 상한을 충분히 높게(≥12 rad/s) 잡아 체감 지연을 0.1초 이내로 |
| 3 | **`project()`가 화면 y도 반환하게 하고, 깊이를 `-depth · sin(카메라 고각)`으로 y에 반영한다.** 계수는 2:1 다이메트릭의 `sin(atan(0.5)) ≈ 0.447`을 상한으로, 0.30~0.45 사이에서 조율. 동시에 다리 stride를 `strideProjection`(=`sin yaw`)만이 아니라 **깊이 성분**으로도 계산해 정면 보행이 살아나게 한다 | 렌더러 핵심 (`CyborgRenderer` + `_View` + `_Limb`) | `cyborg_renderer.dart:833-840`(depth 미사용), `:136`·`:808`(정면 stride=0), `:441-446`(측면 어깨 겹침) | 렌더러 전역 변경. 발 접지 y가 어긋나면 캐릭터가 뜬다 — 발은 `y.foot` 고정, 상체 부위에만 오프셋. `test/cyborg_render_snapshot_test.dart`로 8방향 PNG를 뽑아 눈으로 검수하는 절차를 먼저 확보 |
| 4 | **`MovePathHint`를 지면 위로 올린다.** priority를 `GroundLayer`(-100000) 직후 값으로 바꾸거나, `MoveMarker`처럼 `IsoEntity`로 만들어 깊이 정렬에 참여시킨다 | 클릭 이동 UI | `click_move.dart:94` vs `ground_layer.dart:37` | 엔티티 priority가 위치 의존(`iso.dart:70-72`)이라 고정 상수로는 항상 캐릭터 아래에 둘 수 없다. 지면 직후가 가장 안전 |
| 5 | **조이스틱 탭 누출을 막는다.** `JoystickComponent`를 `TapCallbacks`를 가진 얇은 래퍼로 감싸 `onTapDown`에서 `event.handled = true`만 세운다(`ActionButton`과 같은 방식) | 터치 컨트롤 | `flame-1.38.0/…/joystick_component.dart:19-20`(TapCallbacks 없음), `touch_controls.dart:63`(올바른 선례) | 래퍼의 히트 영역을 조이스틱 배경 반경(62px)과 정확히 맞춰야 한다. 너무 크면 그 주변 땅을 클릭할 수 없다 |
| 6 | **남녀 차별화를 색이 아니라 실루엣 마디·비대칭으로 만든다.** 여성형 `hipWidth`를 `chestWidth`보다 키워 실제 모래시계를 만들고(`18 → 20~21`), `torsoTaper` 곡률을 강화. 남성형은 어깨 패드에 **한쪽만** 확장 유닛을 달아 비대칭 실루엣을 만든다. 두 프레임의 헬멧 실루엣 형태(각진/뾰족한)를 다르게 | 외형 SSOT (`CyborgDesign` + `CyborgRenderer`) | `cyborg_design.dart:184,187`(hip=chest), `:193`(패드 6.5), `:196-198`(색 통일이 의도적 설계) | 색 통일 결정을 존중하는 방향이므로 안전. 다만 `CyborgDesign`에 비대칭 필드가 없어 필드 추가가 필요하고, `cyborg_preview.dart:188-199`의 사양표도 새 수치를 반영해야 한다 |
| 7 | **밝은 배경 전제에 맞게 아웃라인 방향을 뒤집는다.** 실루엣 바깥은 `GamePalette.textPrimary` 계열의 어두운 1px, `accent` 발광은 몸 **안쪽** 라인·코어·바이저에만 남긴다 | 렌더러 아트 디렉션 | `cyborg_renderer.dart:262-268`, `:597-603`(현재 밝은 accent stroke), `palette.dart:5-9`(밝은 데이터 공간이 전제) | 배경 명도가 구역마다 다르다(`floorBase` #F7FCFF vs `wallLeft` #BFE2F2). 한 방향으로만 최적화하면 다른 구역에서 손해 — 위쪽 가장자리에만 얇은 밝은 하이라이트를 남기는 절충 |
| 8 | **거리 기반 LOD를 넣는다.** 화면 투영 높이가 약 48px 미만이면 바이저 주사선·안테나·관자놀이 모듈·흉골 갈비·냉각 리지·척추 레일 점 4개를 생략. 드로우콜 40 → 약 12 | 렌더러 + 카메라 | `cyborg_renderer.dart:605-700`(축소 시 서브픽셀로 소멸하는 디테일), `action_rpg_game.dart:230-234`(zoom 0.55~1.6) | 근/원 전환 지점에서 팝핑이 보인다. 임계값 주변에 히스테리시스 필요 |
| 9 | **blur를 굽는다.** 코어 후광·부츠 밑창 발광·바이저 글로우를 앱 시작 시 코드로 64×64 `ui.Image` 3장(약 50 KB)으로 굽고, 런타임에는 `ColorFilter`로 색만 바꿔 찍는다. 캐릭터당 blur 6~7회 → 0회 | 렌더러 성능 | `cyborg_renderer.dart:179,317,324,409,630` + `iso_entity.dart:67`, 30명 기준 blur 180~210회/프레임 | 스프라이트 시트 도입이 **아니다**(런타임 생성). 다만 `MaskFilter`와 완전히 같은 그라디언트는 아니므로 시각 차이를 스냅샷으로 확인해야 한다 |
| 10 | **대시 고스트의 `saveLayer`를 없앤다.** 고스트를 알파를 낮춘 단색 실루엣(몸통 path 하나)으로 대체하거나 개수를 12 → 4로 줄인다 | 플레이어 렌더링 | `player.dart:257-259`, `:788-806`(고스트당 saveLayer + 전신 드로잉, 최대 12개) | 대시 잔상의 인상이 옅어진다. 30명 동시 표시가 목표라면 감수할 만한 교환 |
| 11 | **적 탭에 공격/타깃팅을 붙인다.** `Enemy`에 `TapCallbacks`를 추가하되, 사거리 안이면 공격·밖이면 그 지점으로 이동(폴백)하게 한다 | 입력 · 전투 | `enemy.dart:26`(TapCallbacks 없음), `click_move.dart:19-31` | 적 밀집 구역에서 "적 사이 빈 땅으로 이동"이 막힐 수 있다. 탭을 소비하지 말고 폴백을 반드시 둘 것. PK 대상(다른 PC)에도 같은 규칙이 필요 |
| 12 | **프리뷰·초상화의 `drawBody` 인자를 게임과 일치시킨다.** `time:`을 전달하고 `baseY` 부호를 통일한다 | 외형 SSOT 호출부 | `cyborg_preview.dart:53-60`, `cyborg_portrait.dart:121` vs `player.dart:823-831` | 없음. 3줄 수준 |
| 13 | **죽은 코드를 정리한다.** `CyborgRenderer.drawPreview`(`:774`), `quantizeYaw`(`iso.dart:118`), `facingOctant`(`:126`), `facesDown`(`:98`) — 모두 `lib/` 내 호출처가 없다 | 정리 | 저장소 전체 grep | `quantizeYaw`는 권고 9 이후에도 쓰이지 않을 전망이나, 캐시 전략을 재검토할 여지를 남기려면 주석으로 사유를 남기고 보류해도 된다 |
| 14 | **적의 방향 표현을 플레이어와 맞춘다(장기).** `enemy.dart:412`의 좌우 플립을 연속 yaw 기반으로 전환 | 적 렌더링 | `enemy.dart:412` vs `player.dart:826` | 적 종류마다 자체 드로잉이라 작업량이 크다. 권고 3이 검증된 뒤에 착수 |

---

## 6. 불확실 · 미확인

- **실측 성능 수치가 없다.** 드로우콜·blur 호출 횟수는 코드에서 정확히 셌으나, 30명 동시 표시 시의 실제 프레임 시간(ms)은 측정하지 않았다. `flutter run --profile` + DevTools 타임라인, 또는 Skia trace로 blur/`saveLayer`의 실제 비중을 확인해야 권고 9·10의 우선순위가 확정된다.
- **조이스틱 탭 누출을 실행으로 재현하지 않았다.** Flame 1.38의 `JoystickComponent`에 `TapCallbacks`가 없다는 것은 소스로 확인했으나, `MultiTapDispatcher`와 `MultiDragDispatcher`가 동시에 붙었을 때 짧은 탭이 실제로 월드까지 내려가는지는 실행으로 확인해야 한다. CLAUDE.md의 "DTD로 테스트" 규칙상 사람이 조작하지 않고 검증하려면 `lib/offline_main.dart`에 탭 이벤트를 주입하는 테스트 코드가 필요하다.
- **`MovePathHint`가 실제로 안 보이는지 눈으로 확인하지 않았다.** priority 관계는 확정이고 `GroundLayer`가 불투명 청크를 굽는다는 것도 코드로 확인했으나, 지면 청크가 뷰포트 전체를 덮는지(월드 가장자리·공백 구역 등)까지는 `_bakeChunk` 내부를 다 읽지 않았다.
- **`_stuckTime` 조기 포기 경계값**(§3.3 마지막)은 계산상 성립하지만 재현하지 못했다. 벽 모서리에서 목표 0.18~0.19타일 거리에 접근할 때만 발생하는 좁은 조건이다.
- **카메라 고각 계수의 최적값**(권고 3의 0.30~0.45)은 수학적 상한(0.447)만 근거이고, 어느 값이 가장 자연스러운지는 스냅샷을 뽑아 사람이 골라야 한다. 캐릭터가 빌보드로 그려지는 이상 완전히 물리적으로 정확한 값이 반드시 가장 보기 좋은 것은 아니다.
- **"예쁘고 화려하게"의 기준이 정의되지 않았다.** 이 보고서는 "화려함 = 32~64px에서의 읽힘 향상"으로 번역해 판단했으나(시스템 프롬프트의 Persona 지시에 따름), 사람이 원하는 것이 그것이 아니라 **프리뷰 배율에서의 장식 밀도**라면 권고 6·7·8의 방향이 달라진다. 특히 권고 8(LOD로 디테일 생략)은 "화려함을 줄이는" 방향으로 읽힐 수 있어 사람의 확인이 필요하다.
- **머리 크기 비율**(headWidth 21 / totalHeight 108 = 5.7등신)이 의도인지 확인하지 못했다. 2.5D 액션 RPG에서는 머리를 키워 4~5등신으로 만드는 관례가 있고 그쪽이 축소 시 읽힘에 유리하지만, 이 프로젝트의 "군용 프레임" 설정과는 충돌할 수 있다. 아트 방향 결정권자의 판단 사항이다.
- **`GAME-DESIGN.md:175`에 `facesDown(dir)` 기반 앞/뒤 판정이 문서화돼 있으나 코드에서는 미사용이다.** 문서가 연속 yaw 도입 이전 상태로 남은 것으로 보이며, 이 불일치를 문서 쪽에서 정리할지 확인이 필요하다.
