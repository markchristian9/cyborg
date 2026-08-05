<!-- cowork:claude | 2026-08-05 12:00:13 | exit=0 | 843s -->
# claude 분석 — aoi-50-50-design

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
> 생성: 2026-08-05 12:00:13 · 소요 843s · 읽기 전용 분석(작업공간 미수정)

---



## 1. 결론 요약

**"AOI 에 몬스터 50 + PC 50" 은 하나의 청크 크기로 만들 수 없다.** 이 월드의 몬스터 밀도(0.00822 기/타일²)가 플레이어 밀도(0.001 명/타일²)의 **8.2 배**여서, 같은 목표 인원 50 을 면적으로 역산하면 청크가 각각 **PC 74 타일 / 몬스터 26 타일**로 갈린다(면적비 8.2, 변 길이비 2.87). 두 축을 **별도 컬럼·별도 청크 크기**로 두는 것이 유일한 해법이다.

**몬스터 쪽은 면적으로 50 을 맞추면 안 된다.** 몬스터는 군집 배치(`cluster_center`+`scatter_around`)인데다 레벨이 중심에서의 반지름에 선형 매핑되어 **밀도가 1/r 로 변한다** — 레벨 1 구역(0.057 기/타일²)이 레벨 200 구역(0.0044)의 **13 배**다. 하나의 청크로 평균 50 을 맞춰도 실측은 대략 0~150 사이를 오간다. 몬스터의 "50" 은 청크가 아니라 **클라이언트 표시 상한**(`_maxActiveMonsters`)으로 만들어야 한다.

**9 청크는 화면 대비 압도적 과잉이지만, 그것이 잘못된 것은 아니다.** 데스크톱 기본 줌에서 화면에 실제로 보이는 그리드 면적은 **약 251 타일²**뿐이다. PC 청크 74 의 3×3(49,284 타일²)은 화면의 **196 배**다. 즉 균등 분포에서 AOI 안 50 명 중 화면에 보이는 것은 **0.25 명**이고, 대역폭의 99.5% 가 화면 밖 좌표다. 이 낭비를 줄이는 정공법은 청크 축소(→ 재구독 진동·화면 구석 누락)가 아니라 **행 크기 축소(세로 분할)와 보고 주기 하향**이다.

**부하는 최적화 이후 몬스터가 역전한다.** 현행(180B·5Hz)에서는 플레이어가 90 MB/s 로 지배적이지만, 세로 분할 + 2Hz 를 적용해 플레이어를 4.4 MB/s 로 내리면 몬스터가 **11.5~41.3 MB/s** 로 2.6~9.4 배 커진다. 몬스터에 같은 처방(청크 구독 + 세로 분할 + 정지 몹 쓰기 금지)을 함께 걸지 않으면 목표는 성립하지 않는다.

---

## 2. 근거

- `spacetimedb/src/world.rs:51` — `WORLD_PLAYABLE_TILES = 1000.0`. 걸을 수 있는 면적 1,000×1,000 = **1,000,000 타일²**. `world.rs:62` 격자 전체는 `WORLD_TILES = 1006`.
- `world.rs:79`·`87-88`·`102` — `MONSTER_MAX_LEVEL = 200`, `CLUSTER_MIN = 5`/`CLUSTER_MAX = 20`(평균 12.5), `CLUSTERS_PER_LEVEL = 3`. → 군집 600 개 × 12.5 = **약 7,500 기**(상한 `MONSTER_CAPACITY = 12,000`, `world.rs:108`).
- `world.rs:868-897` `cluster_center` — 군집 중심은 월드 중심에서 체비쇼프 반경 `inner = 50/2+12 = 37` ~ `outer = 1006/2-24 = 479` 의 **사각 링 위**에만 놓인다. 레벨→반지름은 선형(`t = (level-1)/199`), `band = 442/200 = 2.21 타일/레벨`, `wobble = ±3·band = ±6.63`.
- `world.rs:915-927` `scatter_around` — 군집 내부는 `±CLUSTER_RADIUS(9)` **정사각 19×19 = 361 타일²** 에 5~20 마리. 군집 내부 밀도 = 12.5/361 = **0.0346 기/타일²**.
- `world.rs:659`·`662`·`665-669` — `CHUNK_TILES = 32.0`, `chunk_of(x,y)` 는 `cy * CHUNKS_PER_ROW + cx`. `world.rs:414-423` `Monster.chunk` 는 **집 좌표(`home_x/home_y`) 기준**이며 `#[default(0u32)]`.
- `world.rs:152` `MONSTER_MAX_ROAM_TILES = 26.0` — 몹은 집에서 26 타일 밖으로 못 간다. `world.rs:143` `MONSTER_AGGRO_TILES = 9.0`.
- `world.rs:301-307` — 자동 마이그레이션 조건이 코드 주석으로 못박혀 있다: **"맨 끝에 있어야 하고 기본값이 필요하다."** `next_teleport_at`·`next_hurt_at`·`mp`·`defense`·`deaths`·`invulnerable_until`·`last_damaged_at` 이 전부 이 규칙으로 붙어 있다(`world.rs:306`~`358`).
- `world.rs:267-359` `WorldPlayer` 전체 — **`chunk` 문자열이 한 번도 없다.** 청크 구독의 선행 조건이 아직 없다.
- `world.rs:1451-1467` — `monster_ai` 가 플레이어 청크 3×3 을 `by_chunk` 로 조회. `world.rs:1479-1487` — 그 뒤 **몹마다 전체 플레이어 순회**(주석 `world.rs:1480` "사람 수는 적으므로 전부 재도 싸다").
- `world.rs:1078-1083`(`move_to`)·`1149-`(`teleport_to`)·`995-1021`(`enter_world`)·`1762-1777`(사망 리스폰) — **좌표가 바뀌는 네 지점**. 마지막은 좌표를 월드 중심으로 되돌리므로 청크 갱신을 빠뜨리기 쉽다.
- `lib/game/iso.dart:6`·`9`·`62-67` — `kTileWidth = 128`, `kTileHeight = 64`, `gridToScreen = ((gx-gy)*64, (gx+gy)*32)`. 이 선형변환의 야코비안 행렬식은 `|64·32 − (−64)·32| = 4096` → **그리드 1 타일² = 화면 4,096 px²**.
- `lib/game/action_rpg_game.dart:328-332` — `zoom = clamp(screenSize.y / 760, 0.55, 1.6) × _zoomScale`, `_zoomScale ∈ [0.5, 2.0]`(`:299-300`).
- `action_rpg_game.dart:186-201` — `_blockStreamMargin = 16`, **`_monsterReleaseRadius = 60`**, **`_maxActiveMonsters = 140`**.
- `action_rpg_game.dart:641-664` `_syncRemotePlayers` — **원격 플레이어에는 개수 상한도 거리 필터도 없다.** `presence.others` 전부를 `world.add` 한다. (몬스터는 `:1094` 에서 60 타일로 자르는데 사람은 안 자른다.)
- `lib/spacetime/cyborg_connection.dart:39-44` `kWorldSubscriptions` — `SELECT * FROM world_player` / `SELECT * FROM monster`, **둘 다 전체 구독**.
- `lib/spacetime/spacetime_world_presence.dart:26` `_interval = 200ms`(5Hz), `:38`·`:69`·`:77-80`·`:105` **generation 패턴**, `:121` `_inFlight` 백프레셔, `:215-231` `others` 가 전 행을 그대로 반환.
- `lib/game/entities/remote_player.dart:79-88` — 보간 계수 `dt × 9`, 12 타일 이상 벌어지면 순간이동. 주석(`:18-20`)이 **0.2 초 수신을 전제**로 한다고 명시.
- `GAME-SERVER.md:113-118`(구독 SQL 표) — `ORDER BY`/`LIMIT`/산술식 **전부 불가**. `GAME-SERVER.md:173` — 갱신은 `deletes + inserts` 두 행 이미지(SDK `shared_types.dart:59-68` 확인).

