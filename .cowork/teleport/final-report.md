# 종합 검토 — teleport

> 요청: Add teleport system. — 텔레포트 메뉴 추가, 아이콘 탭 시 bottom sheet 열림, 5개 목적지(세이프존=월드 중앙 + 동/서/남/북) 표시 및 이동
> 분석: **grok 만 유효**. claude·kimi 는 엉뚱한 저장소(`/Users/thruthesky/apps/game/laryen`)를 분석해 전량 무효, codex 는 "작업공간에 게임 코드 없음"으로 분석 중단.
> 원인: 오케스트레이터가 `cowork.sh` 를 플러그인 캐시 절대경로로 호출해 cwd 가 `~/.claude/plugins/cache` 로 잡혔다. 산출물도 그곳에 생성돼 프로젝트로 옮겼다.
> 보정: 무효 3건을 오케스트레이터의 **직접 코드 검증**으로 대체했다. 아래 모든 근거는 내가 실제로 파일을 열어 확인한 것이다.
> 종합: 2026-08-04 · 읽기 전용 분석 — 작업공간 미수정

## 1. 결론

요청한 텔레포트 시스템은 이 저장소에 **존재하지 않으며, 신규 구현이 맞다.** 필요한 기반은 이미 전부 갖춰져 있다 — 세이프존은 이미 월드 중앙 `(500,500)` 에 있고(`level_map.dart:69`), 착지 보정용 `nearestWalkable`(`level_map.dart:196`)과 순간이동 후처리 패턴(`onPlayerDied`, `action_rpg_game.dart:908-929`)이 그대로 재사용 가능하다.

UI 는 **Flutter `showModalBottomSheet` 가 아니라 Flame `PositionComponent` 하단 시트**로 만들어야 한다 — 이 저장소의 인게임 패널은 전부 `camera.viewport` 에 붙는 Flame 컴포넌트이고, 인게임 Material 시트 관례가 하나도 없다.

**가장 중요한 함정: `Player.respawnAt()` 을 재사용하면 안 된다.** 이 함수는 HP·에너지를 가득 채우므로(`player.dart:403-404`) 텔레포트마다 완전 회복되는 어뷰즈가 생긴다. HP/EN 을 유지하는 `teleportTo` 를 따로 만들어야 한다.

서버 변경은 **불필요하다.** `PlayerCharacter` 에 위치 필드가 없고(`spacetimedb/src/lib.rs:86-115`) 타 플레이어 렌더링도 아직 없어, 1차는 로컬 순간이동으로 완결된다.

판정 못 한 것 하나 — 목적지의 가장자리 여백(`edge`) 최적값은 코드에 근거가 없어 내 판단(30타일)이다.

## 2. 네 AI 의견 대조

| 쟁점 | claude | codex | grok | kimi | 검증 결과 |
|---|---|---|---|---|---|
| 대상 저장소 | laryen | "게임 코드 없음" | **actionrpg** | laryen | ⚖️ grok 이 맞음 — `cowork-prompt.md:100` 을 읽고 실제 경로를 찾아냄 |
| 텔레포트 존재 여부 | "이미 완성돼 있음" | 판정 불가 | **미구현, 신규 필요** | "이미 완성돼 있음" | ⚖️ grok — `grep -rn teleport lib/` 결과 0건 |
| UI 계층 | Flutter `showModalBottomSheet` | 판정 불가 | **Flame `PositionComponent`** | Flutter 시트 | ⚖️ grok — 인게임 패널 전부 viewport 컴포넌트 |
| 백엔드 | Nakama + Go UDP | 판정 불가 | **SpacetimeDB, 위치 필드 없음** | Nakama | ⚖️ grok — `lib.rs:86-115` |
| `respawnAt` 재사용 | 해당 없음 | 해당 없음 | **금지 — HP 풀회복 어뷰즈** | 해당 없음 | ✅ 확인 — `player.dart:403-404` |

claude·kimi 의 열은 전부 다른 게임(laryen)에 대한 서술이라 **판정 대상이 아니다.** 이 표는 그들이 무엇을 착각했는지 기록으로만 남긴다.

