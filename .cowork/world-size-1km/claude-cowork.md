<!-- cowork:claude | 2026-08-04 21:07:33 | exit=0 | 498s -->
# claude 분석 — world-size-1km

> 요청: 게임 월드의 크기가 가로 1km, 세로 1km 이어야합니다. 그렇게 되어져 있는지 분석하고 수정/보완해주세요.
> 생성: 2026-08-04 21:07:33 · 소요 498s · 읽기 전용 분석(작업공간 미수정)

---



## 1. 결론 요약

**월드는 이미 가로 1 km × 세로 1 km 로 되어 있다.** 클라이언트 `kWorldTiles = 1000` × `kMetersPerTile = 1.0`(`lib/game/iso.dart:21,27`), 서버 `WORLD_TILES = 1000.0`(`spacetimedb/src/world.rs:48`), 문서(`GAME-DESIGN.md:23,196`)가 모두 일치하고, `LevelMap.generate()` 를 다른 크기로 부르는 경로는 코드에 없다. **크기를 키우는 작업은 불필요하다.**

수정·보완이 실제로 필요한 것은 세 가지다 — ① **명세를 담은 상수 `kWorldSizeMeters` 가 죽어 있다**(참조처 0, `kWorldTiles` 는 리터럴 1000 이라 둘이 어긋나도 아무도 모른다), ② **크기 회귀 테스트가 없다**, ③ **서버 `move_to` 가 허용하는 좌표 범위 `[0, 1000]` 이 클라이언트가 실제로 걸을 수 있는 `[3, 997)` 과 어긋난다**(`world.rs:489-490` vs `level_map.dart:251-255`).

## 2. 근거

- `lib/game/iso.dart:21,24,27` — `kMetersPerTile = 1.0`, `kWorldSizeMeters = 1000.0`, `kWorldTiles = 1000`. 27행 주석은 "`kWorldSizeMeters` / `kMetersPerTile`" 이라 적혀 있으나 **값은 리터럴 `1000`** 이다(유도식이 아니다).
- 전역 grep 결과 — `kWorldSizeMeters` 와 `kWorldChunks`(`iso.dart:24,36`)를 **참조하는 코드가 한 줄도 없다**. 명세를 선언한 상수가 실제 월드를 지배하지 않는다.
- `lib/game/level/level_map.dart:228-232` — `LevelMap.generate({int width = kWorldTiles, int height = kWorldTiles, ...})`.
- `lib/game/action_rpg_game.dart:186,1112` · `test/teleport_test.dart:9` · `test/safe_zone_test.dart:54,104` — `LevelMap.generate()` 호출부는 이 넷뿐이고 **전부 인자 없이** 부른다. 더 작은 맵으로 도는 경로는 없다.
- `lib/game/level/level_map.dart:118-121` — `widthInMeters`/`heightInMeters` 게터가 있으나 grep 상 **참조처가 없다**. 1 km 를 확인할 수단이 있는데 아무도 쓰지 않는다.
- `lib/game/level/level_map.dart:245-262` — `const margin = 3`, 외곽 3칸을 `TileType.none` 으로 고정. **격자는 1000 m 지만 발을 디딜 수 있는 폭은 약 994 m** 다.
- `lib/game/level/level_map.dart:126-129` — `_index` 는 `x >= width` 면 `-1`. 타일 인덱스의 유효 상한은 **999**(1000 이 아니다).
- `lib/game/action_rpg_game.dart:428-439` — 카메라 클램프 `left = -map.height * 64`, `right = map.width * 64`, `bottom = (width+height) * 32`. 그리드 (0,0)~(1000,1000)의 화면 좌표 범위 `[-64000, 64000] × [0, 64000]` 과 **정확히 일치한다. 이상 없음.**
- `spacetimedb/src/world.rs:47-48` — `pub const WORLD_TILES: f32 = 1000.0;` 주석: "클라이언트 `kWorldTiles` 와 같아야 한다". **같은지 검증하는 장치는 없다.**
- `spacetimedb/src/world.rs:489-490` — `let x = grid_x.clamp(0.0, WORLD_TILES);` → 좌표 **1000.0 을 허용**. 클라이언트에서 이 값은 맵 밖이다.
- `spacetimedb/src/world.rs:391-392` — 몹 스폰 `const MARGIN: f32 = 24.0;` 주석은 "가장자리는 지형이 끊겨 있으므로" 인데, 실제 클라이언트 외곽 공백은 **3칸**이다. 값은 안전한 쪽이지만 근거가 실제 지형과 맞지 않는다.
- `spacetimedb/src/world.rs:356-357` — 서버 몹 레벨 `rim = 거리 / 500`, `level = 1 + rim × (MAX_LEVEL - 1)` (**선형**). `spacetimedb/src/leaderboard.rs:30` — `MAX_LEVEL: u32 = 30`(**플레이어 만렙**).
- `lib/game/systems/monster_codex.dart:283,359-367` — 클라이언트 몹 레벨 상한 **200**, 곡선은 `depth^1.6`(`_regionCurve`). 같은 1 km 격자의 같은 지점에서 서버는 최대 30, 클라이언트는 최대 200 을 산출한다.
- `spacetimedb/src/lib.rs:23,172` — `pub mod world;`, `world::bootstrap(ctx)`. 서버 월드는 컴파일·배포 경로에 들어 있다.
- `lib/spacetime/generated/` 목록 — `world_player.dart`·`monster.dart` 가 **없다**. 클라이언트 바인딩이 `world.rs` 추가 이후 재생성되지 않았다.
- `lib/game/systems/wave_director.dart:122-127` — 스폰 폴백이 `_random.nextDouble() * map.width` 로 **월드 전역**을 뽑는다.
- `lib/game/systems/monster_population.dart:147` — `halfSpan = max(width, height) / 2` = 500. 난이도 곡선이 1 km 라는 값에 직접 매달려 있다.
- `lib/game/ui/hud.dart:24,447-454` — 레이더 반경 70 m + 좌표 텍스트. 월드 경계선은 그리지 않는다.