---

## 3. 상세 분석

### 3.1 AOI 를 무엇에서 역산하는가 — 이 프로젝트의 실제 절차

이 프로젝트에서 AOI 설정은 다음 5 단계로 결정된다. 순서를 바꾸면 답이 달라진다.

**① 대상 밀도를 구한다(대상별로 따로).**

```text
플레이어  ρ_p = 1,000명 / (1,000 × 1,000 타일)          = 0.001    명/타일²
          ← world.rs:51 (걸을 수 있는 면적)

몬스터    분포 면적 = (2×479)² − (2×37)² = 917,764 − 5,476 = 912,288 타일²
          ← world.rs:872-873 (inner 37 / outer 479, 사각 링)
          ρ_m = 7,500기 / 912,288                       = 0.00822  기/타일²
```

두 밀도의 비가 **8.22** 다. 이 숫자 하나가 "청크 하나로 둘 다 만족시킬 수 있는가" 의 답을 이미 결정한다.

**② 3×3 나열을 전제로 청크 변 길이를 역산한다.** 구독 SQL 에 `LIMIT`·거리 정렬·산술식이 없으므로(`GAME-SERVER.md:113-118`) 등식 OR 나열이 유일한 문법이다.

```text
9C² × ρ = 목표 인원

PC 50   :  9C² × 0.001   = 50  →  C² = 5,555.6  →  C = 74.5
          검산  C=74 → 9 × 5,476  × 0.001   = 49.3 명  ✅
                C=64 → 9 × 4,096  × 0.001   = 36.9 명
                C=80 → 9 × 6,400  × 0.001   = 57.6 명

몬스터 50:  9C² × 0.00822 = 50  →  C² = 675.9    →  C = 26.0
          검산  C=26 → 9 × 676    × 0.00822 = 50.0 기  ✅
                C=32 → 9 × 1,024  × 0.00822 = 75.8 기
                C=40 → 9 × 1,600  × 0.00822 = 118.4 기
```

> 참고: 직전 분석의 "AOI 100 → 104 타일"과 정합한다. 목표가 100 → 50 으로 절반이 되면 면적도 절반, 변은 `104/√2 = 73.5` — 여기서 나온 74.5 와 일치한다.

**③ 청크 하한을 화면에서 확인한다.** 청크는 인원에서만 역산해서는 안 된다. **3×3 의 보장 반경(플레이어가 자기 청크 모서리에 섰을 때 구독 영역 경계까지의 최소 거리) = C 타일**이고, 이 값이 화면 반폭보다 작으면 화면 구석의 엔티티가 구독 밖이 된다.

**④ 밀도의 균질성을 확인한다.** 플레이어는 이동하므로 장기적으로 균질에 가깝다. 몬스터는 아니다(§3.3).

**⑤ 인원 상한은 표시 계층에서 강제한다.** ①~④ 로 얻는 것은 *면적*이지 *인원*이 아니다.

### 3.2 화면에 실제로 보이는 범위 — 251 타일²

아이소메트릭이라 화면 사각형은 그리드 위에서 마름모가 되고, `visibleGridBounds`(`action_rpg_game.dart:1010-1040`)가 반환하는 AABB 는 실제 시야보다 2 배 넓다. **실제 면적은 야코비안으로 정확히 나온다.**

```text
gridToScreen = ((gx−gy)·64, (gx+gy)·32)          ← iso.dart:62-67
|det J| = |64·32 − (−64)·32| = 4,096 px² / 타일²

보이는 그리드 면적 = (화면 폭 × 화면 높이) / zoom² / 4,096
zoom = clamp(screenSize.y/760, 0.55, 1.6) × _zoomScale   ← action_rpg_game.dart:330-331
```