## 3. 합의 — 검증 통과

유효 분석이 grok 하나뿐이라 다자 합의는 성립하지 않는다. 대신 grok 의 주장 중 **결론을 좌우하는 항목을 내가 전부 직접 열어 검증했고, 모두 사실로 확인됐다**:

- **세이프존은 이미 월드 중앙에 있다** — `level_map.dart:69` 가 `SafeZone.centeredOn(Vector2(width/2, height/2))`, 월드가 1000×1000(`iso.dart:27`)이므로 중심은 `(500,500)`. 한 변 50m(`safe_zone.dart:11`).
- **`respawnAt` 은 HP·EN 을 가득 채운다** — `player.dart:403-404` 의 `_hp = _maxHp; energy = maxEnergy;`. 무적 2초까지 부여(`:422`).
- **카메라는 보간 추적이라 장거리 이동 시 "비행"한다** — `action_rpg_game.dart:371-372` 의 지수 감쇠 스무딩. `onPlayerDied` 는 이를 알고 `camera.viewfinder.position = _cameraTarget()` 로 즉시 스냅한다(`:922`, 주석에 "보간하면 한참을 날아간다"고 명시).
- **스트리밍도 즉시 갱신해야 한다** — `onPlayerDied:926-927` 이 `_refreshBlockStreaming()`·`_refreshMonsterStreaming()` 를 직접 호출. 주기는 각각 0.25s·0.3s(`:423,428`).
- **맵 외곽 3칸은 통행 불가** — `level_map.dart:245-252` 가 `margin = 3` 범위를 `TileType.none` 으로 채운다. 따라서 목적지의 `edge` 는 4 이상이어야 한다.
- **`nearestWalkable` 은 실패 시 조용히 월드 중앙을 반환한다** — `level_map.dart:212` 의 `return spawn.clone()`. 반경 24 안에 통행 가능 칸이 없으면 발생.
- **SpacetimeDB 에 위치가 없다** — `spacetimedb/src/lib.rs:86-115` 의 `PlayerCharacter` 는 id·account·name·kind·level·xp·timestamps 뿐. `spacetime_game_sync.dart` 도 `reportProgress(level, xp)` 만 전송.
- **`WorldMenu` 는 항목 선택 시 스스로 닫는다** — `world_menu.dart:169-170` 이 `close()` 후 `onSelected()` 호출. 텔레포트 항목을 메뉴에 넣으면 별도 close 가 불필요하다.

## 4. 이견 — 자료로 판정

### 쟁점: 동·서·남·북을 어느 축으로 정의할 것인가

유효 분석이 하나뿐이라 AI 간 이견은 없으나, **코드 안에 서로 다른 두 관례가 공존해** 내가 판정해야 했다.

- **관례 A (아이소메트릭 화면 꼭짓점)**: `safe_zone.dart:129-133` 이 `north = gridToScreen(minX, minY)`, `east = (maxX, minY)`, `south = (maxX, maxY)`, `west = (minX, maxY)` 로 부른다. 이는 아이소 투영 후 **화면상 마름모의 네 꼭짓점** 이름이다.
- **관례 B (그리드 축)**: `hud.dart:332-336` 의 미니맵 `toRadar` 가 `grid.x` → 가로, `grid.y` → 세로로 **직접** 매핑한다. 즉 미니맵에서 위=y 작음, 오른쪽=x 큼.

- **판정**: **관례 B(그리드 축)를 채택한다.** 북=y 최소, 남=y 최대, 동=x 최대, 서=x 최소.
- **근거**: 플레이어가 게임 중 방향을 판단하는 유일한 수단이 미니맵(`hud.dart:322-336`)이다. 미니맵에서 위쪽으로 보이는 지역을 "북"이라 부르지 않으면 라벨과 화면이 어긋난다. 관례 A 의 이름들은 `SafeZoneField` 내부에서 마름모 꼭짓점을 구분하려는 지역 변수명일 뿐, 게임 전체의 방위 체계로 쓰인 곳이 없다(`grep` 결과 해당 4개 이름은 그 함수 밖에서 미사용).

