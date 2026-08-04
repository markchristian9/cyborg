<!-- cowork:grok | 2026-08-04 21:04:23 | exit=0 | 308s -->
# grok 분석 — world-size-1km

> 요청: 게임 월드의 크기가 가로 1km, 세로 1km 이어야합니다. 그렇게 되어져 있는지 분석하고 수정/보완해주세요.
> 생성: 2026-08-04 21:04:23 · 소요 308s · 읽기 전용 분석(작업공간 미수정)

---



## 1. 결론 요약

**가로·세로 각 1 km 규격은 이미 충족된다.** 클라이언트 SSOT는 `kWorldTiles = 1000` × `kMetersPerTile = 1.0` = 1000 m이고, 런타임 맵도 `LevelMap.generate()` 기본값으로 그 크기를 만들며, 서버 `WORLD_TILES = 1000.0`과 문서가 같은 전제다.  
**규모를 키우는 “수정”은 불필요**하다. 의미 있는 보완은 (1) 크기 회귀 테스트 부재, (2) 클라 `kWorldTiles` / `kWorldSizeMeters` / 서버 `WORLD_TILES` **삼중 수동 복제**, (3) 서버 `move_to` 클램프 상한 inclusive `1000` vs 클라 타일 인덱스 `0..999` **끝점 1칸 여지**, (4) 외곽 3칸 허공으로 **격자 내부 통행 폭 ≈ 994 m** 의 의도 문서화다.  
몹 240 vs 클라 수천은 **같은 1 km 격자 위의 콘텐츠 권위 문제**이지, “맵이 1 km가 아니다”의 반증이 아니다.

---

## 2. 근거

- `lib/game/iso.dart:17-27` — `kMetersPerTile = 1.0`, `kWorldSizeMeters = 1000.0`, `kWorldTiles = 1000` (“가로 1 km × 세로 1 km”).
- `lib/game/iso.dart:29-36` — `kChunkTiles = 32`, `kWorldChunks = (1000+31)~/32 = 32` → 32×32 = 1024 청크.
- `lib/game/level/level_map.dart:53-57,117-121,228-230,244-254,444-451` — “1 km × 1 km” 주석, `widthInMeters`/`heightInMeters`, `generate` 기본 `width/height = kWorldTiles`, 외곽 `margin = 3` → `TileType.none`, 그 `width`/`height`로 반환.
- `lib/game/action_rpg_game.dart:187,210-212,1144-1145` — `onLoad`/`restart` 모두 `LevelMap.generate()`(인자 없음 = 1000×1000). 다른 `LevelMap.generate(width:, height:)` 호출 없음(저장소 전역 검색).
- `lib/game/action_rpg_game.dart:226-229,433-448` — 줌은 세로 ~760 px 분량 화면; 카메라 클램프는 `map.width`/`map.height` 기준(1 km 맵 전제).
- `spacetimedb/src/world.rs:47-48,313-315,489-490` — `WORLD_TILES: f32 = 1000.0`(클라와 같아야 한다는 주석), 중심 `(500, 500)`, `move_to`가 `clamp(0.0, WORLD_TILES)`.
- `spacetimedb/src/world.rs:55-59,391-392` — 서버 상주 몹 `MONSTER_COUNT = 240`; 스폰 마진 24 타일.
- `GAME-DESIGN.md:23,196-201,690` — 기획·§5.1·상수 요약 모두 “1 km × 1 km / 1000×1000 / ~3 MB”.
- `test/safe_zone_test.dart:13-19` — 안전지대 중심 `(500, 500)` → 1000×1000 전제와 일치. **`expect(map.width, 1000)` 류 테스트는 `test/`에 없음.**
- `lib/game/ui/hud.dart:24,316-320,447-451` — 미니맵은 반경 70 m 레이더 + 좌표(m); 1 km² 전체를 그리지 않음.
- `lib/game/entities/player.dart:322-339` + `level_map.dart:126-128,149-159` — 이동은 명시 월드 클램프가 아니라 `isWalkable`/`isWalkableAt`(범위 밖·`none` → false).
- `lib/game/systems/monster_population.dart:49-52,162-181` — 클라 개체군은 청크 단위 분대(주석상 “수천 마리”); 서버 240과 밀도만 다름.
- `lib/game/level/teleport_destinations.dart:40-62` — `edgeInset = 30`, 외곽 3칸 `none`을 전제로 가장자리 텔레포트.