| 화면(논리px) | `_zoomScale` | zoom | 보이는 월드 px | **보이는 그리드 면적** | AABB 반폭 |
|---|---|---|---|---:|---:|
| 390×844 (폰) | 1.0 | 1.11 | 351×760 | **65 타일²** | ≈ 5.7 타일 |
| 1280×720 | 1.0 | 0.947 | 1352×760 | **251 타일²** | ≈ 11.2 타일 |
| 1920×1080 | 1.0 | 1.42 | 1352×760 | **251 타일²** | ≈ 11.2 타일 |
| 1920×1080 | 0.5 (최대 축소) | 0.711 | 2703×1519 | **1,003 타일²** | ≈ 22.4 타일 |
| 2560×1440 | 0.5 | 0.80 | 3200×1800 | **1,406 타일²** | ≈ 26.5 타일 |

**판정 — 9 청크는 면적으로는 과잉, 보장 반경으로는 필요.**

| 구성 | 3×3 면적 | 화면(251) 대비 | 3×3 보장 반경 | 최대축소 반폭 22.4 커버? |
|---|---:|---:|---:|:---:|
| 현재 AI 청크 32 | 9,216 타일² | 36.7× | 32 타일 | ✅ |
| 몬스터 50 역산 26 | 6,084 타일² | 24.2× | 26 타일 | ⚠️ 여유 3.6 타일 |
| **PC 50 역산 74** | 49,284 타일² | **196×** | 74 타일 | ✅ |
| 직전 분석의 104 | 97,344 타일² | 388× | 104 타일 | ✅ |

즉 **면적 기준으로는 196~388 배 과잉이 맞다.** 균등 분포에서 AOI 안 50 명 중 화면에 들어오는 것은 `251 × 0.001 = 0.25 명`이다. 그렇다고 청크를 화면 크기(≈16 타일 변)로 줄이면 ⓐ 보장 반경이 최대축소 반폭 22.4 에 미달해 화면 구석의 사람이 사라지고 ⓑ 재구독 주기가 `16/3.6 = 4.4초`(최대 속도에서 1.1초)로 떨어져 진동한다. **과잉을 줄이는 올바른 레버는 청크 축소가 아니라 행 크기(180B → 22B)와 보고 주기(5Hz → 2Hz)다.**

한편 이 계산은 요구사항 해석 자체를 가른다. **"한 화면에 PC 50 + 몬스터 50"으로 읽으면 밀도 0.199/타일² 이 필요하고, 이는 플레이어 균등 밀도의 199 배·몬스터 군집 내부 밀도의 5.8 배다.** 현재 배치로는 집결 상황에서만 발생한다. 아래는 "AOI = 구독 범위" 해석으로 진행한다(§6 에 이 해석 문제를 남긴다).

### 3.3 군집 분포가 청크 설계를 무너뜨리는 방식

`cluster_center`(`world.rs:868-897`)는 레벨을 반지름에 **선형** 매핑한다. 레벨당 반지름 증가 `band = (479−37)/200 = 2.21 타일`, 레벨마다 3 군집. 그러면 반지름 r 의 얇은 링(두께 dr)에 들어가는 군집 수는 `3 × (dr/2.21) = 1.357·dr` 이고, 그 링의 면적은 사각 링이므로 `8r·dr`. 따라서

```text
군집 밀도(r) = 1.357 / (8r)              [군집/타일²]
몬스터 밀도(r) = 12.5 × 1.357 / (8r) = 2.12 / r   [기/타일²]
```

| 반지름 r | 해당 레벨 | 몬스터 밀도 | 그 자리에서 50 기를 담는 청크 |
|---:|---:|---:|---:|
| 37 | 1 | 0.0573 | **9.9 타일** |
| 100 | 약 29 | 0.0212 | 16.2 타일 |
| 250 | 약 97 | 0.00848 | 25.6 타일 |
| 479 | 200 | 0.00443 | 35.5 타일 |

**중심부가 바깥의 13 배 조밀하다.** 전역 평균(0.00822)으로 역산한 26 타일은 r≈250 의 중간 지대에서만 맞고, 저레벨 구역에서는 6.7 배(≈335 기), 최외곽에서는 0.54 배(≈27 기)가 된다.

여기에 이산성이 더해진다. 26 타일 3×3(6,084 타일²)에 들어오는 **평균 군집 수는 4.0 개**이고 군집당 마릿수는 5~20 균등이다. 포아송 근사로 총합의 표준편차는

```text
Var = λ·E[X²] = 4 × (12.5² + 4.33²) = 4 × 174.0 = 696   →  σ ≈ 26.4
```

즉 평균 50 인데 **1σ 구간이 24~76, 군집이 하나도 안 걸리는 확률(e⁻⁴)이 1.8%** 다. 몬스터에 대해 "면적으로 50 을 자른다"는 문장은 이 월드에서 물리적으로 성립하지 않는다.

### 3.4 집 좌표 청크의 보장 반경 — 직전 분석의 정정

직전 분석(`final-report.md:160`)은 "`MONSTER_MAX_ROAM_TILES = 26` < 청크 32 이므로 현재 9 청크 검색은 안전하다"고 판정했다. **이 판정은 부정확하다.**

```text
플레이어가 자기 청크 모서리에 섰을 때, 3×3 영역 경계까지의 최소 거리 = 32 타일
그 경계 근처(32 타일)에 서 있는 몹의 집은 최대 26 타일 더 밖에 있을 수 있다
→ 집 청크로 3×3 을 조회할 때 확실히 잡히는 것은 반경 32 − 26 = 6 타일 이내의 몹뿐
```

**보장 반경은 32 가 아니라 6 타일이다.** 어그로 9 타일(`world.rs:143`)보다 작으므로 `monster_ai` 는 6~9 타일 구간의 몹을 드물게 놓칠 수 있고(몹이 집에서 크게 벗어난 추격·리쉬 상태에서만 발생), 화면 반폭 11.2~22.4 타일과 비교하면 **구독용으로는 전혀 못 쓴다.** 몬스터 구독 청크는 반드시 **현재 좌표 기준 별도 컬럼**이어야 한다.

### 3.5 초당 전송량 — 몬스터가 최종 병목

