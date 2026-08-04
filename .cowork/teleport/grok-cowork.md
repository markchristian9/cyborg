<!-- cowork:grok | 2026-08-04 20:38:24 | exit=0 | 502s -->
# grok 분석 — teleport

> 요청: 텔레포트 시스템을 구현하려 한다. 사용자 원문 요청은 다음과 같다.

Add teleport system.
- Add a menu for teleport.
- When the player click on the teleport icon, there should a bottosheet open, and show 5 teleport area.

1) safe zone(center of the game world)
2) east, west, north, south of the game world.

즉 요구사항은 (a) 텔레포트 메뉴/아이콘을 게임 UI 에 추가하고, (b) 아이콘을 누르면 bottom sheet 가 열리며, (c) 그 안에 5개의 텔레포트 목적지(세이프존=월드 중앙, 그리고 동/서/남/북)를 보여주고, (d) 선택하면 플레이어가 그 지점으로 이동하는 것이다.

이 작업공간(Flutter + Flame 2.5D 아이소메트릭 MMORPG, 백엔드는 SpacetimeDB)의 실제 코드를 읽고 다음을 구체적으로 분석하라. 추측하지 말고 반드시 실제 파일:줄 을 근거로 답하라.

1. 현재 게임 UI 메뉴 구조는 어떻게 되어 있나? 텔레포트 아이콘을 어디에 어떤 방식으로 추가해야 기존 컨벤션과 일치하나? (HUD 오버레이인가, Flame 컴포넌트인가, Flutter 위젯 오버레이인가? 기존 인벤토리/캐릭터/리더보드 화면은 어떤 패턴으로 열리나?)
2. 월드 좌표계는 무엇인가? 월드의 중앙/동/서/남/북 좌표를 어떤 값으로 계산해야 하나? 맵 크기·경계·타일 좌표계와 아이소메트릭 변환의 실제 정의를 찾아라. 세이프존이 이미 존재한다면 그 실제 위치는 어디이고 텔레포트 목적지로 무엇을 써야 하나?
3. 플레이어 위치를 순간이동시키려면 어떤 경로로 해야 하나? 플레이어 위치는 로컬에서만 관리되나, SpacetimeDB 로 동기화되나? 멀티플레이 동기화(다른 플레이어에게 보이는 위치)를 깨지 않으려면 어떤 함수/리듀서를 거쳐야 하나? 카메라 추적, 청크/영역 로딩, 몬스터 스폰·어그로, 이동 보간(interpolation) 등에서 순간이동 시 깨질 수 있는 것은 무엇인가?
4. 텔레포트 도착 지점이 벽/블록/장애물과 겹칠 위험은 어떻게 처리해야 하나? 기존 충돌·스폰 위치 결정 로직에 재사용할 수 있는 것이 있나?
5. 밸런스/치팅 관점: PK 가 허용되는 MMORPG 에서 무제한 텔레포트가 만들 문제(전투 중 도주, 쿨다운 필요 여부)를 지적하되, 사용자가 요청하지 않은 기능을 임의로 넣지 말 것. 넣을지 말지는 권고로만 제시하라.
6. 최종적으로: 어떤 파일을 어떻게 수정/신규 생성해야 하는지 구체적인 구현 계획을 파일 단위로 제시하라. 기존 코드 스타일·네이밍 컨벤션을 따를 것.
> 생성: 2026-08-04 20:38:24 · 소요 502s · 읽기 전용 분석(작업공간 미수정)

---



## 1. 결론 요약

텔레포트는 **Flame `camera.viewport` HUD 패널**로 구현해야 한다. 인게임 메뉴·캐릭터·리더보드·인벤이 전부 이 축이고, Flutter Material bottom sheet/`showModalBottomSheet` 인게임 관례는 없다.  
세이프존 목적지는 이미 있는 **월드 중앙 `(500, 500)` 기준 50×50 m 광장**이며 `map.respawnPoint` / `nearestWalkable`로 안전 착지가 가능하다. 동·서·남·북은 맵 가장자리 후보를 `nearestWalkable`에 통과시킨다.  
이동 본체는 `onPlayerDied`의 **즉시 카메라 스냅 + 블록/몬스터 스트리밍 즉시 갱신**을 재사용하되, **`Player.respawnAt`의 HP·에너지 풀 회복은 분리**한 `teleportTo`가 필요하다.  
**SpacetimeDB에 위치 필드·reducer가 없으므로** 1차는 서버 변경 없이 로컬 순간이동이 맞고, 타 플레이어 가시성도 아직 없어 멀티 동기화 깨짐은 당면 문제가 아니다. 무제한 텔레포트의 PK 도주 문제는 권고만 한다.

