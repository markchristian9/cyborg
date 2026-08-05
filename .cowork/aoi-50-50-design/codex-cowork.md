<!-- cowork:codex | 2026-08-05 12:00:25 | exit=0 | 855s -->
# codex 분석 — aoi-50-50-design

> 요청: AOI 영역을 어떻게 설정한는지 설명하고, AOI 에 몬스터 50, PC 50 을 동시에 보여주는 경우, 어떻게 현재 프로젝트를 업데이트하면 좋을지 설명하고 수정/보완할 내용을 알려주세요.

[맥락 — 직전 분석의 결론]
- .cowork/scale-1000-aoi-100/final-report.md 와 GAME-SERVER.md 가 직전 분석의 결과다. 거기서 확정된 사실:
  · 구독 SQL 에 LIMIT·ORDER BY·산술식이 없어 '가까운 N 명'을 구독으로 자를 수 없다. 청크 구독은 면적만 자른다.
  · 행 갱신은 deletes+inserts 두 행 이미지로 전송된다(egress 계산에 ×2).
  · WorldPlayer 에 chunk 컬럼이 아직 없다. Monster.chunk 는 집(home) 좌표 기준이다.
  · monster_ai 가 O(근처 몹 × 전체 플레이어) 다.
- 이번 요청은 목표 수치가 바뀌었다: 동접 1,000 에서 **AOI 안에 몬스터 50 + PC 50** 을 동시에 보여주는 것.

[반드시 답해야 할 질문]
1. AOI 영역을 '어떻게 설정하는가' 를 이 프로젝트 기준으로 구체적으로 설명하라. 청크 크기를 무엇에서 역산하는가? 몬스터 50 과 PC 50 은 밀도가 다른데(몹 약 7,500기 고정 배치 vs 사람 1,000명 이동), 하나의 청크 크기로 둘 다 만족시킬 수 있는가? 각각 다른 청크 크기가 필요한가?
2. 몬스터 50 기준으로 역산한 청크 크기와, PC 50 기준으로 역산한 청크 크기를 각각 계산하라. 현재 월드 크기(world.rs 의 WORLD_PLAYABLE_TILES)와 몬스터 배치 방식(클러스터 배치 — cluster_center/scatter_around)을 반영하라. 몬스터는 균등 분포가 아니라 군집 분포라는 점이 청크 설계에 어떤 영향을 주는가?
3. 화면에 실제로 보이는 범위(카메라 뷰포트)와 AOI 청크 범위의 관계는? 클라이언트 화면 크기·줌 배율을 코드에서 확인하고, 9청크가 화면 대비 과잉인지 부족한지 판단하라.
4. 몬스터 50 + PC 50 일 때의 초당 전송 행 수·바이트를 계산하라. 몬스터는 서버가 3.33Hz 로 쓰고 PC 는 클라이언트가 5Hz 로 보고한다는 비대칭을 반영하라. 둘 중 어느 쪽이 더 큰 부하인가?
5. 이 목표를 위해 현재 프로젝트에서 구체적으로 무엇을 고쳐야 하는가? 서버 스키마(테이블·컬럼·인덱스), 리듀서, 클라이언트 구독 관리, 렌더링 상한까지 파일:줄 단위로 제시하라. 자동 마이그레이션 조건(맨 끝 컬럼 + 기본값)을 지킨 형태로 제시할 것.
6. 청크 경계를 넘을 때의 재구독 전략을 구체적으로 설계하라. 히스테리시스는 어떻게 넣는가? 현재 클라이언트의 generation 패턴을 재사용할 수 있는가?
7. 몬스터 50·PC 50 상한을 실제로 보장하려면 무엇이 더 필요한가? 안전지대처럼 사람이 몰리는 곳에서는 어떻게 되는가?

[산출 형식]
- 모든 주장에 파일:줄 근거를 달 것. 추정치는 계산 과정을 보일 것.
- '가능하다' 로 끝내지 말고 '어떤 수치까지, 어떤 조건에서' 를 명시할 것.
- 코드 변경 제안은 실제 적용 가능한 형태(테이블 정의·SQL·Dart 구독 관리)로 쓸 것.
> 생성: 2026-08-05 12:00:25 · 소요 855s · 읽기 전용 분석(작업공간 미수정)

---



## 1. 결론 요약

