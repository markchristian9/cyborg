<!-- cowork:claude | 2026-08-04 20:36:13 | exit=0 | 371s -->
# claude 분석 — teleport

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
> 생성: 2026-08-04 20:36:13 · 소요 371s · 읽기 전용 분석(작업공간 미수정)

---



## 1. 결론 요약

**요청한 텔레포트 시스템은 이미 전부 구현돼 있다.** (a) 메뉴/아이콘, (b) 아이콘 탭 → bottom sheet, (c) 목적지 목록, (d) 선택 시 이동 — 네 가지 모두 동작하는 코드가 존재한다. 목적지는 5개가 아니라 **10곳**이고, 세이프존(서울역 마을)은 이미 월드 중앙(원점 근처)이다. 따라서 남은 일은 "시스템 추가"가 아니라 **"목적지 목록을 요청대로 중앙+동/서/남/북 5개 방위 체계로 재구성할 것인가"라는 기획 결정** 하나다.

두 가지 전제 오류를 먼저 바로잡는다. ① **분석 대상 작업공간이 틀렸다** — `/Users/thruthesky/.claude/plugins/cache` 는 Claude Code 플러그인 캐시이고 게임 코드가 없다(`.dart` 파일 1개, 그마저 환율 API 테스트 스크립트). 실제 게임은 `/Users/thruthesky/apps/game/laryen` 이다. ② **백엔드는 SpacetimeDB 가 아니라 Nakama + 자체 Go Zone 서버(UDP)** 다.

## 2. 근거

- `/Users/thruthesky/.claude/plugins/cache` Glob 결과 — 하위는 `RevenueCat/`·`claude-plugins-official/`·`thruthesky-skills/` 뿐. 게임 소스 없음. 실제 프로젝트는 `/Users/thruthesky/apps/game/laryen`
- `laryen/CLAUDE.md:167` — "백엔드는 Nakama 서버(`v5-nakama`, TCP 7352/7353)". SpacetimeDB 언급 없음
- `lib/features/game/hud/game_control_pad.dart:94` — `teleport(FontAwesomeIcons.solidBoltLightning, 'Teleport')` — 번개 아이콘이 이미 등록돼 있음
- `game_control_pad.dart:226` — `ControlAction.teleport, // 맨 위(2026-07-26 추가 — 아래 3개 자리는 그대로)` — 컨트롤 패드 수직 컬럼 최상단
- `game_control_pad.dart:559-572` — 아이콘 `onPressed: () => showTeleportSheet(context, game)`
- `game_control_pad.dart:1931-1945` — 게임 메뉴에도 별도 타일(`_menuTile`)로 존재, `onBack: _reopenMenu` 로 메뉴 복귀
- `lib/features/game/teleport/teleport_sheet.dart:26-52` — `showTeleportSheet` 가 `showModalBottomSheet` + 공용 `ResizableSheetFrame` 으로 bottom sheet 를 연다
- `teleport_sheet.dart:252-257` — 목적지 탭 → `widget.game.sendWarp(d.id)` 후 즉시 시트 닫기
- `lib/features/game/teleport/teleport_catalog.dart:142-263` — 목적지 **10곳**(`seoul_station`·`bukchon_hanok_village`·`dongdaemun_bus_terminal`·`incheon_port`·`gangnam_forsythia`·`busan`·`gangnam_subway`·`gangbuk_subway`·`washington_d_c`·`manila`)
- `lib/net/v5_zone_client.dart:784-789` — `sendWarp(String destId)` → `WARP <seq> <destId>`. 주석: "★목적지 *id* 만 보낸다 — 좌표·mapId 를 클라가 정하지 않는다"
- `game-server/zone/internal/sim/teleport_warp.go:68-160` — `OnWarpRequest` 가 서버 권위로 검증·이동
- `game-server/zone/config/game.config.yaml:893-913` — `teleport.destinations` 정의(id·targetMap·safeZone·requiredSkill)
- `game-server/zone/internal/sim/world_metrics.go:13-24` — `WorldHalfExtentCm int32 = 9_600`(±96m, 총 192m), `TileWorldSize int32 = 32`(cm), 격자 600×600. 주석: "원점 (0,0) = 안전지대 중심"
- `lib/features/game/pathfinding/safe_zones_gen.dart:10-15` — 세이프존 bbox(server cm). `seoul_station_town_safe_zone` = `[-490, 165, -1342, -919]` (원점 근처 = 월드 중앙)
- `game-server/zone/internal/sim/det_rand.go:85,98` — 스폰 점은 `pointInPolygon(x,y,poly) && IsWalkableCm(x,y)` 로 뽑음(rejection 64회 + 격자 스캔 fallback)
- `teleport_warp.go:302-309` — `safeZoneSpawnByNameDeoverlap` 가 다른 PC 와 겹치면 seed 를 바꿔 재시도
- `lib/features/game/render/snapshot_interpolator.dart:28-33` — `_teleportThresholdSqCm = 500 * 500`. 500cm 이상 위치 변화는 보간 없이 즉시 점프
- `GAME-DESIGN.md:780` — "빌드·수집·생활·**PvP** 의 다양성(Horizontal) 은 **Phase 11+** 라이브 운영에서 확장" — PvP 는 미구현 계획 단계
- `game-server/zone/internal/monster/lv_band.go:13` — "10 = Skynet (PvP, Lv 100+)" — 밴드 주석뿐, 실제 PK 로직 부재