---

## 2. 근거

- `/Users/thruthesky/.claude/plugins/cache` 최상위: `RevenueCat/`, `claude-plugins-official/`, `thruthesky-skills/` — 게임 `lib/` 없음. (디렉터리 목록)
- `/Users/thruthesky/tmp/games/actionrpg/.cowork/cowork-prompt.md:100-108` — 작업공간 경로 `…/tmp/games/actionrpg`, Flutter+Flame+SpacetimeDB; `:89-91` 인게임 UI는 **전부 Flame `PositionComponent`**.
- `GAME-DESIGN.md:18-24` — Flame 1.38, SpacetimeDB, 1 km²(1000×1000 타일); `:597-600` 타 플레이어 표시·PK 미구현.
- `lib/game/action_rpg_game.dart:43-48,182-288,304-305` — Flutter overlays는 메인/일시정지/게임오버 계열; HUD·조이스틱·`WorldMenu`·캐릭터/리더보드/인벤은 `camera.viewport`; 메뉴 위치 `(size.x-18, 168)`.
- `lib/game/ui/world_menu.dart:10,33-36,169-170,259-279` — 우상단 Flame 햄버거; 항목 선택 시 **스스로 `close()` 후** `onSelected`; 항목: 캐릭터·리더보드·(선택)로그아웃.
- `lib/game/ui/character_screen.dart:11-31` / `leaderboard_screen.dart:11-21` — `isOpen` 토글, 열려도 **게임 미정지**, priority 140/141.
- `lib/game/action_rpg_game.dart:756-806,745-749,1058-1081` — 캐릭터/리더보드 open 시 인벤·상대 패널 close; **인벤 `toggleInventory`는 다른 패널을 닫지 않음**; Esc 닫기 체인.
- `lib/game/iso.dart:17-33,48-53` — 타일=1 m, 월드 1000, 청크 32, `gridToScreen`.
- `lib/game/level/safe_zone.dart:10-30,47-49` / `level_map.dart:69-103,195-212,245-252,233` — 중앙 세이프존, `respawnPoint`, `nearestWalkable`(실패 시 `spawn`), 외곽 `margin=3` 허공, 기본 시드 `20260804`.
- `test/safe_zone_test.dart:15-19,56-81` — center `(500,500)`, 재접속점 항상 세이프존·walkable.
- `lib/game/entities/player.dart:249-266,401-426` — 충돌 이동; `respawnAt`은 위치+상태 클리어+**HP/EN 풀**+무적 2초.
- `lib/game/action_rpg_game.dart:368-393,421-428,470-505,904-938` — 카메라 스무딩; 스트리밍 주기 0.25 s / 0.3 s; 사망 시 **즉시** 카메라·스트리밍.
- `lib/game/net/game_sync.dart:11-12,29-33` / `spacetime_game_sync.dart:8-11,47-56` — `tick` 주석에 위치 스트리밍 여지; 실제 전송은 **level/xp만**; `reportDeath`는 인터페이스·호출만, 구현 no-op.
- `spacetimedb/src/lib.rs:5-6,86-115` — 범위 계정·캐릭터; `PlayerCharacter`에 위치 없음.
- `lib/game/ui/inventory_ui.dart:13-19,68-71` — `PotionQuickBar` **하단 중앙** (`screenSize.y - 10`) — 하단 시트와 겹침 후보.
- `lib/game/level/ground_layer.dart:49-50,77-86` — 프레임당 신규 청크 bake **3개** 한도.
- `lib/game/level/safe_zone.dart:129-133` — 렌더 꼭짓점 이름 north/east/south/west = `(minX,minY)` 등 (그리드 축 관례 단서).
- `lib/main.dart:75-91` — Material `AlertDialog`는 **로그아웃 확인** 등 앱 셸용; 인게임 패널 아님.
- `CLAUDE.md:25-26` / `GAME-DESIGN.md:497-499` — PK 목표; 패널 open 중 pause 금지(MMO).

---

## 3. 상세 분석

### 3.1 분석 경계 (어디가 권위인가)

