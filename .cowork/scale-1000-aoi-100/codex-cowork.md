<!-- cowork:codex | 2026-08-05 10:36:18 | exit=0 | 809s -->
# codex 분석 — scale-1000-aoi-100

> 요청: spacetimedb 를 통해서 동접수를 1,000 명으로 하고, AOI 를 100 명으로 가능하도록 분석해서 문서를 업데이트 해 주세요.

[분석 대상과 맥락]
- 목표 수치: 하나의 SpacetimeDB 데이터베이스에 **동시 접속 1,000 명**, 그리고 한 플레이어의 **관심 영역(AOI) 안에 다른 플레이어 100 명**이 동시에 보이는 상태를 감당하는 것.
- 방금 재작성한 /Users/thruthesky/tmp/games/actionrpg/GAME-SERVER.md 가 현재 판단의 기준 문서다. 이 문서는 '지금 구조의 실질 상한은 동접 수십 명' 이라고 결론냈다. 그 계산이 맞는지 검증하고, 목표치(1,000 동접 / AOI 100)를 달성하기 위한 구체적 설계를 제시해야 한다.
- 서버 모듈: spacetimedb/src/*.rs (SpacetimeDB 2.7, Rust). 특히 world.rs 의 monster_ai / move_to / 테이블 정의.
- 클라이언트: lib/spacetime/cyborg_connection.dart 의 구독 목록, lib/spacetime/spacetime_world_presence.dart 의 좌표 보고 주기.

[반드시 답해야 할 질문]
1. AOI 100 명이 서로 보이는 상태에서 초당 실제 전송되는 행 수와 바이트를 계산하라. 좌표 보고 주기(현재 200ms), 행 크기, 구독 fan-out 을 근거로 자릿수를 확정하라. 그 값이 SpacetimeDB 한 인스턴스와 클라이언트가 감당 가능한 범위인가?
2. SpacetimeDB 의 구독 SQL 제약(SELECT * 만, 조인 2 테이블, 산술식 불가, 인덱스 필수) 안에서 AOI 구독을 실제로 어떻게 구현하는가? 청크 크기는 얼마여야 하고, 청크 경계를 넘을 때 재구독 비용은 얼마인가? RLS 와 View 중 무엇이 적합한가?
3. 쓰기가 전역 락으로 직렬화된다는 제약 아래에서 동접 1,000 명이 초당 5 회씩 move_to 를 부르면(초당 5,000 트랜잭션) 실제로 버티는가? 좌표 보고 주기를 얼마로 낮춰야 하는가? 입력 배칭(여러 명의 이동을 한 리듀서에서 처리)이 가능한가?
4. monster_ai 의 O(근처 몹 x 전체 플레이어) 루프를 어떤 자료구조로 바꿔야 하는가? SpacetimeDB 는 모듈에 메모리 상태를 못 두는데, 매 틱 재구축 비용까지 포함해 계산하라.
5. 테이블 세로 분할(좌표만 따로 빼기), 좌표 정밀도 축소(f32 -> i16 등), 이동 의도 전송(출발점+속도+시작시각), 갱신 빈도 LOD(가까운 사람 5Hz, 먼 사람 1Hz) 각각의 실제 절감량을 수치로 비교하라.
6. 목표를 달성하기 위한 변경 목록을 우선순위와 예상 효과(배수)로 제시하라. 그리고 SpacetimeDB 로는 끝내 불가능해서 설계를 타협해야 하는 지점이 있다면 명확히 지적하라.

[산출 형식]
- 모든 주장에 파일:줄 근거를 달 것. 추정치는 계산 과정을 보일 것.
- '가능하다' 로 끝내지 말고 '어떤 수치까지, 어떤 조건에서' 를 명시할 것.
> 생성: 2026-08-05 10:36:18 · 소요 809s · 읽기 전용 분석(작업공간 미수정)

---



## 1. 결론 요약

현재 구조의 실질 상한이 “동접 수십 명”이라는 방향은 맞지만, 기존 계산은 update를 한 행으로 세어 egress를 약 2배 낮게 잡았고, “전역 뮤텍스 직렬화”는 SpacetimeDB 2.7.1의 확정 사실로 유지할 근거가 부족하다.  
AOI 100명·5Hz·현재 행 구조에서는 초당 50만 건의 논리 변경, 100만 BSATN 행 이미지, 약 180MB/s의 순수 행 데이터와 약 214.5MB/s의 비압축 애플리케이션 전송이 발생한다.  
`104`타일 구독 청크, 테이블 세로 분할, 18B 위치 행, 2Hz 보고를 함께 적용하면 플레이어 위치 부하는 약 7.2MB/s의 행 데이터·21MB/s의 비압축 전송으로 낮아진다. 조건부로 동접 1,000/AOI 100을 노릴 수 있는 범위다.  
다만 정확히 “가장 가까운 100명”만 보장하는 것, 임의의 1,000명 밀집을 자동 제한하는 것, 사용자별 LOD를 한 테이블로 제공하는 것은 현재 구독 SQL만으로 불가능하다. 청크 근사·공개 좌표·인원 제한 또는 별도 AOI membership/gateway 중 하나를 타협해야 한다.

## 2. 근거

- `CLAUDE.md:24-27` — 하나의 공유 월드이며 match/stage 인스턴스로 분리하지 않는 것이 프로젝트 불변 조건이다.
- `CLAUDE.md:30-40` — 다른 플레이어의 이동과 전투를 실시간으로 서로 볼 수 있어야 한다.
- `spacetimedb/Cargo.lock:587-590` — 서버 모듈이 실제로 잠근 SpacetimeDB 버전은 `2.7.1`이다.
- `lib/spacetime/cyborg_connection.dart:34-44` — 현재 월드 구독은 `world_player`와 `monster`의 전체 행 구독이다.
- `lib/spacetime/spacetime_world_presence.dart:21-31,120-143` — 좌표 보고 상한은 200ms/5Hz이며, 0.15타일 미만 이동과 이전 요청 처리 중인 경우는 생략한다.
- `spacetimedb/src/world.rs:267-358` — `WorldPlayer` 한 행에 좌표뿐 아니라 `Identity`, 문자열, HP/MP, 7개 `Timestamp` 등이 함께 들어 있다.
- `lib/spacetime/generated/world_player.dart:98-119` — `WorldPlayer`가 실제 BSATN으로 전체 열을 순서대로 직렬화한다.
- `/Users/thruthesky/.pub-cache/hosted/pub.dev/spacetimedb_sdk-2.4.0/lib/src/codec/bsatn_encoder.dart:85-200` — BSATN의 `u32/f32/i32=4B`, `u64/i64=8B`, 문자열=`4B 길이+UTF-8`, Identity는 원시 바이트로 기록된다.
- `/Users/thruthesky/.pub-cache/hosted/pub.dev/spacetimedb_sdk-2.4.0/lib/src/messages/shared_types.dart:59-68` — 지속 테이블 delta는 `inserts`와 `deletes` 두 행 목록으로 표현되므로 update는 기존 행과 새 행을 모두 운반한다.
- `spacetimedb/src/character.rs:14-23,39-53` — 이름은 2~16 Unicode 문자이고 `kind`는 `male_cyborg` 또는 `female_cyborg`다.
- `spacetimedb/src/world.rs:1038-1083` — `move_to`는 호출자의 행을 읽어 좌표와 `last_move_at`을 포함한 전체 행 update를 수행한다.
- `spacetimedb/src/world.rs:655-669,366-423` — 현 AI 청크는 32타일이며, 몬스터의 `chunk`는 현재 좌표가 아니라 집 좌표에 고정된다.
- `spacetimedb/src/world.rs:1428-1487` — AI는 전체 플레이어를 수집한 후, 모은 각 몬스터마다 다시 전체 플레이어를 순회한다.
- `lib/game/action_rpg_game.dart:541-568,648-669` — 클라이언트는 매 프레임 `presence.others` 전체를 다시 순회해 원격 플레이어를 동기화한다.
- 공식 자료 — 구독 SQL은 전체 행만 반환하고, JOIN은 두 테이블·양쪽 인덱스를 요구하며 산술식과 `LIMIT/ORDER BY`를 지원하지 않는다. [SpacetimeDB SQL Reference](https://spacetimedb.com/docs/reference/sql/)
- 공식 자료 — RLS는 experimental이며 Views 사용을 권한다. 사용자별 `ViewContext`는 1,000명일 때 1,000개의 계산·change tracking을 만든다. [RLS](https://spacetimedb.com/docs/how-to/rls/), [Views](https://spacetimedb.com/docs/functions/views/)
- 공식 자료 — reducer는 동시 실행·재실행될 수 있으므로 전역/정적 상태가 금지된다. 이는 모든 reducer가 하나의 전역 뮤텍스로 실행된다는 주장과 일치하지 않는다. [Reducers](https://spacetimedb.com/docs/functions/reducers/)
- 공식 자료 — Rust 계좌이체 벤치마크는 약 265,541 TPS지만 구독 fan-out·AI가 없는 다른 workload다. Maincloud는 단일 DB 1,000+ 연결을 목표로 하지만 workload별 처리량은 보증하지 않는다. [Benchmark](https://spacetimedb.com/blog/benchmarking), [Maincloud](https://spacetimedb.com/maincloud)

## 3. 상세 분석

### 3.1 AOI 100명의 실제 전송량

계산 조건은 다음과 같다.

- 동접 `N=1,000`
- 전원 지속 이동, reducer RTT가 200ms 미만이라 실제 5Hz 유지
- 각 플레이어 위치 변경을 다른 플레이어 정확히 100명이 구독
- 몬스터·전투 이벤트·초기 snapshot 제외
- 현재 `WorldPlayer` 행 사용

`WorldPlayer` BSATN 크기는 고정 180B가 아니다.

```text
고정부 =
Identity 32
+ character_id 8
+ 문자열 길이 prefix 8
+ level 4
+ 좌표 8
+ hp/max_hp 8
+ bool 1
+ Timestamp 7×8
+ mp/max_mp/defense/deaths 4×4
= 141B

행 크기 S = 141 + UTF8(name) + UTF8(kind)
```

이름 2~16문자, UTF-8 1~4B/문자, `kind` 11~13B이므로 `S=154~218B`다. 기존 문서와 비교하기 위한 대표값은 `[가정] 180B`다.

한 update는 프로토콜에서 기존 행 delete와 새 행 insert로 전송된다.

```text
논리 변경 = 1,000 × 5 × 100 = 500,000건/s
BSATN 행 이미지 = 500,000 × 2 = 1,000,000행/s
순수 행 데이터 = 1,000,000 × S
              = 154~218MB/s
              ≈ 180MB/s (대표값)
```

현재 SDK 메시지 구조에서 단일 행 update의 비압축 envelope는 약 `69B`다. 따라서 대표 전송량은 다음과 같다.

```text
한 관찰자에게 보내는 update ≈ 2×180 + 69 = 429B
전체 ≈ 500,000 × 429 = 214.5MB/s ≈ 1.72Gbps
클라이언트당 ≈ 100 × 5 × 429 = 214.5KB/s, 500 update/s
```

| 구조 | 논리 변경/s | 행 이미지/s | 순수 행 데이터 | 비압축 전송 기준 | 클라이언트당 |
|---|---:|---:|---:|---:|---:|
| 현재 전체 구독, 5Hz | 5,000,000 | 10,000,000 | 대표 1.8GB/s | 대표 2.145GB/s | 약 2.145MB/s |
| AOI 100, 현재 행, 5Hz | 500,000 | 1,000,000 | 대표 180MB/s | 대표 214.5MB/s | 214.5KB/s |
| AOI 100, 18B 위치 행, 5Hz | 500,000 | 1,000,000 | 18MB/s | 약 52.5MB/s | 52.5KB/s |
| AOI 100, 18B 위치 행, 2Hz | 200,000 | 400,000 | 7.2MB/s | 약 21MB/s | 21KB/s |
| AOI 100, 22B 이동 의도, 1Hz | 100,000 | 200,000 | 4.4MB/s | 약 11.3MB/s | 11.3KB/s |

따라서 `GAME-SERVER.md:185-190`의 현재 전체 구독 계산은 순수 행 기준으로도 약 2배 작다. 동접 1,000에서는 900MB/s가 아니라 대표 1.8GB/s이며, 단일행 메시지 envelope까지 포함하면 약 2.145GB/s다.

실제 WebSocket 바이트는 Brotli/gzip 적용 여부와 v3 frame batching에 따라 이보다 작을 수 있다. 현재 자료만으로 압축률을 확정할 수 없으므로 위 값은 “확정 가능한 비압축 상한”이다. 클라이언트 대역폭 0.2MB/s 자체는 높지 않지만, 모바일 Dart에서 초당 500개의 delta와 매 프레임 100개 객체 재생성·순회를 감당하는지는 별도 측정이 필요하다. `[판단]` 서버 비용과 serialization 부담 때문에 214.5MB/s를 운영 목표로 채택해서는 안 된다.

몬스터는 포함하지 않았다. 현재 `SELECT * FROM monster`도 반드시 AOI 구독과 세로 분할을 적용해야 하며, AOI 안 몬스터 수가 정해지지 않아 그 부분은 숫자를 확정할 수 없다.

### 3.2 구독 SQL 안에서 가능한 AOI

권장 구조는 RLS나 사용자별 View가 아니라, 공개된 공간 행에 정수 `subscription_chunk` 인덱스를 두고 클라이언트가 청크를 직접 구독하는 방식이다.

```sql
SELECT * FROM world_player_pos WHERE subscription_chunk = 42

SELECT profile.*
FROM world_player_profile profile
JOIN world_player_pos pos
  ON profile.character_id = pos.character_id
WHERE pos.subscription_chunk = 42

SELECT vitals.*
FROM world_player_vitals vitals
JOIN world_player_pos pos
  ON vitals.character_id = pos.character_id
WHERE pos.subscription_chunk = 42
```

`character_id`는 양쪽 PK/인덱스, `subscription_chunk`는 btree여야 한다. 각 쿼리는 최대 두 테이블만 사용하고 전체 행을 반환하므로 공식 제약 안에 들어간다.

청크 크기는 AOI 반경이 아니라 “1,000명이 1km²에 균등 분포했을 때 3×3 청크에 약 100명”이라는 가정으로 산출할 수 있다.

```text
밀도 = 1,000 / 1,000,000 = 0.001명/타일²
9C² × 0.001 = 100
C = 105.4타일
```

구현값으로 `SUBSCRIPTION_CHUNK_TILES=104`를 권한다. 3×3 내부 청크 면적에는 평균 약 97명이 들어오며, `106`이면 약 101명이다. 이는 평균값일 뿐 인원 상한이 아니다. 특정 청크에 500명이 모이면 500행이 온다.

현재 32타일 AI 청크와 104타일 구독 청크는 별도 컬럼이어야 한다. 104타일 경계를 보행 속도 3.6타일/s로 넘는 주기는 약 `28.9초`, 최대 허용 속도 14타일/s에서는 `7.4초`다.

축 방향 경계 이동 시 3×3 중 6청크는 유지되고 3청크만 교체된다.

```text
새 strip의 평균 플레이어 수
= 3 × 104² × 0.001
≈ 32.4행
```

대각선 경계에서는 5청크가 교체되어 평균 약 54행이다. 각 청크를 별도 query set으로 관리하고 새 3/5개를 먼저 `subscribe`, 응답 후 이전 3/5개를 `unsubscribe`해야 한다. 현재 SDK는 행별 query-set ownership을 추적하므로 겹친 청크가 남아 있으면 행을 제거하지 않는다. 반대로 9청크 전체를 하나의 새 query set으로 다시 걸면 겹친 6청크의 snapshot도 다시 받을 수 있으므로, 기존 문서의 “겹치는 쿼리는 추가 비용이 없다”는 표현은 네트워크 비용 관점에서 삭제해야 한다.

RLS와 View의 판정은 다음과 같다.

- 성능 우선 AOI: 둘 다 사용하지 않고 직접 인덱스 구독.
- 좌표 은닉이 필수가 아니면 공개 위치 테이블이 가장 단순하고 공유 가능한 구조다.
- 좌표 은닉이 필수라면 공식 권고상 `ViewContext`가 RLS보다 적합하지만, 1,000개의 사용자별 계산이 필요하다.
- RLS는 `:sender`를 사용할 수 있으나 experimental이다.
- `AnonymousViewContext`는 사용자별 위치를 알 수 없고 인자를 받지 않으므로 “내 주변”을 표현하지 못한다.

### 3.3 5,000 `move_to`/s와 입력 배칭

`GAME-SERVER.md:59-69`의 “전역 뮤텍스”는 현재 공식 문서와 충돌한다. SpacetimeDB 2.x는 reducer 동시 실행과 serializability retry 가능성을 명시한다. 따라서 5,000 TPS 자체를 이유로 불가능하다고 결론낼 수 없다.

엄격 직렬화가 실제 배포 환경에서 적용된다고 가정하면 예산은 다음과 같다.

| 보고 주기 | 이동 TPS | 이동 하나당 절대 최대 시간 | AI에 30%를 남긴 예산 |
|---:|---:|---:|---:|
| 200ms/5Hz | 5,000 | 200µs | 140µs |
| 500ms/2Hz | 2,000 | 500µs | 350µs |
| 1,000ms/1Hz | 1,000 | 1ms | 700µs |

현재 `move_to`는 PK 조회, 부동소수점 검증·거리 계산, 한 행 update와 subscription fan-out을 수행한다. 측정값 없이 140µs 이내라고 보증할 수 없다. 반면 공식 Rust microbenchmark 265,541 TPS와 비교하면 5,000 TPS는 약 53배 낮지만, 그 benchmark에는 AOI 100 fan-out과 AI가 없다.

권장값은 다음과 같다.

- 즉시 적용 기준: `500ms/2Hz`
- 먼 플레이어 또는 이동 의도: `1,000ms/1Hz`
- 기존 원격 플레이어 보간은 200ms 수신을 전제로 하므로 `lib/game/entities/remote_player.dart:77-90`을 속도 기반 외삽으로 바꿔야 한다.

여러 사용자의 입력을 한 reducer 호출로 보내는 것은 직접 연결 클라이언트 구조에서는 안전하지 않다. `ctx.sender()`는 호출자 한 명만 증명하므로 한 클라이언트가 다른 999명의 이동을 제출할 권한이 없다.

가능한 배칭은 두 가지다.

1. 각 클라이언트가 자신의 여러 입력을 배열로 1회 제출한다. 트랜잭션은 줄지만 최종 상태만 복제되므로 사실상 보고 빈도를 낮추는 것과 같다.
2. 각 클라이언트가 private `PendingMove`를 갱신하고 scheduled reducer가 최신 1,000행을 한 번에 public position으로 발행한다. public delta의 메시지 수는 줄지만 입력 5,000 TPS와 private 쓰기는 남고, 한 번의 큰 트랜잭션이 AI와 충돌할 수 있다.

진정한 다중 사용자 입력 배칭에는 신뢰할 수 있는 외부 gateway가 필요하며, 이는 현재 “클라이언트가 DB에 직접 연결”하는 구조를 바꾸는 설계 타협이다.

### 3.4 `monster_ai` 자료구조와 재구축 비용

현재 비용은 동접 1,000에서 다음과 같다.

```text
7,500 몬스터 × 1,000 플레이어
= 7,500,000 거리 계산/tick
× 3.33Hz
≈ 25,000,000 거리 계산/s
```

전역 상태를 유지할 수 없다는 것은 “지역 변수도 못 쓴다”는 뜻이 아니다. 현재 코드도 reducer 안에서 지역 `HashMap`을 이미 사용한다(`spacetimedb/src/world.rs:1444-1447`). 올바른 구조는 매 AI tick 다음처럼 재구축하는 것이다.

```text
cell 크기: 16타일
players_by_cell: HashMap<u32, Vec<PlayerLite>>
1. 플레이어 1,000명을 현재 좌표 기준 cell에 넣는다: O(1,000)
2. 몬스터 7,500기를 한 번 순회한다: O(7,500)
3. 각 몬스터는 자기 cell과 이웃 8cell의 플레이어만 비교한다.
```

균등 분포 계산은 다음과 같다.

```text
16타일 cell 수 ≈ 63×63 = 3,969
cell당 플레이어 ≈ 1,000 / 3,969 = 0.252
몬스터당 9cell 후보 ≈ 2.27명

거리 계산/tick ≈ 7,500 × 2.27 = 17,025
거리 계산/s ≈ 56,700
```

현재 2,500만/s 대비 약 441배 감소한다. 매 틱 재구축 비용은 플레이어 1,000개 삽입, 몬스터 7,500개 순회, 약 17,000개 거리 계산이며, 초당으로는 각각 약 3,333·25,000·56,700회다.

`[추측]` 인덱스와 벡터 관리 메모리는 수십~수백 KB 수준이지만 Rust allocator와 실제 행 복사 비용은 측정해야 한다. 로컬 맵은 reducer가 끝나면 버려지므로 지속성 제약을 어기지 않는다.

현재 `Monster.chunk`는 집 좌표 기준이다. 몬스터가 최대 26타일 이동하므로 경계 근처에서는 현재 위치와 집 청크가 달라져 한 칸 이웃 검색이 실제 근처 플레이어를 놓칠 수 있다. 선택지는 다음과 같다.

- 권장: AI는 몬스터 전체 7,500행을 순회하면서 현재 좌표로 16타일 cell을 계산한다.
- 대안: `home_chunk`와 현재 `ai_chunk`를 분리하고, 몬스터가 cell 경계를 넘을 때만 `ai_chunk` 인덱스를 갱신한다.
- 기존 `chunk`를 그대로 쓸 경우 검색 범위를 최소 5×5로 넓혀야 하지만 후보 수가 약 2.8배 증가한다.

모든 1,000명이 한 cell에 모이면 공간 해시도 몬스터당 1,000명을 비교한다. 정확한 최단거리 대상 선택을 유지하는 한 이 최악값은 사라지지 않는다. 밀집 지역에서는 “후보 100명 상한” 또는 “정확한 최근접 대신 cell 대표 대상”이라는 게임 규칙 타협이 필요하다.

### 3.5 각 최적화의 절감량

권장 compact 위치 행은 다음과 같이 구성할 수 있다.

```text
character_id u64          8B
x_q, y_q i16             4B
subscription_chunk u16    2B
motion_seq u32            4B
합계                     18B
```

인증용 `Identity → character_id`는 private presence 테이블에 두면 public 위치 행에서 32B Identity를 제거할 수 있다. 그 대가로 `move_to`에 PK 조회 한 번이 추가된다.

| 변경 | 비교 | 절감 |
|---|---|---:|
| 세로 분할, Identity 유지 | 대표 180B → 46B 위치 행 | 74.4%, 3.91배 |
| 세로 분할 + public 키를 `character_id`로 | 대표 180B → 22B f32 위치 행 | 87.8%, 8.18배 |
| 좌표 `f32×2 → i16×2` | 22B → 18B | 18.2%, 1.22배 |
| 좌표 축소만 현 행에 적용 | 180B → 176B | 2.2%, 1.02배 |
| 5Hz compact 위치 → 1Hz 이동 의도 | `5×18=90B/s` → `1×22=22B/s` | 75.6%, 4.09배 |
| 이동 의도 변경이 평균 0.5Hz | `90B/s` → `0.5×22=11B/s` | 87.8%, 8.18배 |
| 가까운 20명 5Hz, 먼 80명 1Hz | `500` → `20×5+80×1=180` 변경/클라이언트/s | 64%, 2.78배 |

`i16` 좌표는 `round(tile×32)`로 인코딩하면 최대 월드 좌표도 약 32,192로 `i16::MAX` 안에 들어간다. 최대 양자화 오차는 `1/64=0.015625`타일이다.

이동 의도는 최소 `character_id`, 출발 좌표, 속도 벡터, 시작 tick, 청크로 약 22B다. 다만 연속 이동 중 청크가 자동으로 바뀌지 않으므로 클라이언트가 경계에서 의도를 갱신하거나, 1Hz scheduled reducer가 1,000개 의도를 재계산해 경계를 넘은 행만 갱신해야 한다.

LOD는 동일한 한 위치 행으로는 구현할 수 없다. 행이 5Hz로 바뀌면 모든 구독자가 5Hz delta를 받기 때문이다. `PlayerMotionFast`와 `PlayerMotionSlow/Intent`를 분리하고, 가까운 청크는 fast, 먼 ring은 slow를 구독해야 한다.

### 3.6 달성 가능한 조건

다음 조건을 동시에 만족하면 `[판단]` 단일 DB에서 동접 1,000/AOI 100은 현실적인 부하 시험 대상이 된다.

- 104타일 구독 청크의 3×3 AOI
- 구독 대상이 실제로 100명 이하라는 밀집도 계약
- public 위치 행 18B
- 기본 2Hz, 먼 대상 1Hz
- 몬스터도 전체 구독 제거
- AI 16타일 transient spatial hash
- 사용자별 View/RLS를 실시간 AOI 경로에서 사용하지 않음

이 조건의 플레이어 위치 부하는 약 7.2MB/s의 행 데이터, 단일행 메시지 기준 약 21MB/s, 클라이언트당 약 21KB/s·200 update/s다. Maincloud가 공식적으로 말하는 1,000+ 연결 범위 안이지만, AI·전투·몬스터 delta를 더한 실제 수용 여부는 p95/p99 측정으로만 확정할 수 있다.

## 4. 리스크 · 함정

- 일반 청크 구독에는 `LIMIT`과 거리 정렬이 없으므로 “정확히 가장 가까운 100명” 또는 “최대 100명”을 보장하지 않는다. 밀집 시 트래픽이 다시 인원수에 비례한다.
- 현재 문서의 전역 뮤텍스 주장은 공식 2.x 실행 모델과 충돌한다. 반대로 실제 Maincloud 2.7.1의 commit 경합·retry 정책도 작업공간에는 없으므로 병렬성을 보증해서도 안 된다.
- `Monster.chunk`가 집 좌표에 고정되어 있어 현재 위치 기반 AOI/AI 인덱스로 재사용하면 경계에서 대상을 놓친다.
- 500ms 좌표 snapshot으로 주기만 늘리면 현재 보간기가 목표에 일찍 도착해 멈칫한다. 외삽 또는 이동 의도가 함께 필요하다.
- LOD는 구독 SQL 옵션이 아니다. fast/slow 테이블 분리와 중복 제거가 없으면 절감 효과가 없다.
- public 청크 구독은 정상 클라이언트만 AOI를 지킬 뿐, 변조 클라이언트가 전체 청크를 구독하는 것을 막지 않는다.
- AOI를 보안으로 강제하려고 사용자별 View를 사용하면 1,000개의 계산 상태가 생긴다. RLS는 experimental이다.
- 서버는 `2.7.1`인데 Dart SDK는 `2.4.0`이다(`pubspec.lock:528-535`). 현재 동작 여부와 별개로 v3 batching·compression·subscription ownership을 부하 시험 환경에서 검증해야 한다.
- 기존 클라이언트는 매 프레임 원격 목록 전체를 새 객체로 만든다. AOI 100은 작아 보이지만 저사양 모바일의 allocation/GC 부하는 미확인이다.
- 월드를 여러 DB로 나누는 최후 수단은 단일 공유 월드·비인스턴스 규칙(`CLAUDE.md:24-27`)과 직접 충돌한다.
- 대표 214.5MB/s를 한 달 유지하면 비압축 기준 약 556TB egress다. 실제 압축 후에도 현재 Pro 포함량 500GB를 크게 넘을 가능성이 높다. [Maincloud Pricing](https://spacetimedb.com/pricing)

## 5. 권고안

| 순위 | 권고 | 범위 | 근거 | 리스크 |
|---|---|---|---|---|
| 1 | 전체 `world_player`/`monster` 구독을 제거하고, 104타일 `subscription_chunk`별 query set을 유지한다. 경계 이동 시 새 3/5개를 먼저 구독한다. | 서버 테이블·Dart 구독 관리자 | `lib/spacetime/cyborg_connection.dart:34-44`, 공식 [SQL Reference](https://spacetimedb.com/docs/reference/sql/) | 평균 AOI일 뿐 100명 상한은 아님 |
| 2 | `WorldPlayerProfile`·`WorldPlayerPos`·`WorldPlayerVitals`로 세로 분할하고, public 위치 키는 `character_id`로 축소한다. 예상 위치 egress 8.18배 감소. | 서버 schema·generated bindings·클라이언트 cache | `spacetimedb/src/world.rs:267-358`, `lib/spacetime/generated/world_player.dart:98-119` | private Identity 매핑 조회가 한 번 추가됨 |
| 3 | `monster_ai`를 16타일 transient spatial hash로 바꾸고 현재 좌표를 사용한다. 균등 분포 기준 거리 계산 약 441배 감소. | `monster_ai` 내부 | `spacetimedb/src/world.rs:1428-1487` | 1,000명 밀집 최악값에는 후보 상한 필요 |
| 4 | 좌표 snapshot은 즉시 500ms/2Hz로 낮추고, 먼 대상은 1Hz 이동 의도로 전환한다. TPS·egress 각각 2.5배, intent 기준 추가 4.09배 절감. | Dart 보고·Rust 이동 검증·보간 | `lib/spacetime/spacetime_world_presence.dart:21-31,120-143`, `lib/game/entities/remote_player.dart:77-90` | 외삽·서버 시간·청크 경계 재분류 필요 |
| 5 | fast/slow 위치 테이블로 LOD를 구현한다. 가까운 20명 5Hz/먼 80명 1Hz이면 2.78배 절감. | 서버 복제 모델·클라이언트 구독 ring | `lib/spacetime/cyborg_connection.dart:39-44`, 공식 [Subscriptions SQL](https://spacetimedb.com/docs/reference/sql/) | 테이블 중복, fast/slow snapshot 충돌 제거 필요 |
| 6 | 좌표를 `round(tile×32)`의 `i16`으로 저장한다. compact 행에서 추가 1.22배 절감. | public 위치·몬스터 위치 | `spacetimedb/src/world.rs:51-68`, `spacetimedb/src/world.rs:283-284` | 기존 f32 API·generated binding 마이그레이션 필요 |
| 7 | 출시 기준을 `1,000 sockets`, `2,000/5,000 move TPS`, `AOI 100`, AI·전투 동시 부하로 고정하고 reducer p95<50ms, p99<100ms, AI tick<100ms, tick 밀림 0을 gate로 둔다. | 부하 시험·운영 판단 | `GAME-SERVER.md:341-350`, 공식 [Benchmark](https://spacetimedb.com/blog/benchmarking) | 임계값은 사용자 체감 목표에 따라 사람 판단 필요 |

우선순위 1·2·4·6을 함께 적용하면 현재 전체 구독·5Hz·180B 행 대비 순수 플레이어 위치 데이터는 대표 `1.8GB/s → 7.2MB/s`, 약 250배 감소한다. 메시지 envelope까지 포함한 비압축 기준은 약 `2.145GB/s → 21MB/s`, 약 102배 감소한다.

## 6. 불확실 · 미확인

- 실제 캐릭터 이름의 UTF-8 길이 분포가 없어 현재 평균 행 크기 180B는 대표값일 뿐이다.
- Maincloud가 v3 메시지를 어떤 크기로 batch하고 Brotli/gzip을 언제 적용하는지 확인되지 않았다. 실제 wire byte는 WebSocket capture가 필요하다.
- 배포된 Maincloud 2.7.1 host의 reducer 병렬도, commit 직렬 구간, retry 정책과 할당된 NIC 용량이 미확인이다.
- AOI의 물리 반경, 허용 최대 밀집 인원, AOI 안 평균 몬스터 수가 정의되지 않았다. 104타일은 균등 분포 100명이라는 계산 가정이다.
- “AOI 100”이 평균 목표인지, 표시 상한인지, 정확히 최근접 100명인지 사람의 제품 결정이 필요하다.
- 좌표를 공개해 변조 클라이언트의 전체 월드 구독을 허용할지, 사용자별 View 비용을 감수할지 보안 결정이 필요하다.
- 이동 의도의 평균 변경 빈도는 실제 조작 로그가 없어 1Hz/0.5Hz를 가정했다.
- `move_to`, AI tick, subscription fan-out의 실제 p50/p95/p99 및 serializability retry 횟수가 측정되지 않았다.
- Flutter/Dart 클라이언트가 100개 원격 엔티티, 초당 200~500 delta, 매 프레임 목록 할당을 감당하는 저사양 기기 기준이 없다.
- 한 지역에 1,000명이 모이는 상황까지 지원해야 한다면 direct chunk AOI로는 100명 네트워크 상한을 보장할 수 없다. 서버 AOI membership, 입장 제한, 외부 gateway 또는 다중 DB 중 하나가 추가로 필요하다.