---

## 3. 상세 분석

### 3.1 규격이 이 프로젝트에서 의미하는 것

| 축 | 값 | 의미 |
|---|---|---|
| 한 변 미터 | `kWorldSizeMeters = 1000` | 가로·세로 각 1 km |
| 한 변 타일 | `kWorldTiles = 1000` | 면적 100만 칸 = 1 km² |
| 타일 실거리 | `kMetersPerTile = 1.0` | **타일 번호 ≈ 미터** |
| 청크 | 32×32 타일 × 32×32 청크 | 스트리밍 단위 |

요구 “가로 1 km, 세로 1 km”는 여기서 **그리드 논리 크기**(`kWorldTiles × kMetersPerTile`)다. 화면 픽셀(타일 128×64)이나 한 화면에 보이는 범위가 아니다.

세 상수(`kMetersPerTile`, `kWorldSizeMeters`, `kWorldTiles`)는 주석상 서로 유도 관계이지만 **코드상 독립 리터럴**이다. `kWorldTiles == kWorldSizeMeters / kMetersPerTile`을 강제하는 assert/테스트가 없다.

### 3.2 데이터 경로 — 런타임도 1 km인가

1. SSOT: `iso.dart`.
2. 생성: `LevelMap.generate()` → `cells = width * height` 평면 배열 3장(약 3 MB) → 같은 `width`/`height`로 반환.
3. 진입: `ActionRpgGame.onLoad` / `restart` → 인자 없는 `generate()`만. 프로덕션에 작은 맵 주입 경로 없음.
4. 서버: `WORLD_TILES = 1000.0`, `world_center = (500, 500)`, 이동 클램프 동일 격자 스케일.

문서(`GAME-DESIGN.md`)와 코드가 일치한다. “문서만 1 km” 가설은 성립하지 않는다.

### 3.3 1 km를 “감당”하는 구조 (크기가 맞아도 필수인 이유)

100만 칸을 객체화하지 않는다.

- 지형: `Uint8List` + 청크 `Picture` 캐시(프레임당 소수 청크).
- 구조물: 시야+여유 청크 마운트.
- 몹: 장부 ↔ 근처만 컴포넌트(활성 46 m / 해제 60 m / 상한 140).

크기 상수를 바꾸면 스트리밍·개체군 밀도가 같이 움직여야 한다. **지금 크기를 맞추는 작업은 이미 끝난 상태**다.

### 3.4 “1 km”와 어긋나 보일 수 있는 경계 (규격 충족과 별개)

| 항목 | 사실 | 판정 |
|---|---|---|
| 격자 한 변 | 1000 타일 = 1000 m | **규격 충족** |
| 외곽 통행 | `margin = 3` → 내부 인덱스 대략 3‥996 | 월드 **정의** 1 km, **테두리 허공 제외 폭** ≈ 994 m. 내부 노이즈 허공·대로는 별개 |
| 서버 좌표 상한 | `clamp(0.0, 1000.0)` inclusive | `floor(1000)` → 인덱스 1000 → 클라 맵 밖. **끝점 1 차이 가능** |
| 클라 이동 | walkability만 | 맵 밖·`none`은 사실상 차단 |
| 화면 체감 | 줌 ~760 px 세로 분량, 레이더 70 m | “맵이 작다”는 **뷰 스케일** 문제이지 상수 미달 아님 |
| 크기 회귀 테스트 | `width/height == 1000` 직접 assert **없음** | 상수 변경 시 조용히 깨질 수 있음 |
| 서버 vs 클라 몹 | 240 vs 청크 분대×~1000청크 | **크기 동일, 밀도·권위 이중** — 1 km 미충족의 증거가 아님 |

### 3.5 범위와 권위

- **월드 기하 크기**: 클라 `iso.dart` + 서버 `WORLD_TILES`(수동 동기, 주석만).
- **지형 실체**: 클라 절차 생성. 서버는 타일 맵을 들고 있지 않음.
- **MMORPG**: 공유해야 할 1차 조건은 “같은 1 km 격자”. 그 조건은 이미 맞다. 남은 과제는 몹·전투 권위 등 **콘텐츠 동기**다.