## 5. 고유 통찰 — 검증됨

- **grok**: **`nearestWalkable` 의 침묵 실패** — `level_map.dart:212` 가 반경 24 탐색 실패 시 예외나 null 이 아니라 `spawn`(월드 중앙)을 반환한다. 확인 결과 사실이다. 외곽 목적지가 지형상 전부 막히면 "동쪽으로 갔는데 중앙에 도착"하는 조용한 오동작이 된다. 다수결이었다면 나오지 않았을 발견이다.

- **grok**: **`toggleInventory` 는 다른 패널을 닫지 않는다** — `action_rpg_game.dart:745-749` 확인. 캐릭터·리더보드는 서로와 인벤을 닫지만(`:756-789`) 인벤은 자기만 토글한다. 따라서 텔레포트 시트를 열 때 **인벤토리 close 를 명시하지 않으면** 두 패널이 겹쳐 입력 레이어가 충돌한다.

- **grok**: **`PotionQuickBar` 가 하단 중앙을 점유한다** — `inventory_ui.dart:68-71` 의 `position = Vector2(..., screenSize.y - 10)`, priority 95. 하단 시트가 이 영역을 덮으면 퀵슬롯 터치가 막힌다. 시트 높이 설계 시 실질적 제약이다.

## 6. 반증 — 근거가 틀린 주장

- **claude 전체 보고서** — ❌ 근거로 든 `lib/features/game/teleport/teleport_sheet.dart`, `game_control_pad.dart`, `game-server/zone/internal/sim/teleport_warp.go`, `teleport_catalog.dart` 는 **이 저장소에 존재하지 않는 경로**다. 전부 `/Users/thruthesky/apps/game/laryen` 의 파일이다. "텔레포트가 이미 구현돼 있다", "백엔드는 Nakama", "목적지가 10곳" 등 결론 전부를 채택하지 않는다.

- **kimi 전체 보고서** — ❌ 위와 동일. `docs/teleport.md`·`v5_zone_client.dart` 등 없는 경로를 인용한다. "이미 완전히 구현되어 있다"는 결론은 이 저장소에 대해 거짓이다. 확인: `grep -rn "teleport" lib/` 결과 **0건**.

- **claude·kimi 공통** — ❌ "요청문의 SpacetimeDB 전제가 틀렸다"는 지적 자체가 틀렸다. `spacetimedb/` 디렉터리와 `lib/spacetime/` 이 실재하며 `CLAUDE.md` 가 SpacetimeDB 를 명시한다. 그들이 본 저장소가 틀렸을 뿐이다.

- **codex** — 분석 중단은 정당했다. "작업공간에 게임 코드가 없다"는 사실이며(`~/.claude/plugins/cache` 에는 실제로 없다), 없는 것을 지어내지 않고 멈춘 것은 올바른 처신이다. 반증 대상이 아니다.

## 7. 최종 권고

