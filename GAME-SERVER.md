# GAME-SERVER — 동접 1,000 · AOI 100 을 SpacetimeDB 로 만들 수 있는가

## 한 줄 결론

**동접 1,000 은 조건부로 가능하다. 그러나 "AOI 100" 은 지금 정의로는 만들 수 없다 — 정의를 바꿔야 목표가 성립한다.**

SpacetimeDB 때문에 못 만드는 *기능*은 이 문서 어디에도 없다. 서버 권위 이동·충돌·길찾기·전투·PK·스킬·텔레포트·실시간 동기화는 모두 구현 가능하고, 우리는 이미 상당수를 [`spacetimedb/src/world.rs`](spacetimedb/src/world.rs) 에 돌리고 있다.

막히는 것은 기능이 아니라 **"가까운 100 명만 보내라" 라는 문장을 구독 SQL 로 쓸 수 없다는 것**이다. `LIMIT` 도 거리 정렬도 없다. 청크 구독은 *면적*을 자를 뿐 *인원*을 자르지 못한다. 그래서 AOI 는 두 겹으로 재정의해야 한다.

> **AOI 100 의 실행 가능한 정의**
> ① **면적** — 균등 분포에서 평균 100 명이 들어오는 크기의 청크를 구독한다 (104 타일, → [§7](#7-관심-영역-구독을-실제로-만드는-법))
> ② **상한** — 그 안에 몇 명이 있든 클라이언트는 가까운 100 명만 그린다 (표시 계층에서 강제)
>
> ①만으로는 집결 시 트래픽이 다시 인원수에 비례한다. ②가 없으면 목표는 보장되지 않는다.

그리고 **한 지점에 1,000 명 집결은 어떤 최적화로도 불가능하다.** 이것만은 게임 설계로 회피해야 한다([§9](#9-끝내-불가능한-것)).

---

## 이 문서가 정정한 것

이 문서는 4 AI 교차 분석(`.cowork/scale-1000-aoi-100/final-report.md`)으로 이전 판을 검증한 결과다. 두 가지가 틀렸었다.

| 이전 판의 서술 | 검증 결과 |
|---|---|
| 전체 구독 시 동접 1,000 에서 약 900 MB/s | ❌ **약 1.8 GB/s.** SpacetimeDB 는 행 갱신을 `deletes + inserts` **두 행 이미지**로 보낸다 |
| "쓰기는 전역 뮤텍스로 직렬화된다"(플랫폼 사양) | ⚠️ **확정 사실이 아니다.** 공식 문서는 동시 실행 권리를 유보한다. 서드파티 관찰을 사양처럼 단정한 것은 오류 |

첫째는 목표 수치를 두 배 어렵게 만들고, 둘째는 반대로 낙관 쪽으로 푼다. 근거는 [§4 A·B](#4-두-가지-정정) 에 원문과 함께 적었다.

---

## 1. SpacetimeDB 를 한 장으로

데이터베이스가 곧 게임 서버다. 별도의 애플리케이션 서버가 없고, 클라이언트는 DB 에 직접 WebSocket 으로 붙는다.

| 개념 | 하는 일 | 우리 코드 |
|---|---|---|
| **table** | 세계의 상태. 모든 진실이 여기 있다 | `WorldPlayer`, `Monster`, `PlayerCharacter` |
| **reducer** | 상태를 바꾸는 유일한 통로. 한 번 호출 = 한 트랜잭션 | `move_to`, `attack_monster`, `cast_skill` |
| **scheduled reducer** | 서버 틱. `ScheduleAt::Interval` 로 주기 실행 | `monster_ai`(300ms), `regen_tick`(1s), `monster_tick`(5s) |
| **view** | 읽기 전용 파생 데이터. 구독 가능 | `my_account`, `leaderboard`, `my_rank` |
| **subscription** | 클라이언트가 걸어 두는 SQL. 행이 바뀌면 자동으로 밀려온다 | `SELECT * FROM monster` 등 |

핵심 루프는 이렇다.

```text
scheduled reducer 실행
        ↓
AI · 이동 · 충돌 · 전투 판정
        ↓
테이블 갱신
        ↓
트랜잭션 commit
        ↓
바뀐 행을 구독 중인 클라이언트에게만 델타 전송  ← 여기가 비용의 대부분
        ↓
클라이언트가 로컬 캐시 갱신 → 렌더링에서 보간
```

**서버 틱(3~20Hz)과 화면 프레임(60Hz)은 별개다.** 서버가 300ms 마다 몬스터 좌표를 갱신해도 클라이언트는 그 사이를 보간해 부드럽게 그린다. 서버가 프레임마다 좌표를 보낼 필요는 없고, 보내서도 안 된다.

---

## 2. 설계를 강제하는 다섯 가지 제약

이 다섯은 "주의사항" 이 아니라 **아키텍처의 전제**다.

### 2.1 쓰기 처리량은 코어 수만큼 늘지 않는다

공식 문서는 이렇게 적는다.

> "SpacetimeDB **reserves the right to execute multiple reducers concurrently** in separate execution environments (e.g., with MVCC)."
> "**If a serializability anomaly is detected, SpacetimeDB may re-execute your reducer with the same arguments**, causing modifications to global state to occur multiple times."
> — [Reducers](https://spacetimedb.com/docs/functions/reducers/)

읽는 법이 중요하다. **"권리를 유보한다"는 그렇게 한다는 약속이 아니다.** 그리고 서드파티 구현 분석은 현재 커밋 구간이 전역 락으로 직렬화된다고 관찰한다([strn.cat](https://strn.cat/w/articles/spacetime/)). Maincloud 2.7.1 의 실제 병렬도는 공개 자료에 없다.

따라서 설계 원칙은 셋이다.

1. **쓰기 처리량이 코어 수만큼 확장된다고 가정한 설계를 하지 않는다.**
2. 동시에 "직렬화 때문에 초당 5,000 트랜잭션이 불가능하다" 고 **단정하지도 않는다.** 측정이 답이다.
3. **커밋 구간 직렬화는 어느 정도든 존재한다.** 그러므로 긴 트랜잭션을 피하고 **틱 하나가 하는 일의 총량을 줄이는 원칙은 그대로 유효하다.** 존별로 틱을 나누는 것이 처리량을 존 수만큼 늘려 주지는 않지만, 트랜잭션 하나하나를 짧게 만드는 값어치는 있다.

> 예산 감각: 3.33Hz AI 틱이 커밋 구간의 30% 를 넘으면 안 된다. 즉 한 틱은 **90ms 안에** 끝나야 하고, 여기에 초당 수천 회의 `move_to` 와 전투 reducer 가 같은 자원을 두고 경쟁한다.

### 2.2 수평 확장이 없다

하나의 데이터베이스는 하나의 머신에서 돈다. Maincloud 는 80 코어 / 256GB 급 장비를 쓰지만, 부하가 한계를 넘으면 선택지는 둘뿐이다.

- 월드를 여러 데이터베이스로 쪼갠다 → **DB 간 이동·거래·채팅을 직접 만들어야 하고**, [CLAUDE.md](CLAUDE.md) 의 "하나의 공유 월드, 인스턴스 분리 없음" 원칙과 정면으로 충돌한다.
- 또는 월드 하나가 감당할 인원을 설계로 낮춘다.

BitCraft Online 이 전체 백엔드를 단일 SpacetimeDB 모듈로 운영한다는 사례가 있지만, 그것은 **그 게임의 부하 특성**에서 성립한 결과다. 우리 게임의 몹 수·틱 주기·가시 범위에 대한 보증이 아니다.

### 2.3 모듈에 메모리를 둘 수 없다

reducer 는 WASM 안에서 돌고, **전역·정적 변수 사용은 정의되지 않은 동작(undefined behavior)** 이다. 공식 문서가 드는 이유는 다섯 가지 — 실행 환경이 매번 새로 뜰 수 있고, 모듈 갱신 시 초기화되고, 동시 실행될 수 있고, 재시작 시 소멸하고, 롤백돼도 메모리 값은 남는다. 네트워크·파일·시스템 콜도 없다.

이것이 뜻하는 바:

- **quadtree·spatial hash 를 틱 사이에 유지할 수 없다.** 일반 게임 서버 권고를 그대로 옮기면 안 된다. 방법은 둘이다 — **테이블의 인덱스 컬럼으로 표현**하거나([`Monster.chunk`](spacetimedb/src/world.rs#L414) + `by_chunk` btree 가 그것이다), **틱마다 로컬 `HashMap` 으로 재구축**한다. 후자는 지역 변수라 제약을 어기지 않고, 실제로 `monster_ai` 가 이미 로컬 `HashMap` 을 쓴다([world.rs:1446](spacetimedb/src/world.rs#L1446)).
- **navmesh 를 캐시할 수 없다.** A* 를 쓰려면 그래프를 테이블에 넣거나 코드에 상수로 박는다.
- 좌표(`f32`)에는 범위 인덱스를 걸 수 없다. **공간 질의는 정수 청크 컬럼을 경유해야 한다.**

### 2.4 구독 SQL 은 생각보다 좁다

여기가 목표 달성의 핵심 병목이다. 구독 언어는 쿼리 언어의 **진부분집합**이다.

| | 구독(subscription) | 쿼리(query) |
|---|---|---|
| 컬럼 프로젝션 | **불가**. `SELECT *` 만 | 개별 컬럼, `COUNT` 가능 |
| JOIN | **최대 2 테이블**, 조인 컬럼 **양쪽에 인덱스 필수** | 제한 없음 |
| 산술식 (`WHERE x + 1 > y`) | **불가** | 가능 |
| `ORDER BY` / `LIMIT` | **불가** | 가능 |
| 서브쿼리 · 집계 | **불가** | 가능 |
| 비교 연산자 | `= < > <= >= != <>` 가능 | 동일 |

설계에 직결되는 결과:

- **"가까운 100 명" 을 구독으로 표현할 수 없다.** `ORDER BY distance LIMIT 100` 이 없고, 거리 계산에 필요한 산술식도 없다. → AOI 재정의가 강제된다.
- **행의 일부만 받을 수 없다.** 큰 행을 구독하면 전부 온다. 유일한 해법은 **테이블을 세로로 쪼개는 것**.
- 조인 컬럼 양쪽에 인덱스가 없으면 구독이 **런타임 에러로 깨진다.** 인덱스를 지우는 순간 클라이언트가 죽는다.

### 2.5 게임 엔진이 주는 것은 아무것도 없다

물리, 충돌 해석, 길찾기, 히트박스, 어그로 테이블, AOI 관리 — **하나도 내장되어 있지 않다.** 전부 Rust 로 직접 쓴다. SpacetimeDB 는 "트랜잭션과 실시간 복제를 해 주는 DB" 이지 게임 서버 프레임워크가 아니다.

---

## 3. 기능별 판정표

| 기능 | 가능 | 어디에 값을 치르는가 |
|---|:---:|---|
| 서버 권위 입력 검증 | ✅ | reducer 호출 빈도가 곧 부하 |
| 몬스터 AI·추격·이동 | ✅ | 틱 비용이 `활성 몹 × 판단 대상` 으로 곱해진다 ([§5.3](#53-monster_ai-의-곱셈)) |
| 걷기/달리기/스태미나 | ✅ | 상태 컬럼 몇 개. 사실상 공짜 |
| 충돌 판정 | ✅ | 직접 구현. 공간 분할은 인덱스 컬럼 또는 틱 로컬 해시 |
| A* 길찾기 | ✅ | 매 틱 재계산 금지. 경로를 테이블에 저장하고 재사용 |
| 몬스터↔PC 전투 | ✅ | reducer 안에서 완결. 이미 구현됨 |
| PC↔PC PK | ✅ | 동일. 판정을 한 함수로 모을 것 |
| 스킬·버프·디버프 | ✅ | 지속 효과를 틱으로 돌리면 틱 대상이 늘어난다 |
| 텔레포트 | ✅ | 원자적 위치 변경. 이미 구현됨 |
| 인벤토리·거래·경제 | ✅ | 트랜잭션 원자성이 그대로 해결해 준다. **이 스택의 최대 강점** |
| 채팅·길드·퀘스트 | ✅ | 테이블 + reducer |
| 화면 동기화 | ⚠️ | **여기가 병목.** 구독 범위가 전부를 결정한다 ([§5](#5-지금-구조가-터지는-지점)) |
| 면적 기반 AOI | ⚠️ | 청크 구독으로 가능. 재구독 관리 필요 ([§7](#7-관심-영역-구독을-실제로-만드는-법)) |
| **인원 상한 AOI ("가까운 100 명")** | ❌ | **구독 SQL 로 표현 불가.** 표시 계층에서 강제해야 한다 |
| 관찰자별 갱신 빈도 LOD | ❌ | 쓰기 1 회가 그 행의 모든 구독자에게 나간다. fast/slow 테이블 분리로만 흉내 |
| 이벤트 연출 동기화 | ⚠️ | 이벤트 테이블은 **삽입 후 즉시 삭제하면 전달되지 않는다** ([§6.5](#65-이벤트는-상태와-분리하되-함정을-피한다)) |
| 다중 유저 입력 배칭 | ❌ | `ctx.sender()` 가 호출자 한 명만 증명한다 ([world.rs:1694](spacetimedb/src/world.rs#L1694)) |
| 월드 샤딩 | ❌ | 플랫폼이 주지 않는다 ([§2.2](#22-수평-확장이-없다)) |
| 외부 API 연동 (결제 등) | ❌ | reducer 에서 네트워크 불가. Procedure 로 분리 |

한 reducer 는 한 트랜잭션이므로, PK 공격 하나에서 **MP 소비 → 쿨다운 → 피해 → 사망 → 경험치 → 드롭**을 함께 처리하고 중간 실패 시 전부 롤백할 수 있다. SpacetimeDB 를 고른 값을 여기서 회수한다.

---

## 4. 두 가지 정정

### A. 행 갱신은 두 행으로 전송된다

Dart SDK 의 델타 디코더를 직접 열어 확인했다.

```dart
// spacetimedb_sdk-2.3.1/lib/src/messages/shared_types.dart:59-68
class PersistentTableRows extends TableUpdateRows {
  final BsatnRowList inserts;
  final BsatnRowList deletes;
```

지속 테이블의 델타는 `inserts` 와 `deletes` **두 목록**으로 표현된다. 행 하나를 갱신하면 **옛 행과 새 행이 모두 운반된다.** 따라서 모든 egress 계산에 ×2 가 붙는다. 이전 판의 수치는 전부 절반이었다.

### B. "전역 뮤텍스" 는 확정 사실이 아니다

[§2.1](#21-쓰기-처리량은-코어-수만큼-늘지-않는다) 에 옮긴 공식 문서 원문대로다. 이전 판이 서드파티 블로그의 구현 관찰을 플랫폼 사양처럼 단정했다. 정확한 서술은 "코어 수만큼 확장된다고 가정하지 말 것" 이며, "직렬화 때문에 불가능" 이라는 결론은 근거가 없다.

**이 정정에도 [§6](#6-목표를-성립시키는-변경) 의 권고는 전부 살아남는다** — 커밋 구간 직렬화가 얼마든 존재하는 한, 틱을 가볍게 하고 쓰기 횟수를 줄이는 것은 여전히 옳기 때문이다.

---

## 5. 지금 구조가 터지는 지점

세 곳이다. 전부 **동접 수에 대해 제곱으로 커진다.**

> 행 크기는 BSATN 필드 합계 추정이다 — `world_player` ≈ 180B, `monster` ≈ 90B. 정확한 값은 측정으로 확정해야 하지만 **자릿수는 바뀌지 않는다.**

### 5.1 `world_player` 전체 구독 — 가장 먼저 터진다

모든 클라이언트가 모든 플레이어를 구독한다([cyborg_connection.dart:39](lib/spacetime/cyborg_connection.dart#L39)). 각자 5Hz 로 좌표를 보고한다([spacetime_world_presence.dart:26](lib/spacetime/spacetime_world_presence.dart#L26)).

```text
논리 변경/s = N × 5 × N = 5N²
행 이미지/s = 10N²            ← §4 A
```

| 동접 | 행 이미지/s | egress |
|---:|---:|---:|
| 50 | 25,000 | 약 4.5 MB/s |
| 100 | 100,000 | 약 18 MB/s |
| 200 | 400,000 | 약 72 MB/s |
| **1,000** | **10,000,000** | **약 1.8 GB/s** |

동접 1,000 은 네트워크만으로 불가능하다. Maincloud 는 **egress 를 과금**하므로 이 숫자는 요금 고지서이기도 하다.

### 5.2 `monster` 전체 구독 — 사람보다 클 수 있다

몬스터는 **서버가 3.33Hz 로 계속 쓴다.** 사람이 5Hz 로 보고하는 것보다 갱신원이 많다.

초기 스냅샷만 7,500 행 × 90B ≈ **675KB × 접속자**다. 그 뒤로는 움직인 몹만 델타로 나가지만, 그 델타가 **모든 구독자에게** 간다. 사람 한 명 주변에서 매 틱 10 기가 움직인다고 보수적으로 잡으면:

```text
행 이미지/s = N × 10 × 3.33 × N × 2 ≈ 67N²
```

동접 100 명이면 초당 약 67 만 행, 약 **60 MB/s**. 본인 화면에 보이지도 않는 몹의 좌표가 대부분이다. **AOI 를 적용해도 몬스터가 남는다** — [§6.1](#61-청크-구독으로-aoi-를-만든다-효과-최대) 참고.

### 5.3 `monster_ai` 의 곱셈

[world.rs:1428](spacetimedb/src/world.rs#L1428) 의 구조는 이렇다.

```rust
let players = ctx.db.world_player().iter()...   // 전체 스캔: O(N)
for player in &players {                         // 사람마다 9 청크 조회
    for monster in ctx.db.monster().by_chunk().filter(key) { ... }
}
for (_, monster) in nearby {
    for player in &players { ... }               // ← 몹마다 전체 플레이어 순회
}
```

마지막 루프가 **O(근처 몹 수 × 전체 플레이어 수)** 다. 코드 주석은 "사람 수는 적으므로 전부 재도 싸다"([world.rs:1480](spacetimedb/src/world.rs#L1480))고 적었는데, **동접 수십 명 전제이며 목표 규모에서 거짓이 된다.**

| 동접 | 근처 몹 집합 | 거리 계산 / 틱 | 초당 |
|---:|---:|---:|---:|
| 10 | 약 660 | 6,600 | 22,000 |
| 100 | 약 6,000 | 600,000 | 200만 |
| 1,000 | 7,500 (전부) | 7,500,000 | **2,500만** |

여기에 낭비가 하나 더 있다 — **같은 지역의 사람마다 같은 9 청크를 다시 조회한다**([world.rs:1448-1468](spacetimedb/src/world.rs#L1448)). 한곳에 100 명이 모이면 동일한 인덱스 스캔을 900 번 반복한다.

---

## 6. 목표를 성립시키는 변경

효과 순이다. 누적 효과는 [§8](#8-목표-달성-조건표) 에 표로 정리했다.

### 6.1 청크 구독으로 AOI 를 만든다 (효과 최대)

`10N²` 의 **구독자 쪽 N 을 상수 A 로 바꾼다.** 이러면 전송량이 동접 수와 무관해진다.

선행 조건: **`WorldPlayer` 에 청크 컬럼이 없다.** [world.rs:267-359](spacetimedb/src/world.rs#L267) 를 확인했다 — `chunk` 가 한 번도 나오지 않는다. 추가가 먼저다.

- 컬럼은 **맨 끝에, 기본값과 함께** 추가해야 한다 — 이미 배포된 표의 자동 마이그레이션 조건이다([world.rs:301](spacetimedb/src/world.rs#L301) 이 같은 이유를 적어 두었다).
- `move_to`·`teleport_to`·`enter_world` 가 좌표를 쓸 때 함께 갱신한다.
- **몬스터의 구독용 청크는 현재 좌표 기준으로 새로 둔다.** 기존 [`Monster.chunk`](spacetimedb/src/world.rs#L414) 는 *집 좌표* 고정이라 AI 용으로는 안전하지만(roam 26 < 청크 32), 구독은 "지금 화면에 보이는 위치" 를 기준으로 해야 한다.

### 6.2 테이블을 세로로 쪼갠다

구독은 행 전체를 보낸다([§2.4](#24-구독-sql-은-생각보다-좁다)). `WorldPlayer` 는 지금 **좌표 8 바이트를 보내려고 180 바이트를 보낸다.**

```text
WorldPlayer        (거의 안 바뀜)   name, kind, level, max_hp, max_mp, defense, entered_at
WorldPlayerPos     (자주 바뀜)      character_id, x, y, chunk        ← 22B
WorldPlayerVitals  (전투 중 바뀜)    character_id, hp, mp, alive, deaths
```

**public 위치 행의 키를 `Identity`(32B) 가 아니라 `character_id`(8B) 로 둔다.** `Identity → character_id` 매핑은 private 테이블에 남긴다. 좌표 행에서 Identity 가 과반을 차지하므로, 이 한 가지가 세로 분할 다음으로 큰 절감이다. 대가는 `move_to` 에 PK 조회 한 번 추가.

몬스터도 같은 방식이 적용된다. 다만 [`Monster`](spacetimedb/src/world.rs#L366) 는 `hp`·`alive`·`tagged_by` 를 같은 행에서 판정하므로([world.rs:1211-1215](spacetimedb/src/world.rs#L1211), [world.rs:1462](spacetimedb/src/world.rs#L1462)) 분할 기준이 플레이어보다 까다롭다.

### 6.3 AI 틱에서 곱셈을 제거한다

플레이어를 **먼저 청크로 묶고**, 몹은 자기 청크와 이웃 8칸의 사람만 본다. 틱 로컬 `HashMap` 이므로 [§2.3](#23-모듈에-메모리를-둘-수-없다) 제약을 어기지 않는다.

```rust
// 사람을 셀 → 플레이어 목록으로 한 번만 묶는다: O(N)
let mut by_cell: HashMap<u32, Vec<PlayerLite>> = ...;
// 몹은 자기 이웃 셀의 사람만 잰다
```

16 타일 셀 기준 효과:

| 분포 | 거리 계산 / 틱 | 초당 | 현재 대비 |
|---|---:|---:|---:|
| 균등 (1,000명 / 1km²) | 약 17,000 | 약 5.7만 | **약 440 배 감소** |
| 100명 집결 | 약 30,000 | 약 10만 | 약 250 배 감소 |
| 1,000명 한곳 집결 | 약 200,000 | 약 66만 | 약 38 배 감소 |

**핵심은 배수가 아니라 상한이 생긴다는 것이다.** 지금은 최악값이 곧 평균값이지만, 개선 후에는 분산될수록 싸진다.

추가로:

- **아무도 없는 청크는 건너뛴다.** 1,024 칸 중 사람이 있는 칸만 처리하면 한산한 시간대의 틱 비용이 거의 0 이 된다.
- **같은 지역 사람들의 중복 청크 조회를 없앤다** ([§5.3](#53-monster_ai-의-곱셈) 의 두 번째 낭비).
- **움직이지 않은 몹은 쓰지 않는다.** 변화 없는 `update` 는 구독자 전원에게 델타를 만든다. `regen_tick` 은 이미 이 원칙을 지키고 있다([world.rs:1621](spacetimedb/src/world.rs#L1621), [world.rs:1648](spacetimedb/src/world.rs#L1648)).

### 6.4 좌표 보고를 2Hz 로 낮춘다

쓰기 횟수와 egress 를 동시에 2.5 배 줄이는 단일 변경이다. [spacetime_world_presence.dart:26](lib/spacetime/spacetime_world_presence.dart#L26) 의 `_interval` 을 500ms 로.

주의할 것 둘:

- **원격 보간을 외삽으로 바꿔야 한다.** [`remote_player.dart`](lib/game/entities/remote_player.dart) 의 보간은 200ms 수신을 전제로 한다. 그대로 두면 목표에 일찍 도착해 멈칫한다.
- **사거리 판정이 보수적으로 바뀐다.** 서버 좌표가 최대 500ms 낡으므로, 최대 속도 14 타일/s([world.rs:167](spacetimedb/src/world.rs#L167))에서 최대 7 타일까지 어긋날 수 있다. `ATTACK_RANGE_TILES = 2.2`([world.rs:115](spacetimedb/src/world.rs#L115))가 이를 흡수하는지 확인이 필요하다.

> **이미 자연 백프레셔가 있다.** [spacetime_world_presence.dart:121](lib/spacetime/spacetime_world_presence.dart#L121) 의 `_inFlight` 가 이전 `move_to` 응답 전에는 다음 보고를 막는다. 즉 **실효 보고율 = min(5Hz, 1/RTT)** 다. 서버가 밀리면 클라이언트가 알아서 줄인다 — 다만 그것은 체감 지연으로 나타난다. 부하 시험에서는 **요청 TPS 가 아니라 실측 TPS 를 봐야 한다.**

### 6.5 이벤트는 상태와 분리하되, 함정을 피한다

연출(스킬 시전, 피격, 사망 이펙트)은 상태가 아니라 사건이다. 별도 테이블로 둔다.

```text
CombatEvent: event_id, chunk, source_id, target_id, event_type, server_ts, payload, expires_at
```

> ⚠️ **같은 reducer 안에서 삽입하고 삭제하면 클라이언트에 전달되지 않는다.** 트랜잭션의 최종 상태만 복제되기 때문이다. 반드시 남겨 두었다가 별도 scheduled reducer 로 지운다. 클라이언트는 `event_id` 로 중복을 거른다.

우리 코드의 `deaths` 카운터 방식(상태 증가로 사건 전달)은 이 함정을 아예 피하는 대안이며 **재접속·재구독에 더 강하다**(지나간 이벤트가 되살아나지 않는다). 이벤트 테이블을 도입하더라도 이 장점을 잃지 않도록 용도를 나눌 것.

### 6.6 선택 — 좌표 정밀도와 이동 의도

1~4 를 끝낸 뒤 측정으로 판단할 것들이다.

- **`f32` → `i16`** (`round(tile × 32)`, 최대 좌표 32,192 로 `i16` 안에 들어가고 양자화 오차 1/64 타일): 22B → 18B, 추가 1.22 배.
- **이동 의도 전송** (출발점 + 속도 + 시작 시각): 직선 이동에서 쓰기 횟수가 크게 준다. **서버가 판정할 때 같은 공식으로 위치를 구한다면 완전한 서버 권위다.** 다만 전투 중 방향 전환이 잦으면 이득이 사라지고, 충돌·사거리·AI 타겟팅이 전부 "시각 → 위치" 함수를 공유해야 한다.

---

## 7. 관심 영역 구독을 실제로 만드는 법

[§2.4](#24-구독-sql-은-생각보다-좁다) 때문에 `WHERE x BETWEEN ...` 같은 자연스러운 방법이 없다. 선택지는 셋이고, **결론은 ① 하나뿐이다.**

### ① 청크 번호를 클라이언트가 나열한다 — 채택

```sql
SELECT * FROM world_player_pos WHERE chunk = 529 OR chunk = 530 OR chunk = 531
  OR chunk = 561 OR chunk = 562 OR chunk = 563
  OR chunk = 593 OR chunk = 594 OR chunk = 595
```

등식 비교라 문법 안에 들고 btree 인덱스를 그대로 탄다. 서버가 클라이언트별 계산을 하지 않는다.

**청크 크기는 인원에서 역산한다.** 목표가 AOI 100 이므로:

```text
밀도 = 1,000명 / (1,000 × 1,000 타일) = 0.001 명/타일²
9C² × 0.001 = 100  →  C = 105.4

검산  C = 104 → 9 × 104² × 0.001 = 97.3 명   ✅ 채택
      C = 128 → 9 × 128² × 0.001 = 147.5 명  ❌ 목표 초과
      C =  64 → 9 ×  64² × 0.001 = 36.9 명   (여유는 크나 재구독 잦음)
```

**구현값: `SUBSCRIPTION_CHUNK_TILES = 104`.**

재구독 주기도 문제없다. 보행 3.6 타일/s([player.dart:73](lib/game/entities/player.dart#L73)) 기준 **약 29 초**, 최대 속도 14 타일/s 에서도 7.4 초다. 축 방향으로 경계를 넘으면 9 칸 중 3 칸만 교체되고(평균 약 32 행), 대각선이면 5 칸(약 54 행)이다. 무시할 수준이다.

- **AI 청크(32)와 반드시 별도 컬럼**이어야 한다. 32 는 어그로 9 타일에 맞춘 값이고([world.rs:143](spacetimedb/src/world.rs#L143)), 104 는 구독 인원에 맞춘 값이다. 목적이 다르다.
- **새 구독을 먼저 걸고 옛 것을 나중에 해제한다.** 순서를 뒤집으면 주변 엔티티가 순간 사라진다. 기존 클라이언트가 이미 쓰는 generation 패턴([spacetime_world_presence.dart:38](lib/spacetime/spacetime_world_presence.dart#L38))을 재사용할 것.
- **경계에 히스테리시스를 둔다.** 경계선에 걸쳐 서 있으면 재구독이 진동한다.

### ② RLS (`:sender`) — 지금은 채택하지 않는다

`#[client_visibility_filter]` 에 `:sender` 를 써서 서버가 거를 수 있다. 그러나 **experimental·unstable 로 명시**되어 있고 공식 문서가 Views 를 권한다. RLS 테이블과 조인할 때 구독 갱신이 나오지 않는 알려진 이슈도 있다. 그리고 **같은 구독 방언이라 거리 필터를 쓸 수 없다** — 결국 청크 등식만 가능한데, 본질적으로 사용자별 필터라 접속자 수만큼 계산된다.

→ AOI 용도로는 부적합. 나중에 **"치트 클라이언트의 전체 구독을 막는" 보안 목적**으로만 재검토한다([§10](#10-미해결--사람-판단이-필요한-것)).

### ③ Views — AOI 에는 부적합

`AnonymousViewContext` 뷰는 한 번 계산해 전원에게 공유되지만 **파라미터를 받지 못하므로**(컨텍스트만) "내 주변" 을 표현할 수 없다. 사용자별 뷰(`ViewContext`)로는 가능하지만 1,000 명이면 1,000 번 계산된다.

→ 리더보드처럼 **전원이 같은 것을 보는 데이터**에 쓴다. 우리가 이미 그렇게 쓰고 있다([leaderboard.rs:232](spacetimedb/src/leaderboard.rs#L232)).

### 그리고 ①로도 해결되지 않는 것

**청크 구독은 면적을 자를 뿐 인원을 자르지 않는다.** 한 청크에 1,000 명이 서면 1,000 행이 온다. 안전지대(50 타일, [world.rs:73](spacetimedb/src/world.rs#L73))처럼 사람이 몰리는 곳이 특히 그렇다.

→ **"가까운 100 명만 그린다" 를 클라이언트 표시 계층에서 강제해야 한다.** 이것이 AOI 100 의 두 번째 겹이다. 대역폭까지 상한을 두려면 서버 측 AOI membership 테이블이 필요하고, 그것은 사용자별 계산이라 다시 비싸진다.

---

## 8. 목표 달성 조건표

동접 1,000 · 전원 이동 · AOI 안 100 명 기준. 플레이어 위치 트래픽만 계산했다.

| 단계 | 구성 | 행 이미지/s | egress | 클라이언트당 |
|---|---|---:|---:|---:|
| 현재 | 전체 구독 · 5Hz · 180B | 10,000,000 | **약 1.8 GB/s** | 약 1.8 MB/s |
| +① AOI 104 청크 | 구독자 100 고정 | 1,000,000 | 약 180 MB/s | 약 180 KB/s |
| +② 세로 분할 (22B) | `character_id` 키 | 1,000,000 | 약 22 MB/s | 약 22 KB/s |
| +③ 보고 2Hz | | 400,000 | **약 8.8 MB/s** | 약 8.8 KB/s |
| +④ `i16` 좌표 (18B) | | 400,000 | 약 7.2 MB/s | 약 7.2 KB/s |

**누적 약 200 배 감소.** 여기에 [§6.3](#63-ai-틱에서-곱셈을-제거한다) 의 AI 개선(균등 분포 약 440 배)을 더하면 목표 구간에 들어간다.

**단, 몬스터가 남는다.** 서버가 3.33Hz 로 계속 쓰기 때문에 밀집 지역에서는 몬스터 트래픽이 플레이어보다 클 수 있다. 몬스터에도 ①②를 적용하고, 정지 몹 update 금지·거리별 AI 주기 LOD 를 함께 걸어야 한다.

### 목표는 이 조건에서 성립한다

- 구독 청크 104 타일, 3×3 AOI
- public 위치 행 22B 이하 (세로 분할 + `character_id` 키)
- 기본 보고 2Hz
- 몬스터도 전체 구독 제거 + 정지 몹 쓰기 금지
- AI 는 틱 로컬 공간 해시 (16 타일 셀)
- 사용자별 View / RLS 를 실시간 AOI 경로에 쓰지 않음
- **클라이언트 표시 상한 100 명**
- **평균 밀도 계약** — 1,000 명이 넓게 분산

마지막 두 줄이 기술이 아니라 **기획 규격**이라는 점이 중요하다.

---

## 9. 끝내 불가능한 것

최적화로 해결되지 않는다. 설계로 회피해야 한다.

1. **한 지점에 1,000 명 집결.** 관찰 관계가 `1,000 × 999 ≈ 100 만` 이 된다. 어떤 구독 설계로도 국소 N² 로 회귀한다. → 월드 보스·대규모 집회 콘텐츠를 만든다면 입장 제한, 표시 상한, 전용 프로토콜 중 하나가 필요하다.
2. **"가까운 100 명" 을 구독으로 자르는 것.** `LIMIT`·거리 정렬·산술식이 전부 없다.
3. **관찰자별 갱신 빈도 LOD.** 쓰기 1 회가 그 행의 모든 구독자에게 나간다. fast/slow 테이블을 분리해 흉내낼 수는 있지만 중복 제거가 따라온다.
4. **다중 유저 입력 배칭.** [world.rs:1694](spacetimedb/src/world.rs#L1694) 의 `require_world_player` 가 `ctx.sender()` 로만 주체를 정한다. 한 클라이언트가 남의 이동을 제출할 경로가 프로토콜에 없다. **레버는 배칭이 아니라 보고 주기다.**
5. **수평 확장.** 단일 DB = 단일 머신. 넘으면 월드 분할 + DB 간 이동을 자체 구현해야 하고, 이는 [CLAUDE.md](CLAUDE.md) 의 단일 공유 월드 원칙과 충돌한다.
6. **측정 없는 "1,000 명 가능" 단정.** 봇 부하 시험이 유일한 답이다.

---

## 10. 미해결 · 사람 판단이 필요한 것

- **"AOI 100" 이 평균인가 최악 상한인가.** 평균이면 청크 104 로 충분하고, 최악 상한이면 클라이언트 씬닝이 필수다. **제품 결정.**
- **월드 보스·집회 콘텐츠를 만들 것인가.** 만든다면 §9-1 의 대책이 선행되어야 한다.
- **월드 테이블을 계속 public 으로 둘 것인가.** [lib.rs:15-16](spacetimedb/src/lib.rs#L15) 의 머리말은 "**모든 테이블이 비공개다**" 라고 적혀 있으나, `world_player`·`monster`·`monster_kill` 은 모두 `public` 이다. 머리말이 월드 도입 이전에 쓰인 채 갱신되지 않았다. **치트 클라이언트가 `SELECT * FROM world_player` 를 그대로 걸 수 있고, 청크 구독은 이를 막지 못한다.** 막으려면 RLS(experimental) 또는 사용자별 View(N 배 계산) 중 하나를 감수해야 한다 — 대역폭이 아니라 보안 결정이다.
- **Dart SDK 2.3.1 ↔ 서버 2.7.1 버전 차이.** 구독 ownership·압축·배칭 동작이 최신 서버와 맞는지 확인되지 않았다.

---

## 11. 측정하지 않으면 알 수 없는 것

같은 1,000 명이라도 부하가 자릿수로 다르다.

| | 감당 가능한 1,000 명 | 감당 불가능한 1,000 명 |
|---|---|---|
| 분포 | 넓게 흩어짐 | 한 곳에 집결 |
| 가시 엔티티 | 각자 100 명 이하 | 각자 999 명 + 이펙트 |
| AI | 활성 지역만 | 전 지역 최고 주기 |
| 관찰 관계 | N × 100 | **N × (N−1) ≈ 100 만** |

**출시 판단 전에 자동 봇으로 확인해야 할 것:**

- 동시 WebSocket 1,000 연결의 안정성
- **실측 이동 TPS** (요청 TPS 가 아니라 — `_inFlight` 백프레셔 때문에 다르다)
- reducer p50 / p95 / p99 지연 — 합격선 예: p95 < 50ms, p99 < 100ms
- **AI 틱 벽시계 시간과 틱 밀림 여부** — 합격선 예: < 100ms, 밀림 0
- 초당 행 이미지 수와 전체·클라이언트당 egress
- 구독 전환(청크 이동) 지연과 재구독 중 화면 공백
- **집결 1,000 vs 분산 1,000** 두 시나리오 대조
- 광역 스킬 + PK 동시 발생
- 재접속·장애 복구
- 저사양 모바일이 원격 100 명 + 초당 수백 델타를 감당하는지

SpacetimeDB 의 단순 트랜잭션 벤치마크(초당 26~30 만 건대)는 참고치일 뿐이다. 계좌 이체 같은 짧은 트랜잭션과, A*·충돌·광역 스킬·대규모 구독 fan-out 이 얽힌 MMORPG 틱은 다른 작업이다.

---

## 12. 실행 계획

[§8](#8-목표-달성-조건표) 의 조건을 코드에 반영하는 순서. 근거는 `.cowork/scale-1000-aoi-100/final-report.md`.

| 순위 | 작업 | 범위 | 검증 |
|---:|---|---|---|
| 1 | `WorldPlayer`·`Monster` 에 구독용 청크 컬럼(104 타일, 현재 좌표) 추가 + 구독을 9 청크 OR 나열로 교체 | [world.rs:267](spacetimedb/src/world.rs#L267)·[366](spacetimedb/src/world.rs#L366), [cyborg_connection.dart:39](lib/spacetime/cyborg_connection.dart#L39) | 두 클라이언트를 멀리 떨어뜨려 서로의 행이 캐시에서 사라지는지 |
| 2 | `monster_ai` 를 틱 로컬 청크→플레이어 맵으로 재작성 + 정지 몹 쓰기 금지 | [world.rs:1428-1487](spacetimedb/src/world.rs#L1428) | `test/monster_authority_test.dart` + 어그로/리쉬 경계 |
| 3 | 세로 분할 `WorldPlayerPos(character_id, x, y, chunk)` | [world.rs:267-359](spacetimedb/src/world.rs#L267) + 클라이언트 재조합 | 전체 테스트 + 2 인 접속 |
| 4 | 좌표 보고 500ms + 원격 외삽 | [spacetime_world_presence.dart:26](lib/spacetime/spacetime_world_presence.dart#L26), [remote_player.dart](lib/game/entities/remote_player.dart) | 2 인 접속 육안 확인, 사거리 판정 회귀 |
| 5 | 클라이언트 표시 상한 100 명 | 렌더링 | 집결 시연 |
| 6 | `i16` 좌표 | public 위치 행 | 양자화 오차 확인 |
| 7 | 부하 시험 (§11) | 봇 | 합격선 판정 |

---

## 출처

- [Subscriptions](https://spacetimedb.com/docs/clients/subscriptions/) · [SQL Reference](https://spacetimedb.com/docs/reference/sql/) (구독/쿼리 언어 차이) · [Reducers](https://spacetimedb.com/docs/functions/reducers/) (동시 실행·전역 상태 금지) · [Views](https://spacetimedb.com/docs/functions/views/) · [Row Level Security](https://spacetimedb.com/docs/how-to/rls/) (experimental 명시) · [Performance Best Practices](https://spacetimedb.com/docs/tables/performance/) · [Schedule Tables](https://spacetimedb.com/docs/tables/schedule-tables/) · [Transactions and Atomicity](https://spacetimedb.com/docs/databases/transactions-atomicity/)
- [Moving and Colliding (Unity 튜토리얼, 50ms 서버 틱)](https://spacetimedb.com/docs/tutorials/unity/part-4/)
- [Pricing](https://spacetimedb.com/pricing) · [Maincloud](https://spacetimedb.com/maincloud) · [Benchmarks](https://spacetimedb.com/blog/benchmarking)
- [SpacetimeDB: a short technical review](https://strn.cat/w/articles/spacetime/) — 구현 관찰(서드파티, 버전 미명시)
- 델타 인코딩 확인: `spacetimedb_sdk-2.3.1/lib/src/messages/shared_types.dart:59-68`
- 4 AI 교차 분석: `.cowork/scale-1000-aoi-100/final-report.md`