### 3.6 질문에 대한 직접 답

- **“1 km × 1 km로 되어 있는가?”** → **예.** 상수·생성·서버·문서가 일치.
- **“수정이 필요한가?”** → **규모 변경은 아니오.** 보완은 회귀 테스트·클램프 끝점 정렬·상수 동기 검증·(선택) 테두리 의도 문서화.
- 이 분석은 읽기 전용이다. 파일 수정은 하지 않았다.

---

## 4. 리스크 · 함정

- **오판**: “1 km가 안 보여” → 카메라 줌·70 m 레이더·스트리밍 때문이다. 상수를 키우거나 줄이면 텔레포트 `edgeInset=30`, 안전지대 중심 500, 청크 밀도, 메모리(~3 MB 전제)가 연쇄로 흔들린다.
- **서버 `clamp(0, WORLD_TILES)`**: 좌표 `1000.0` 허용. 클라 `floor` 시 인덱스 1000. 지금 클라 이동은 walkability로 거의 막히지만, 지연 보간·치트 리포트·향후 서버 권위 위치 동기에서 끝선 글리치 여지. (실시간 위치 동기 전에는 **저빈도** 이슈.)
- **삼중 SSOT**: Dart 두 상수 + Rust 한 상수. 한쪽만 바꾸면 “1 km 월드” 전제가 깨진다. 자동 검증 없음.
- **실질 통행 ≠ 격자 한 변**: 외곽 3 m void는 의도. “정확히 1000 m를 걸을 수 있어야 한다”로 읽으면 오해. 현 설계는 **격자 1 km + 테두리 허공**.
- **`LevelMap.generate(width:, height:)` 오버라이드**: 테스트·실험용 API. 프로덕션이 기본값만 써도, 실수로 작은 맵을 넣으면 인구·스트리밍 공식이 그대로 따라가 밀도만 비정상화.
- **몹 이중 월드**: 크기 문제는 아니지만, 공유 1 km 맵에서 “빈 들판(서버 240) / 북적임(클라 수천)”이 갈린다. 크기 수정으로 해결되지 않는다.
- **메모리 상한**: 1000²×3 바이트 ≈ 3 MB. 한 변을 수 km로 키우면 제곱 증가 — 현 구조의 상한에 가깝다.

---

## 5. 권고안

| 순위 | 권고 | 범위 | 근거 | 리스크 |
|---|---|---|---|---|
| 1 | **규모 변경 금지.** 이미 1 km×1 km. “수정”은 키우기가 아니라 **고정·검증** | 기획·구현 | `iso.dart:23-27`, `level_map.dart:228-230`, `world.rs:48` | 불필요 변경 시 스트리밍·밸런스 붕괴 |
| 2 | **회귀 테스트**: `LevelMap.generate()` 후 `width/height == kWorldTiles`, `widthInMeters/heightInMeters == kWorldSizeMeters`, `kWorldTiles * kMetersPerTile == kWorldSizeMeters`, `chunksX/Y == kWorldChunks` | `test/` (예: `world_size_test.dart`) | `test/`에 `kWorldTiles`/`map.width==1000` assert 부재; `safe_zone_test`는 중심 500만 암시 | 비용 소, 회귀 조기 발견 |
| 3 | **클라·서버 월드 상수 동기 검증** — 통합 테스트 또는 배포 체크리스트에 `kWorldTiles == WORLD_TILES`(값 1000). 장기적으로 생성 소스 단일화 검토 | `test/spacetime_integration_test.dart` 등 / 문서 | `world.rs:47-48` 수동 복제 | 서버 재배포 규율 필요 |
| 4 | **서버 `move_to` 클램프를 클라 타일 범위와 정렬** — 예: max를 `WORLD_TILES - ε` 또는 “한 변 길이 exclusive, 유효 좌표 `[0, WORLD_TILES)`”로 문서+코드 일치 | `spacetimedb/src/world.rs:489-490` | 클라 `0..width-1` (`level_map.dart:126-128`), `floor` 인덱스 | 배포 필요; 끝선 세션 미세 보정. **우선도는 크기 충족 다음** |
| 5 | **(문서)** 외곽 3칸 허공·실질 테두리 제외 폭 ≈994 m를 `GAME-DESIGN.md` §5.1에 한 줄 — “월드 격자 1 km, 테두리 3 m void” | 문서 | `level_map.dart:245-254`, `teleport_destinations.dart:40-45` | 구현 변경 없음 |
| 6 | **범위 밖(후속)**: 1 km 공유 시 몹 권위(서버 240 vs 클라 개체군) 정렬 — **크기 요청의 실행 대상 아님** | `world.rs` / `monster_population.dart` | `MONSTER_COUNT=240` vs 청크 분대 | 대규모 설계 |

