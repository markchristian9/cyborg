<!-- cowork:codex | 2026-08-04 21:03:04 | exit=0 | 229s -->
# codex 분석 — world-size-1km

> 요청: 게임 월드의 크기가 가로 1km, 세로 1km 이어야합니다. 그렇게 되어져 있는지 분석하고 수정/보완해주세요.
> 생성: 2026-08-04 21:03:04 · 소요 229s · 읽기 전용 분석(작업공간 미수정)

---



## 1. 결론 요약

논리적 월드 크기는 이미 **가로 1,000 m × 세로 1,000 m**로 설정되어 있다. 타일당 1 m이고 기본 맵이 1,000 × 1,000타일이므로 요구 규격과 일치한다 (`lib/game/iso.dart:17-27`, `lib/game/level/level_map.dart:228-235`).
다만 외곽 3타일은 통행 불가이므로, “끝에서 끝까지 걸을 수 있는 공간”을 뜻한다면 실제 가용 폭은 최대 994 m보다 작다 (`lib/game/level/level_map.dart:245-260`).
크기 자체를 다시 변경할 필요는 없지만, 클라이언트·서버에 1,000 값이 중복되고 이를 검증하는 테스트가 없어 향후 불일치할 위험이 있다 (`lib/game/iso.dart:23-27`, `spacetimedb/src/world.rs:47-48`).
따라서 우선 보완할 부분은 크기 변경이 아니라 **단위·경계 의미 고정, 회귀 테스트, 서버 이동 경계 정합성, 마지막 부분 청크 보정**이다.

## 2. 근거

- `CLAUDE.md:12-15` — 모든 플레이어가 사용하는 단일 오픈 월드이며 분리된 스테이지가 없다고 규정한다.
- `lib/game/iso.dart:17-27` — `kMetersPerTile = 1.0`, `kWorldSizeMeters = 1000.0`, `kWorldTiles = 1000`으로 선언되어 있다.
- `lib/game/level/level_map.dart:117-124` — 맵의 미터 크기를 `타일 수 × kMetersPerTile`로 계산하고 청크 수도 맵 크기에서 산출한다.
- `lib/game/level/level_map.dart:228-235` — `LevelMap.generate()`의 기본 `width`와 `height`가 모두 `kWorldTiles`이며, `width * height`개의 셀을 할당한다.
- `lib/game/action_rpg_game.dart:182-198` — 실제 게임 시작 경로가 크기 인자 없이 `LevelMap.generate()`를 호출하므로 기본 1,000 × 1,000타일을 사용한다.
- `lib/game/action_rpg_game.dart:1095-1120` — 재시작할 때도 크기 인자 없이 같은 기본 맵을 다시 생성한다.
- `lib/game/level/ground_layer.dart:112-125` — 타일 `(x, y)`는 `(x, y)`부터 `(x+1, y+1)`까지 그려져 1,000개 타일의 물리적 경계가 좌표 1,000까지 이어진다.
- `lib/game/level/level_map.dart:126-158` — 유효한 타일 인덱스는 `0 <= x < width`, `0 <= y < height`이고 바깥은 통행 불가로 처리한다.
- `lib/game/level/level_map.dart:241-260` — 맵 외곽 3타일을 명시적으로 `TileType.none`으로 만든다.
- `lib/game/entities/player.dart:24-29`·`lib/game/entities/player.dart:322-340` — 플레이어는 반경 0.28타일의 네 모서리가 모두 통행 가능한지 검사하므로 외곽 통행 불가 영역을 넘어갈 수 없다.
- `spacetimedb/src/world.rs:47-53` — 서버도 타일당 1 m라는 전제로 `WORLD_TILES = 1000.0`을 별도로 선언한다.
- `spacetimedb/src/world.rs:486-520` — 서버 이동은 좌표를 `0.0`부터 `WORLD_TILES`까지 clamp하지만 클라이언트 지형이나 몸체 반경은 검사하지 않는다.
- `lib/game/level/ground_layer.dart:128-161` — 마지막 청크의 렌더 대상은 맵 크기 1,000에서 끝나지만 청크 bounds는 32타일 전체인 좌표 1,024까지 계산한다.
- `lib/game/net/spacetime_game_sync.dart:7-12`·`lib/game/net/spacetime_game_sync.dart:59-67` — 현재 클라이언트 서버 동기화는 레벨·경험치만 전송하며 월드 좌표는 연결하지 않는다.
- `lib/spacetime/generated/client.dart:71-95`·`lib/spacetime/generated/client.dart:208-215` — 생성된 클라이언트 바인딩에도 `WorldPlayer`, `Monster`, `move_to` 같은 월드 스키마·reducer가 아직 등록되어 있지 않다.