## 3. 상세 분석

### 3.1 "1 km 인가" 에 대한 직접 답 — 그렇다

이 프로젝트에서 거리의 권위는 **그리드(타일)** 이고 `kMetersPerTile = 1.0` 이므로 타일 번호가 곧 미터다(`GAME-DESIGN.md:137,151`). 따라서 한 변 1000 타일 = 1000 m 다. 데이터 경로를 끝까지 따라가면 어긋나는 지점이 없다.

```
iso.dart:27  kWorldTiles = 1000
  └▶ level_map.dart:228-232  generate(width: 1000, height: 1000)
       └▶ Uint8List(1_000_000) × 3장 (타일·구조물 높이·구조물 종류)
            └▶ action_rpg_game.dart:186  map = LevelMap.generate()   ← 인자 없음
server: world.rs:48  WORLD_TILES = 1000.0  → world_center() = (500, 500)
```

카메라 클램프(`action_rpg_game.dart:428-439`)까지 `map.width`/`map.height` 를 그대로 쓰고 있어 화면이 월드 밖 허공을 비추지도 않는다. 즉 **"1 km 로 만들어라" 는 작업은 이미 완료된 상태다.**

### 3.2 그런데 그 1 km 를 지키는 장치가 없다

세 개의 상수가 서로 독립적으로 존재한다.

| 상수 | 값 | 참조처 | 문제 |
|---|---|---|---|
| `kWorldSizeMeters` (`iso.dart:24`) | 1000.0 | **0곳** | 명세를 선언만 하고 아무 힘이 없다 |
| `kWorldTiles` (`iso.dart:27`) | 1000 (리터럴) | 생성·청크 계산 | 실질 권위. 위 상수와 연결돼 있지 않다 |
| `WORLD_TILES` (`world.rs:48`) | 1000.0 | 서버 전역 | 손으로 복제. 주석으로만 연결 |

`kMetersPerTile` 을 0.5 로 바꾸면 월드는 500 m 가 되는데 `kWorldSizeMeters` 는 여전히 1000 을 주장한다. 반대로 `kWorldSizeMeters` 를 800 으로 바꿔도 월드는 1000 타일 그대로다. **어느 쪽을 고쳐도 컴파일도 테스트도 통과한다.** 이것이 이번 요청("1 km 인지 확인하라")에 대한 실질적 결함이다 — 지금은 확인할 방법이 사람이 직접 세 파일을 여는 것뿐이다.