오케스트레이터 검증(실행 시): `flutter test`에 크기 테스트 포함 · 서버 변경 시 `cargo test` + wasm 빌드 · `flutter analyze`.

---

## 6. 불확실 · 미확인

- **런타임 프로파일**: 기기에서 1000×1000 생성 시간·메모리 피크는 미측정. 코드 할당량 ~3 MB 추정.
- **maincloud 배포본** `WORLD_TILES`가 로컬 `spacetimedb`와 같은지는 배포 산출물 미확인 — 소스 기준만.
- **클라 상주 몹 총수** exact 값은 시드·통행 가능 칸에 따라 변동. “수천”은 주석·청크×분대 상한으로만 지지.
- 사용자가 “1 km가 아니다”고 **체감한 구체 증상**(가장자리 텔레포트 실패, 미니맵, 좌표 상한 등)이 없으면, 크기 상수 문제가 아닐 가능성이 큼 — 증상 재현 정보 없음.
- 타일 ≠ 1 m 로 바꿀 기획 의도는 코드·문서에 없음.
- 서버 위치 동기·클라 예측이 **실제로** 끝선 `1000.0`을 쓰는지는 멀티플레이 동기 미구현 단계에서 관측 불가(`[미관측]`).

---

## 7. 자기 비판으로 바로잡은 것

- ❌ 철회: 1차 `world.rs:498-499` 클램프 인용 — 다시 여니 클램프는 **`489-490`**. 498-499는 속도 예산 보간 분기. 줄 번호 오류.
- ❌ 철회: 1차 `action_rpg_game.dart:186` / `1126` — 실제 `LevelMap.generate()`는 **`187`**, restart는 **`1144`**.
- 🔁 수정: 1차 카메라 클램프 `424-438` → 실제 `_clampToWorld`는 **`433-448`** (앞 줄은 위치 갱신 호출부).
- 🔁 수정: “실질 통행 ≈994 m”를 **규격 미충족처럼 읽히게 둔 뉘앙스** → **격자 1 km는 충족**, 994 m는 **의도된 테두리 void를 뺀 내부 폭**으로만 기술. 내부 노이즈 허공은 대로로 연결되므로 “한 축 연속 994 m 보장”은 아님.
- 🔁 수정: 서버 clamp를 크기 미달의 핵심 결함처럼 둔 인상 → **규격 충족 후의 끝점 정렬 보완**, 실시간 위치 동기 전에는 저빈도.
- 🔁 수정: 몹 240 vs 수천을 1 km 보완 목록과 같은 급으로 묶은 점 → **크기 반증이 아님**을 §1·§3.4·권고 6에서 명시. 범위 밖 후속.
- ➕ 추가: `kMetersPerTile` / `kWorldSizeMeters` / `kWorldTiles`가 **주석상 유도 관계이나 독립 리터럴**이라 어긋날 수 있음 — 회귀 테스트에 관계식 assert 포함 권고.
- ➕ 추가: 화면 줌(`_zoomForSize`, 세로 ~760 px) + 레이더 70 m가 “맵이 작아 보이는” **주된 체감 원인** — `action_rpg_game.dart:226-229`, `hud.dart:24,316-320`.
- ➕ 추가: `teleport_destinations.dart:40-45`가 외곽 3칸 `none`을 전제로 `edgeInset=30`을 잡음 → 테두리 허공은 버그가 아니라 텔레포트 설계와 정합.
- 살아남은 핵심 결론(이미 1 km×1 km, 규모 변경 불필요, 회귀 테스트·상수 동기·클램프 끝점 보완)은 **줄 번호를 고친 뒤에도** `iso.dart`·`level_map.dart`·`world.rs`·`GAME-DESIGN.md`가 지지한다.
