<!-- cowork:kimi | 2026-08-04 20:42:55 | exit=0 | 773s -->
# kimi 분석 — teleport

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
> 생성: 2026-08-04 20:42:55 · 소요 773s · 읽기 전용 분석(작업공간 미수정)

---

• 작업공간 실제 구조를 먼저 확인하겠습니다.

• 실제 게임 프로젝트 경로를 찾기 위해 cowork 기록을 읽어보겠습니다.

• 

## 1. 결론 요약

  텔레포트 시스템은 **이미 완전히 구현되어 있다** — HUD 번개 아이콘 + bottom sheet(`showTeleportSheet`) + `WARP` 프로토콜 + 서버 검증까지 2026-07-26 에 도입됐다(`docs/teleport.md`, `lib/features/game/teleport/teleport_sheet.dart:26-52`). 따라서 이 요청은 신규 구축이 아니라 **기존 시트의 목적지 구성을 "세이프존 중앙 + 동/서/남/북 5곳"으로 바꾸거나 추가하는 작업**이다. 실제 프로젝트는 지정 작업공간(`~/.claude/plugins/cache`)이 아니라 **`/Users/thruthesky/apps/game/laryen`** 이고, 백엔드는 요청문의 전제와 달리 **SpacetimeDB 가 아니라 Nakama + Go UDP Zone 서버**다. 새 wire 를 만들 필요는 없고, 서버 yaml 의 `teleport.destinations` 에 5개 목적지를 등록하고 클라 카탈로그를 미러링하면 기존 WARP 경로가 그대로 동작한다.

  

## 2. 근거

  - `.cowork/hp/.logs/codex.log:1024` — 이전 cowork 세션이 실제 게임 프로젝트 위치를 `/Users/thruthesky/apps/game/laryen` 으로 기록. 지정 작업공간(`plugins/cache`)에는 게임 코드가 없음(`*.dart` 1개=스킬 테스트 스크립트뿐, `pubspec.yaml` 0건).
  - `laryen/pubspec.yaml` (firebase_core 등) + `GAME-SERVER.md:1-10` — 백엔드는 **Nakama(TS) + Go Zone(UDP)**, Firebase 는 챗봇용. SpacetimeDB 흔적 없음 → 요청문 전제 오류.
  - `lib/features/game/hud/game_control_pad.dart:94,225-230,559-572` — `ControlAction.teleport`(번개 아이콘)가 조이스틱 위 유틸 컬럼 맨 위에 이미 존재, 탭 시 `showTeleportSheet(context, game)` 호출.
  - `lib/features/game/teleport/teleport_sheet.dart:26-52` — bottom sheet: `showModalBottomSheet(isScrollControlled: true, backgroundColor: Colors.transparent)` + `ResizableSheetFrame`. `:254` — 선택 시 `game.sendWarp(d.id)`.
  - `game_control_pad.dart:1931-1945`, `lib/router.dart:301` — 메뉴(☰) 항목과 푸시 딥링크로도 동일 시트 진입.
  - `game-server/zone/internal/sim/world_metrics.go:13-15,26` — `WorldHalfExtentCm = 9600`(±96m), **원점 (0,0) = 맵 중심**, 1타일=32cm, 600×600 타일. `lib/core/map_metrics.dart:52-57` 클라 미러 동일 값.
  - `lib/features/game/render/iso_projection.dart:18-19` — `worldToScreen`: `sx = x - y`, `sy = (x + y) * 0.5` (1cm=1px). 방향 축: **+x=동, -x=서, +y=남, -y=북**(`game.config.yaml:895-901` 주석으로 실증).
  - `game-server/zone/internal/sim/spawn_zones_gen.go:21-26` — 메인 세이프존 `seoul_station_town_safe_zone` 폴리곤 bbox x -490..165, y -1342..-919 → 중심 ≈ **(-163, -1131)**.
  - `game-server/zone/internal/sim/teleport_warp.go:68-160` — 서버 `OnWarpRequest`: allowlist(`config.TeleportDestFor`) → 거래 중 거부 → 사망 중 거부 → 출입증 검증 → same-map 이면 `safeZoneSpawnByNameDeoverlap` 으로 좌표 교체 + 입력/autopilot 리셋 + 스폰 보호 150tick + `StateRespawn` EVENT 방송.
  - `game-server/zone/config/game.config.yaml:893-913` — `teleport.destinations` 에 이미 10개 목적지(서울역 무조건, 마을 4곳 Lv20, 부산 Lv30, 지하철 Lv100, 워싱턴/마닐라) — **목적지는 좌표가 아니라 safeZone 이름 기반**.
  - `lib/features/game/render/snapshot_interpolator.dart:33` — 500cm 이상 위치 급변 시 보간 없이 즉시 점프(순간이동 시 끌림 없음). `player_component.dart:1050-1070` — `_input==0` 이면 서버 좌표 즉시 대입(self reconcile).
  - `lib/features/game/render/iso_hunt_game.dart:7075-7097` — `recenterCameraOnRespawn()`: 카메라 `snap: true` 재추적.
  - `game-server/zone/internal/sim/walkable.go:41-50,100` — `IsWalkableCm`(비트셋 충돌 판정), `IsMobForbiddenCm`(세이프존=몹 금지). 클라 동일 규칙 `lib/features/game/pathfinding/walkable_grid.dart:24`.
  - `GAME-DESIGN.md:2422` — "1차 출시까지 모든 필드는 PvP 비활성(PC 끼리 무피해)" → **PK 미구현**. 향후 계획(Skynet, 관악 PK)은 `:2100-2110`, `:2420-2437`.
  - `docs/teleport.md:131-143,218-226` — 세이프존 바닥 타일 없으면 갇힘 → 최근접 walkable 폴백 존재; 클라 카탈로그↔서버 yaml drift 는 테스트로 가드.

  