3×3, 즉 9청크 AOI를 유지한다면 평균 몬스터 50에는 약 **27타일**, 평균 PC 50에는 약 **74타일** 청크가 필요하다. 밀도가 7.5배 달라 하나의 청크 크기로 두 목표를 동시에 맞출 수 없다.  
다만 몬스터는 군집 배치이고 PC는 안전지대에 1,000명이 몰릴 수 있으므로, 27·74타일은 모두 **균등분포 평균값**일 뿐 50개 상한을 보장하지 않는다.  
현재 행 구조에서 50몬스터+50PC가 계속 움직이면 클라이언트당 약 **833 행 이미지/s, 120KB/s**, 동접 1,000 전체 약 **833,000 행 이미지/s, 120MB/s**이며, 동일 개체 수에서는 PC 트래픽이 더 크다.  
권장 구조는 AI용 32타일 청크를 유지하면서 `monster_aoi_chunk=27`, `player_aoi_chunk=74`를 별도로 추가하고, 이중 구독 전환·히스테리시스·가까운 50개 렌더 상한을 함께 적용하는 것이다.

## 2. 근거

- `CLAUDE.md:24-43` — 단일 공유 월드이며 다른 플레이어의 이동·전투가 실시간으로 보여야 하고 PK도 허용된다.
- `.cowork/cowork-prompt.md:60-66` — 클라이언트를 신뢰하지 않고 서버의 `ctx.sender()`를 권위로 사용하며, 시간·난수도 서버 값만 쓰는 것이 프로젝트 원칙이다.
- `.cowork/cowork-prompt.md:100-108` — 실제 배포 대상은 `spacetimedb/`이고 `lib/spacetime/generated/`는 생성 코드이므로 직접 수정하지 않는다.
- `spacetimedb/src/world.rs:47-73` — 통행 가능 월드는 1,000×1,000타일이고, 안전지대는 한 변 50타일이다.
- `spacetimedb/src/world.rs:75-108` — 몬스터는 200레벨×3군집×군집당 5~20기다. 범위는 3,000~12,000기, 기대값은 7,500기다.
- `spacetimedb/src/world.rs:713-750` — 실제 초기 배치는 각 레벨·섹터마다 `cluster_center`를 정하고 반경 9타일 안에 `scatter_around`로 뿌린다.
- `spacetimedb/src/world.rs:858-926` — 군집 중심은 안전지대 밖 반경 37~479타일의 레벨 띠와 세 방위에 배치되며, 군집 사이 최소 간격이나 AOI별 수용량 제한은 없다.
- `spacetimedb/src/world.rs:267-359` — `WorldPlayer`에는 아직 AOI 청크 컬럼이 없고, 새 컬럼은 맨 끝에 기본값과 함께 추가해야 자동 마이그레이션된다.
- `spacetimedb/src/world.rs:366-423` — 기존 `Monster.chunk`는 32타일 AI 인덱스이며 현재 위치가 아니라 `home_x/home_y` 기준이다.
- `spacetimedb/src/world.rs:132-152,1428-1487` — AI는 300ms, 즉 약 3.33Hz로 실행되고, 주변 몬스터마다 전체 플레이어를 다시 순회한다.
- `spacetimedb/src/world.rs:1499-1543` — 실제 몬스터 행 갱신은 추격·귀환 중일 때만 발생한다. 정지한 몬스터 50기가 매 틱 쓰인다는 계산은 상한 시나리오다.
- `lib/spacetime/cyborg_connection.dart:34-44` — 현재 클라이언트는 `world_player`와 `monster` 전체를 구독한다.
- `lib/spacetime/spacetime_world_presence.dart:21-42,68-145` — PC 위치 보고는 200ms/5Hz이고 `_inFlight` 백프레셔와 기존 `_generation` 패턴이 있다.
- `lib/game/action_rpg_game.dart:287-340`, `lib/game/iso.dart:5-77`, `lib/main.dart:128-140` — 화면 크기는 고정하지 않고 `GameWidget`이 실제 화면을 채우며, 줌은 화면 높이와 사용자 배율 0.5~2.0으로 정해진다.
- `lib/game/action_rpg_game.dart:158-201,637-664,1088-1140` — 몬스터 렌더 상한은 현재 140이지만 PC는 상한 없이 전부 컴포넌트로 만든다.
- `GAME-SERVER.md:107-124,160-173` — 구독 SQL에는 산술식·`ORDER BY`·`LIMIT`이 없고, update는 옛 행 delete와 새 행 insert의 두 행 이미지로 전달된다.
- `/Users/thruthesky/.pub-cache/hosted/pub.dev/spacetimedb_sdk-2.4.0/lib/src/subscription/subscription_manager.dart:159-170,224-243` — 구독마다 별도 query-set ID를 만들 수 있고 개별 해제가 가능하다.
- `/Users/thruthesky/.pub-cache/hosted/pub.dev/spacetimedb_sdk-2.4.0/lib/src/cache/table_cache.dart:259-335` — 겹치는 query set은 행 소유권을 함께 보유하므로 새 구독 적용 후 옛 구독을 해제해도 겹치는 행은 유지된다.