| 순위 | 권고 | 범위 | 근거 | 리스크 | 검증 방법 |
|---|---|---|---|---|---|
| 1 | **`lib/game/level/teleport_destinations.dart` 신규** — 5개 목적지 enum(`safeZone`·`north`·`south`·`east`·`west`) + `Vector2 resolve(LevelMap)`. 세이프존은 `map.respawnPoint()`, 나머지는 그리드 축 가장자리를 `nearestWalkable` 통과 | 레벨 | `level_map.dart:93-103,196-212` | 낮음. `edge` 값은 판단 | `flutter test` + 5점 walkable 단위 테스트 |
| 2 | **`Player.teleportTo(Vector2)` 신규** — 위치 설정 + 이동·넉백·대시·고스트 정리 + `syncTransform()`. **HP/EN 유지**, `respawnAt` 복붙 금지 | 엔티티 | `player.dart:401-426` | 낮음. 상태 미정리 시 착지 후 미끄러짐 | 실행 후 텔레포트 직후 HP 불변 확인 |
| 3 | **`lib/game/ui/teleport_sheet.dart` 신규** — Flame `PositionComponent` 하단 슬라이드업 시트, 5버튼, `isOpen`/`_anim`, `GamePalette`, priority 142 | UI | `character_screen.dart:18`(140)·`leaderboard_screen.dart:21`(141) | 중간. 퀵바(`inventory_ui.dart:68-71`)와 높이 충돌 주의 | 실행 후 스크린샷 |
| 4 | **`ActionRpgGame.teleportPlayer()`** — `resolve` → `teleportTo` → **카메라 즉시 스냅** → `_refreshBlockStreaming()`·`_refreshMonsterStreaming()` → 시트 닫기. `onPlayerDied` 패턴 그대로 | 게임 루프 | `action_rpg_game.dart:908-929` | 낮음 | 장거리 이동 시 카메라 비행·팝인 없는지 육안 |
| 5 | **`WorldMenuIcon.teleport` 추가 + 메뉴 항목** — 글리프 추가, `WorldMenuEntry(label: '텔레포트', ...)` 등록 | UI | `world_menu.dart:10,360-417`·`action_rpg_game.dart:259-280` | 낮음 | 메뉴 열어 아이콘 렌더 확인 |
| 6 | **패널 상호 배제 + Esc 체인 편입** — 시트 open 시 캐릭터·리더보드·**인벤토리** close. Esc 체인 최상단에 시트 추가 | 게임 루프 | `action_rpg_game.dart:745-749,756-789,1061-1071` | 낮음. 누락 시 입력 레이어 충돌 | Esc 순차 닫기 확인 |
| 7 | **`test/teleport_test.dart` 신규** — 5점 walkable·세이프존 포함 회귀. 시드 `20260804` 고정 | test | `test/safe_zone_test.dart:15-19`·`level_map.dart:233` | 없음 | `flutter test` |
| 8 | **SpacetimeDB·`GameSync` 변경 없음** | net | `lib.rs:86-115`·`spacetime_game_sync.dart:47-56` | 미래 프레즌스 도입 시 재작업 | — |
| 9 | *(요청 외 — 넣지 않음)* 쿨다운·전투 중 잠금 | 밸런스 | `CLAUDE.md:25-26`(PK 목표) | 스코프 크리프 | 제품 결정 후 별건 |

**되돌리기 비용**: 전부 신규 파일 3개 + 기존 파일 3개의 국소 수정이며, 서버·DB·외부 영향이 없다. `git revert` 로 완전히 되돌릴 수 있다.

## 8. 미해결 · 사람 판단 필요

- **`edge` 값(가장자리에서 안쪽으로 몇 타일)** — 코드에 근거 상수가 없다. `margin=3`(통행 불가)과 `avenueSpacing=40`(대로 간격)만 확정 사실. 30타일로 잡되 실플레이 감성은 미측정이다.
- **방위 라벨 표기** — §4 판정대로 그리드 축을 쓰지만, 아이소 화면에서 "북"은 화면 위쪽 대각선이라 플레이어가 순간 혼동할 수 있다. 라벨에 좌표를 병기하는 것으로 완화했으나 기획 확정은 아니다.
- **동시 진행 중인 다른 작업과의 충돌** — 같은 저장소에서 `world-size-1km`(월드 크기 검증) cowork 가 병렬 실행 중이다. 월드 크기가 바뀌면 이 기능의 동/서/남/북 좌표가 함께 바뀐다. `kWorldTiles` 파생으로 구현해 하드코딩을 피했으나, 그쪽 결론을 확인할 필요가 있다.
- **`.cowork/cowork-prompt.md` 의 분석 주제 문단이 HP·몬스터 피해 재설계로 남아 있다**(`:25-36`) — 텔레포트와 무관한 persona 다. 이번 종합은 같은 문서의 **불변 규칙**(Flame UI 강제, 서버 신뢰 원칙, 작업 경로)만 채택했다.

## 9. 적용 결과

> 적용: 2026-08-04 · 커밋 **하지 않음**(사유 아래)

