<!-- cowork:kimi | 2026-08-04 21:04:12 | exit=0 | 297s -->
# kimi 분석 — world-size-1km

> 요청: 게임 월드의 크기가 가로 1km, 세로 1km 이어야합니다. 그렇게 되어져 있는지 분석하고 수정/보완해주세요.
> 생성: 2026-08-04 21:04:12 · 소요 297s · 읽기 전용 분석(작업공간 미수정)

---

• 

## 1. 결론 요약

  **이미 가로 1 km × 세로 1 km 로 되어 있다. 수정할 코드는 없다.** 단일 진실 상수 `kWorldSizeMeters = 1000.0` / `kWorldTiles = 1000`(`lib/game/iso.dart:21-27`)이 정의돼 있고, `kMetersPerTile = 1.0` 이라 타일 = 미터가 성립한다. 맵 생성(`LevelMap.generate` 기본값 `level_map.dart:229-230`), 카메라 가둠, 이동 통행 판정, 몬스터 배치·난이도 곡선, 텔레포트 목적지가 전부 이 상수나 `map.width/height` 에서 파생되므로 하드코딩된 어긋남은 발견되지 않았다. 서버(SpacetimeDB)도 `WORLD_TILES = 1000.0`(`spacetimedb/src/world.rs:48`)으로 일치한다. 보완이 필요한 것은 크기 자체가 아니라 **회귀 방지**다 — 월드 크기를 못 박는 테스트가 없고, 클라이언트·서버 두 상수가 주석 한 줄에만 의존해 수동 동기 상태다.

  

## 2. 근거

  - `lib/game/iso.dart:21` — `const double kMetersPerTile = 1.0;` (타일 = 미터)
  - `lib/game/iso.dart:23-27` — `kWorldSizeMeters = 1000.0`(주석 "가로 1 km × 세로 1 km"), `kWorldTiles = 1000`
  - `lib/game/level/level_map.dart:229-230` — `LevelMap.generate({int width = kWorldTiles, int height = kWorldTiles})`; 호출처 `lib/game/action_rpg_game.dart:186,1118` 은 인자 없이 기본값 사용
  - `lib/game/level/level_map.dart:118-121` — `widthInMeters`/`heightInMeters` = `tilesToMeters(width/height)` → 1000 m
  - `spacetimedb/src/world.rs:47-48` — `pub const WORLD_TILES: f32 = 1000.0;` (주석: "클라이언트 `kWorldTiles` 와 같아야 한다")
  - `spacetimedb/src/world.rs:498-499` — 서버 `move_to` reducer 가 좌표를 `clamp(0.0, WORLD_TILES)` 로 가둠 (월드 밖 좌표 서버 수용 불가)
  - `spacetimedb/src/world.rs:400-401` — 몬스터 스폰 범위 `MARGIN(24) ~ WORLD_TILES - MARGIN`
  - `lib/game/entities/player.dart:328-331` + `lib/game/level/level_map.dart:126-128,150-158` — 플레이어 착지 판정 `_canStandAt` → `isWalkableAt` → 범위 밖 인덱스는 `false`, 즉 맵 가장자리(외곽 3칸은 `TileType.none`, `level_map.dart:245-255`) 밖으로 걸어 나갈 수 없음
  - `lib/game/action_rpg_game.dart:436-447` — `_clampToWorld` 가 카메라를 월드 마름모 안에 가둠 (주석 "1 km 월드라…")
  - `lib/game/systems/monster_population.dart:147,162-163,178` — 몬스터 배치·구역 레벨이 `map.width/height` 파생 `halfSpan`(=500)과 청크 루프(`map.chunksX/Y`) 기반, 크기 상수 비하드코딩
  - `lib/game/level/teleport_destinations.dart:54-64` — 동/서/남/북 목적지가 `map.width`/`map.height` 파생 (`edgeInset = 30`)
  - `GAME-DESIGN.md:23,196,690` — 설계 문서도 "1 km × 1 km (1000 × 1000 타일)" 로 일치
  - `test/monster_codex_test.dart:117-135` — 구역 레벨 테스트가 `halfSpan = 500` 전제로 짜여 있어 1000타일 월드와 정합

  