## 3. 상세 분석

### 3.1 AOI 크기를 무엇에서 역산하는가

3×3 청크의 한 변을 `C`, 월드 면적을 `A`, 개체 수를 `N`, 목표 평균 개체 수를 `T`라 하면 다음과 같다.

```text
밀도 ρ = N / A
AOI 면적 = 9C²
목표 T = 9C²ρ
C = √(T / (9ρ))
```

현재 통행 가능 면적은 `1,000² = 1,000,000타일²`이다(`spacetimedb/src/world.rs:47-73`).

**몬스터 기준**

```text
군집 수 = 200레벨 × 3 = 600
군집당 기대값 = (5 + 20) / 2 = 12.5
기대 몬스터 수 = 600 × 12.5 = 7,500
ρmonster = 7,500 / 1,000,000 = 0.0075

Cmonster = √(50 / (9 × 0.0075))
         = 27.22타일
```

정수 구현값을 27로 내리면:

```text
9 × 27² × 0.0075 = 49.21기
```

그러므로 `[판단]` 평균 목표에는 `MONSTER_AOI_CHUNK_TILES = 27`이 적합하다. 실제 랜덤 개체 수 범위 3,000~12,000을 그대로 대입하면 필요한 크기는 약 43.0~21.5타일이므로, 운영 DB의 실제 `monster.count()`를 확인하지 않고 27을 확정해서는 안 된다(`spacetimedb/src/world.rs:75-108,705-718`).

**PC 기준**

```text
ρplayer = 1,000 / 1,000,000 = 0.001

Cplayer = √(50 / (9 × 0.001))
        = 74.54타일
```

정수값 검산은 다음과 같다.

```text
C=74 → 9 × 74² × 0.001 = 49.28명
C=75 → 9 × 75² × 0.001 = 50.63명
```

따라서 평균 50 이하를 우선하면 `[판단]` `PLAYER_AOI_CHUNK_TILES = 74`가 맞다.

같은 3×3 청크 크기로 둘을 동시에 맞추는 것은 불가능하다.

| 청크 크기 | 평균 몬스터 | 평균 PC |
|---:|---:|---:|
| 27 | 49.21 | 6.56 |
| 74 | 369.63 | 49.28 |

하나의 27타일 격자를 공유하되 PC만 약 69개 셀을 구독하는 방법은 수학적으로 가능하다. 그러나 9개 대신 수십 개의 `OR` 조건과 잦은 경계 전환이 필요하다. `[판단]` AI용 32타일, 몬스터 AOI용 27타일, PC AOI용 74타일을 목적별로 분리하는 편이 단순하고 안전하다.

### 3.2 몬스터 군집 배치가 주는 영향

27타일 계산은 월드 전체 평균일 뿐이다. 실제 배치는 다음 특성이 있다.

- 한 군집의 최대 20기가 약 18×18타일 안에 들어간다(`spacetimedb/src/world.rs:90-102,914-926`).
- 3×3 몬스터 AOI는 81×81타일이므로 여러 군집을 동시에 포함할 수 있다.
- `cluster_center`에는 다른 군집과의 최소 거리나 “어떤 3×3 창에도 50기 이하”라는 검사가 없다(`spacetimedb/src/world.rs:868-897`).
- 레벨은 반경 37~479 구간에 거의 선형으로 배치된다. 같은 반경 폭에 비슷한 수의 레벨이 들어가지만 안쪽 둘레는 더 짧으므로, `[판단]` 안전지대 주변 저레벨 띠가 외곽보다 조밀해질 가능성이 크다.

따라서 `C=27`은 “장기 평균 약 49기”까지만 말할 수 있다. 몬스터 50 상한을 보장하려면 다음 중 하나가 추가되어야 한다.

1. 배치 시 모든 3×3 몬스터 창의 합이 50 이하인지 검사하고 초과 군집을 다른 위치로 이동한다.
2. 현재 위치 기준 셀별 수용량을 서버가 유지하고 몬스터 이동도 그 수용량을 넘지 않게 한다.
3. 서버가 관찰자별 가까운 50기 membership을 계산한다.
4. 네트워크는 평균 AOI를 허용하되 클라이언트 렌더만 가까운 50기로 제한한다.