## 3. 상세 분석

**논리적 크기**

현재 크기 계산은 다음과 같다.

`1,000타일 × 1.0 m/타일 = 1,000 m`

가로와 세로가 모두 같은 기본값을 사용하므로 총 경계 상자는 1,000 m × 1,000 m이고 면적은 1 km²다. 실제 게임 시작과 재시작 모두 별도 크기를 넘기지 않으므로 이 기본값이 런타임에도 적용된다 (`lib/game/iso.dart:17-27`, `lib/game/level/level_map.dart:228-235`, `lib/game/action_rpg_game.dart:182-198`, `lib/game/action_rpg_game.dart:1118-1120`).

타일 인덱스는 `0..999`이지만 마지막 타일이 좌표 999부터 1,000까지 차지하므로 월드 폭이 999 m인 것은 아니다. 렌더링도 각 타일의 끝점을 `x + 1`, `y + 1`로 잡는다 (`lib/game/level/ground_layer.dart:112-125`, `lib/game/level/ground_layer.dart:158-175`).

**월드 경계와 플레이 가능 영역**

논리 경계와 통행 가능 영역은 동일하지 않다. 생성기는 좌우·상하 각각 3타일을 `TileType.none`으로 비우므로 외곽 내부 사각형만 계산해도 994 × 994타일이다. 그 안에도 절차적 데이터 공백과 구조물이 추가되므로 실제 보행 가능한 바닥 면적은 더 작다 (`lib/game/level/level_map.dart:241-260`, `lib/game/level/level_map.dart:327-375`).

플레이어 중심은 몸체 반경 0.28타일까지 고려한 네 지점이 모두 통행 가능해야 이동할 수 있다. 따라서 첫 통행 가능 타일의 경계에도 플레이어 중심이 완전히 닿을 수는 없다 (`lib/game/entities/player.dart:24-29`, `lib/game/entities/player.dart:322-340`). 이는 월드 크기가 잘못된 것이 아니라 의도된 낙하 방지 여백이지만, 요구사항에서 말하는 1 km가 “논리 경계”인지 “실제 횡단 가능 거리”인지에 따라 판정이 달라진다.

**청크와 렌더링**

1,000은 청크 크기 32로 나누어떨어지지 않으므로 한 축에 32개 청크가 생기고 마지막 청크는 실제로 8타일만 포함한다 (`lib/game/iso.dart:29-36`, `lib/game/level/level_map.dart:123-124`). 타일 생성 루프는 `math.min(..., map.width)`로 정확히 1,000에서 끝나므로 1,024까지 바닥이 그려지지는 않는다 (`lib/game/level/ground_layer.dart:153-175`).

반면 `_chunkBounds()`는 마지막 청크도 32타일 전체로 계산해 좌표 1,024까지의 cull 영역을 만든다. 현재 이 bounds가 추가 바닥을 생성하지는 않지만 월드 외곽 렌더 메타데이터가 실제 크기보다 크다는 구조적 불일치다 (`lib/game/level/ground_layer.dart:128-161`).

카메라는 아이소메트릭 마름모를 정확히 제한하지 않고 이를 감싸는 직사각형에 clamp한다. 충돌 월드가 커지는 것은 아니지만 외곽 모서리에서 데이터 공간 밖의 허공이 보일 수 있다 (`lib/game/action_rpg_game.dart:424-438`).

**MMORPG 서버 경계**

서버도 `WORLD_TILES = 1000.0`이므로 수치상 클라이언트와 일치한다 (`spacetimedb/src/world.rs:47-53`). 그러나 두 값은 서로 독립된 리터럴이며 런타임 계약 검사가 없다.