## 3. 상세 분석

  **정의 계층.** 월드 크기의 단일 진실은 `lib/game/iso.dart` 두 상수다. `kMetersPerTile = 1.0` 이므로 "1000타일 = 1000 m = 1 km" 가 성립하고, 가로·세로가 각각 `kWorldTiles` 기본값으로 들어가므로 정사각형 1 km² 이다.

  **소비 계층(전부 파생, 하드코딩 없음).**
  - 지형: `LevelMap.generate` 는 1000×1000 = 100만 칸을 `Uint8List` 3장(바닥·구조물 높이·종류)으로 들고, 외곽 3칸(`margin = 3`, `level_map.dart:245`)은 허공으로 뚫어 경계를 만든다.
  - 통행·전투: 플레이어와 적의 이동은 `isWalkableAt` 을 거치므로 논리적 월드 밖으로 나가는 경로가 없다.
  - 렌더링·스트리밍: 청크 격자(`kChunkTiles = 32`) 기준이며 `chunksX/chunksY`(`level_map.dart:123-124`)와 시야 클램프(`monster_population.dart:101-108`, `action_rpg_game.dart:509-512`, `ground_layer.dart:72-75`)가 모두 맵 크기에서 계산된다.
  - 서버: 좌표 클램프·스폰·안전지대·몬스터 레벨 곡선(`world.rs:365-366`, 중심 거리를 `WORLD_TILES/2` 로 정규화)이 같은 1000 전제다.

  **설계 문서와의 일치.** `GAME-DESIGN.md` 의 월드 규격 기술(:23, :196, :690)이 코드와 정확히 일치한다 — 문서↔코드 불일치 발견은 없다.

  **청크 경계 처리.** 1000 은 32 로 나누어떨어지지 않아 `kWorldChunks = 32`(iso.dart:36), 마지막 청크는 8타일 폭이다. `level_map.dart:173-174` 와 `ground_layer.dart:160-161` 이 `math.min(start + kChunkTiles, width)` 로 끝을 잘라 처리하므로 오버런은 없다.

  **범위·경계.** 이 판단은 클라이언트 로컬 월드 + SpacetimeDB 서버 월드 두 계층 모두에 해당한다. 두 계층이 각자 상수를 들고 있으므로 "월드 크기 변경" 은 양쪽을 함께 바꿔야 하는 영역이며, 지금은 양쪽 다 1000 으로 맞물려 있다.

  

## 4. 리스크 · 함정

  - **진실 공급원 이원화.** 클라이언트 `kWorldTiles`(iso.dart:27)와 서버 `WORLD_TILES`(world.rs:48)는 주석 한 줄("같아야 한다")에만 의존한다. 한쪽만 바뀌면 서버가 1000 밖 좌표를 거절/클램프하거나 클라이언트가 맵 밖을 렌더링하는 어긋남이 생긴다. `.cowork/teleport/final-report.md:130` 도 동일한 위험("월드 크기가 바뀌면 동/서/남/북 좌표가 함께 움직인다")을 지적했다.
  - **회귀 감지 수단 부재.** `kWorldTiles == 1000` 이나 `LevelMap.generate()` 기본 크기를 못 박는 테스트가 없다(`test/` 에서 확인된 것은 safe_zone 50 m 검증뿐, `test/safe_zone_test.dart:18-19`). 누군가 상수를 고쳐도 CI 가 잡지 못한다.
  - **미니맵은 전체 월드가 아닌 레이더.** `hud.dart:24` `_radarRangeTiles = 70` — 플레이어 주변 ±70 m 만 보여 주므로 "1 km 월드" 의 전체 윤곽을 확인할 화면 수단이 없다. 규격 위반은 아니지만, 1 km 규모 체감·검증용 전체 맵이 없다는 점은 인지해 둘 만하다 [판단].
  - **클라이언트·서버 몬스터 밀도 비대칭.** 서버는 `MONSTER_COUNT = 240`(world.rs:59), 클라이언트 로컬 개체군은 청크당 3~12마리씩 수천 마리(`monster_population.dart:181`). 월드 크기 문제는 아니지만, 멀티플레이 전환 시 같은 1 km² 안에서 개체 수가 두 체계로 갈라져 있는 상태다.
  - **마지막 청크 8타일.** 버그는 아니나 청크 단위 균등 가정(예: 청크당 스폰 수)이 가장자리에서 자연스럽게 줄어든다 — 향후 크기를 32 의 배수로 바꿀 때만 신경 쓸 지점.

  