1·2는 현재 군집 사냥터 설계를 바꾸며, 3은 접속자별 계산·상태가 추가된다. 4만으로는 렌더 상한은 보장하지만 수신 트래픽 상한은 보장하지 못한다.

### 3.3 카메라 뷰포트와 9청크의 관계

화면 크기는 고정 해상도가 아니다. `GameWidget`이 `Scaffold.body`를 채우고, 줌은 다음 식이다(`lib/main.dart:128-140`, `lib/game/action_rpg_game.dart:287-340`).

```text
z = clamp(H / 760, 0.55, 1.6) × userZoom
userZoom ∈ [0.5, 2.0]
```

아이소메트릭 역변환을 적용하면 카메라 사각형을 감싸는 그리드 AABB 한 변은 다음과 같다(`lib/game/iso.dart:62-77`, `lib/game/action_rpg_game.dart:1006-1039`).

```text
S = H / (64z) + W / (128z)
```

16:9 화면이고 기본 화면 배율이 clamp에 걸리지 않는 경우:

```text
기본 줌:      S ≈ 22.43타일
최대 줌 아웃: S ≈ 44.86타일
```

실제 카메라 영역은 AABB 안의 마름모이며 면적은 기본 약 251타일², 최대 줌 아웃 약 1,003타일²다.

| 구독 | 면적 | 기본 화면 대비 | 최대 줌 아웃 대비 |
|---|---:|---:|---:|
| 몬스터 3×3×27 | 6,561타일² | 약 26.2배 | 약 6.5배 |
| PC 3×3×74 | 49,284타일² | 약 196.6배 | 약 49.1배 |

따라서 보통 화면에서 9청크는 양쪽 모두 과잉이며 PC 쪽 과잉이 특히 크다. 그럼에도 PC 청크가 큰 이유는 화면 크기가 아니라 “균등분포에서 50명을 확보할 면적”에서 역산했기 때문이다.

3×3 창에서 플레이어가 중심 청크 경계에 붙었을 때도 바깥 경계까지 최소 한 청크가 남는다. 몬스터 청크 27은 16:9 최대 줌 아웃의 반폭 약 22.43타일보다 4.57타일 넓어 일반 화면은 포함한다. 다만 지원 화면 비율 상한이 없으므로 약 2.55:1보다 넓은 초광폭 화면에서는 완전 줌 아웃 시 27타일 버퍼가 부족할 수 있다. 이 경우에는 5×5로 늘려 평균 몬스터 수를 초과시키거나, 최소 줌을 제한하거나, 뷰포트 기반으로 쿼리 셀 수를 동적으로 늘려야 한다.

균등분포라면 실제 최대 줌 아웃 화면 안의 기대값은 PC 약 1명, 몬스터 약 7.5기에 불과하다. “50+50을 화면에 정확히 보인다”는 것은 군집·집결 지역에서만 성립한다. AOI 50은 평상시에는 “최대 50개 후보를 캐시에 둔다”는 의미로 해석해야 한다.

### 3.4 전송 행 수와 바이트

`GAME-SERVER.md`가 사용한 현재 행 크기 추정치는 `WorldPlayer≈180B`, `Monster≈90B`다(`GAME-SERVER.md:183-191`). update는 delete+insert 두 행 이미지다(`GAME-SERVER.md:160-173`).

50개가 계속 움직이는 클라이언트당 상한은 다음과 같다.

| 종류 | 논리 갱신/s | 행 이미지/s | 순수 행 바이트/s |
|---|---:|---:|---:|
| PC 50×5Hz | 250 | 500 | 500×180 = 90,000B |
| 몬스터 50×3.33Hz | 166.5 | 333 | 333×90 = 29,970B |
| 합계 | 416.5 | 약 833 | 약 119,970B |

동접 1,000명이 모두 같은 평균 관찰 관계를 가진다면:

```text
행 이미지 = 833 × 1,000 ≈ 833,000행/s
순수 행 데이터 ≈ 119.97MB/s
```

이는 프로토콜 헤더·초기 스냅샷을 제외하고 압축 전 필드 크기로 계산한 값이다. 동일한 50개씩을 비교하면 PC가 행 수로 1.5배, 바이트로 약 3배 크다.

서버의 원천 쓰기 관점은 다르다. 모든 7,500기 몬스터가 움직인다면 `7,500×3.33≈24,975` 몬스터 갱신/s로 PC 전체의 `1,000×5=5,000`보다 크다. 그러나 실제 코드는 추격·귀환 중인 몬스터만 갱신하므로 활성 몬스터 수를 측정해야 한다(`spacetimedb/src/world.rs:1499-1543`).

고빈도 위치 행을 약 22B로 세로 분할하면(`GAME-SERVER.md:259-269`):

