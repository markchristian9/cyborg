<!-- cowork:kimi | 2026-08-04 23:12:42 | exit=0 | 789s -->
# kimi 분석 — server-authority

> 요청: 서버 권위 판정을 하도록 해 주세요. 서버 권위 이동, 서버 권이 이벤트, 사망, HP/MP 감소/회복, 스킬, 등등 서버가 판정을 하고 클라에서는 렌더링만 하도록 해 주세요.

참고: 형제 게임 라리엔(~/apps/game/laryen, 읽기 전용 참고만 가능)의 서버 권위 이동 관련 코드/로직을 참고해 주세요. 라리엔은 Go UDP Zone Server 로 30Hz sim tick + 10~15Hz 스냅샷 브로드캐스트 + 클라 예측/서버 reconcile 구조입니다. 다만 Cyborg 는 SpacetimeDB(reducer + 구독 + scheduled reducer) 백엔드이므로 그 차이를 감안한 설계를 제시해 주세요.
> 생성: 2026-08-04 23:12:42 · 소요 789s · 읽기 전용 분석(작업공간 미수정)

---

• 작업공간 자료와 라리엔 참고 코드를 먼저 읽겠습니다.

• 서버 모듈의 핵심 부분을 직접 확인합니다.

• 서버의 플레이어 상태 테이블과 수치 함수를 확인합니다.

• 마지막으로 몬스터 스폰 규모와 입장 흐름을 확인합니다.

• 

## 1. 결론 요약

  라리엔식 30Hz 시뮬레이션 틱을 SpacetimeDB 에 그대로 옮기는 것은 불가능하다 — SpacetimeDB 의 실행 단위는 "의도를 받는 원자적 reducer 트랜잭션" 과 "저주파 scheduled reducer" 뿐이므로, 초당 30회 전체 월드 시뮬레이션을 돌리는 Go Zone Server 모델은 구조가 다르다. 대신 **"클라이언트는 의도(intent)만 reducer 로 보내고, 판정 결과는 공개 테이블 행이 되며, 구독이 곧 스냅샷"** 인 이벤트 주도 서버 권위로 설계해야 한다. 놀랍게도 그 골격은 이미 `spacetimedb/src/world.rs` 에 절반 이상 깔려 있다(`attack_monster`·`move_to`·`world_player.hp/alive`) — 문제는 ① 몬스터→플레이어 피해·사망 판정 틱이 없고, ② 리스폰 스케줄러가 무장(arm)되지 않았으며, ③ 서버 수치가 구 규격(HP 100 기반)이라 클라이언트 신 규격(HP 10,000)과 어긋나고, ④ 무엇보다 **클라이언트가 이 서버 전투를 한 군데도 호출하지 않는다** 는 것이다. 서버 권위화의 본체는 새 인프라가 아니라 "이미 있는 서버 판정에 클라이언트를 접속하고, 빠진 판정 축(몹의 반격·사망·회복·MP·스킬)을 같은 패턴으로 추가하는 일" 이다.

  