| 권고 | 적용 | 파일 | 검증 |
|---|---|---|---|
| 1 (§7 1순위) | ✅ 적용 | `lib/game/level/teleport_destinations.dart` (신규 105줄) | `flutter test test/teleport_test.dart` 9/9 통과 |
| 2 | ✅ 적용 | `lib/game/entities/player.dart:428-458` `teleportTo` | HP·EN·쿨다운 미변경을 코드로 확인. `respawnAt` 은 그대로 보존 |
| 3 | ✅ 적용 | `lib/game/ui/teleport_sheet.dart` (신규 383줄) | `flutter analyze` 에러 0 |
| 4 | ✅ 적용 | `lib/game/action_rpg_game.dart` `teleportPlayerTo` | 카메라 즉시 스냅 + `_refreshBlockStreaming`/`_refreshMonsterStreaming` 호출 — `onPlayerDied` 와 동일 후처리 |
| 5 | ✅ 적용 | `lib/game/ui/world_menu.dart:10, 394-416` | `WorldMenuIcon.teleport` + 마름모 포털 글리프 |
| 6 | ✅ 적용 | `action_rpg_game.dart` open/close/Esc | 캐릭터·리더보드·인벤 open 시 시트 close, Esc 체인 최상단 편입 |
| 7 | ✅ 적용 | `test/teleport_test.dart` (신규 9케이스) | 전체 `flutter test` 106/106 통과 — 회귀 없음 |
| 8 | ✅ 준수 | — | SpacetimeDB·`GameSync` 무수정 |
| 9 | ⏸️ 보류 | — | 쿨다운·전투 잠금은 요청 밖이라 넣지 않음(§7 9순위 그대로) |

**검증 결과**
- `flutter test` — **106/106 통과**. 신규 9케이스 포함, 기존 테스트 회귀 없음.
- `flutter analyze` — 에러 0. 남은 23건은 전부 기존 코드의 style info/warning이며, `teleport_sheet.dart:106` 의 `avoid_renaming_method_parameters` 는 `hud.dart`·`inventory_ui.dart`·`character_screen.dart`·`leaderboard_screen.dart` 가 모두 쓰는 프로젝트 컨벤션과 동일하다.
- **실행 검증(스크린샷)은 하지 않았다.** 아래 사유와 같다.

**커밋하지 않은 사유 — 중요**

같은 저장소에서 **다른 세션 두 개가 동시에 작업 중**이다(`ps` 로 확인):
- `.cowork/hp` — "PC HP 1만, 몬스터 레벨별 피해" 작업
- `.cowork/world-size-1km` — "월드 1km 크기 검증" 작업

`git diff --stat` 기준 `world_menu.dart`(21줄)·`iso.dart`(25줄)·`main.dart`(60줄) 등 34개 파일이 이미 그들 손에 수정돼 있다. 내가 건드린 `world_menu.dart`·`player.dart`·`action_rpg_game.dart` 에도 그들의 미완성 변경이 섞여 있어, 지금 커밋하면 **남의 진행 중 작업이 함께 커밋된다.** 같은 이유로 앱 실행 빌드도 불안정할 수 있어 실행 검증을 보류했다.

**사람 확인·후속 조치 필요**
- 커밋 시점은 사용자가 정해야 한다. 병렬 작업이 끝난 뒤 통합 커밋하거나, 내 6개 파일만 선택 커밋하는 판단이 필요하다.
- `world-size-1km` 작업이 `kWorldTiles` 를 바꾸면 동/서/남/북 좌표가 함께 움직인다. 이 구현은 상수를 하드코딩하지 않고 `map.width`/`map.height` 파생으로 짜서 자동 추종하지만, 그쪽 결론 확인이 필요하다.
- 실제 화면 확인(아이콘 렌더·시트 레이아웃·퀵슬롯 겹침)은 실행 검증이 남아 있다.

**권고에 없었지만 필요해진 변경**
- `toggleInventory` 에 `_teleportSheet.close()` 추가. 인벤토리는 원래 다른 패널을 닫지 않는 예외지만(§5 고유 통찰), 텔레포트 시트는 화면 하단을 덮고 입력을 가로채므로 겹치면 둘 다 눌리지 않는다. 주석으로 사유를 남겼다.