전제: N=1,000, 갱신은 `deletes+inserts` 2 행(`GAME-SERVER.md:173`), PC 청크 74(자기 행의 구독자 ≈ 50), 몬스터 청크 32(자기 행의 구독자 = 9,216 × 0.001 ≈ **9.2 명**).

**플레이어 — 클라이언트가 보고한다(비대칭의 한쪽).**

```text
쓰기/s      = N × f
행 이미지/s = N × f × S_p × 2      (S_p = 50)

5Hz : 1,000 × 5 × 50 × 2 = 500,000 행/s
2Hz : 1,000 × 2 × 50 × 2 = 200,000 행/s
```

**몬스터 — 서버가 3.33Hz 로 쓴다(비대칭의 반대쪽).** 쓰기가 나는 것은 어그로/귀가 중인 몹뿐이다(`world.rs:1508`·`1537`; `:1518-1520` 에서 어그로 밖이면 `continue`).

```text
움직이는 몹 수 = 1,000명 × 어그로 원(π·9² = 254 타일²) × 밀도
  분산 시(전역 평균 0.00822):  254,000 × 0.00822 = 2,088 기
  군집 안(0.0346)     :  254,000 × 0.0346  = 8,788 → 전체 7,500 기로 상한

행 이미지/s = 움직이는 몹 × 3.33 × S_m × 2      (S_m = 9.2)
  분산 : 2,088 × 3.33 × 9.2 × 2 = 127,900 행/s
  집중 : 7,500 × 3.33 × 9.2 × 2 = 459,400 행/s
```

| 구성 | 플레이어 행/s | 플레이어 바이트/s | 몬스터 행/s | 몬스터 바이트/s | **더 큰 쪽** |
|---|---:|---:|---:|---:|---|
| 현행 전체 구독·5Hz·180B/90B | 10,000,000 | 1.8 GB/s | 13,900,000 | 1.25 GB/s | 플레이어 |
| +청크 구독 (74 / 32), 5Hz | 500,000 | 90 MB/s | 127,900 | 11.5 MB/s | **플레이어 7.8×** |
| +2Hz | 200,000 | 36 MB/s | 127,900 | 11.5 MB/s | **플레이어 3.1×** |
| +플레이어만 세로분할 22B | 200,000 | **4.4 MB/s** | 127,900 | **11.5 MB/s** | **몬스터 2.6×** |
| +몬스터도 세로분할 20B | 200,000 | 4.4 MB/s | 127,900 | 2.6 MB/s | 플레이어 1.7× |
| 위 + 사람이 몰린 최악 | 200,000 | 4.4 MB/s | 459,400 | 9.2 MB/s | **몬스터 2.1×** |

**답: 최적화 전에는 플레이어, 최적화 후에는 몬스터가 더 큰 부하다.** 그리고 몬스터는 클라이언트가 보고 주기를 조절할 수 없는 축이다 — `_inFlight` 백프레셔(`spacetime_world_presence.dart:121`)는 플레이어 보고에만 걸린다. 몬스터 쪽 레버는 ⓐ 세로 분할 ⓑ 정지 몹 쓰기 금지 ⓒ 거리별 AI 주기 LOD 셋뿐이다.

초기 스냅샷도 함께 개선된다. 전체 구독 시 `7,500 × 90B = 675 KB × 접속자`(`GAME-SERVER.md:211`)가 청크 32 3×3 에서 `75.8 × 90B = 6.8 KB` 로 **99 배** 준다. PC 는 `49.3 × 180B = 8.9 KB`.

---

## 4. 리스크 · 함정

- **자동 마이그레이션은 되돌릴 수 없다.** `world.rs:301-307` 이 요구하는 두 조건(맨 끝 + 기본값)을 어기면 이미 배포된 `world_player`·`monster` 의 기존 행을 읽지 못한다. 특히 **기본값 `0` 은 "청크 0 = 월드 좌상단"** 을 뜻하므로, 마이그레이션 직후 재계산 전까지 모든 기존 행이 좌상단 청크에 몰려 보인다. 몬스터는 `rebuild_monsters`(`world.rs:816`) 또는 `monster_tick` 리스폰(`world.rs:1674`)이 지날 때 제 값을 얻지만, `world_player` 는 첫 `move_to` 전까지 잘못된 청크에 남는다.
- **좌표가 바뀌는 지점이 네 곳인데 하나가 눈에 안 띈다.** `move_to`(`world.rs:1078`)·`teleport_to`(`world.rs:1149`)·`enter_world`(`world.rs:995`)는 명백하지만, **`apply_damage_to_player` 의 사망 리스폰(`world.rs:1762-1777`)이 좌표를 월드 중심으로 되돌린다.** 여기서 청크를 갱신하지 않으면 죽은 사람이 안전지대에 서 있는데 구독상으로는 죽기 전 사냥터 청크에 남아, **본인 화면에서 주변이 통째로 비고 남들 화면에서는 유령이 사냥터에 남는다.**
- **몬스터 구독 청크를 집 좌표(`Monster.chunk`)로 재사용하면 보장 반경이 6 타일이다**(§3.4). 화면 반폭 11.2 타일보다 작아 **화면 구석의 몹이 그냥 안 보인다.** 반드시 현재 좌표 기준 새 컬럼을 써야 한다.
- **원격 플레이어에 표시 상한이 없다**(`action_rpg_game.dart:641-664`). 몬스터는 60 타일·140 기로 자르는데(`:198`·`:201`·`:1094`) 사람은 안 자른다. 안전지대(50×50 = 2,500 타일², `world.rs:73`)는 PC 청크 74 의 3×3 안에 통째로 들어가므로, **거기 300 명이 모이면 300 개의 `RemotePlayerEntity` 가 그대로 `world.add` 된다.** AOI 청크를 도입해도 이 경로는 그대로다.
- **2Hz 로 낮추면 원격 보간이 깨진다.** `remote_player.dart:79-88` 의 `dt × 9` 는 200ms 수신 전제이며 주석에 그렇게 적혀 있다(`:18-20`). 500ms 로 늦추면 약 110ms 만에 목표에 도달해 나머지 390ms 를 멈춰 선다 — 걷다 서다를 반복한다. 외삽으로 바꾸거나 계수를 `dt × 3.6` 수준으로 내려야 한다.
- **2Hz 는 사거리 판정을 흔든다.** `ATTACK_RANGE_TILES = 2.2`(`world.rs:115`)인데 `MAX_MOVE_SPEED = 14`(`world.rs:167`)에서 500ms 는 **최대 7 타일** 오차다. 사거리의 3.2 배다. PK(`attack_player`)에서 특히 드러난다.
- **구독 전환 공백은 화면에서 "사람이 사라졌다 나타남" 으로 보인다.** `spacetime_world_presence.dart:73-85` 는 `_querySetId` 를 **하나만** 들고 있어 "새 것 먼저, 옛 것 나중" 을 표현할 수 없다. 두 개를 잠시 공존시키는 구조로 바꿔야 한다.
- **`monster_ai` 의 곱셈은 이 변경으로 개선되지 않는다.** `world.rs:1479-1487` 은 구독과 무관한 서버 내부 루프다. 청크 구독만 넣고 AI 를 그대로 두면 네트워크는 200 배 줄어도 틱 벽시계가 그대로여서 `move_to` 응답이 밀리고, `_inFlight` 백프레셔가 실효 보고율을 떨어뜨려 **"최적화했는데 더 끊긴다"** 로 나타난다.
- **월드 테이블이 public 이라 구독 축소는 보안 대책이 아니다**(`GAME-SERVER.md:432`). 치트 클라이언트는 여전히 `SELECT * FROM world_player` 를 걸 수 있다.