## 3. 상세 분석

### 3-1. UI 구조 — HUD 는 Flutter 위젯 오버레이

세 계층이 분리돼 있다. **Flame 컴포넌트**(`IsoHuntGame`/`iso_hunt_world.dart`)가 월드를 그리고, 그 위에 **Flutter 위젯 오버레이**로 HUD 가 얹힌다(`game_control_pad.dart`·`game_hud_overlay.dart`). 시트는 전부 `showModalBottomSheet` 다.

텔레포트 진입점은 **두 곳**이다. ① 컨트롤 패드 수직 컬럼 최상단 번개 아이콘(`game_control_pad.dart:226`) — 직접 열기라 `onBack` 을 주지 않는다. ② 게임 메뉴 타일(`:1931`) — `onBack: _reopenMenu` 로 메뉴 복귀. 이 구분은 `CLAUDE.md:131` 의 "표시 판정은 `onBack` 콜백 유무뿐" 규칙을 정확히 따른 것이다.

시트 자체는 공용 `ResizableSheetFrame`(30~90% 스냅·글래스 배경·전용 핸들)을 재사용한다 — `CLAUDE.md:137` 의 ABSOLUTE 규칙("목록형 바텀 시트는 반드시 공용 프레임 재사용")대로다. **인벤토리·리더보드도 같은 패턴**이므로 새 UI 를 만들 이유가 없다.

### 3-2. 월드 좌표계와 방위

서버 좌표는 **cm 단위 정수, 원점 (0,0) = 월드 중앙**, 범위 ±9,600cm(`world_metrics.go:15`). 1 타일 = 32cm, 격자 600×600. 클라 렌더는 `destTileSize` 64×32 아이소메트릭으로 투영하고, `iso_hunt_world.dart:1173-1176` 이 "object 데이터 좌표의 맵 중앙 = server world 원점" 으로 정렬한다.

**y 축 부호는 지명이 알려준다** — `gangbuk_bukchon_hanok_village_town_safe_zone` 의 y 는 `[-4799, -4220]`(음수), `gangnam_forsythia_town_safe_zone` 의 y 는 `[3337, 4274]`(양수). 강북=북, 강남=남이므로 **y 음수 = 북, y 양수 = 남**이다.

기존 마을 5곳의 bbox 중심을 계산하면:

| 목적지 | 중심 (x, y) cm | 방위 성격 |
|---|---|---|
| `seoul_station` | (−163, −1131) | **중앙** (원점 근처) |
| `dongdaemun_bus_terminal` | (2539, −4806) | 북(y 최소) · 동쪽 치우침 |
| `bukchon_hanok_village` | (−8983, −4510) | 북서 |
| `incheon_port` | (−9241, 3550) | **서**(x 최소) · 남쪽 치우침 |
| `gangnam_forsythia` | (4503, 3806) | 남(y 최대) **겸** 동(x 최대) |