```text
PC      500 × 22 ≈ 11.0KB/s/클라이언트
몬스터  333 × 22 ≈  7.3KB/s/클라이언트
합계                 약 18.3KB/s/클라이언트
동접 1,000           약 18.3MB/s
```

단, HP·생사·태그 등 저빈도 상태 행의 추가 트래픽은 별도다.

### 3.5 서버 스키마와 reducer 변경안

`[판단]` 첫 배포는 기존 행에 AOI 컬럼을 맨 끝에 추가하는 최소 변경이 안전하다.

```rust
const PLAYER_AOI_CHUNK_TILES: f32 = 74.0;
const MONSTER_AOI_CHUNK_TILES: f32 = 27.0;

const PLAYER_AOI_CHUNKS_PER_ROW: u32 =
    (WORLD_TILES / PLAYER_AOI_CHUNK_TILES) as u32 + 1; // 14
const MONSTER_AOI_CHUNKS_PER_ROW: u32 =
    (WORLD_TILES / MONSTER_AOI_CHUNK_TILES) as u32 + 1; // 38

fn player_aoi_chunk_of(x: f32, y: f32) -> u32 {
    let cx = (x / PLAYER_AOI_CHUNK_TILES).max(0.0) as u32;
    let cy = (y / PLAYER_AOI_CHUNK_TILES).max(0.0) as u32;
    cy * PLAYER_AOI_CHUNKS_PER_ROW + cx
}

fn monster_aoi_chunk_of(x: f32, y: f32) -> u32 {
    let cx = (x / MONSTER_AOI_CHUNK_TILES).max(0.0) as u32;
    let cy = (y / MONSTER_AOI_CHUNK_TILES).max(0.0) as u32;
    cy * MONSTER_AOI_CHUNKS_PER_ROW + cx
}
```

`WorldPlayer` 테이블 매크로에는 `player_aoi_chunk` btree를 추가하고 필드는 현재 마지막 필드 뒤에 둔다.

```rust
index(
    accessor = by_player_aoi_chunk,
    btree(columns = [player_aoi_chunk])
)

// WorldPlayer의 현재 마지막 필드 뒤
#[default(0u32)]
pub player_aoi_chunk: u32,
```

`Monster`에는 기존 AI용 `chunk`를 유지하고 별도 인덱스를 추가한다.

```rust
index(
    accessor = by_monster_aoi_chunk,
    btree(columns = [monster_aoi_chunk])
)

// 기존 Monster.chunk 뒤, 새 마지막 필드
#[default(0u32)]
pub monster_aoi_chunk: u32,
```

기존 `Monster.chunk`를 27타일 또는 현재 좌표 기준으로 바꾸면 안 된다. 그것은 집 좌표 기반 AI 후보 인덱스라는 별도 역할을 가진다(`spacetimedb/src/world.rs:414-423,1448-1468`).

좌표를 쓰는 모든 경로에서 새 컬럼도 같은 트랜잭션으로 갱신해야 한다.

- PC 입장: `spacetimedb/src/world.rs:995-1021`
- PC 이동: `spacetimedb/src/world.rs:1078-1083`
- 텔레포트: `spacetimedb/src/world.rs:1149-1158`
- 사망 후 안전지대 재가동: `spacetimedb/src/world.rs:1762-1777`
- 몬스터 최초 배치: `spacetimedb/src/world.rs:729-745`
- 몬스터 귀환·추격: `spacetimedb/src/world.rs:1508-1512,1537-1541`
- 몬스터 리스폰: `spacetimedb/src/world.rs:1672-1684`

기본값 0은 자동 마이그레이션만 통과시킬 뿐 기존 행을 올바른 AOI로 옮기지 않는다. 배포 후에는 private 진행표로 커서를 보존하는 멱등 `backfill_aoi_chunks` reducer를 두고 몬스터를 수백 행씩 나누어 갱신해야 한다. 완료 전에는 새 구독으로 전환하면 안 된다.

그 다음 단계에서는 고빈도 위치를 새 public projection table로 분리하는 것이 좋다.

```rust
#[spacetimedb::table(
    accessor = world_player_pos,
    public,
    index(accessor = by_aoi_chunk, btree(columns = [aoi_chunk]))
)]
pub struct WorldPlayerPos {
    #[primary_key]
    pub character_id: u64,
    pub grid_x: f32,
    pub grid_y: f32,
    pub aoi_chunk: u32,
}

#[spacetimedb::table(
    accessor = monster_pos,
    public,
    index(accessor = by_aoi_chunk, btree(columns = [aoi_chunk]))
)]
pub struct MonsterPos {
    #[primary_key]
    pub id: u64,
    pub grid_x: f32,
    pub grid_y: f32,
    pub aoi_chunk: u32,
}
```