## 2. 근거

  - `spacetimedb/src/world.rs:805-880` — `attack_monster`: 피해량·사거리(2.2타일)·쿨다운(0.35초)·선점 태그·킬 판정이 전부 서버 측. 주석 "클라이언트는 의도만 보낸다"(`:802-804`).
  - `spacetimedb/src/world.rs:686-723` — `move_to`: 서버는 속도 상한(14타일/초, `:139`)만 검증하고 초과분은 잘라서 받아들임. 좌표의 진실은 여전히 클라이언트 보고다.
  - `spacetimedb/src/world.rs:170-211` — `WorldPlayer` 에 `hp`·`max_hp`·`alive`·`next_attack_at` 열이 이미 있음. 그러나 **mp·defense·버프 열은 없다.**
  - `spacetimedb/src/world.rs:289-295, 883-909` — `monster_tick` scheduled reducer(리스폰)는 선언돼 있으나 `monster_tick_timer` 행을 insert 하는 코드가 모듈 전체에 없음. `MONSTER_TICK_SECS`(`:130`)도 미사용. **리스폰은 현재 절대 실행되지 않는다.**
  - `spacetimedb/src/world.rs:142, 363-372` — 서버 수치는 구 규격: `BASE_MAX_HP = 100`, 레벨당 +18, `player_damage = 14 + 3×(lv-1)`. 클라이언트는 기본 HP 10,000, 레벨당 +1,000, 근접 26(`lib/game/entities/player.dart:45`, `lib/game/systems/level_system.dart:152`, `player.dart:70-71`) — 양쪽이 완전히 다른 게임을 말하고 있다.
  - `spacetimedb/src/world.rs:79, 87-88, 102, 108` — 몬스터 배치는 레벨 200 × 방위 3 × 군집 5~20 = **최대 12,000 마리**. `GAME-DESIGN.md:651, 790` 의 "서버 권위 몬스터 240기" 와 정면으로 어긋남(문서가 낡았거나 코드가 폭주한 것).
  - `lib/game/net/spacetime_game_sync.dart:96` 와 `spacetimedb/src/leaderboard.rs:289-324` — 현재 서버에 실제로 가는 성장 데이터는 클라이언트 자가 신고 `report_progress(totalXp)` 뿐. `reportKill`/`reportDeath` 는 클라에서 호출되지만 no-op 오버라이드다. 조작 클라이언트는 서버 전투를 우회해 누적 XP 를 직접 올릴 수 있다(leaderboard.rs:276-287 이 이를 자인하고 "서버 전투가 유일한 출처가 되면 제거" 라고 적음).
  - `lib/game/entities/player.dart:583-588` + `lib/game/action_rpg_game.dart:1347-1391` — 사망 판정·리스폰은 전적으로 클라이언트. 서버 `WorldPlayer.alive` 는 이 흐름과 연결돼 있지 않다.
  - `lib/game/entities/enemy.dart:296-334`, `lib/game/entities/projectile.dart:84-98` — 몹→플레이어 피해는 클라이언트 `applyDamage` 호출로만 발생. 서버에는 몹이 플레이어를 때리는 경로가 아예 없다.
  - `spacetimedb/src/lib.rs:9-18` — 서버 설계 원칙: `ctx.sender()` 에서만 소유자 도출, 비공개 테이블, `ctx.timestamp`·`ctx.random()` 만 사용. 단 원칙 3("모든 테이블 비공개")은 `world_player`·`monster`·`monster_kill` 이 public 이라 world.rs:33-39 가 예외를 문서화해 둠(머리말은 미갱신).
  - 라리엔 `game-server/zone/internal/sim/constants.go:7-9` — `TickHz = 30`, `SnapStrideTick = 2` (15Hz 스냅샷). `/Users/thruthesky/apps/game/laryen` 에서 확인.
  - 라리엔 `internal/sim/sim.go:928-951, 1218-1337` — `INPUT <seq> <dx> <dy>` 를 받아 tick 에서만 위치 판정(16방향 양자화, 축 분리 벽 슬라이드, 입력 9틱 stale 시 강제 정지).
  - 라리엔 `internal/sim/pc_attack.go:40-171`, `internal/sim/combat.go:24-174` — 공격은 `ATTACK <seq>` 의도만 받고 다음 tick 에 판정; 사망 처리(사망 EVENT → XP 페널티 → HP/MP 완전 회복 → safe zone 부활 → 스폰 보호)가 서버 단일 수렴점 `CombatResolve` 에 모여 있음.
  - 라리엔 `lib/features/game/render/player_component.dart:46, 996-1049` — 클라이언트 예측 + 서버 SNAP 적응형 lerp reconcile(오차 ≥90px 이면 k=0.5 강 수렴). `lib/features/game/render/snapshot_interpolator.dart:7-39` — 100ms 버퍼 스냅샷 보간, 역순 SNAP 폐기.

  