`test/` 전체에 `expect(map.width, kWorldTiles)` 류의 검증이 없다. `test/safe_zone_test.dart:13` 이 `SafeZone.centeredOn(Vector2(500, 500))` 로 중심 500 을 **암시**할 뿐이고, 이건 월드가 1000 이라는 사실을 간접적으로 전제할 뿐 강제하지 않는다.

### 3.3 경계 정합 — 서버가 허용하는 1 km 와 클라이언트가 걸을 수 있는 1 km 가 다르다

축 하나를 늘어놓으면 이렇다.

```
0        3                                        997      1000
├────────┼─────────────────────────────────────────┼────────┤
│ none   │        통행 가능 (약 994 m)              │ none   │   클라이언트 (level_map.dart:251-255)
├────────┴─────────────────────────────────────────┴────────┤
│              move_to 가 허용 (0 ~ 1000, 양끝 포함)          │   서버 (world.rs:489-490)
└───────────────────────────────────────────────────────────┘
        ↑ 서버만 허용                              서버만 허용 ↑
```

두 가지가 겹쳐 있다.

1. **오프바이원.** `clamp(0.0, WORLD_TILES)` 는 상한 1000.0 을 포함한다. 타일 인덱스의 유효 상한은 999 이므로(`level_map.dart:126-129`) 좌표 1000.0 은 어느 타일에도 대응하지 않는다.
2. **외곽 여백 미반영.** 클라이언트는 외곽 3칸을 통행 불가로 못 박았는데(`level_map.dart:251-255`) 서버는 그 사실을 모른다.

지금은 증상이 드러나지 않는다 — `lib/spacetime/generated/` 에 `world_player.dart` 가 없어 **클라이언트가 서버 월드를 아직 읽지 않기 때문**이다. 그러나 이 프로젝트의 다음 단계가 원격 플레이어 표시(`GAME-DESIGN.md:606-608`)이므로, 그때 다른 요원의 고스트가 데이터 공백 위에 서 있는 그림이 나온다. **MMORPG 전제에서 이 6 m 폭 띠는 "모두가 같은 월드에 있다" 는 명제가 처음으로 깨지는 지점이다.**

### 3.4 1 km 라는 값에 매달려 있는 파생 수치들

월드 크기는 상수 하나가 아니라 **여러 곳에서 500(=halfSpan)이라는 값으로 재사용되는 축**이다.

| 위치 | 1 km 의존 방식 |
|---|---|
| `monster_population.dart:147,175,178` | `halfSpan = 500`. 중심에서의 거리 / 500 이 곧 구역 난이도 |
| `monster_codex.dart:359-363` | `depth^1.6 × 199` → 구역 레벨 1~200 |
| `world.rs:356-357` | `rim × 29` → 구역 레벨 1~30 (**선형, 상한 다름**) |
| `teleport_destinations.dart:45` | `edgeInset = 30`. 월드 크기와 무관한 절대값 |
| `hud.dart:24` | 레이더 70 m. 월드의 7 % 만 보인다 |
| `action_rpg_game.dart:130,134` | 몹 활성 46 m / 해제 60 m |

여기서 **서버와 클라이언트의 난이도 곡선이 정면으로 어긋난다.** 월드 가장자리(거리 500 m)에서 클라이언트는 200 레벨 몹을 세우고 서버는 30 레벨 몹을 세운다. 게다가 서버는 몹 레벨 상한으로 `leaderboard::MAX_LEVEL`(플레이어 만렙 30)을 그대로 끌어다 쓴다(`world.rs:96,357`) — 이 프로젝트가 용어 수준에서 금지한 **플레이어 `level` 과 몬스터 레벨의 혼동**이 코드에 들어 있는 셈이다.