이 두 테이블만 고빈도로 갱신하고, 이름·외형·레벨·HP·생사·태그는 별도 저빈도 AOI 상태표로 분리해야 한다. 생성 Dart 파일은 직접 편집하지 않고 스키마 확정 후 다시 생성해야 한다(`.cowork/cowork-prompt.md:100-108`).

`monster_ai`는 플레이어를 현재 위치 셀별 `HashMap<u32, Vec<PlayerLite>>`로 먼저 묶고, 같은 AI 청크를 여러 플레이어가 중복 조회하지 않게 바꿔야 한다. 현재 전체 플레이어 대상 탐색은 `O(주변 몬스터×전체 PC)`다(`spacetimedb/src/world.rs:1444-1487`).

### 3.6 클라이언트 구독과 히스테리시스

두 테이블은 서로 다른 격자를 쓰므로 query set도 분리하는 것이 좋다.

```sql
SELECT * FROM world_player
WHERE player_aoi_chunk = p1 OR player_aoi_chunk = p2 ... OR player_aoi_chunk = p9

SELECT * FROM monster
WHERE monster_aoi_chunk = m1 OR monster_aoi_chunk = m2 ... OR monster_aoi_chunk = m9
```

각 목록은 현재 중심 청크와 이웃 8개를 계산한다. PC가 74타일 경계를 넘었다고 몬스터 query set까지 교체하거나 그 반대가 되지 않도록 `_playerAoiQuerySetId`와 `_monsterAoiQuerySetId`를 따로 둔다.

`[판단]` 히스테리시스는 청크 폭의 10%가 적절한 시작값이다.

```text
PC:      H = 7.4타일
몬스터:  H = 2.7타일
```

현재 중심 인덱스가 `i`일 때 다음 조건까지 유지한다.

```text
오른쪽 전환: position >= (i + 1) × C + H
왼쪽 전환:   position <  i      × C - H
```

두 전환점 사이가 `2H` 데드밴드가 되어 경계에서 왕복해도 구독이 진동하지 않는다. 텔레포트처럼 여러 청크를 한 번에 건너면 즉시 `floor(position/C)`로 재설정한다.

전환 순서는 다음이어야 한다.

1. 원하는 새 9청크를 계산한다.
2. 새 query set을 구독한다.
3. 해당 `SubscribeApplied`와 초기 행 캐시 적용을 확인한다.
4. 요청 당시 generation이 아직 최신인지 검사한다.
5. 최신이면 새 ID를 활성화한 뒤 옛 query set을 해제한다.
6. 늦게 도착한 결과면 새 ID만 해제한다.

현재 `_generation`이 입장·퇴장 사이 늦은 완료를 거르는 방식은 그대로 재사용할 수 있다(`lib/spacetime/spacetime_world_presence.dart:33-38,68-112`). 다만 현재 `_subscribing` boolean 하나만으로는 구독 도중 발생한 더 최신 경계 이동을 잃을 수 있으므로, 채널별 `_desiredWindow`를 저장하고 진행 중 전환이 끝나면 최신 목표를 다시 처리해야 한다.

SDK의 `subscribe()`는 서버 거절 때도 예외 없이 완료될 수 있다고 명시한다. 단순히 `await subscribe()`가 끝났다는 이유만으로 옛 구독을 풀지 말고 `onSubscribeApplied`와 `onSubscriptionError`를 query-set ID별로 확인해야 한다(`/Users/thruthesky/.pub-cache/hosted/pub.dev/spacetimedb_sdk-2.4.0/lib/src/subscription/subscription_manager.dart:159-170,508-557`).

### 3.7 렌더·수신 상한 보장

몬스터는 현재 반경 60타일 안의 최대 140기를 입력 순서대로 마운트한다(`lib/game/action_rpg_game.dart:195-201,1088-1124`). 이를 거리순 후보 50기로 바꿔야 한다.

PC는 현재 `presence.others`를 모두 `_remotePlayers`에 넣는다(`lib/game/action_rpg_game.dart:637-664`). 다음 규칙이 필요하다.

```text
1. 파티장·현재 공격 대상 등 필수 대상을 먼저 예약
2. 나머지를 거리 제곱 오름차순, 동률이면 character_id 순으로 정렬
3. 전체 50개까지만 RemotePlayerEntity 생성·유지
4. 선택에서 빠진 기존 엔티티는 removeFromParent
```