## 3. 상세 분석

  ### 3.1 현재 서버 권위 지도 (사실 정리)

  | 축 | 현재 판정 주체 | 근거 |
  |---|---|---|
  | 계정·캐릭터·세션 | 서버(완결) | `lib.rs:181-187` |
  | 누적 XP 의 진실 | 서버이나 **클라 자가 신고 경로가 열려 있음** | `leaderboard.rs:289` |
  | 몬스터 목록·HP·선점·킬·XP 지급 | 서버(**단 클라가 미호출**) | `world.rs:805-987` |
  | 플레이어 이동 | 클라 결정, 서버는 속도 상한만 | `world.rs:686-723` |
  | 몹→플레이어 피해 | 클라 전담(서버 경로 없음) | `enemy.dart:296-334` |
  | 사망·리스폰·무적 | 클라 전담 | `player.dart:583-641` |
  | HP/MP 회복(휴식) | 클라 전담 | `rest_recovery.dart:11-20` |
  | MP·버프·방어력 | 서버 스키마에 열 자체가 없음 | `world.rs:170-211` |
  | 스킬 | 양쪽 어디에도 없음 | `lib/` 에 skill/ability 검색 결과 없음 |
  | PK | 미구현 | `GAME-DESIGN.md:792` |

  ### 3.2 라리엔 모델 → SpacetimeDB 모델 매핑

  라리엔의 각 기법을 Cyborg 에서 대체할 수단은 다음과 같다.

  | 라리엔 (Go UDP) | Cyborg (SpacetimeDB) 대응 | 차이의 본질 |
  |---|---|---|
  | 30Hz `Sim.Tick` (`sim.go:1074`) | 초저주파 scheduled reducer(수 초 단위) + 이벤트 reducer | SpacetimeDB 는 매 실행이 트랜잭션 커밋. 30Hz 전체 시뮬은 비현실. 틱은 "몹 정비" 용도로만 쓰고, 반응성이 필요한 판정은 의도 reducer 안에서 즉시 처리 |
  | `INPUT <seq> <dx> <dy>` + 서버 위치 판정 | 기존 `move_to(x, y)` + 속도 상한 검증 유지 | 완전 서버 이동 시뮬레이션은 예측·롤백 인프라가 필요하며 world.rs:134-138 주석이 이미 "지금 단계에서 얻는 것보다 비용이 크다" 고 기각해 둠. **이 판단은 SpacetimeDB 에서 더욱 타당** — tick 이 없으니 방향 벡터 모델 자체가 성립하지 않는다 |
  | 15Hz binary 스냅샷 + AOI + MTU budget (`snap_binary.go:306-488`) | public 테이블 구독(`world_player`, `monster`) | 구독 갱신이 곧 스냅샷이다. 단 AOI 가 없으므로 **전체 테이블이 모든 클라에 흘러간다** — 최대 12,000 마리 몹 테이블 전체 구독은 대역·캐시 양쪽에서 파탄적이다(아래 3.4) |
  | 클라 예측 + 적응형 lerp reconcile (`player_component.dart:996-1049`) | 클라 예측 이동 유지 + 구독으로 돌아온 본인 `world_player` 좌표와의 오차를 lerp 보정 | 이미 `move_to` 가 상한 초과분을 잘라 당기므로(`world.rs:703-713`), 클라가 자기 서버 좌표를 무시하면 지연 튐 때마다 서버와 클라 위치가 영구히 벌어진다 |
  | seq dedup (`session/manager.go:315, 499`) | 불필요 — reducer 호출은 SpacetimeDB 전송이 순서·신뢰성을 보장하고, 쿨다운(`next_attack_at`)이 서버 측 중복 방어를 겸함 | UDP 라서 필요했던 장치이며 WebSocket 기반 SpacetimeDB 에는 해당 없음 |
  | `CombatResolve` 단일 수렴점 (`combat.go:24-174`) | 서버 `world.rs` 에 "플레이어 피해 적용" 단일 내부 함수(가칭 `apply_damage_to_player`) — 몹 반격 틱·PK·스킬이 모두 여기를 통과 | 사망 판정·리스폰·XP 페널티를 한 곳에 모으는 라리엔의 구조는 그대로 가져올 가치가 있다 |

  ### 3.3 빠진 판정 축을 채우는 설계 (SpacetimeDB 식)

  - **몹→플레이어 피해·사망**: scheduled reducer(가칭 `world_combat_tick`, 주기 1~2초)가 살아 있는 몹 × 월드 플레이어의 근접 쌍을 훑어 `피해 = monster.level − defense(최소 0 또는 1)` 를 `world_player.hp` 에서 깎고, 0 이하면 `alive = false` + 사망 시각 기록. 리스폰은 별도 reducer(`respawn`) 또는 tick 에서 안전지대 좌표·HP 완전 회복으로. 이 tick 은 기존 `monster_tick`(리스폰)과 같은 스케줄에 합치는 것이 트랜잭션 수를 줄인다. 단 **몹 수가 수천이면 인덱스 없이 전수 스캔은 못 한다** — 몹 테이블에 리전 인덱스 열을 두고 "플레이어가 있는 리전의 몹" 만 훑어야 한다.
  - **이동**: `move_to` 모델 유지. 라리엔의 "서버가 위치를 결정" 과 달리 "서버가 상한 안에서 수용" 하는 준(準)서버 권위인데, 이것은 이미 world.rs:134-138 이 의식적으로 선택한 트레이드오프이며 SpacetimeDB 제약(틱 없음)상 유일하게 현실적인 선택이다. 클라 측에는 라리엔식 적응형 lerp reconcile 만 이식하면 된다.
  - **공격·스킬**: `attack_monster` 패턴을 그대로 복제한다. 사격은 별도 reducer(사거리·MP 비용·쿨다운 서버 검증), 스킬은 `use_skill(skill_id, target_id?)` — 습득 여부·MP·쿨다운을 서버가 검증하고 효과를 즉시 커밋. 라리엔의 `OnUseSkill`(`skill.go:39`) 과 같은 의도-검증 구조다. 단 라리엔의 지속 장판·지연 강타(tick 기반)는 SpacetimeDB 에서는 구현 단가가 크므로 1차 범위에서는 즉시 판정 스킬로 제한하는 것을 권한다 `[판단]`.
  - **HP/MP 회복**: 휴식 회복(`rest_recovery.dart:11-20`)을 combat tick 안으로 옮겨 서버가 `hp`/`mp` 를 회복시킨다. tick 주기(1~2초)가 회복 단위가 되므로 클라이언트는 회복을 렌더링만 한다.
  - **스키마 추가**(모두 맨 끝 + 기본값 규칙 — `world.rs:204-209` 주석의 마이그레이션 제약 준수): `WorldPlayer` 에 `mp`/`max_mp`/`defense`/`died_at`/`next_skill_at` 등, `Monster` 에 리전 열. 
  - **자가 신고 경로 제거**: 서버 전투가 유일한 XP 출처가 되는 시점에 `report_progress` 를 없앤다 — leaderboard.rs:285-287 이 이미 그렇게 예고돼 있다. 이것이 anti-cheat 의 실질적 완결이다.

  ### 3.4 가장 큰 구조적 문제: 몹 규모와 구독

  `MONSTER_MAX_LEVEL = 200 × CLUSTERS_PER_LEVEL = 3 × 5~20` 으로 bootstrap 이 심는 몹은 **3,000~12,000 마리**(`world.rs:79-108, 409-436`)다. public `monster` 테이블을 통째로 구독하면 접속할 때마다 수천 행이 초기 로딩되고 매 틱 갱신이 전체 브로드캐스트된다. 라리엔이 AOI + 1400바이트 MTU budget 으로 해결한 문제(`snap_binary.go:127-130`)를 SpacetimeDB 에서는 테이블 공개 구독만으로는 해결할 수 없다. 대안은 ① 몹 테이블에 리전(예: 50×50 타일 구역) 인덱스 열을 두고 구독 쿼리를 리전 단위로 거는 것 — 단 내 위치가 바뀔 때 구독을 동적으로 바꿔야 하며 SDK 의 구독 쿼리 필터 지원 범위 확인이 필요하다(§6), ② 몹 수 자체를 문서의 240기 수준으로 줄이는 것, ③ view 로 근처 몹만 내리는 것 — 단 view 의 읽기 전용 핸들에는 `iter()` 가 없고 인덱스 범위 조회뿐이라 거리 필터는 리전 인덱스가 전제돼야 한다.

  ### 3.5 수치의 단일 진실 공급원

  서버 권위가 성립하려면 피해·HP·쿨다운 수치가 **서버 한 곳**에만 있어야 하고 클라이언트는 렌더링 추정치로만 써야 한다. 현재는 정반대로, 클라(HP 10,000/피해 = 몹 레벨 — `player.dart:45`, `monster_codex.dart:405-489`)와 서버(HP 100/피해 14+3lv — `world.rs:142, 370-372`)가 서로 다른 두 게임의 수치를 들고 있다. 서버 권위 전환의 첫 작업은 사람이 정한 신 규격(HP 10,000, 방어 0, 피해 = 몹 레벨)을 **서버 `world.rs` 에 먼저 심는 것**이고, 그 다음 클라이언트 로컬 판정을 지우는 순서여야 한다. 반대 순서(클라부터 서버 호출로 바꾸기)를 하면 클라가 서버의 구 규격 결과를 렌더링하게 되어 체감이 즉시 깨진다.

  