즉 **세이프존=중앙은 이미 정확히 맞다.** 하지만 나머지 4곳은 정확한 동/서/남/북 축이 아니라 네 모서리(사분면)에 가깝고, 특히 `gangnam_forsythia` 가 동·남 양쪽에서 최대라 **"동"과 "남"을 서로 다른 마을에 배정하면 하나는 부정확해진다**. 동쪽 끝(+9600 근처)에는 마을이 아예 없다.

### 3-3. 이동 경로 — 클라는 목적지 id 만 보낸다

플레이어 위치는 **로컬 관리가 아니라 서버 권위**다. 경로는 다음과 같다.

`showTeleportSheet` → 타일 탭 → `game.sendWarp(destId)` → `v5_zone_client.dart:788` 이 `WARP <seq> <destId>` 를 **신뢰 채널**로 전송(서버 `LastWarpSeq` dedup 으로 재전송해도 1회만 처리) → 서버 `OnWarpRequest` 가 검증 → 결과는 `WARPRES <destId> <result> <reason>` 로 회신.

**좌표를 클라가 정하지 않는 것이 이 설계의 핵심 보안**이다(`v5_zone_client.dart:780-781`). 서버 카탈로그 allowlist 밖 id 는 `unknown_dest` 로 거부된다.

서버는 두 갈래로 처리한다(`teleport_warp.go:108-160`):

- **같은 맵**(서울역·동대문·인천·북촌·강남 개나리 — 전부 `laryen_2km`): 좌표만 바꾼다. 재연결·로딩 0. 다음 SNAP 의 self 좌표로 반영
- **다른 맵**(부산·지하철 2종·해외 2종): 기존 `TELE` 경로 재사용 → 클라 `_enterDungeon` 이 재연결. `pendingTransfer` 보안(서버가 발급한 목적지만 다음 HELLO 에서 허용)이 그대로 적용

### 3-4. 순간이동 시 깨질 수 있는 것들 — 이미 전부 처리돼 있다

질문한 항목이 하나씩 대응된다.

- **이동 보간**: `snapshot_interpolator.dart:33` 의 `_teleportThresholdSqCm = 500*500` — 500cm 이상 변화는 선형 보간 대신 즉시 점프. "주르륵 미끄러지는 잔상" 방지
- **카메라 추적**: `teleport_warp.go:158` 이 `broadcastPlayerEvent(sid, StateRespawn)` 로 respawn 이벤트를 **재사용**해 클라가 카메라·예측 위치를 즉시 스냅하게 한다. 별도 wire 추가 없음
- **잔류 이동 입력**: `teleport_warp.go:130-136` 이 `VxCmps`·`VyCmps`·`InputDx/Dy`·`UserInputDx/Dy` 를 전부 0 으로 리셋. 주석대로 "조이스틱 release(INPUT 0,0)가 유실되면 도착 후 옛 방향으로 계속 밀린다"
- **자동 공격·어그로**: `:139-148` 이 `AutopilotEnabled`·`AutopilotSearch`·`AutopilotZoneLocked`·`AutopilotTargetSpawnID` 등을 해제해 옛 사냥터 anchor 로 끌려가지 않게 한다. 단 **파티 follower 는 예외**(`updatePartyFollowAnchors` 가 매 tick 재설정)
- **몬스터 즉사**: `:153` 이 `SpawnProtectionUntilTick = s.tick + SpawnProtectionTicks` 로 도착 직후 스폰 보호
- **포털 재발동 루프**: `:151` 이 `InTeleportZone` edge-trigger 상태를 갱신해 도착지가 텔레포트 영역과 겹쳐도 즉시 재발동하지 않게 한다
- **청크 로딩**: `world_metrics.go:9` — "청크 상수/`WorldToChunk`/`active_chunk` 는 **제거되었다**". 월드가 192m 단일이라 청크 개념 자체가 없다

### 3-5. 도착 지점 충돌 — 재사용 가능한 함수가 이미 있다

두 단계로 막는다.