이렇게 하면 공식 클라이언트의 렌더 상한은 몬스터 50+PC 50으로 보장된다. 그러나 SQL 결과 자체는 50개로 제한되지 않는다.

안전지대에는 모든 플레이어가 입장할 수 있고 잘못된 입장 좌표는 중심으로 교정된다(`spacetimedb/src/world.rs:931-980`). 따라서 1,000명이 안전지대 한 청크에 몰리면 PC query는 1,000행을 수신한다. 클라이언트가 50명만 그려도 네트워크는 줄지 않는다.

네트워크까지 정확히 50으로 제한해야 한다면 `[판단]` 서버가 다음 불변식을 관리해야 한다.

```text
관찰자 한 명당:
  AoiMembership(kind=pc)      ≤ 50행
  AoiMembership(kind=monster) ≤ 50행
```

서버는 공간 셀로 후보를 좁힌 뒤 거리·우선순위로 50개를 골라 membership 차이만 갱신하고, 클라이언트는 membership과 위치표를 인덱스 JOIN으로 구독한다. 이는 안전지대에서도 상한을 만들지만 접속자별 membership 계산·저장 비용이 생긴다. 단순 청크보다 훨씬 비싸므로 “렌더 50”이 요구사항인지 “수신까지 50”인지 먼저 확정해야 한다.

## 4. 리스크 · 함정

- **27·74는 평균값이다.** 몬스터 군집과 PC 집결에는 확정 상한이 아니다. 이를 “최대 50”으로 문서화하면 운영에서 즉시 깨진다(`spacetimedb/src/world.rs:713-750,858-926`).
- `#[default(0u32)]`만 배포하면 기존 몬스터가 모두 청크 0에 남는다. 백필 완료 전에 구독을 바꾸면 대부분의 몬스터가 사라진 것처럼 보인다(`spacetimedb/src/world.rs:301-307,420-423`).
- PC가 죽으면 안전지대 중심으로 순간 이동한다. 이 경로에서 `player_aoi_chunk`를 바꾸지 않으면 좌표와 구독 인덱스가 서로 다른 지역을 가리킨다(`spacetimedb/src/world.rs:1762-1777`).
- 몬스터의 기존 `chunk`를 현재 좌표 기준으로 바꾸면 AI용 집 청크 의미가 깨지고, 매 이동마다 기존 AI 인덱스까지 다시 쓰게 된다(`spacetimedb/src/world.rs:414-423`).
- 새 구독보다 옛 구독을 먼저 해제하면 화면 공백이 생긴다. 반대로 겹치는 query set을 오래 유지하면 스냅샷·델타를 중복 수신한다.
- 27타일 몬스터 AOI는 일반 16:9 화면을 포함하지만 지원 화면 비율 상한이 없어 초광폭 최대 줌 아웃까지 보장하지 못한다(`lib/game/action_rpg_game.dart:287-340`).
- 세로 분할은 egress를 크게 줄이지만 authoritative 테이블과 projection table을 같은 reducer에서 항상 함께 갱신해야 한다. 한 경로라도 빠지면 서버 판정과 화면이 분리된다.
- `world_player`·`monster`가 `public`이므로 수정된 공식 클라이언트가 AOI를 지켜도 임의 클라이언트는 전체 구독을 걸 수 있다(`spacetimedb/src/world.rs:267,366-369`). 이는 프로젝트 머리말의 “모든 테이블 비공개”와도 충돌한다(`spacetimedb/src/lib.rs:15-16`).
- 서버 membership으로 수신 상한을 만들면 1,000관찰자×100대상 상태가 생긴다. 전체를 매 틱 재작성하면 AOI 최적화가 오히려 새로운 병목이 된다.
- `.cowork/cowork-prompt.md:21-23`은 실시간 멀티플레이가 아직 없다고 적지만 실제로는 전체 구독·원격 PC·서버 권위 몬스터가 구현돼 있다(`lib/spacetime/spacetime_world_presence.dart:11-16`, `lib/game/action_rpg_game.dart:637-664`). 해당 시스템 프롬프트의 현재 단계 설명은 실제 구현보다 뒤처져 있다.

## 5. 권고안