## 4. 리스크 · 함정

  - **리스폰 스케줄러 미무장(기존 결함)**: `monster_tick_timer` 행을 insert 하는 코드가 없어(`world.rs:289-295` 선언만 존재) 죽은 몹은 영원히 죽은 채다. 서버 전투를 켜는 순간 이것이 즉시 사용자-facing 버그가 된다. `init`/`bootstrap` 에서 타이머 행을 심어야 한다.
  - **수치 이중화 상태에서의 부분 전환**: `attack_monster` 만 클라에 붙이고 몹 반격은 클라에 두면, "내가 때리는 것은 서버 판정·내가 맞는 것은 클라 판정" 이라는 최악의 중간 상태가 된다 — 조작 클라가 무적 사냥으로 서버 XP 를 정당하게 채굴할 수 있다. **공격 판정과 피격 판정은 반드시 같은 이정표에서 함께 옮겨야 한다.**
  - **전체 테이블 구독 폭증**: 위 3.4. 12,000행 몹 테이블 + 접속자 수 × 구독은 maincloud 에서 대역·CPU 양쪽의 병목이 된다. 몹 수나 구독 단위를 해결하지 않고 클라를 `monster` 구독으로 전환하면 안 된다.
  - **scheduled reducer 의 비용과 정확도**: 수천 몹 × 수십 플레이어의 근접 판정을 WASM 트랜잭션으로 1~2초마다 도는 비용, 그리고 SpacetimeDB 스케줄러의 실제 최소 주기·지터가 미확인이다(§6). 주기가 길어지면 "맞고 죽는" 체감이 둔해지므로, 클라는 피격을 즉시 연출하되 서버 확정 전까지 HP 를 잠정 표시하는 예측 계층이 필요하다(라리엔의 예측-보정과 같은 철학).
  - **reducer 재실행 멱등성**: world.rs:29-31 이 명시한 대로 직렬화 충돌 시 같은 인자로 재실행될 수 있다. 사망 처리에서 XP 페널티·사망 수 증가를 넣을 때 "이미 죽은 상태면 통과" 가드가 없으면 두 번 차감된다. 라리엔 `CombatResolve` 의 단일 수렴점 구조를 가져오되, 모든 부수 효과는 테이블 상태에서 유도 가능하게 설계해야 한다.
  - **지형 지식의 비대칭**: 서버는 블록·방화벽(hazard)·통행 불가 지형을 모른다(`world.rs:149-155` 주석이 텔레포트에서 이를 인정). hazard 도트 피해(`player.dart:501-520`)와 벽 충돌을 서버 권위로 옮기려면 지형 데이터를 서버에 심어야 하며, 1차 범위에서는 제외하고 "몹 피해·회복·사망" 으로 경계를 긋는 것이 현실적이다. 단 이 경우 hazard 로는 죽지 않는 몸이 서버에는 살아있는 것으로 남는 불일치를 수용할지 결정이 필요하다.
  - **원거리 몹 발사체**: `projectile.dart:84-98` 의 궤적 판정을 서버가 하려면 발사체 시뮬레이션이 필요하다. 틱이 없는 SpacetimeDB 에서는 "사거리 내 즉시 판정" 으로 몹 원거리 공격을 재설계하는 편이 낫다 `[판단]`.
  - **MMORPG 전제의 함정**: 같은 몹에 수십 명이 `attack_monster` 를 몰리게 보내면 해당 행 갱신이 직렬화 지점이 된다. world.rs:24-27 이 이를 감수하고 락 대신 직렬화를 택했지만, 인기 사냥터에서 reducer 지연은 곧 조작감 악화다. 군집 분산 배치(`CLUSTERS_PER_LEVEL`)가 완충재이나 수용 인원 상한에 대한 실측이 없다.
  - **문서-코드 불일치**: `GAME-DESIGN.md:651, 790` (240기) vs 코드(최대 12,000), `lib.rs:15-16` (모든 테이블 비공개) vs world public 테이블 3개, `GAME-DESIGN.md:749` ("monster_tick 5초마다") vs 미무장. 종합 단계에서 문서 갱신이 필요하다.

  