## 3. 상세 분석

  ### 3-1. UI 메뉴 구조와 텔레포트 아이콘 위치 (질문 1)

  HUD 는 Flame 오버레이 `'hud'` 하나(`game_page.dart:2359-2373`, 등록된 Flame overlay 는 hud/trade 둘뿐) 위의 **순수 Flutter 위젯 트리**다. 모든 서브 화면(인벤토리=gear sheet, 리더보드, 설정, 채팅, 텔레포트)은 `Navigator.push` 가 아니라 **`showModalBottomSheet` + `ResizableSheetFrame`** 패턴으로 열린다. **텔레포트 아이콘과 시트는 이미 이 컨벤션대로 존재한다**: 패드 유틸 컬럼(`game_control_pad.dart:225-230`), 메뉴 항목(`:1931-1945`), 딥링크(`router.dart:301`). 사용자가 "상시 보이는 아이콘"을 원한다면(패드는 기본 숨김) 상단 바 우측 아이콘 열(`game_hud_overlay.dart:2429-2483`)에 `HudIconButton` + 기존 `showTeleportSheet` 연결이 컨벤션상 정확한 추가 위치다.

  ### 3-2. 월드 좌표계와 5개 목적지 (질문 2)

  월드는 600×600타일, ±9600cm(192m×192m), 원점=맵 중심, +x=동/+y=남. 렌더는 64×32px 아이소메트릭, 변환은 `iso_projection.dart:18-19`. 요구사항의 5개 목적지를 실제 좌표로 환산하면:

  - **중앙(세이프존)**: 메인 safe zone 폴리곤 중심 ≈ (-163, -1131) — 단, 기존 시스템은 좌표가 아니라 `seoul_station_town_safe_zone` **이름**으로 지정하면 서버가 영역 내 walkable 점을 결정론적으로 고른다(`teleport_warp.go:144-153`).
  - **동**: 강남권 sub-zone 중심, 예: `gangnam_apgujeong_sub_zone` 중심 (8634, -128) 또는 강남 개나리 마을 safe zone(이미 WARP 목적지로 존재, `game.config.yaml:900`).
  - **서**: 강북권, 예: `gangbuk_ray_station_sub_zone` 중심 (-7823, 1471) 또는 북촌 한옥 마을/인천항 safe zone.
  - **남**: 관악권, 예: `gwanak_k_art_hall_sub_zone` 중심 (-471, 8038) — 정남축.
  - **북**: 동대문권, 예: `dongdaemun_jangan_cherry_blossom_road_sub_zone` 중심 (-2235, -7786) 또는 동대문 터미널 마을 safe zone.

  주의: sub-zone 중심은 **사냥터 한복판**(몹 어그로 위험)이므로, 시스템 정석은 safe zone 이름 기반 도착이다.

  ### 3-3. 순간이동 경로 (질문 3)

  위치 권위는 **100% 서버**다 — 클라는 방향(dx/dy)만 보내고 좌표를 보내는 wire 자체가 없다(`v5_zone_client.dart:546`, `sim.go:1218-1288`). 순간이동의 정답 경로는 이미 있는 **WARP**: `sendWarp(destId)` → 서버 `OnWarpRequest` 검증(allowlist/거래/사망/출입증) → same-map 은 좌표 교체 + 8가지 상태 정리(속도 0·입력 0·autopilot 해제·InTeleportZone 재계산·스폰 보호 5초 등, `teleport_warp.go:127-153`) → `StateRespawn` EVENT → 클라 `forceClearDeathLock()` + 카메라 스냅. 보간 깨짐은 이미 방어됨(500cm 점프 임계, `_input==0` 즉시 대입). **SpacetimeDB 리듀서 같은 것은 존재하지 않는다** — 요청문의 백엔드 전제가 틀렸다.

  ### 3-4. 도착지 충돌 처리 (질문 4)

  재사용 자산이 모두 있다: 서버 `IsWalkableCm`(비트셋), `safeZoneSpawnByNameDeoverlap`(세이프존 내 겹침 없는 walkable 점), `nearestSafeZoneSpawn`(부활용 최근접 세이프존), `docs/teleport.md:131-143` 의 최근접 walkable 폴백. **safe zone 이름 기반 목적지를 쓰면 충돌 문제는 원천적으로 발생하지 않는다**(세이프존은 몹 금지 + walkable 보장 + 바닥 없음 폴백 존재).

  ### 3-5. 밸런스/치팅 (질문 5)

  - **PK 는 현재 미구현**(`GAME-DESIGN.md:2422`)이라 "전투 중 텔레포트 도주"는 몹 상대로만 의미가 있고, 이미 세이프존 진입 시 deaggro 규칙(`:271-274`)과 동일한 회피 수단이 게임에 상존한다. 기존 WARP 도 거부 사유가 `trading`/`dead` 뿐이라 전투 중 사용 가능하다.
  - 다만 향후 PK 도입(2~3차, `:2100-2110`, `:2420-2437`) 시 무제한 텔레포트는 PK 도주 수단이 된다. **권고로만 제시**: 전투 중(최근 피격 N초) WARP 거부 플래그 또는 쿨다운을 서버 `OnWarpRequest` 검증 목록에 추가하는 것 — 지금 넣을지는 사용자 결정 사항.
  - 요청의 5목적지(특히 동/서/남/북 사냥터 직행)는 기존 설계의 **출입증(레벨+부품) 게이팅**(`docs/teleport.md:26-37`)을 우회할 수 있다. 게이팅을 적용할지도 사용자 결정.

  