| 루트 | 내용 | 텔레포트 구현 권위 |
|---|---|---|
| `…/plugins/cache` | Claude 플러그인 캐시 + `.cowork/teleport` 분석 로그 | 코드 없음 |
| `…/tmp/games/actionrpg` | Cyborg 본 저장소 | **권위 소스** (`.cowork/cowork-prompt.md:100`) |

요청 스택(Flutter+Flame 아이소 + SpacetimeDB)과 일치하는 코드는 **actionrpg**뿐이다.  
참고: `.cowork/cowork-prompt.md` 본문의 **이번 분석 주제 문단은 HP·몬스터 피해 재설계**로 남아 있다(`:25-36`). 텔레포트 요청과 주제가 어긋나므로 persona의 “전투 수식 설계자”를 억지로 텔레포트에 투영하지 않고, 같은 문서의 **불변 규칙**(Flame UI, 서버 신뢰 원칙, 작업 경로)만 채택한다.

### 3.2 UI 메뉴 구조 — 아이콘·시트를 어디에?

**계층**

| 계층 | 실제 용도 | 텔레포트 |
|---|---|---|
| Flutter `GameWidget.overlayBuilderMap` | 메인/일시정지/게임오버 풀스크린 (`main.dart:106-110`) | 비권장 |
| Flame `camera.viewport` | HUD·조이스틱·월드메뉴·패널 | **권장** |
| Flame `world` | 지형·엔티티 | 메뉴 아님 |

**기존 열기 패턴**

1. 우상단 `WorldMenu` → 항목 탭 시 메뉴가 먼저 `close()` → `openCharacterScreen` / `openLeaderboard` (`world_menu.dart:169-170`, `action_rpg_game.dart:259-279`).
2. 패널은 viewport에 **항상 마운트**, `_open`/`_anim`으로 표시 (`character_screen.dart:24-31`).
3. 캐릭터↔리더보드 open 시 인벤·상대 패널 close + `GameAudio.play(Sfx.uiClick)` (`756-789`).
4. **인벤토리는 예외**: `toggleInventory`는 자기만 토글하고 다른 패널을 닫지 않는다 (`745-749`). “모든 패널이 완전 상호 배타”는 사실이 아니다.
5. Esc: 리더보드 → 캐릭터 → 월드메뉴 → 인벤 → 일시정지 (`1058-1071`).
6. 패널이 열려도 `pauseEngine` 하지 않음 (`GAME-DESIGN.md:497-499`, 화면 주석).

**요청 “teleport icon + bottom sheet” 정렬**

- 코드에 인게임 `showModalBottomSheet` **없음** (Material 다이얼로그는 로그아웃 확인 등, `main.dart:75-91`).
- 인벤 패널은 **화면 중앙 카드** (`inventory_ui.dart:327-336`); 하단 고정 UI는 `PotionQuickBar` (`:68-71`).
- **권장**
  - **진입 아이콘**: 요청 문구상 전용 아이콘이 1순위. 앵커 — 미니맵 `origin = (size.x - 132 - 18, 18)` (`hud.dart:22,325`), 월드메뉴 `(size.x - 18, 168)` (`action_rpg_game.dart:305`). 미니맵 바로 아래·메뉴 왼쪽에 44×44급 버튼이 레이아웃상 자연스럽다.
  - **보조 진입**(최소 침습): `WorldMenuEntry(label: '텔레포트', …)` + `WorldMenuIcon` 확장. 단 이것은 햄버거 서브항목이지 “전용 아이콘”과는 다름.
  - **시트**: 신규 Flame `PositionComponent`(예: `TeleportSheet`), 하단 슬라이드 업으로 bottom-sheet UX. priority는 인벤(120)·월드메뉴(130)보다 위, 캐릭터(140)/리더보드(141)와 같은 **140대**.
  - `openTeleport()`: 캐릭터·리더보드·**인벤** close (인벤은 지금 자동 close 안 됨). 월드메뉴는 항목 경로면 이미 닫힘; 전용 아이콘 경로면 열린 메뉴만 선택적 close.
  - 하단 시트 높이는 **퀵슬롯(`PotionQuickBar`)** 과 겹치지 않게 margin 확보 (`inventory_ui.dart:68-71`).

### 3.3 월드 좌표 · 5 목적지

**좌표계 (`iso.dart`)**

- 논리: 그리드 타일, **1 타일 = 1 m**.
- 크기: **1000 × 1000**.
- 화면: `screenX = (gx-gy)*64`, `screenY = (gx+gy)*32 - z*56`.
- 청크: 32 → 한 변 약 32 청크.