## 5. 권고안

  | 순위 | 권고 | 범위 | 근거 | 리스크 |
  |---|---|---|---|---|
  | 1 | 신 규격 수치를 서버에 먼저 심는다: `BASE_MAX_HP` 10,000, 레벨당 성장치, `player_damage`, 몹 피해 = `monster.level`, `defense` 개념을 `world.rs` 수치 함수들에 반영하고 `WorldPlayer` 에 `mp`/`max_mp`/`defense` 열을 맨 끝+기본값으로 추가 | 서버 `world.rs` | `world.rs:142, 363-372`, 마이그레이션 규칙 `world.rs:204-209` | 기존 배포 행의 `hp/max_hp` 가 구 규격으로 남음 — 재초기화(`rebuild_monsters` 류) 또는 마이그레이션 reducer 필요 |
  | 2 | `monster_tick_timer` 를 `init`/`bootstrap` 에서 무장하고, 그 스케줄을 `world_combat_tick` 으로 확장해 몹 반격(피해 = level − defense)·사망 판정·휴식 회복·리스폰을 한 트랜잭션 주기로 묶는다. 몹 스캔은 리전 인덱스로 제한 | 서버 `world.rs` | `world.rs:289-295, 883-909`, 라리엔 `combat.go:24-174` | tick 트랜잭션 비용; 주기를 길게 잡으면 피격 체감이 둔해져 클라 예측 표시가 전제가 됨 |
  | 3 | 플레이어 피해 적용을 단일 내부 함수로 수렴시키고, 사망 시 `alive=false`·안전지대 리스폰·HP/MP 완전 회복·무적 창을 서버가 처리. 모든 부수 효과는 재실행 멱등하게(가드: 이미 죽었으면 통과) | 서버 `world.rs` | `world.rs:29-31` (재실행 원칙), 라리엔 `CombatResolve` | 멱등성 누락 시 XP 페널티·사망 수 이중 차감 |
  | 4 | 몹 테이블 규모 결정을 선행한다: 12,000 마리 유지라면 리전 인덱스 + 리전 단위 구독으로 AOI 를 만들고, 아니면 몹 수를 줄인다. 결정 전까지 클라의 `monster` 통 구독 전환 금지 | 서버 스키마 + 클라 구독(`cyborg_connection.dart`) | `world.rs:79-108`, 라리엔 AOI `snap_binary.go:127-130` | SDK 구독 필터 지원 범위에 따라 설계가 갈림(§6) |
  | 5 | 클라이언트 전환: `MonsterPopulation` 로컬 장부를 `monster` 구독으로 교체하고(GAME-DESIGN.md:802-806 이 이미 계획), 근접·사격·(신규) 스킬을 의도 reducer 호출로 바꾸며, `Player.applyDamage` 는 "서버 hp 구독 반영 + 즉시 연출용 잠정 예측" 으로 축소. 본인 `world_player` 좌표와의 오차는 라리엔식 적응형 lerp 로 보정 | 클라 `lib/game/` | `GAME-DESIGN.md:802-806`, `player.dart:544-598`, 라리엔 `player_component.dart:996-1049` | 대규모 클라 리팩터링; 오프라인/프리뷰 모드(`offline_main.dart`, `preview_main.dart`)의 로컬 전투는 별도 유지 결정 필요 |
  | 6 | 서버 전투가 유일한 XP 출처가 되는 시점에 `report_progress` reducer 와 클라 `SpacetimeGameSync` 신고 경로를 제거한다 | 서버 `leaderboard.rs` + 클라 `net/` | `leaderboard.rs:276-287` | 순서를 앞당기면 오프라인 플레이의 성장이 증발 — 5번 완료 후에만 |
  | 7 | 스킬은 즉시 판정형(의도 reducer + MP·쿨다운 서버 검증)으로 1차 범위를 자르고, 지속 장판·지연 강타 같은 tick 의존 스킬은 combat tick 이 안정화된 뒤에 추가한다 | 서버 + 클라 공통 | 라리엔 `skill.go:39` 대비 SpacetimeDB 틱 제약 | 스킬 시스템 자체가 신설이므로 기획(스킬 목록)이 선행돼야 함 — 현재 양쪽에 없음 |

  