| 순위 | 권고 | 범위 | 근거 | 리스크 |
|---|---|---|---|---|
| 1 | 목표를 “평균 AOI 50 + 공식 클라이언트 렌더 최대 50”인지 “네트워크 수신도 최대 50”인지 확정한다. 후자면 서버 membership을 채택한다. | 제품·서버 경계 | `GAME-SERVER.md:376-380` | membership 계산·저장 비용 |
| 2 | `WorldPlayer` 맨 끝에 기본값 있는 `player_aoi_chunk`와 btree를, `Monster` 맨 끝에 `monster_aoi_chunk`와 btree를 추가한다. 값은 우선 74·27로 둔다. | `spacetimedb/src/world.rs:267-423` | 운영 DB 실제 밀도와 다를 수 있음 |
| 3 | 백필 진행표와 배치형 `backfill_aoi_chunks` reducer를 추가하고, 완료 확인 후에만 클라이언트 AOI 구독을 활성화한다. | 서버 마이그레이션 | `spacetimedb/src/world.rs:301-307,420-423` | 대량 단일 트랜잭션은 틱 지연 유발 |
| 4 | 입장·이동·텔레포트·사망·몬스터 배치·추격·귀환·리스폰에서 현재 좌표 기반 AOI 청크를 함께 갱신한다. 기존 32타일 `Monster.chunk`는 유지한다. | 서버 reducer | `spacetimedb/src/world.rs:995-1021,1078-1083,1149-1158,1508-1541,1672-1684,1762-1777` | 누락 경로에서 좌표/인덱스 불일치 |
| 5 | PC 74타일과 몬스터 27타일용 query-set 관리자를 분리하고, 10% 히스테리시스·새 구독 우선·generation 폐기를 구현한다. | `lib/spacetime/spacetime_world_presence.dart:33-145` | 중복 스냅샷, 오류 처리 복잡도 |
| 6 | PC와 몬스터의 고빈도 위치를 `WorldPlayerPos`·`MonsterPos`로 분리하고 저빈도 프로필·전투 상태를 별도 표로 구성한다. | 서버 스키마·Dart 바인딩 | `GAME-SERVER.md:259-271` | 서버·클라이언트 동시 전환 필요 |
| 7 | `monster_ai`에서 플레이어를 현재 위치 셀로 한 번 그룹화하고, 몬스터마다 전체 플레이어를 순회하는 루프를 제거한다. | AI reducer | `spacetimedb/src/world.rs:1428-1487` | 어그로·리쉬 경계 회귀 |
| 8 | 몬스터 후보와 PC 후보를 거리·ID로 안정 정렬하고 각각 최대 50개만 컴포넌트로 유지한다. 파티장·공격 대상은 50개 안에서 우선 예약한다. | `lib/game/action_rpg_game.dart:158-201,637-664,1088-1140` | 군중 속 대상 교체·팝인 |
| 9 | 근거리/원거리 구독, 경계 왕복, 텔레포트, 사망 재가동, 안전지대 1,000명, 군집 과밀, 16:9·21:9 최대 줌 아웃을 부하·통합 테스트에 추가한다. | `test/world_presence_test.dart:52-89`, `test/monster_authority_test.dart:47-74` | Maincloud 테스트 비용 |
| 10 | 실제 셀 점유 히스토그램의 p50·p95·p99와 wire bytes를 측정한 뒤 27·74를 재조정한다. | 관측·운영 | `GAME-SERVER.md:437-459` | 실측 전 수치는 평균 추정에 머묾 |

## 6. 불확실 · 미확인

- 지정된 작업공간은 `/Users/thruthesky/.claude/plugins/cache`였지만 요청의 실제 프로젝트와 직전 보고서는 `/Users/thruthesky/tmp/games/actionrpg`에서 발견됐다. 본 분석의 코드 근거는 후자다.
- 운영 중인 `withcenter-cyborg` DB의 실제 몬스터 행 수와 27타일·74타일 셀별 점유 분포는 작업공간 자료만으로 확인할 수 없다. 7,500은 코드상 기대값이다.
- 180B·90B·22B는 필드 기반 추정치다. BSATN 헤더, 문자열 길이, WebSocket 배칭·압축을 포함한 실제 wire bytes는 미측정이다.
- 최대 지원 화면 크기·종횡비가 정해져 있지 않아 고정 3×3 몬스터 AOI가 모든 기기에서 카메라를 덮는다고 보장할 수 없다.
- 구독 적용 p95/p99 지연과 경계 이동 중 중복 스냅샷 크기가 측정되지 않았다. 히스테리시스 10%는 시작값이며 실측으로 조정해야 한다.
- 서버 membership을 선택할 경우 SpacetimeDB 2.7 구독 JOIN의 실제 비용과 1,000관찰자 갱신 처리량을 별도 검증해야 한다.
- 스키마 제안은 읽기 전용 분석이므로 코드 생성·컴파일·마이그레이션·통합 테스트로 문법과 배포 호환성을 검증하지 않았다.