밀도도 갈린다. 서버는 1 km² 에 **240 마리**(`world.rs:59`), 클라이언트는 1024 청크 × 청크당 3~13 마리로 **수천 마리** 규모다(`monster_population.dart:181`). 서버 밀도로 계산하면 몹 사이 평균 간격이 약 61 m 라 활성 반경 46 m 를 넘는다 — 서버 권위로 넘어가는 순간 **1 km 월드가 텅 빈 들판이 된다.** [추측] 정확한 클라이언트 개체 수는 시드와 통행 가능 칸에 따라 달라 실행해 봐야 확정된다.

### 3.5 1 km 월드에서만 드러나는 웨이브 스폰 결함

`wave_director.dart:122-127` 의 최후 폴백:

```dart
final x = _random.nextDouble() * map.width;   // 0 ~ 1000
final y = _random.nextDouble() * map.height;
if (map.isWalkableAt(x, y)) return Vector2(x, y);
```

플레이어와의 거리를 전혀 보지 않는다. 1 km 월드에서 이 경로를 타면 적이 최대 1.4 km 떨어진 곳에 생기고, 그 적은 활성 반경 46 m 밖이라 플레이어가 걸어가지 않는 한 영원히 잠들어 있다. 그런데 웨이브 종료 판정은 `enemies.every((enemy) => !enemy.isAlive)`(`action_rpg_game.dart:616`) 이므로 **웨이브가 끝나지 않는다.** 220 회 시도가 모두 실패해야 도달하는 드문 경로지만, 맵이 작던 시절에는 무해했던 코드가 1 km 로 커지면서 위험해진 전형적인 사례다.

### 3.6 범위와 경계

- **월드 기하 크기** — 클라이언트 `iso.dart` 와 서버 `world.rs` 양쪽에 복제되어 있다. 한쪽만 고치면 안 된다.
- **지형 실체** — 클라이언트 전용 절차 생성. 서버는 타일을 갖지 않으므로 통행 가능 여부를 판정할 수 없다. 서버 쪽에서 할 수 있는 것은 **격자 범위와 여백을 상수로 맞추는 것까지**이며, 그 이상(데이터 공백 회피)은 지형을 서버로 올리거나 시드를 공유해야 하는 별개의 과제다.
- **결정 권한** — 서버 변경은 `spacetime publish` 재배포를 수반한다. 클라이언트만 고치는 선택지와 명확히 갈린다.

## 4. 리스크 · 함정

- **"1 km 가 안 되어 보인다" 는 체감은 크기 문제가 아니다.** 화면에 보이는 것은 세로 약 760 px 분량(`action_rpg_game.dart:217-221`)이고 레이더는 70 m 다(`hud.dart:24`). 이 체감을 근거로 `kWorldTiles` 를 키우면 지형 배열이 제곱으로 늘고(현재 3 MB) 스트리밍·개체군 밀도·`edgeInset` 이 연쇄로 무너진다. **크기 상수는 건드리지 말아야 한다.**
- **`kWorldTiles` 를 `kWorldSizeMeters ~/ kMetersPerTile` 로 바꾸는 것은 값이 바뀌지 않는 안전한 변경**이지만(1000.0 ~/ 1.0 = 1000), Dart const 문맥에서 `~/` 가 허용되는지는 실제 컴파일로 확인해야 한다. [추측] 언어 명세상 허용되는 연산자로 알고 있으나 이 저장소에서 컴파일해 보지는 않았다.
- **서버 클램프를 좁히면 이미 끝선에 있는 세션 좌표가 한 번 보정된다.** 눈에 띄지 않는 수준이지만 되돌리려면 재배포가 필요하다.
- **서버 몹 레벨 상한을 30 → 200 으로 바꾸면 기존 몬스터 240 마리의 레벨이 전부 바뀐다.** `bootstrap` 은 `count() > 0` 이면 건너뛰므로(`world.rs:346`) 재배포만으로는 반영되지 않고, 기존 행을 지우는 별도 조치가 필요하다. 이건 되돌리기 어려운 축에 속한다.
- **서버·클라이언트 몹 밀도(240 vs 수천)를 지금 정렬하려 들면 요청 범위를 크게 넘는다.** 어느 쪽이 권위인지는 아직 정해지지 않은 설계 결정이며(`GAME-DESIGN.md:597-611`), 크기 문제가 아니다.
- **`.cowork/cowork-prompt.md` 가 `spacetimedb/src/world.rs` 를 언급하지 않는다.** 파일 목록·전투 수치 표 어디에도 없다. 프롬프트 작성 이후 추가된 것으로 보이며, "서버가 전투를 시뮬레이션하지 않는다" 는 프롬프트의 전제(§5)와 달리 **서버에 몬스터·킬 판정·PK 골격이 이미 들어와 있다**. 지침 문서와 실제 자료가 어긋나는 지점이므로 프롬프트를 갱신하는 편이 좋다.
- **생성 코드가 뒤처져 있다.** `lib/spacetime/generated/` 에 `world_player`·`monster` 바인딩이 없어, 서버 월드 관련 수정은 지금 당장은 클라이언트에서 검증할 수단이 없다. `dart run spacetimedb_sdk:generate` 재실행이 선행되어야 실효를 확인할 수 있다.