## 6. 불확실 · 미확인

  - **scheduled reducer 의 실제 최소 주기·지터·비용**: SpacetimeDB 2.7 에서 초 단위 반복 스케줄의 보장 수준을 문서로 확인하지 못했다. 1~2초 전투 틱이 현실적인지는 실측이 필요하다. `[추측]` 수 초 단위는 가능하나 서브초 반복은 비현실적일 것.
  - **SDK 구독 쿼리 필터**: Dart SDK(`spacetimedb_sdk ^2.4.0`) 가 `WHERE` 절이 있는 부분 구독을 지원하는지, 구독을 실행 중에 동적으로 교체할 수 있는지 미확인. 리전 AOI 설계(권고 4)의 성립 조건이다.
  - **몹 실제 배치 수**: `GAME-DESIGN.md` 의 240 과 코드 상수(최대 12,000) 중 어느 것이 의도인지 사람 판단이 필요하다. bootstrap 의 실제 루프(레벨 전체를 도는지)는 415~436행을 부분 확인했을 뿐 전체 스폰 수를 실행해 세지는 못했다.
  - **PK 의 요구 범위**: "서버 권위 이벤트" 에 PK 가 포함되는지(PK 는 `GAME-DESIGN.md:792` 기준 미구현). `attack_player` reducer 는 `attack_monster` 패턴으로 자연스럽게 파생되지만, 이번 요청이 PK 까지 요구하는지는 불명확하다.
  - **오프라인·프리뷰 모드의 처우**: `lib/offline_main.dart`·`lib/preview_main.dart` 가 서버 없이 도는 경로인데, 서버 권위 전환 후 이 모드들에 로컬 전투를 얼마나 남길지 결정이 필요하다.
  - **서버 전투 수치와 리더보드 경험치 곡선의 정합**: 서버 `monster_xp`(world.rs:357-360, 레벨당 +12%)와 클라 `LevelSystem` 의 킬 XP 감소(0.97^lv — `level_system.dart:174-180`)가 다른 곡선이다. 서버가 XP 의 유일 출처가 되면 클라 곡선은 무효가 되는데, 어느 쪽을 정본으로 할지 수치 설계 판단이 필요하다.