1. **벽/void 회피**: `safeZoneSpawnByName` → `randomPointInPolygon`(`det_rand.go:79-90`)이 `pointInPolygon && IsWalkableCm` 조건으로 결정론 rejection sampling 64회, 실패 시 `fallbackWalkableInPolygon` 격자 스캔. 주석대로 "PC 가 벽/void 에 스폰돼 갇히는 것을 막는다"
2. **다른 PC 와 겹침 회피**: `safeZoneSpawnByNameDeoverlap`(`teleport_warp.go:302-309`)이 `tooCloseToPC` 면 seed 를 바꿔 재시도

또 `ValidateTeleportMaps`(`:314-334`)가 **기동 시** 설정의 맵·안전지대 이름 실재를 검증하고, 없으면 `panic` 으로 부팅을 막는다 — 주석대로 "메뉴에 떠 있는데 눌러도 엉뚱한 곳에 도착" 하는 조용한 오동작을 원천 차단한다.

`teleport_warp.go:297-301` 이 명시적으로 경고한다: **`nearestSafeZoneSpawn` 을 대신 쓰면 안 된다** — 그건 출발지에서 가장 가까운 영역을 고르므로 "인천으로 보내려 해도 출발지가 동대문 근처면 동대문이 뽑힌다".

### 3-6. 밸런스 — 현재 쿨다운은 없고, PK 도 없다

`OnWarpRequest` 의 거부 조건은 **거래 중**(`inventoryBusy`, `:84`), **사망 중**(`HpI32 <= 0`, `:90`), **출입증 미습득**(`:96`) 셋뿐이다. **쿨다운·전투 중 제한·시전 시간이 전혀 없다.**

다만 요청문의 "PK 가 허용되는 MMORPG" 라는 전제는 **현재 코드와 맞지 않는다**. `GAME-DESIGN.md:780` 은 PvP 를 Phase 11+ 라이브 운영 확장 항목으로 두고 있고, `lv_band.go:13` 의 "Skynet (PvP, Lv 100+)" 는 밴드 주석일 뿐 실제 PK 로직이 없다. `GAME-DESIGN.md:251` 은 오히려 **PC-PC hard collision 을 ABSOLUTE 로 금지**한다.

따라서 "전투 중 도주" 문제는 **현재로선 PvP 가 아니라 PvE 한정**이다. 무제한 텔레포트로 몬스터·보스 어그로를 즉시 끊고 마을로 복귀할 수 있다. 다만 진입 장벽이 이미 세 겹이다 — 레벨(Lv20/30/100), 부품 납품(`game.config.yaml:864-866`, "공짜 금지"), 피트 NPC 대면 학습. 그리고 도착지가 항상 **안전지대**라 사냥터→사냥터 전술 이동은 애초에 불가능하다.

## 4. 리스크 · 함정

- 🛑 **가장 큰 리스크는 "이미 있는 것을 다시 만드는 것"이다.** 새 `teleport_menu.dart` 나 별도 시트를 만들면 `teleport_sheet.dart` 와 이중화돼, 서버 목적지가 늘 때 한쪽만 갱신되는 조용한 drift 가 생긴다
- 🛑 **`teleport_catalog.dart` 는 서버 `game.config.yaml` 의 표시용 복제 SSOT 다** — `teleport_catalog.dart:3-7` 이 경고한다. 클라만 고치면 "메뉴엔 갈 수 있다고 떠 있는데 눌러도 거부" 가 된다. **반드시 서버 yaml 과 함께** 바꿔야 하고, `teleport_catalog_test.dart` 가 CI 로 가드한다
- 🛑 **목적지를 5개로 줄이면 기존 캐릭터가 깨진다.** `CLAUDE.md:30-38` 의 ABSOLUTE 하위호환 규칙 — 이미 `skill_teleport_busan`·`skill_teleport_subway` 를 부품 수십 개 바쳐 배운 캐릭터가 있다면, 그 목적지를 지우는 것은 **소급 불가능한 손실**이다
- 🛑 **마을 세이프존과 텔레포트 목적지는 1:1 강제**다 — 서버 테스트 `TestEveryTownSafeZoneHasTeleportDest`(`teleport_catalog.dart:188` 주석)가 강제한다. 목적지를 지우면 이 테스트가 깨진다
- **동/서/남/북 라벨은 현재 지형과 정확히 맞지 않는다** — §3-2 표대로 `gangnam_forsythia` 가 동·남 양쪽 최대이고, 동쪽 끝에는 마을이 없다. 억지로 라벨을 붙이면 플레이어가 "동쪽으로 갔는데 남쪽이잖아" 라고 느낀다
- **yaml 을 바꾸면 Zone·Nakama 를 *함께* 재배포**해야 한다(`CLAUDE.md:27`) — 한쪽만 올리면 판정이 갈린다
- **쿨다운을 넣는다면 코드가 아니라 `game.config.yaml` 에** — `CLAUDE.md:19-28` ABSOLUTE. 클라에 상수로 박으면 조정할 때마다 스토어 재출시(리드타임 수일)가 걸린다
- **`ResizableSheetFrame` 호출 계약을 어기지 말 것** — `CLAUDE.md:138` 이 `constraints`·`useSafeArea: true`·자체 grabber 를 금지한다. `constraints` 를 주면 30~90% 가 화면의 12~36% 로 왜곡된다