## 5. 권고안

| 순위 | 권고 | 범위 | 근거 | 리스크 |
|---|---|---|---|---|
| 1 | **크기 상수를 건드리지 말 것.** 월드는 이미 1 km × 1 km 다. 이번 작업은 "키우기" 가 아니라 **고정·검증**이다 | 판단 | `iso.dart:21,27`, `level_map.dart:228-232`, `world.rs:48`, `GAME-DESIGN.md:23` | 불필요한 변경 시 스트리밍·밸런스 동시 붕괴 |
| 2 | **`test/world_size_test.dart` 신설.** ① `kWorldSizeMeters == 1000.0` ② `tilesToMeters(kWorldTiles.toDouble()) == kWorldSizeMeters` ③ `LevelMap.generate().width/height == kWorldTiles` ④ `widthInMeters/heightInMeters == 1000` ⑤ `chunksX == chunksY == 32` ⑥ 안전지대 중심 == (500,500) ⑦ **통행 가능 경계 계약** — `isWalkable(2,*)` 은 false, 안쪽은 true | 클라이언트 테스트 | `test/` 에 크기 검증 부재. `safe_zone_test.dart:13` 이 500 을 암시할 뿐 | 없음. 비용 최소, 효과 최대 |
| 3 | **`iso.dart` 의 상수를 명세에서 유도.** `kWorldTiles` 를 `kWorldSizeMeters ~/ kMetersPerTile` 로 바꿔 값(1000)은 그대로 두되 **명세가 실제를 지배하게** 한다. 쓰이지 않는 `kWorldChunks` 는 `LevelMap.chunksX` 와 중복이므로 제거하거나 실제로 쓴다 | 클라이언트 | `iso.dart:24,27,36` — 참조처 0인 죽은 상수 | const 문맥에서 `~/` 컴파일 확인 필요 |
| 4 | **외곽 여백 `margin = 3` 을 `iso.dart` 의 `kWorldEdgeMarginTiles` 상수로 승격.** 지금은 `level_map.dart:245` 안에 갇혀 있어 서버·텔레포트·테스트가 각자 다른 숫자를 쓴다(`edgeInset = 30`, 서버 `MARGIN = 24`) | 클라이언트 | `level_map.dart:245`, `teleport_destinations.dart:45`, `world.rs:391` | 없음 |
| 5 | **서버 `move_to` 클램프를 클라이언트 격자와 정렬.** `clamp(0.0, WORLD_TILES)` → 통행 가능 범위 `[MARGIN, WORLD_TILES - MARGIN]` 으로 좁히고, `WORLD_TILES` 가 **배타 상한**임을 주석에 못 박는다. `cargo test` 에 경계 케이스 추가 | 서버 | `world.rs:489-490` vs `level_map.dart:126-129,251-255` | `spacetime publish` 재배포 필요. 끝선 좌표 세션이 한 번 보정됨 |
| 6 | **`GAME-DESIGN.md` §5.1 에 경계 계약 한 줄 명시** — "격자 1000 × 1000 m, 외곽 3 m 는 통행 불가 테두리이므로 실질 통행 폭 994 m. 서버 `WORLD_TILES` 와 손으로 동기화한다" | 문서 | `level_map.dart:251-255`, `world.rs:47` | 구현 변경 없음 |
| 7 | **`WaveDirector` 스폰 폴백을 플레이어 주변으로 한정.** 월드 전역 무작위 대신 `maxDistance` 를 단계적으로 넓히고, 최후에는 `map.nearestWalkable(playerGrid)` 를 쓴다 | 클라이언트 | `wave_director.dart:122-127`, `action_rpg_game.dart:616` | 낮음. 스폰 실패 시 플레이어에게 더 가까이 붙을 수 있음 |
| 8 | **서버 몬스터 레벨 상한을 플레이어 만렙에서 분리.** `world.rs:357` 의 `MAX_LEVEL`(=30) 대신 `MONSTER_MAX_LEVEL = 200` 을 별도 선언하고, 곡선도 클라이언트와 같은 `depth^1.6` 로 맞춘다 | 서버 | `world.rs:96,356-357`, `leaderboard.rs:30` vs `monster_codex.dart:283,359-367` | **높음.** 기존 몹 240 행의 레벨이 바뀌며, `bootstrap` 이 `count()>0` 으로 건너뛰므로 기존 행 삭제가 별도로 필요 |
| 9 | **(선택) 미니맵에 월드 경계선.** 레이더 반경 70 m 안에 월드 가장자리가 들어오면 선을 그린다 | 클라이언트 UI | `hud.dart:321-393` — 경계 표시 없음 | 낮음. Flame `PositionComponent` 캔버스 좌표 기준으로 그려야 한다 |
| 10 | **(선행 조건) 생성 코드 재생성** — `dart run spacetimedb_sdk:generate` 로 `world_player`·`monster` 바인딩을 만들어야 5·8번의 효과를 클라이언트에서 확인할 수 있다 | 빌드 | `lib/spacetime/generated/` 에 해당 파일 부재, `lib.rs:23` | 생성물은 손으로 고치지 않는다는 규칙 준수 필요 |