**세이프존 (기존)**

- `SafeZone.centeredOn(Vector2(width/2, height/2))` → 기본 **`(500, 500)`**, halfExtent 25 → **50 m 정사각**.
- `LevelMap.respawnPoint` — 광장 안 랜덤 walkable (실패 시 `nearestWalkable(safeZoneCenter)`).
- 생성 시 중앙 구조물·방화벽 제거 (`level_map` 세이프 클리어 루프; 테스트 `safe_zone_test.dart:61-73`로 검증).
- 플레이어 시작: `Player(grid: map.respawnPoint())` (`action_rpg_game.dart:175`).

**5 목적지 (구현 시 계산)**

| 라벨 | 후보 좌표 | 보정 |
|---|---|---|
| Safe zone | `map.respawnPoint(rng)` 또는 `nearestWalkable(map.safeZoneCenter)` | 세이프존·walkable 보장 |
| East | `nearestWalkable(Vector2(width - edge, height/2))` | 벽/허공 회피 |
| West | `nearestWalkable(Vector2(edge, height/2))` | 동일 |
| North | `nearestWalkable(Vector2(width/2, edge))` | 동일 |
| South | `nearestWalkable(Vector2(width/2, height - edge))` | 동일 |

- **`edge` 하한**: 맵 외곽 `margin = 3` 칸은 `TileType.none` (`level_map.dart:245-252`) → **edge ≥ 4 필수**. 최적 감성 값(15 vs 40 등)은 코드 상수 없음 → **`[판단]` 예: 20~40**, 대로 간격 40(`avenueSpacing`)을 참고해 “가장자리 느낌” 튜닝.
- **방위 축 `[판단]`**: 코드에 텔레포트용 동서남북 enum 없음. (1) 미니맵이 `Δx`→가로·`Δy`→세로 (`hud.dart:332-336`), (2) `SafeZoneField`가 north=`(minX,minY)` 등 꼭짓점을 부름 (`safe_zone.dart:129-133`), (3) `pushOutside`에서 y 감소를 top으로 취급 (`:82-92`). → **+x=East, −y 쪽=North(작은 y), +y=South**로 UI 라벨하는 것이 기존 관례와 맞다. 아이소 화면 대각선 “북쪽”과 혼동하지 않도록 라벨/툴팁에 그리드 기준을 밝히면 안전.

**`nearestWalkable` 함정**: 반경 24 안 실패 시 **`spawn`(월드 중앙)** 반환 (`level_map.dart:196-212`). 외곽 목적지가 전부 막히면 조용히 중앙으로 떨어질 수 있다 → 텔레포트 API는 실패 시 UI 피드백 또는 edge 재시도가 필요.

### 3.4 순간이동 경로 · 동기화

**로컬 권위**: `Player.grid` (`IsoEntity`). 매 프레임 `syncTransform()` → 화면 좌표·depth (`iso_entity.dart:39-50`). 네트워크 위치 보간 코드 **없음**(대시 잔상 `_ghosts`만 로컬 연출).

**서버 현황**

- `SpacetimeGameSync`: `reportProgress(level, xp)` 5초 주기 + 레벨업 즉시 (`spacetime_game_sync.dart:8-11,47-56`).
- `PlayerCharacter`: id, account, name, kind, level, xp, timestamps — **위치 없음** (`lib.rs:90-115`, generated `player_character.dart`).
- `GameSync.reportDeath` 주석: 사망은 “위치 이동”이므로 다른 플레이어에게 전달되어야 한다 (`game_sync.dart:29-33`) — **의도만 있고 Spacetime 구현 없음**. `onPlayerDied`에서 `sync?.reportDeath` 호출 (`938`)은 no-op.
- `GameSync.tick` 주석: “위치 스트리밍처럼 주기적인 전송에 쓴다” (`:11-12`) — 인터페이스 여지만 존재.

**재사용할 레퍼런스 — `onPlayerDied` (`904-938`)**

1. (사망 전용) 잔해 이펙트  
2. `player.respawnAt(map.respawnPoint(_))`  
3. `camera.viewfinder.position = _cameraTarget()` — 스무딩 스킵  
4. `_refreshBlockStreaming()` / `_refreshMonsterStreaming()`  
5. 이펙트·배너·`reportDeath`

텔레포트는 2–4(+선택 5)와 동일 후처리가 필요하다. 단 **`respawnAt` 통째 재사용 금지**:

- `_hp = _maxHp`, `energy = maxEnergy` → 전투 중 텔레포트 = 풀 회복 어뷰즈  
- 레벨·XP·버프 유지 의도는 살릴 수 있음(주석 `401-400`)  
- 입력/넉백/대시/`_ghosts` 클리어·`syncTransform`은 재사용 가치 있음  

**권장 API (구현 시 스케치, 작성은 하지 않음)**

- `Player.teleportTo(Vector2 point)` — `grid` 설정, 이동·넉백·대시·고스트 정리, `syncTransform()`, HP/EN **유지**. (짧은 무적은 선택; 요청 없음)
- `ActionRpgGame.teleportPlayer(…)` — `nearestWalkable` → `player.teleportTo` → 카메라 즉시 → 스트리밍 즉시 → 시트 닫기 → (선택) 배너/SFX.

**멀티플레이**

- 현재: 타 플레이어 렌더 없음 → 로컬 `grid` 조작만으로 “동기화 깨짐” 없음.  
- 미래 프레즌스(`GAME-DESIGN.md:606-608`): 서버 위치 권위 시 클라이언트 단독 텔레포트는 치트 → 그때 reducer + 구독. **cowork-prompt 서버 원칙**: `account_id`를 인자로 받지 않고 `ctx.sender()` 세션 도출 (`lib.rs:9-11`, cowork-prompt Instructions 2).

### 3.5 충돌 · 착지

- 이동: 몸 반경 코너 4점 `isWalkableAt` (`player.dart:249-266`, `bodyRadius` 약 0.28).
- 스폰 보정: `nearestWalkable` 반경 24.
- 세이프존 내부: 전 칸 walkable 테스트됨.
- 외곽 4방: 노이즈 허공·타워 가능 → **필수 `nearestWalkable`**.
- 적: 세이프존 안 플레이어 타겟 불가 (`enemy.dart:174-177`); 순간이동으로 세이프 진입 시 어그로 해제에 유리.

### 3.6 순간이동 시 깨질 수 있는 것

| 시스템 | 위험 | 기존 완화 |
|---|---|---|
| 카메라 스무딩 (`_updateCamera`) | 1 km 횡단 “비행” | 사망 시 즉시 스냅 — 텔레포트도 **필수** |
| 블록 스트리밍 0.25 s | 도착 직후 빈 공간 | `_refreshBlockStreaming` 즉시 |
| 몬스터 활성 46 m / 해제 60 m | 구 위치 적 잔류·신 위치 미활성 | `_refreshMonsterStreaming` 즉시 |
| GroundLayer bake 3/frame | 도착 후 잠시 바닥 미베이크 | 기존 한도; 선택적 예산 일시 상향 |
| 적 어그로 1–5 m | 추격 중 원거리 점프 | 거리·세이프존으로 페이즈 전환 |
| 대시/넉백 미정리 | 착지 후 미끄러짐 | `respawnAt`과 같이 상태 클리어 |
| 투사체·픽업 | 구 위치 잔여 | 치명적 아님 |
| 서버 프레즌스 | 미구현 | N/A |

### 3.7 밸런스 / 치팅 (요청 외 → 권고만)

- PK 목표(`CLAUDE.md:25-26`) 대비 무제한 텔레포트 = **전투 중 세이프 도주**, 외곽 파밍 후 즉시 귀환, 미래 PvP 회피.
- 현재 전투·위치는 클라이언트 권위 → 서버 검증 불가(cowork-prompt Instructions 5와 동일 한계).
- **요청에 없는** 쿨다운·전투 잠금·비용은 넣지 말고 §5 선택 항으로만.

### 3.8 파일 단위 구현 계획 (실행하지 않음)

네이밍: snake 파일 + Pascal 클래스 (`WorldMenu`, `LeaderboardScreen`, `respawnPoint`). UI 라벨 한글 (`'캐릭터 정보'` 패턴).