---

## 5. 권고안

| 순위 | 권고 | 범위 | 근거 | 리스크 |
|---|---|---|---|---|
| 1 | **`WorldPlayer` 에 `sub_chunk: u32`(74 타일, 현재 좌표) 를 맨 끝·기본값 0 으로 추가** + `by_sub_chunk` btree 인덱스 | `world.rs:358` 뒤, 테이블 매크로 `:267` | §3.1 역산 74.5, `world.rs:301-307` 마이그레이션 조건 | 기본값 0 = 좌상단 청크. 첫 `move_to` 전까지 오배치 |
| 2 | **`Monster` 에 `pos_chunk: u32`(32 타일, 현재 좌표) 를 맨 끝·기본값 0 으로 추가** + `by_pos_chunk` 인덱스. 기존 `chunk`(집 좌표)는 그대로 둔다 | `world.rs:423` 뒤, 매크로 `:366-376` | §3.4 보장 반경 6 타일 → 32 타일 | 몹이 청크 경계를 넘을 때 인덱스 재기입. 몹은 집 ±26 타일이라 빈도는 낮다 |
| 3 | **좌표를 쓰는 네 지점 전부에서 청크를 함께 갱신** — `move_to`(`world.rs:1078`)·`teleport_to`(`:1149`)·`enter_world`(`:995`)·**사망 리스폰(`:1762-1777`)**, 몹은 `monster_ai`(`:1508`·`:1537`)·`monster_tick`(`:1674`) | 리듀서 6 곳 | §4 첫째·둘째 함정 | 하나라도 빠뜨리면 유령 행이 남는다. 회귀 테스트 필수 |
| 4 | **구독을 9 청크 OR 나열로 교체** — `kWorldSubscriptions` 를 상수에서 `worldSubscriptionsFor(cx, cy)` 함수로 | `cyborg_connection.dart:39-44` | `GAME-SERVER.md:113-118`(등식만 가능) | 잘못된 청크 번호를 넣으면 조용히 빈 화면 |
| 5 | **재구독을 히스테리시스 + 겹침 전환으로** — `_querySetId` 를 2 개 슬롯으로, generation 패턴 재사용 | `spacetime_world_presence.dart:33-38`·`73-85` | §4 "구독 전환 공백" | 두 구독이 겹치는 동안 일시적으로 행이 2 배 |
| 6 | **표시 상한을 실제로 건다** — 원격 플레이어 거리순 50 명(현재 상한 없음), `_maxActiveMonsters` 140 → 50, `_monsterReleaseRadius` 60 → 화면 기준 | `action_rpg_game.dart:641-664`·`:198`·`:201` | §3.2, §4 "표시 상한 없음" | "전원 보임" 기대와 충돌 — 제품 결정 |
| 7 | **몬스터 정지 시 쓰기 금지** — `monster_ai` 에서 이동량이 유의미할 때만 `update` | `world.rs:1508`·`1537` | §3.5 몬스터가 최종 병목 | 미세 이동이 끊겨 보일 수 있음 |
| 8 | **세로 분할** — `WorldPlayerPos(character_id, x, y, sub_chunk)` 22B, `MonsterPos(id, x, y, pos_chunk)` 20B | `world.rs:267-359`·`366-424` + 클라 재조합 | §3.5 표 4~5 행 | 서버·클라 동시 변경, 파급 최대. 1~7 이후에 |
| 9 | **보고 2Hz + 원격 외삽 + 사거리 재검토** | `spacetime_world_presence.dart:26`, `remote_player.dart:79-88`, `world.rs:115` | §3.5, §4 | 최대 7 타일 좌표 오차 |
| 10 | **`monster_ai` 곱셈 제거**(틱 로컬 청크→플레이어 맵) | `world.rs:1428-1487` | §4 마지막 함정 | 어그로/리쉬 경계 회귀 |

### 5.1 서버 스키마 — 자동 마이그레이션 조건을 지킨 형태

`world.rs` 상수 영역(`:659` 부근)에 구독용 청크를 **AI 청크와 별개로** 추가한다.