서버 `move_to`는 속도만 제한하고 좌표를 닫힌 구간 `[0, 1000]`에 넣는다. 클라이언트는 타일 인덱스 1,000을 맵 밖으로 판정하고 몸체 전체의 통행 가능성까지 검사하므로, 서버는 클라이언트에서 설 수 없는 외곽·공백·구조물 좌표도 받아들일 수 있다 (`spacetimedb/src/world.rs:486-520`, `lib/game/level/level_map.dart:126-158`, `lib/game/entities/player.dart:322-340`).

현재 생성된 Dart 바인딩과 `SpacetimeGameSync`가 이 월드 reducer를 사용하지 않기 때문에 이 불일치는 아직 실제 이동 동기화에 적용되지 않는다. 다만 단일 공유 월드로 전환할 때 반드시 정리해야 한다 (`lib/game/net/spacetime_game_sync.dart:7-12`, `lib/spacetime/generated/client.dart:208-215`).

## 4. 리스크 · 함정

- **요구사항 해석 차이** — 논리 경계는 정확히 1 km × 1 km지만 외곽 3타일이 모두 통행 불가다. “1 km를 실제로 걸어서 횡단 가능해야 한다”는 의미라면 현재 구조는 충족하지 않는다 (`lib/game/level/level_map.dart:241-260`).
- **세 개의 독립된 크기 표현** — `kWorldSizeMeters`, `kWorldTiles`, 서버 `WORLD_TILES`가 각각 1,000으로 적혀 있으며 앞의 두 값조차 코드로 파생되지 않는다. 어느 하나만 변경하면 문서상 미터 크기와 실제 배열·서버 경계가 달라진다 (`lib/game/iso.dart:23-27`, `spacetimedb/src/world.rs:47-48`).
- **서버와 클라이언트의 경계 규칙 불일치** — 서버는 좌표 1,000과 통행 불가 지형을 허용할 수 있지만 클라이언트 충돌은 이를 거부한다. 서버 권위 이동이 연결되면 위치 보정, 벽 통과, 맵 밖 공격 판정 문제가 생길 수 있다 (`spacetimedb/src/world.rs:486-520`, `lib/game/entities/player.dart:322-340`).
- **부분 청크의 과대 bounds** — 마지막 8타일 청크가 렌더 메타데이터상 32타일로 계산된다. 현재 그려지는 타일 수는 맞지만 외곽 culling·디버그 시각화가 실제 경계와 어긋날 수 있다 (`lib/game/level/ground_layer.dart:128-161`).
- **시각적 경계와 충돌 경계 차이** — 카메라가 마름모가 아닌 직사각형 외접 영역에 갇히므로 모서리에서 월드가 실제보다 넓은 빈 공간처럼 보일 수 있다 (`lib/game/action_rpg_game.dart:424-438`).
- **회귀 검증 부족** — 관련 Dart 테스트는 안전지대가 맵 중앙인지와 텔레포트 목적지가 상대적으로 올바른지만 확인하고, 기본 맵이 정확히 1,000 m × 1,000 m인지는 고정하지 않는다 (`test/safe_zone_test.dart:53-59`, `test/teleport_test.dart:20-50`). Rust 테스트도 안전지대 중심만 검사한다 (`spacetimedb/src/world.rs:743-750`).
- **서버 소스와 생성 클라이언트의 시차** — 서버에는 월드 표와 reducer가 있지만 현재 Dart 생성물에는 없다. 월드 크기 계약을 서버에 추가하더라도 코드 재생성·구독·클라이언트 연결이 함께 이루어지지 않으면 적용되지 않는다 (`spacetimedb/src/world.rs:104-177`, `lib/spacetime/generated/client.dart:71-95`).

## 5. 권고안