1. **생성** `lib/game/ui/teleport_sheet.dart` — 하단 시트, 5버튼, `isOpen`/`_anim`, `GamePalette`, TapCallbacks.  
2. **생성** `lib/game/level/teleport_destinations.dart` — enum/라벨 + `Vector2 resolve(LevelMap, Random?)` 내부 `nearestWalkable`.  
3. **수정** `lib/game/action_rpg_game.dart` — 마운트, `openTeleport`/`closeTeleport`/`teleportPlayer`, Esc 체인, 캐릭터/리더보드 open 시 시트 close 역방향 편입, (선택) 전용 아이콘 레이아웃.  
4. **수정** `lib/game/entities/player.dart` — `teleportTo` (HP/EN 유지).  
5. **수정(소)** `lib/game/ui/world_menu.dart` — 메뉴 항목 경로를 쓸 때만 `WorldMenuIcon.teleport` + 글리프.  
6. **생성** `test/teleport_test.dart` — 5점 walkable, 세이프 포함, 시드 고정 회귀.  
7. **서버/GameSync** — 1차 **수정하지 않음**. (선택) 미래 훅은 실제로 호출할 때만 추가.  
8. **문서(선택)** `GAME-DESIGN.md` §11에 한 줄.

---

## 4. 리스크 · 함정

- **루트 오인**: cowork cwd가 `plugins/cache`이면 구현 에이전트가 “코드 없음”으로 종료할 수 있음. 수정 루트는 `tmp/games/actionrpg`.
- **`respawnAt` 오용**: 텔레포트마다 풀피·풀EN → 밸런스 붕괴.
- **카메라/스트리밍 누락**: 장거리 “비행”, 빈 맵·몬스터 팝인.
- **가장자리 raw 좌표 / `nearestWalkable`→`spawn` 폴백**: 허공 착지 또는 의도치 않은 중앙 착지.
- **방위 라벨**: 아이소 화면 방향 vs 그리드 축 혼선.
- **하단 시트 ↔ 퀵슬롯·조이스틱** 터치 겹침.
- **Flutter overlay로 bottom sheet**: 인게임 Flame 입력·MMO non-pause 규칙과 어긋남 (`cowork-prompt.md:89-91`).
- **패널 상호 배타 불완전**: 인벤은 지금 다른 패널과 안 닫힘 — 텔레포트 open 시 인벤 close를 명시하지 않으면 입력 레이어 겹침.
- **미래 멀티**: 로컬 텔레포트만 고착되면 프레즌스 도입 시 전면 재작업; 서버 원칙 위반(클라이언트 신뢰) 설계 금지.
- **요청 외 쿨다운 강제 구현** = 스코프 크리프.

---

## 5. 권고안

| 순위 | 권고 | 범위 | 근거 | 리스크 |
|---|---|---|---|---|
| 1 | **신규** `teleport_sheet.dart` — Flame 하단 시트 + 5목적지 버튼; `GamePalette`/우선순위 140대 | UI | `character_screen.dart:11-31`, `cowork-prompt.md:89-91` | 퀵바(`inventory_ui.dart:68-71`)와 높이 충돌 |
| 2 | **전용 텔레포트 아이콘**을 viewport에 배치(미니맵 아래·월드메뉴 인근); 요청 “icon”에 맞춤. WorldMenu 항목은 보조 | 게임 UI | `action_rpg_game.dart:304-305`, `hud.dart:325` | 우상단 밀집 시 터치 타깃 축소 |
| 3 | **`teleport_destinations.dart`** — 5점 + `nearestWalkable`; 세이프는 `respawnPoint`/`safeZoneCenter` | 레벨 | `level_map.dart:90-103,195-212` | edge·폴백 시 중앙 착지 — UI 알림 권장 |
| 4 | **`Player.teleportTo`** — 위치·전투 상태 정리·`syncTransform`만; **HP/EN 유지**. `respawnAt` 복붙 금지 | 엔티티 | `player.dart:401-426` | 대시 미정리 시 미끄러짐 |
| 5 | **`ActionRpgGame.teleportPlayer`** — 카메라 즉시 + `_refreshBlockStreaming` + `_refreshMonsterStreaming`; Esc·open 상호 close에 시트 편입; open 시 **인벤도 close** | 게임 루프 | `onPlayerDied` 916-924, Esc 1058-1067, 인벤 745-749 | 이펙트 과다 연출 부담 |
| 6 | **SpacetimeDB / `GameSync` 1차 변경 없음** | net | `spacetime_game_sync.dart:8-11`, `lib.rs:86-115` | 미래 프레즌스 시 재작업 — 문서에 “로컬 전용” 한 줄이면 충분 |
| 7 | **`test/teleport_test.dart`** — walkable·세이프존·외곽 보정 회귀 (시드 `20260804`) | test | `safe_zone_test.dart`, `level_map.dart:233` | 맵 생성 비용 — 단위 테스트 범위 한정 |
| 8 | *(선택·요청 외)* 쿨다운 30–60 s 또는 세이프존에서만 출발 등 도주 완화 — **제품 결정 후** | 밸런스 | `CLAUDE.md:25-26`, PK 미구현 | 스코프 크리프 |