```rust
/// 플레이어 구독용 청크 한 변(타일).
///
/// AI 청크(CHUNK_TILES = 32)와 목적이 다르다. 32 는 어그로 9 타일에 맞춘 값이고,
/// 이 값은 **AOI 안 인원 50 명**에서 역산한 값이다.
///   9C² × (1,000명 / 1,000,000타일²) = 50  →  C = 74.5
const PLAYER_SUB_CHUNK_TILES: f32 = 74.0;
const PLAYER_SUB_CHUNKS_PER_ROW: u32 = (WORLD_TILES / PLAYER_SUB_CHUNK_TILES) as u32 + 1; // 14

/// 몬스터 구독용 청크 한 변(타일).
///
/// 인원이 아니라 **화면 보장 반경**에서 정한다. 몬스터 밀도는 중심에서의 거리에
/// 따라 13 배까지 변해(레벨 1 구역 0.057 → 레벨 200 구역 0.0044 기/타일²)
/// 면적으로 인원을 자를 수 없다. 마릿수 상한은 클라이언트 표시 계층이 맡는다.
/// 32 이면 3×3 의 보장 반경이 32 타일로, 최대 축소 화면 반폭(22.4)을 덮는다.
const MONSTER_SUB_CHUNK_TILES: f32 = CHUNK_TILES; // 32.0
const MONSTER_SUB_CHUNKS_PER_ROW: u32 = CHUNKS_PER_ROW; // 32

pub fn player_sub_chunk_of(x: f32, y: f32) -> u32 {
    let cx = (x / PLAYER_SUB_CHUNK_TILES).max(0.0) as u32;
    let cy = (y / PLAYER_SUB_CHUNK_TILES).max(0.0) as u32;
    cy * PLAYER_SUB_CHUNKS_PER_ROW + cx
}
```

`WorldPlayer`(`world.rs:267`) — 매크로에 인덱스를 더하고, 컬럼은 **`last_damaged_at`(`:358`) 뒤 맨 끝**에 둔다.

```rust
#[spacetimedb::table(
    accessor = world_player,
    public,
    index(accessor = by_sub_chunk, btree(columns = [sub_chunk]))
)]
pub struct WorldPlayer {
    // … 기존 컬럼 그대로 (identity … last_damaged_at) …

    /// 구독용 공간 청크. `player_sub_chunk_of(grid_x, grid_y)` 로 만든다.
    ///
    /// **현재 좌표로 정한다.** 구독은 "지금 화면에 보이는 위치" 를 기준으로
    /// 해야 한다. 몹의 `chunk`(집 좌표)와 목적이 다르다.
    ///
    /// 맨 끝에 있고 기본값이 있어야 한다 — `next_teleport_at` 과 같은 이유
    /// (world.rs:301-307). 기본값 0 은 좌상단 청크라 실제 위치와 어긋나지만,
    /// 다음 `move_to` 한 번이면 제 값을 얻는다.
    #[default(0u32)]
    pub sub_chunk: u32,
}
```

`Monster`(`world.rs:366`) — `chunk`(집 좌표, `:423`) **뒤 맨 끝**에.

```rust
#[spacetimedb::table(
    accessor = monster,
    public,
    index(accessor = by_alive_died, btree(columns = [alive, died_at])),
    index(accessor = by_chunk,      btree(columns = [chunk])),      // AI 후보 수집(집 좌표)
    index(accessor = by_pos_chunk,  btree(columns = [pos_chunk]))   // 구독(현재 좌표)
)]
pub struct Monster {
    // … 기존 컬럼 … pub chunk: u32,

    /// 구독용 청크. `chunk_of(grid_x, grid_y)` — **현재 좌표** 기준이다.
    ///
    /// `chunk`(집 좌표)로 구독하면 보장 반경이 32 − MONSTER_MAX_ROAM_TILES(26)
    /// = 6 타일밖에 안 되어 화면 구석의 몹이 오지 않는다. 목적이 다르므로
    /// 컬럼을 나눈다.
    #[default(0u32)]
    pub pos_chunk: u32,
}
```

### 5.2 리듀서 — 좌표를 쓰는 곳마다

```rust
// world.rs:1078  move_to
ctx.db.world_player().identity().update(WorldPlayer {
    grid_x: next_x,
    grid_y: next_y,
    sub_chunk: player_sub_chunk_of(next_x, next_y),   // 추가
    last_move_at: ctx.timestamp,
    ..me
});

// world.rs:1149  teleport_to — grid_x/grid_y 와 함께 sub_chunk 를 넣는다
// world.rs:1001  enter_world — WorldPlayer 리터럴에 sub_chunk: player_sub_chunk_of(spawn_x, spawn_y)

// world.rs:1762-1777  apply_damage_to_player 의 사망 리스폰 — 놓치기 가장 쉬운 곳
let (cx, cy) = world_center();
WorldPlayer {
    hp: victim.max_hp,
    grid_x: cx,
    grid_y: cy,
    sub_chunk: player_sub_chunk_of(cx, cy),           // 추가 — 없으면 유령이 사냥터에 남는다
    ..victim
}

// world.rs:1508 / 1537  monster_ai 의 두 update
ctx.db.monster().id().update(Monster {
    grid_x: nx,
    grid_y: ny,
    pos_chunk: chunk_of(nx, ny),                      // 추가
    ..monster
});

// world.rs:1674  monster_tick 리스폰 — 집으로 되돌아가므로 함께
pos_chunk: chunk_of(monster.home_x, monster.home_y),
```

`bootstrap`(`world.rs:729-745`)의 `insert` 에도 `pos_chunk: chunk_of(x, y)` 를 넣는다(`chunk` 와 같은 값에서 출발).

**정지 몹 쓰기 금지**(권고 7) — `world.rs:1530-1543` 의 접근 분기에서:

```rust
let (nx, ny) = step_toward(monster.grid_x, monster.grid_y, player.grid_x, player.grid_y, step);
// 변화 없는 update 는 구독자 전원에게 델타를 만든다. regen_tick 이 이미 지키는 원칙
// (world.rs:1621·1648)을 여기에도 적용한다.
if dist_sq(nx, ny, monster.grid_x, monster.grid_y) > 0.0001 {
    ctx.db.monster().id().update(Monster { grid_x: nx, grid_y: ny, pos_chunk: chunk_of(nx, ny), ..monster });
    moved += 1;
}
```