## 4. 리스크 · 함정

  - **전제 오류**: 요청문이 백엔드를 SpacetimeDB 로 기술했지만 실제는 Nakama + Go Zone. SpacetimeDB 리듀서를 찾아 구현 계획을 세우면 전부 무효가 된다.
  - **중복 구현 위험**: 텔레포트 기능 전체가 이미 존재한다. "새로 만들기"로 접근하면 아이콘·시트·프로토콜이 이중으로 생겨 컨벤션과 테스트(`docs/teleport.md:218-226` 의 drift 가드)를 깬다.
  - **사냥터 중심 좌표 직행의 위험**: 동/서/남/북을 sub-zone 중심으로 하면 도착 즉시 다수 몹 어그로. 서버의 5초 스폰 보호(`constants.go:175`)가 있어도 저레벨은 위험. 세이프존 없는 좌표에 바닥 타일이 없으면 갇힘 사례도 문서화돼 있다(`docs/teleport.md:131-143`).
  - **작업공간 불일치**: 지정 작업공간은 플러그인 캐시이고 게임 코드가 없다. 이 보고서의 근거는 전부 `/Users/thruthesky/apps/game/laryen` 에서 확인한 것이다.
  - **출입증 게이팅 충돌**: 무제한 5방향 텔레포트는 기존 Lv20/Lv30/Lv100 출입증 경제를 무력화시킨다 — 기획 의도와 충돌하므로 사용자 확인이 필요하다.
  - 입력 리셋 계약: same-map 강제 이동을 새 경로로 만들 때 `teleport_warp.go:127-153` 의 8가지 상태 정리를 하나라도 빠뜨리면 "텔레포트 후 옛 위치로 되걷기" 회귀가 재발한다(주석에 실제 사례 기록).

  