**검증 절차**: 2·3·4·7·9 → `flutter analyze`(error/warning 0) + `flutter test`. 5·8 → `cd spacetimedb && cargo test` + `cargo build --target=wasm32-unknown-unknown --release` + `spacetime publish withcenter-cyborg --server maincloud -p ./spacetimedb --yes`.

## 6. 불확실 · 미확인

- **Dart const 문맥에서 `~/` 사용 가능 여부**를 이 저장소에서 컴파일로 확인하지 않았다(권고 3). 불가하다면 `kWorldTiles` 는 리터럴로 두고 테스트에서 `kWorldSizeMeters / kMetersPerTile == kWorldTiles` 를 강제하는 방식으로 대체할 수 있다.
- **클라이언트 상주 몬스터의 정확한 총수**는 시드와 통행 가능 칸에 좌우되어 실행 없이는 확정할 수 없다. "청크당 3~13 × 1024 청크" 라는 상한 구조만 코드에서 확인했다.
- **1000 × 1000 생성의 실기기 소요 시간·메모리 피크**를 측정하지 않았다. 배열 할당량 약 3 MB 는 코드에서 계산한 값이다.
- **maincloud 에 실제 배포된 `world.rs` 가 로컬 소스와 같은지** 확인하지 못했다. 소스 기준으로만 판단했다.
- **`GroundLayer`·`LevelMap` 의 노이즈가 뚫는 데이터 공백의 실제 비율**(따라서 서버 몹 240 마리 중 몇 마리가 허공에 서는지)은 실행해야 알 수 있다. 임계값 `n < 0.30`(`level_map.dart:260`)만 확인했다.
- **`.cowork/cowork-prompt.md` 가 `world.rs` 를 모른다는 점**은 사람의 판단이 필요하다. 프롬프트를 갱신할지, 아니면 `world.rs` 를 아직 미완성 계층으로 취급할지에 따라 권고 5·8 의 우선순위가 달라진다.
- 이 분석은 **읽기 전용**으로 수행했다. 어떤 파일도 수정하지 않았고, 위 권고는 전부 글로만 적은 것이다.