---

## 6. 불확실 · 미확인

- 오케스트레이터가 의도한 쓰기 루트가 `actionrpg`가 맞는지(세션 cwd는 `plugins/cache`) 사람 확인.
- 동·서·남·북 UI 카피가 **그리드 축**인지 **화면 방위**인지 기획 확정 없음 — §3.3은 코드 관례 기반 `[판단]`.
- `edge` 최적값 및 “가장자리 감성”은 시드 `20260804` 맵 실플레이 미측정.
- 멀티 프레즌스·PK 일정 미상 → 1차 로컬 전용 vs 서버 선행 분기.
- GroundLayer 순간이동 직후 빈 청크 체감 프레임 수 런타임 미측정.
- `.cowork/cowork-prompt.md`가 **HP 분석용 주제**를 아직 들고 있음 — 텔레포트 전용 불변 규칙은 문서화되어 있지 않음(일반 Flame/서버 규칙만 유효).
- `Overlays.levelUp` 상수는 있으나 `main.dart` overlay 빌더 미등록 — 텔레포트와 무관, 혼동 주의.

---

## 7. 자기 비판으로 바로잡은 것

- ❌ 철회: “`.cowork/cowork-prompt.md` 없음” — `…/tmp/games/actionrpg/.cowork/cowork-prompt.md`를 다시 열어 **존재** 확인. 1차는 플러그인 cache 루트만 보고 단정함. (단 본문 분석 주제는 HP·피해 재설계로 남아 있어 텔레포트 persona로 그대로 쓰지 않음.)
- 🔁 수정: “모든 패널이 상호 배타 open” → **캐릭터/리더보드만** 상대·인벤을 닫고, **`toggleInventory`는 다른 패널을 닫지 않음** (`action_rpg_game.dart:745-749,756-789`). 텔레포트 open 시 인벤 close를 **명시 권고**로 강화.
- 🔁 수정: “Overlays는 main/pause/gameOver뿐” → 클래스에 **`levelUp` 상수도 존재** (`:43-48`); 빌더 등록은 세 메뉴뿐 (`main.dart:106-110`). 근거를 과장하지 않음.
- 🔁 수정: “open 시 WorldMenu도 닫기”를 필수처럼 씀 → 메뉴 항목 경로는 **`onSelected` 전 스스로 close** (`world_menu.dart:169-170`). 전용 아이콘 경로만 선택적 close.
- 🔁 수정: edge “15~25”를 사실처럼 서술 → 코드 상수는 **`margin=3`**, **`avenueSpacing=40`**만 확정. edge 최적값은 `[판단]`.
- 🔁 수정: `GameSync`에 `reportTeleport` 훅 예약을 권고 상위에 둠 → **1차 서버/인터페이스 변경 없음**으로 격하. `reportDeath` 주석이 이미 “위치 이동” 미래 의도를 담고 있고(`game_sync.dart:29-33`), 미호출 훅은 데드 코드.
- ➕ 추가: **`nearestWalkable` 실패 시 `spawn`(중앙) 폴백** (`level_map.dart:212`) — 외곽 텔레포트 침묵 실패 위험.
- ➕ 추가: **`PotionQuickBar` 하단 중앙** (`inventory_ui.dart:68-71`) — bottom sheet 레이아웃 충돌의 구체 근거.
- ➕ 추가: GroundLayer **`_chunkBudgetPerFrame = 3`** (`ground_layer.dart:49-50`) — 착지 직후 바닥 지연의 수치 근거.
- ➕ 추가: `SafeZoneField` 꼭짓점 이름 north/east/south/west (`safe_zone.dart:129-133`) — 방위 축 `[판단]`의 코드 단서.
- ➕ 추가: cowork-prompt **작업 경로·Flame UI 강제** (`:89-91, :100`)로 UI 계층 결론을 문서 규칙과 일치시킴.
- 🔁 약화: laryen 반증을 핵심 결론처럼 씀 → 존재 확인(`/Users/thruthesky/apps/game/laryen`)은 했으나 SpacetimeDB 불일치로 **본 보고서 범위 밖**; 장황한 가지치기는 축소.