## 5. 권고안

  | 순위 | 권고 | 범위 | 근거 | 리스크 |
  |---|---|---|---|---|
  | 1 | 크기 상수 회귀 테스트 추가: `kWorldSizeMeters == 1000`, `kWorldTiles == 1000`, `kMetersPerTile == 1.0`, `LevelMap.generate()` 의 `width/height/widthInMeters` 가 1000 임을 검증 | `test/` (클라이언트) | `lib/game/iso.dart:21-27`, `level_map.dart:229-230` | 없음 — 읽기 전용 단언 테스트 |
  | 2 | 서버 쪽에 `WORLD_TILES == 1000.0` 및 `move_to` 클램프 상한 단위 테스트 추가(`world.rs` 기존 `#[cfg(test)]` 모듈에) | `spacetimedb/src/world.rs` | `world.rs:48,498-499,732` | 없음 |
  | 3 | 클라·서버 상수 동기를 주석 의존에서 한 단계 올리기: 생성 코드 경로(`dart run spacetimedb_sdk:generate`)처럼 크기 상수를 한 곳에서 만들어 양쪽에 심거나, 최소한 클라이언트 테스트가 `WORLD_TILES` 값을 `spacetimedb/src/world.rs` 에서 읽어 대조 | 양 계층 공통 | `world.rs:47` 주석 | 과한 자동화는 빌드 복잡도 증가 — 파일 파싱 대조 테스트 수준이 적정 [판단] |
  | 4 | 월드 크기 변경 시 점검 목록을 `GAME-DESIGN.md` §5 또는 `iso.dart` 주석에 명시(iso.dart 상수 → world.rs → 몬스터 codex 테스트의 `halfSpan = 500` → 텔레포트 `edgeInset`) | 문서 | `test/monster_codex_test.dart:117-135`, `teleport_destinations.dart:45` | 없음 |
  | 5 | (선택) 디버그/개발용 전체 월드 맵 오버레이 — 1 km² 규모와 구역 레벨 분포를 눈으로 검증할 수단 | `lib/game/ui/` | `hud.dart:24,319-328` | 신규 UI 작업 — 이번 요청 범위 밖 [판단] |

  

## 6. 불확실 · 미확인

  - `lib/game/ui/world_menu.dart`·`lib/game/ui/teleport_sheet.dart` 등 UI 가 월드 크기를 문자열로 어딘가에 표시하는지는 열어 보지 않았다. 표시가 있다면 상수 파생인지 하드코딩인지 확인이 필요하다.
  - `spacetimedb/src/` 의 나머지 파일(계정·리더보드)은 월드 크기와 무관해 보이나, 월드 크기를 참조하는 다른 서버 파일이 있는지 전수 검색(`WORLD_TILES` 사용처는 world.rs 내부로 확인됐지만 다른 파일의 별도 상수 가능성)은 완료하지 못했다.
  - `.cowork/world-size-1km/` 에 병렬 cowork 흔적(다른 AI 의 프롬프트·grok 1차 결과)이 있고 `kimi-cowork.md`·`claude-cowork.md` 가 비어 있는 상태다 — 이 보고서가 그 파이프라인의 산출물로 수집될 것으로 보이며, 오케스트레이터의 최종 판단이 남아 있다.
  - 월드 크기를 1 km 로 "바꿔야" 하는 게 아니라 "유지 확인" 이 맞는 상황이므로, 사람이 의도한 게 확장(예: 2 km)이었다면 그때는 §5-4 의 점검 목록이 출발점이 된다 — 사람 판단 필요.