## 5. 권고안

| 순위 | 권고 | 범위 | 근거 | 리스크 |
|---|---|---|---|---|
| 1 | **먼저 사용자에게 현황을 보고하고 의도를 확인한다** — "요청한 텔레포트 시스템은 이미 있고 목적지가 10곳이다. 5개 방위 체계로 *바꾸길* 원하는가, 아니면 기존 것을 못 찾은 것인가?" 실제 화면을 DTD 로 띄워 스크린샷으로 보여준다 | 기획 결정 | `teleport_sheet.dart:26`·`game_control_pad.dart:94,226,559` | 없음(확인 절차) |
| 2 | **아무것도 바꾸지 않는다(기본 권고)** — 요구사항 (a)(b)(c)(d)가 전부 충족돼 있고, 세이프존=월드 중앙도 이미 맞다. 목적지가 5개가 아니라 10곳인 것은 *초과 달성*이지 결함이 아니다 | 전체 | `teleport_catalog.dart:142-263`·`safe_zones_gen.dart:10` | 없음 |
| 3 | **방위를 원한다면 — 지우지 말고 *표시만* 방위로 보강한다.** `TeleportDestDef` 에 `compass` 필드(예: `'center'`/`'north'`)를 추가해 이름 옆에 방위 배지·아이콘을 붙이고, 목록을 방위순으로 정렬한다. 목적지는 그대로 10곳 유지 | 클라 표시 전용 (`teleport_catalog.dart` + `teleport_sheet.dart:_destTile`) | `CLAUDE.md:30-38`(하위호환)·§3-2 좌표표 | 낮음. 서버 무변경. 단 방위 배정이 §3-2대로 애매하므로 사용자 확정 필요 |
| 4 | **정확한 동/서/남/북을 원한다면 — 마을을 *지우는* 게 아니라 동쪽에 새로 만든다.** 현재 동쪽 끝(x≈+9600)에 마을이 없어 `gangnam_forsythia` 가 동·남을 겸한다. TMX 에 마을을 그리고 `spawn_zones_gen.go` 재생성 → `game.config.yaml` `destinations` 등록을 한 세트로 | 서버 TMX + `game.config.yaml:893` + `safe_zones_gen.dart` 재생성 | `teleport_catalog.dart:188`(마을=목적지 1:1 강제)·`world_metrics.go:15` | 중간. TMX 작업 + 재배포 필요. `ValidateTeleportMaps` panic 주의 |
| 5 | **쿨다운은 넣지 말 것을 권고한다(현시점).** PvP 가 미구현이라 "전투 중 도주" 문제가 아직 존재하지 않고, 사용자가 요청하지도 않았다. 훗날 PvP 도입 시 `game.config.yaml` 에 `teleport.cooldownSec`·`teleport.combatLockSec` 로 추가하고 `OnWarpRequest` 초입에서 검증 | 서버 `game.config.yaml` + `teleport_warp.go:83` 근처 | `GAME-DESIGN.md:780`(PvP Phase 11+)·`CLAUDE.md:19-28`(yaml SSOT) | 낮음(미실행). 지금 넣으면 불필요한 UX 마찰만 생김 |
| 6 | **도착 지점 충돌 처리는 손대지 말 것** — `randomPointInPolygon` + `IsWalkableCm` + `tooCloseToPC` 3중이 이미 완비돼 있고, 새 목적지를 추가해도 `safeZoneSpawnByNameDeoverlap` 하나만 호출하면 그대로 재사용된다 | 서버 `det_rand.go`·`teleport_warp.go:302` | `det_rand.go:85,98`·`teleport_warp.go:304` | 없음(무변경) |