| 순위 | 권고 | 범위 | 근거 | 리스크 |
|---|---|---|---|---|
| 1 | `kWorldSizeMeters`를 기준값으로 두고 `kWorldTiles`가 `kWorldSizeMeters / kMetersPerTile`과 정확히 일치하도록 파생 또는 assert한다. 서버에도 같은 단위·상한·월드 규격 버전을 명시한다. | `lib/game/iso.dart`, `spacetimedb/src/world.rs` | `lib/game/iso.dart:17-27`, `spacetimedb/src/world.rs:47-53` | Dart와 Rust 사이에는 여전히 별도 산출물이므로 배포 시 버전 검사가 필요하다. |
| 2 | 기본 맵의 `width == 1000`, `height == 1000`, `widthInMeters == 1000`, `heightInMeters == 1000`, 타일 인덱스 999는 내부이고 1000은 외부라는 회귀 테스트를 추가한다. 서버도 중심 500과 상한 규칙을 테스트한다. | `test/`, `spacetimedb/src/world.rs` 테스트 모듈 | `lib/game/level/level_map.dart:117-158`, `spacetimedb/src/world.rs:321-333` | 상수 자체만 비교하는 테스트는 계층 간 불일치를 잡지 못하므로 양쪽 경계 의미까지 검사해야 한다. |
| 3 | 서버 이동 범위를 “월드 경계 `[0,1000]`”와 “유효한 플레이어 중심 좌표”로 분리하고, `move_to`에서 상한 exclusive 규칙·몸체 반경·통행 가능 지형을 클라이언트와 동일하게 검증한다. | 서버 권위 이동 및 충돌 | `spacetimedb/src/world.rs:486-520`, `lib/game/entities/player.dart:322-340` | 지형 판정을 서버로 옮기려면 동일한 시드·생성 알고리즘 또는 서버용 통행 데이터가 필요하다. |
| 4 | `_chunkBounds()`의 `x1`, `y1`도 `_bakeChunk()`처럼 `map.width`와 `map.height`로 제한하고, 카메라 외곽 표시가 의도인지 확인한 뒤 필요하면 아이소메트릭 마름모 기준으로 보정한다. | 지면 렌더링·카메라 | `lib/game/level/ground_layer.dart:128-161`, `lib/game/action_rpg_game.dart:424-438` | 카메라 제한을 과하게 좁히면 큰 화면이나 낮은 줌에서 가장자리가 떨릴 수 있다. |
| 5 | 설계 문서에 “논리 경계 1,000 × 1,000 m”와 “외곽 3 m 통행 불가 및 절차적 공백이 포함된 가용 영역”을 구분해 적고, 월드 동기화 연결 시 서버 규격 버전을 검증한다. | 문서·클라이언트/서버 프로토콜 | `GAME-DESIGN.md:191-204`, `lib/game/level/level_map.dart:241-260` | 규격 버전 불일치 시 접속을 차단할지 경고만 할지는 운영 정책 결정이 필요하다. |
| 6 | 서버 월드 스키마를 실제로 사용할 단계에는 Dart 코드를 다시 생성하고 월드 데이터 구독·`enter_world`·`move_to` 연결까지 한 작업으로 검증한다. 생성 파일은 직접 수정하지 않는다. | SpacetimeDB 클라이언트 연동 | `.cowork/cowork-prompt.md:103-108`, `lib/spacetime/generated/client.dart:208-215` | 서버 배포와 생성 코드의 순서가 어긋나면 기존 클라이언트가 새 스키마를 사용하지 못한다. |

## 6. 불확실 · 미확인

- “1 km × 1 km”가 논리적 월드 경계를 뜻하는지, 플레이어가 실제로 끝에서 끝까지 횡단 가능한 거리를 뜻하는지는 사람의 기획 판단이 필요하다. 현재는 전자만 충족한다 (`lib/game/level/level_map.dart:241-260`).
- `maincloud`의 `withcenter-cyborg`에 현재 작업공간의 `spacetimedb/src/world.rs`가 실제 배포되어 있는지는 확인하지 않았다. 저장소 설정상 배포 대상은 `./spacetimedb`다 (`spacetime.json:1-5`).
- 읽기 전용 분석 규칙에 따라 `flutter test`, `flutter analyze`, Rust 테스트 및 실제 화면 실행은 수행하지 않았다. 따라서 런타임 화면에서 외곽 허공이 어느 정도 노출되는지는 미확인이다.
- 실제 통행 가능한 바닥의 총면적과 동서·남북 최장 횡단 거리는 절차적 지형의 공백·구조물 배치까지 계산해야 확정할 수 있다 (`lib/game/level/level_map.dart:241-260`, `lib/game/level/level_map.dart:327-415`).