### 5.3 클라이언트 구독 관리

`cyborg_connection.dart:39-44` 를 상수에서 함수로 바꾼다.

```dart
/// 플레이어 구독용 청크 한 변(타일). 서버 `PLAYER_SUB_CHUNK_TILES` 와 같아야 한다.
const int kPlayerSubChunkTiles = 74;
const int kPlayerSubChunksPerRow = 14;   // (1006 / 74) + 1

/// 몬스터 구독용 청크. 서버 `MONSTER_SUB_CHUNK_TILES`(= CHUNK_TILES) 와 같다.
const int kMonsterSubChunkTiles = 32;
const int kMonsterSubChunksPerRow = 32;

/// 월드에 들어가 있는 동안 거는 구독.
///
/// **면적만 자른다.** 구독 SQL 에는 LIMIT 도 거리 정렬도 없으므로
/// "가까운 50 명" 은 여기서 표현할 수 없다 — 인원 상한은 표시 계층이 맡는다.
List<String> worldSubscriptionsFor(int tileX, int tileY) {
  String ors(int cx, int cy, int perRow, int span, String table, String column) {
    final keys = <int>[];
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        final nx = cx + dx, ny = cy + dy;
        if (nx < 0 || ny < 0 || nx >= perRow || ny >= perRow) continue;
        keys.add(ny * perRow + nx);
      }
    }
    return 'SELECT * FROM $table WHERE ${keys.map((k) => '$column = $k').join(' OR ')}';
  }

  return [
    ors(tileX ~/ kPlayerSubChunkTiles, tileY ~/ kPlayerSubChunkTiles,
        kPlayerSubChunksPerRow, 3, 'world_player', 'sub_chunk'),
    ors(tileX ~/ kMonsterSubChunkTiles, tileY ~/ kMonsterSubChunkTiles,
        kMonsterSubChunksPerRow, 3, 'monster', 'pos_chunk'),
  ];
}
```

`SpacetimeWorldPresence`(`spacetime_world_presence.dart`) — 기존 `_generation` 패턴(`:38`·`:77-80`)은 **그대로 재사용할 수 있다.** 바꿀 것은 `_querySetId` 를 단일 슬롯에서 겹침 전환용 2 슬롯으로 만드는 것뿐이다.

```dart
  /// 지금 구독의 기준 청크. 실제 좌표가 아니라 **구독을 건 시점의** 청크다.
  int? _subCx, _subCy;
  int? _querySetId;          // 현재 유효한 구독
  bool _switching = false;

  /// 경계 히스테리시스(타일).
  ///
  /// 경계선 위를 왕복하면 재구독이 진동한다. 새 청크에 이만큼 들어간 뒤에야
  /// 전환한다 — 보행 3.6 타일/s 에서 최소 2.2 초, 최대 속도 14 타일/s 에서도
  /// 0.57 초 간격이 보장된다.
  static const double _chunkHysteresis = 8.0;

  /// 재구독 최소 간격. 대시·넉백으로 경계를 스치는 경우까지 흡수한다.
  static const Duration _resubCooldown = Duration(milliseconds: 1500);
  DateTime? _lastResubAt;

  Future<void> _maybeResubscribe(Vector2 grid, {bool force = false}) async {
    if (!_entered || _switching) return;
    final cx = grid.x ~/ kPlayerSubChunkTiles;
    final cy = grid.y ~/ kPlayerSubChunkTiles;
    if (!force && cx == _subCx && cy == _subCy) return;

    if (!force) {
      // 새 청크 안쪽으로 히스테리시스만큼 들어왔는가.
      final localX = grid.x - cx * kPlayerSubChunkTiles;
      final localY = grid.y - cy * kPlayerSubChunkTiles;
      final inset = math.min(
        math.min(localX, kPlayerSubChunkTiles - localX),
        math.min(localY, kPlayerSubChunkTiles - localY),
      );
      if (inset < _chunkHysteresis) return;

      final last = _lastResubAt;
      if (last != null && DateTime.now().difference(last) < _resubCooldown) return;
    }

    final generation = _generation;      // 기존 패턴 그대로
    _switching = true;
    final old = _querySetId;
    try {
      // **새 것을 먼저 건다.** 순서를 뒤집으면 주변 엔티티가 한 박자 사라진다.
      final id = await _client.subscriptions
          .subscribe(worldSubscriptionsFor(grid.x.toInt(), grid.y.toInt()));
      if (generation != _generation) {   // 그 사이 월드를 떠났다
        _client.subscriptions.unsubscribe(id);
        return;
      }
      _querySetId = id;
      _subCx = cx;
      _subCy = cy;
      _lastResubAt = DateTime.now();
      if (old != null) _client.subscriptions.unsubscribe(old);   // 옛 것은 나중에
    } finally {
      _switching = false;
    }
  }
```

`report`(`:120-133`)의 끝에서 `_maybeResubscribe(grid)` 를 부르고, **텔레포트·사망 리스폰 직후에는 `force: true`** 로 부른다(월드를 가로지르는 이동이라 히스테리시스가 의미 없다 — `action_rpg_game.dart:1618-1624` 가 카메라·스트리밍을 즉시 맞추는 것과 같은 이유).

재구독 1 회의 실제 비용:

```text
PC   축 방향 경계 통과 → 9칸 중 3칸 교체 = 3 × 74² × 0.001 = 16.4 명 in/out
     대각선            → 5칸 교체        = 27.4 명
     통과 간격: 보행 74/3.6 = 20.6 초 · 최대 속도 74/14 = 5.3 초
몬스터 축 3칸 = 3 × 32² × 0.00822 = 25.2 기 · 간격 8.9 초(보행) / 2.3 초(최대)
```

### 5.4 렌더링 상한 — "50" 을 실제로 보장하는 유일한 지점