**구현 계획(권고 3 채택 시, 파일 단위)** — 새 파일은 하나도 필요 없다:

1. `lib/features/game/teleport/teleport_catalog.dart` — `TeleportDestDef` 에 `final String compass;` 추가(기본값 `''`), 10개 항목에 값 채움. 기존 `nameKo`/`icon` 네이밍 컨벤션 그대로
2. `lib/features/game/teleport/teleport_sheet.dart:213-260` `_destTile` — `title` 의 `Text` 를 `Row` 로 바꿔 방위 배지를 앞에 붙임. `crossAxisAlignment: CrossAxisAlignment.center` **명시**(`CLAUDE.md:120` ABSOLUTE)
3. `lib/l10n/app_ko.arb` 외 3개 언어 — `teleportCompassNorth` 등 방위 문구 추가. 기존 `teleportSheetTitle` 계열과 같은 네이밍
4. 서버 변경 없음 — `game.config.yaml`·`teleport_warp.go` 무수정 (표시 전용이므로 SSOT drift 없음)
5. 검증 — `bash scripts/verify.sh client` → DTD 로 `iPhone 17 Pro Max` 실행 → 텔레포트 아이콘 탭 → `xcrun simctl io screenshot` (`CLAUDE.md:99-113` ABSOLUTE)

## 6. 불확실 · 미확인

- **사용자의 진짜 의도를 모른다.** 요청문이 "Add teleport system" 인데 이미 존재한다는 것은, ① 기존 구현을 모르고 있거나 ② 10곳이 너무 많아 5개 방위로 *단순화*하길 원하거나 ③ 다른 프로젝트를 생각하고 있는 것 중 하나다. **§5 권고 1(확인)이 다른 어떤 작업보다 먼저다**
- **분석 대상 작업공간이 `cache` 로 지정된 이유를 모른다.** cowork 를 게임 프로젝트가 아닌 플러그인 캐시 디렉토리에서 실행한 것으로 보이나, 의도적인지 실수인지 확인 못 했다
- **"PK 가 허용되는 MMORPG" 라는 전제의 출처를 못 찾았다.** `GAME-DESIGN.md` 는 PvP 를 Phase 11+ 미래 항목으로 두고 `lv_band.go` 에 주석만 있다. 사용자가 *계획*을 말한 것인지, 내가 못 찾은 PK 구현이 어딘가 있는지 미확인
- **`TODO.md` 를 읽지 않았다.** `CLAUDE.md:10-17` 이 "지금 무엇을 먼저 할 것인가의 단일 권위" 라고 명시하며 세션 시작 시 필독을 ABSOLUTE 로 요구한다. 텔레포트 관련 미완 항목이 거기 있을 수 있다
- **동/서/남/북 배정은 내 계산이지 기획 결정이 아니다.** §3-2 표의 bbox 중심 계산은 `safe_zones_gen.dart` 근거로 정확하지만, `gangnam_forsythia` 를 "동"으로 볼지 "남"으로 볼지는 **사람이 정할 문제**다
- **`ArrivalMessageComponent`(`lib/features/game/render/arrival_message.dart`)와 미니맵(`minimap_widget.dart`)이 방위를 이미 표시하는지 확인 못 했다** — 방위 UI 를 넣는다면 이 둘과의 일관성을 먼저 봐야 한다
- **다른 맵(부산·지하철·해외)의 세이프존 좌표는 확인 못 했다** — `safe_zones_gen.dart` 는 `laryen_2km` 것만 담고 있다. cross-map 목적지의 방위는 애초에 의미가 없을 수 있다