## 5. 권고안

  | 순위 | 권고 | 범위 | 근거 | 리스크 |
  |---|---|---|---|---|
  | 1 | 구현 착수 전 사용자에게 확인: 기존 텔레포트 시스템 존재를 아는지, 요청이 "기존 시트 목적지를 5곳(중앙+동서남북)으로 교체"인지 "별도 신규"인지 | 기획 결정 | `docs/teleport.md` 전체, `teleport_sheet.dart:26-52` | 확인 없이 진행 시 중복 구현 |
  | 2 | 5개 목적지는 `game.config.yaml` `teleport.destinations` 에 **safe zone 이름 기반**으로 추가(중앙=기존 `seoul_station`, 동=강남 개나리, 서=북촌/인천항, 남·북은 필요 시 신규 safe zone 또는 sub-zone 좌표) | `game-server/zone/config/game.config.yaml:893-913` | `teleport_warp.go:96-153` | yaml 이 SSOT — 코드 상수 우회 금지(GAME-SSOT.md §0) |
  | 3 | 클라 표시 미러 `teleport_catalog.dart` 에 동일 5개 반영 + drift 가드 테스트 갱신 | `lib/features/game/teleport/teleport_catalog.dart`, `test/` | `docs/teleport.md:218-226` | 서버↔클라 불일치 시 테스트 실패 |
  | 4 | UI 는 기존 `showTeleportSheet` 재사용; "상시 보이는 아이콘"이 요구 의도면 상단 바 아이콘 열에만 `HudIconButton` 1개 추가 | `lib/features/game/hud/game_hud_overlay.dart:2429-2483` | `game_control_pad.dart:559-572` | 패드 컬럼 중복 추가 시 레이아웃 밀림 |
  | 5 | (선택·사용자 결정) 전투 중 WARP 거부 또는 쿨다운을 `OnWarpRequest` 검증 목록에 추가 | `game-server/zone/internal/sim/teleport_warp.go:84-106` | `GAME-DESIGN.md:2420-2437` (향후 PK) | 사용자 미요청 기능 — 임의 추가 금지 |
  | 6 | (남/북에 safe zone 이 없다면) TMX 에 safe zone 영역 추가 후 `spawn_zones_gen.go` 재생성, 또는 `nearestWalkableAround` 폴백 경유 | `assets/map/seoul_map.tmx`, `game-server/zone/internal/sim/map_data.go:286-358` | `docs/teleport.md:131-143` | TMX 수정은 생성물 재생성·테스트 연쇄 |

  

## 6. 불확실 · 미확인

  - **사용자 의도**: 기존 텔레포트(10개 목적지, 출입증 게이팅)를 모르고 요청한 것인지, 알면서 5개 고정 목적지의 별도 시스템을 원하는지 — 이 답에 따라 권고 2~4의 방향이 갈린다.
  - **"동/서/남/북"의 정의**: 맵 가장자리 사냥터(전투 콘텐츠)인지, 각 방향의 마을/세이프존(안전 거점)인지 사용자 원문만으로는 불명확. 둘은 도착 안전성과 출입증 설계가 완전히 다르다.
  - **출입증 적용 여부**: 새 5개 목적지를 무제한(서울역처럼)으로 할지, 기존 스킬 게이팅에 태울지 — 밸런스상 사용자 결정 필요.
  - 기존 WARP 목적지 10개를 유지한 채 5개를 추가하는지, 시트를 5개로 교체하는지 미확인.
  - PK 도입 시점(2~3차 업데이트)의 실제 로드맵 진행 상황은 문서상 계획만 확인했고 현재 개발 상태는 미확인이다.