```dart
// action_rpg_game.dart:641  _syncRemotePlayers — 지금은 상한도 거리 필터도 없다.
/// 동시에 그리는 다른 요원의 상한.
///
/// 구독은 면적만 자른다(청크 74 의 3×3 = 49,284 타일²). 안전지대
/// (50×50, world.rs:73)는 그 안에 통째로 들어가므로, 사람이 몰리면 수백 행이
/// 온다. **"가까운 50 명" 은 여기서만 만들어진다.**
static const int _maxRemotePlayers = 50;

void _syncRemotePlayers() {
  final all = presence.others.toList()
    ..sort((a, b) => (a.grid - player.grid).length2
        .compareTo((b.grid - player.grid).length2));
  final visible = all.length > _maxRemotePlayers
      ? all.sublist(0, _maxRemotePlayers)
      : all;
  // … 이하 기존 로직(seen/applySnapshot/removeWhere)에 visible 을 쓴다 …
}
```

몬스터는 이미 상한이 있으므로 값만 조인다(`action_rpg_game.dart:198`·`201`).

```dart
/// 60 → 화면 기준. 최대 축소 시 화면 AABB 반폭이 약 22.4 타일이므로
/// 그보다 조금 넉넉한 값이면 충분하다. 60 은 화면의 7 배 면적을 그리고 있었다.
static const double _monsterReleaseRadius = 28;

/// 140 → 50. 기획 규격("AOI 안 몬스터 50")을 여기서 강제한다.
static const int _maxActiveMonsters = 50;
```

> ⚠️ `_maxActiveMonsters` 는 현재 **거리 정렬 없이 선착순으로 자른다**(`:1110` 의 `continue`). 50 으로 조이면 "가까운 50 기" 가 아니라 "먼저 순회된 50 기" 가 되어 눈앞의 몹이 안 그려질 수 있다. 상한을 내리는 것과 **거리순 정렬을 넣는 것은 한 묶음**이다.

---

## 6. 불확실 · 미확인

- **"AOI 에 50+50 을 동시에 보여준다" 의 해석이 확정되지 않았다.** ⓐ *구독 범위 안에 50+50* 이면 본 보고서 그대로(청크 74/32)다. ⓑ *한 화면에 50+50 이 보인다* 면 화면 251 타일²에 밀도 0.199/타일² 가 필요하고, 이는 플레이어 균등 밀도의 199 배·몬스터 군집 내부 밀도의 5.8 배다 — **청크 설계가 아니라 월드 배치 밀도(`CLUSTER_MIN/MAX`, `CLUSTERS_PER_LEVEL`, 동접 목표)를 바꿔야 하는 문제**가 된다. 사람이 정해야 한다.
- **동접 1,000 이 이번에도 전제인지 미확인.** PC 청크 74 는 `ρ_p = 1,000/1,000,000` 에서 나온 값이라 동접이 500 이면 105 타일, 2,000 이면 52 타일이 된다. 목표 동접이 바뀌면 청크를 다시 역산해야 한다.
- **행 크기 180B / 90B / 22B / 20B 는 전부 BSATN 필드 합계 추정치다**(`GAME-SERVER.md:187` 이 스스로 추정이라 적었다). 실측하지 않았고, 압축·배칭 적용 후의 wire 바이트는 다르다. 자릿수는 바뀌지 않지만 절대값은 믿을 수 없다.
- **SpacetimeDB 2.7 에서 이미 배포된 테이블에 btree 인덱스를 추가하는 것이 자동 마이그레이션으로 처리되는지 확인하지 못했다.** `world.rs:301-307` 이 명시하는 것은 *컬럼* 조건뿐이다. 인덱스 추가가 수동 마이그레이션을 요구하면 배포 절차가 달라진다. **`[추측]`** — 배포 전에 로컬 인스턴스에서 반드시 확인해야 한다.
- **군집 밀도 계산은 `ring_direction`(`world.rs:904-912`)이 정사각 둘레라는 점을 반영했으나, `wobble ±6.63 타일`(`:879`)로 인접 ±3 레벨이 반지름 방향으로 겹치는 효과는 근사로만 다뤘다.** 실제 밀도 편차는 계산값(13 배)보다 완만할 수 있다. 확정하려면 배포된 DB 에서 `pos_chunk` 별 `COUNT` 를 실제로 뽑아야 한다.
- **어그로 원을 `π·9² = 254 타일²` 로 계산했으나, `monster_ai` 는 안전지대 안의 사람을 건너뛴다**(`world.rs:1524-1526`). 안전지대에 사람이 몰리는 시간대에는 움직이는 몹 수가 계산보다 적다. 반대로 사냥터에 몰리면 계산보다 많다.
- **`_monsterReleaseRadius` 60 → 28 이 자동 사냥·파티 추적의 다른 반경과 충돌하는지 확인하지 못했다.** `autoHunt` 의 탐색 반경과 `partyFollow` 가 60 타일 안의 몹/사람 존재를 전제하고 있다면 회귀가 난다. 값을 바꾸기 전에 `lib/game/systems/auto_hunt.dart`·`party_follow.dart` 를 열어야 한다.
- **`_maxActiveMonsters` 를 50 으로 내렸을 때 저레벨 구역(밀도 0.057)에서 무슨 일이 나는지 실측이 없다.** 그 구역은 청크 32 3×3 에 평균 525 기가 있어 90% 가 안 그려진다. "사냥터가 텅 비어 보인다" 로 나타날 수 있다.
- **직전 분석의 권고 3(세로 분할)·10(`monster_ai` 재작성)은 본 보고서에서 순위만 조정했을 뿐 새로 검증하지 않았다.** 그 두 건의 근거는 `.cowork/scale-1000-aoi-100/final-report.md` 에 있다.
- **부하 시험이 없다.** `GAME-SERVER.md:448-459` 의 항목 중 하나도 실행된 기록을 찾지 못했다. 본 보고서의 모든 수치는 계산이며 측정이 아니다.
