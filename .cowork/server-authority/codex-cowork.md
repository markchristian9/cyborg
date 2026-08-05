<!-- cowork:codex | 2026-08-04 22:55:21 | exit=0 | 683s -->
# codex 분석 — server-authority

> 요청: 서버 권위 판정을 하도록 해 주세요. 서버 권위 이동, 서버 권이 이벤트, 사망, HP/MP 감소/회복, 스킬, 등등 서버가 판정을 하고 클라에서는 렌더링만 하도록 해 주세요.

참고: 형제 게임 라리엔(~/apps/game/laryen, 읽기 전용 참고만 가능)의 서버 권위 이동 관련 코드/로직을 참고해 주세요. 라리엔은 Go UDP Zone Server 로 30Hz sim tick + 10~15Hz 스냅샷 브로드캐스트 + 클라 예측/서버 reconcile 구조입니다. 다만 Cyborg 는 SpacetimeDB(reducer + 구독 + scheduled reducer) 백엔드이므로 그 차이를 감안한 설계를 제시해 주세요.
> 생성: 2026-08-04 22:55:21 · 소요 683s · 읽기 전용 분석(작업공간 미수정)

---



## 1. 결론 요약

현재 Cyborg는 서버 권위 게임이 아니다. 서버의 `attack_monster`만 피해·사거리·쿨다운을 부분 판정하며, 이동·몬스터 AI·HP/MP·스킬·사망·회복·드롭·인벤토리·XP의 실질적 정본은 클라이언트다. `spacetimedb/src/world.rs:664-706`, `lib/game/entities/player.dart:184-245`, `lib/game/action_rpg_game.dart:1225-1366`

목표 구조는 클라이언트가 좌표·피해·HP·XP를 보고하는 대신 입력과 행동 의도만 보내고, SpacetimeDB의 private 상태 테이블과 scheduled reducer가 고정 순서로 이동·충돌·전투·사망·회복을 확정한 뒤 view 구독으로 상태와 연출 이벤트를 전달하는 형태여야 한다. `.cowork/cowork-prompt.md:60-66`

Laryen에서 가져올 것은 30Hz라는 숫자 자체보다 입력 `seq`, 고정 틱 순서, 서버 판정, 로컬 이동 예측·reconcile, 원격 보간의 책임 분리다. UDP ACK·재전송·패킷 스냅샷은 SpacetimeDB reducer 트랜잭션과 구독 캐시로 대체해야 한다. `~/apps/game/laryen/GAME-DESIGN.md:164-199`

서버 권위 전환 전에 서버 HP 100과 클라이언트 HP 10,000, 공개 월드 테이블과 private-view 원칙 등 이미 존재하는 계약 불일치를 먼저 해소해야 한다. `spacetimedb/src/world.rs:141-142`, `lib/game/entities/player.dart:41-48`, `spacetimedb/src/lib.rs:15-18`

## 2. 근거

- `.cowork/cowork-prompt.md:14-23` — Cyborg는 PK가 가능한 단일 공유 월드 MMORPG이며, 현재 실시간 멀티플레이 전투 동기화는 아직 없다고 정의한다.
- `CLAUDE.md:26-38` — 플레이어와 몬스터는 한 월드의 공유 객체이고, 타인의 이동·전투가 실시간으로 보여야 하며 PK도 허용된다.
- `spacetimedb/src/lib.rs:7-18` — 소유자를 `ctx.sender()`로 도출하고, 테이블은 private, 시각·난수는 서버 값을 사용한다는 서버 원칙이 명시돼 있다.
- `spacetimedb/src/world.rs:166-210` — 현재 `WorldPlayer`는 `public`이며 좌표·HP·공격/텔레포트 시각만 있다. MP·energy·defense·velocity·facing·입력 seq·버프·스킬 상태는 없다.
- `spacetimedb/src/world.rs:664-706` — `move_to`는 클라이언트가 보낸 절대 좌표를 속도 상한으로 자를 뿐, 서버 입력 적분·지형 충돌·사망 상태 검사를 하지 않는다.
- `spacetimedb/src/world.rs:783-863` — `attack_monster`는 서버 좌표로 사거리·쿨다운·피해·킬·XP를 판정하므로 현재 서버 권위에 가장 가까운 부분이다.
- `spacetimedb/src/world.rs:865-892` — 현재 scheduled reducer는 죽은 몬스터 리스폰만 처리하며 이동·AI·몬스터 공격·플레이어 피해는 시뮬레이션하지 않는다.
- `lib/game/action_rpg_game.dart:531-546` — 매 프레임 클라이언트가 입력, Flame 컴포넌트 업데이트, 몬스터 장부, 진행 동기화를 수행하고 완성된 자기 좌표를 서버에 보고한다.
- `lib/game/entities/player.dart:184-245`, `lib/game/entities/player.dart:446-598` — 근접 공격, MP 소비 발사체, 대시, 타격 판정, 방어, HP 감소와 사망이 모두 클라이언트에서 처리된다.
- `lib/game/entities/enemy.dart:133-215`, `lib/game/entities/enemy.dart:296-395`, `lib/game/entities/projectile.dart:47-100` — 몬스터 AI·공격·피해·사망과 발사체 이동·충돌도 전부 클라이언트 프레임 루프에 있다.
- `lib/game/action_rpg_game.dart:1225-1267`, `lib/game/action_rpg_game.dart:1318-1366` — 클라이언트가 킬·XP·드롭을 확정하고 사망 즉시 직접 리스폰한 다음 사망 사실만 보고한다.
- `lib/spacetime/cyborg_connection.dart:34-41`, `lib/game/action_rpg_game.dart:1436-1437` — 월드 구독은 `world_player`만 받고, 실제 몬스터는 클라이언트 `MonsterPopulation`으로 다시 생성한다. 서버 `Monster`와 화면의 몬스터가 아직 하나의 개체가 아니다.
- `lib/game/net/spacetime_game_sync.dart:55-117`, `spacetimedb/src/leaderboard.rs:269-323` — 클라이언트가 계산한 `totalXp`를 주기적으로 신고하며, 서버 코드도 그 값이 조작될 수 있다고 명시한다.
- `~/apps/game/laryen/game-server/zone/internal/sim/sim.go:1103-1188` — Laryen은 플레이어 이동→몬스터 AI→플레이어 공격/스킬→몬스터 공격→사망→HP/MP 회복 순서로 서버 틱을 처리한다.
- SpacetimeDB 공식 문서 — scheduled reducer는 schedule table 행을 삽입해야 실행되며 interval 실행을 지원한다. reducer 하나의 상태 변경은 원자적으로 commit/rollback되고, view와 구독은 변경된 행을 클라이언트 캐시에 실시간 전달한다. [Schedule Tables](https://spacetimedb.com/docs/tables/schedule-tables/), [Transactions and Atomicity](https://spacetimedb.com/docs/databases/transactions-atomicity/), [Views](https://spacetimedb.com/docs/functions/views/), [Subscriptions](https://spacetimedb.com/docs/clients/subscriptions/)

## 3. 상세 분석

### 현재 권위 경계

| 영역 | 현재 정본 | 문제 |
|---|---|---|
| 이동 | 클라이언트 `Player._updateMovement`; 서버는 완성 좌표를 속도 제한 | 조작 클라이언트가 지형·대시·사망 이동 제한을 우회할 수 있다. `lib/game/entities/player.dart:325-372`, `spacetimedb/src/world.rs:664-706` |
| 몬스터 | 클라이언트 AI와 클라이언트별 `MonsterPopulation` | 같은 공유 몬스터의 위치·공격·사망이 사용자마다 달라질 수 있다. `lib/game/entities/enemy.dart:133-215`, `lib/game/action_rpg_game.dart:1436-1437` |
| 플레이어 공격 | 클라이언트 근접/발사체와 미사용에 가까운 서버 `attack_monster`가 병존 | 어느 결과가 정본인지 화면 경로가 통일되지 않았다. `lib/game/entities/player.dart:184-227`, `spacetimedb/src/world.rs:783-863` |
| HP·MP·energy | 클라이언트 `Player`의 mutable 필드 | 서버 `WorldPlayer`에는 MP·energy·defense가 없어 감소·회복을 판정할 수 없다. `lib/game/entities/player.dart:38-87`, `spacetimedb/src/world.rs:182-210` |
| 포션·버프·회복 | 클라이언트 인벤토리와 프레임 타이머 | 수량 소비, 회복량, 버프 지속 시간을 조작할 수 있다. `lib/game/systems/inventory.dart:80-118`, `lib/game/systems/buff.dart:88-139`, `lib/game/systems/rest_recovery.dart:41-60` |
| 사망·리스폰 | 클라이언트가 HP 0과 리스폰 좌표를 결정 | 서버와 다른 사용자에게 사망과 무적 시간이 일관되게 보장되지 않는다. `lib/game/entities/player.dart:583-588`, `lib/game/action_rpg_game.dart:1318-1366` |
| 성장·보상 | 클라이언트가 킬·드롭·XP를 확정한 뒤 `totalXp` 신고 | 서버 권위 전투와 클라이언트 신고 경로가 같은 성장값을 동시에 갱신한다. `lib/game/action_rpg_game.dart:1225-1267`, `spacetimedb/src/leaderboard.rs:276-287` |

### 목표 서버 모델

[설계 판단] 다음 상태를 모두 `spacetimedb/`의 private 테이블로 두고, 클라이언트에는 필요한 열만 view로 노출해야 한다.

- `WorldPlayerState`: `character_id`, 정수 좌표·속도, `cell_id`, facing/action state, HP/MP/energy와 최대값, defense, alive, 무적·공격·대시 시각, 마지막 활동·피격 시각, `last_processed_input_seq`.
- `PlayerInputState`: 호출자의 최신 이동 입력과 `seq`. 좌표가 아니라 정규화 전 방향 또는 이동 목적지만 보관한다.
- `PendingAction`: 공격·스킬·아이템 사용 의도, 채널별 `seq`, 대상 entity 또는 목표 위치. 클라이언트 피해량·MP 비용·쿨다운·시각은 받지 않는다.
- `MonsterState`: 현재 `Monster`에 AI phase, target, facing, velocity, attack/telegraph 시각과 `cell_id`를 추가한다.
- `ProjectileState`·`AreaEffectState`: 벽·유도·지속 피해처럼 게임 판정이 있는 발사체와 장판만 서버가 시뮬레이션한다.
- `InventoryItem`, `ActiveBuff`, `SkillCooldown`, `GroundDrop`: 소유·수량·만료·습득을 서버가 관리한다.
- `CombatEvent`와 `ActionReceipt`: 전자는 주변 사용자의 피해 텍스트·공격·사망·리스폰·스킬 FX용이고, 후자는 요청자에게 성공 여부와 실패 사유를 돌려주는 용도다. 실제 상태가 정본이며 이벤트는 표현 신호다.

현재 `PlayerCharacter`에는 성장값만 있고 전투 자원은 없으므로 영구 성장과 접속 중 전투 상태의 생명주기를 구분해야 한다. `spacetimedb/src/lib.rs:90-139`

### 입력과 reducer

[설계 판단] 공개 reducer는 다음처럼 의도만 받아야 한다.

- `set_move_input(seq, dx, dy)` 또는 `set_move_target(seq, destination)`.
- `request_attack(seq, target_id)`.
- `request_skill(seq, skill_id, target_kind, target_id/position)`.
- `request_use_item(seq, inventory_slot/item_id)`.
- `request_dash(seq, dx, dy)`와 `request_teleport(destination_id)`.

모든 reducer는 `ctx.sender()`에서 조종 캐릭터를 찾고, 사망·거래/메뉴 잠금·자원·소유·쿨다운을 검증해야 한다. 클라이언트 시각, `account_id`, HP, 피해, 드롭, XP는 인자로 받지 않는다. `spacetimedb/src/lib.rs:9-18`, `spacetimedb/src/world.rs:896-905`

이동 입력에는 Laryen과 같은 단조 `seq` 및 입력 유효기간이 필요하다. Laryen은 오래된 입력을 폐기하고 300ms 동안 새 입력이 없으면 자동 정지한다. `~/apps/game/laryen/game-server/zone/internal/session/manager.go:494-512`, `~/apps/game/laryen/game-server/zone/internal/sim/constants.go:35-38`

SpacetimeDB는 UDP가 아니므로 ACK 재전송기를 복사할 필요는 없지만, SDK가 reducer를 오프라인 저장소에 대기시킬 수 있는 API를 제공하므로 실시간 이동·공격·스킬에는 `dropIfOffline: true`와 서버 `seq` 검증을 함께 써야 한다. `lib/spacetime/generated/reducers.dart:14-32`

### scheduled reducer의 틱

[설계 판단] `WorldTickTimer`가 고정 시뮬레이션 틱을 구동하고 다음 순서를 유지해야 한다.

1. 오래된 입력 자동 정지, 만료 버프·쿨다운 정리.
2. 플레이어 입력→속도→서버 지형 충돌→위치 확정.
3. 몬스터 감지·추격·telegraph·이동.
4. 플레이어 공격·스킬·발사체·장판 판정.
5. 아직 살아 있는 몬스터의 공격, 방화벽 등 환경 피해.
6. HP 감소, 사망, 즉시 안전지대 리스폰, 드롭·XP·인벤토리 반영.
7. HP/MP/energy 회복.
8. `CombatEvent` 발행과 클라이언트용 replica 갱신.

플레이어 공격을 몬스터 공격보다 먼저 처리하면 같은 틱에 죽은 몬스터가 마지막 공격을 가하는 현상을 막을 수 있다. Laryen도 이 순서를 명시한다. `~/apps/game/laryen/game-server/zone/internal/sim/sim.go:1159-1188`

동일 틱의 HP 변경·아이템 소비·킬·XP·사망 이벤트는 하나의 reducer 트랜잭션에서 함께 반영해야 한다. 그러면 일부만 성공하는 상태가 생기지 않는다. [SpacetimeDB Transactions and Atomicity](https://spacetimedb.com/docs/databases/transactions-atomicity/)

연산은 정수 고정소수 좌표와 정수 HP/MP를 권장한다. Laryen은 모든 위치 산술을 정수 cm로 처리해 순회 순서와 결과를 고정한다. `~/apps/game/laryen/game-server/zone/internal/sim/sim.go:1035-1040`, `~/apps/game/laryen/game-server/zone/internal/sim/sim.go:1279-1302`

### HP·MP·방어·사망 수렴점

[설계 판단] 서버에 `apply_damage`, `restore_hp`, `spend_mp`, `restore_mp`, `consume_item`, `resolve_death` 같은 내부 단일 수렴점을 두어 기본 공격·스킬·발사체·방화벽·포션이 같은 규칙을 사용하게 해야 한다.

첫 서버 권위 버전은 다음 Cyborg 계약을 그대로 옮겨야 한다.

- 1레벨 기본 HP 10,000. `lib/game/entities/player.dart:41-48`
- 방어력 0, 버프 없음에서 몬스터의 최종 1회 피해는 `monster.level`. `.cowork/cowork-prompt.md:28-32`
- 방어 후 버프 배율을 적용하고 마지막에 한 번 정수화. `lib/game/entities/player.dart:531-566`
- 방화벽은 무적과 defense를 무시하며 0.5초마다 최대 HP의 4% 피해. `lib/game/entities/player.dart:501-519`
- 안전지대 회복은 HP 초당 12%, MP 초당 15%, 야전 MP는 초당 0.5%. `lib/game/systems/rest_recovery.dart:8-20`
- 사망 시 안전지대에서 HP·MP·energy를 완전히 회복하고 이동·공격 상태를 초기화하며 2초 무적을 준다. `lib/game/entities/player.dart:600-640`

서버의 현재 `BASE_MAX_HP=100`, 레벨당 `+18`은 이 계약과 맞지 않으므로 서버 권위 전환 때 그대로 유지하면 안 된다. `spacetimedb/src/world.rs:141-142`, `spacetimedb/src/world.rs:362-365`

### view·AOI·이벤트 전달

모든 내부 테이블은 private로 두고 다음 view를 명시적으로 구독해야 한다. `.cowork/cowork-prompt.md:60-66`, `.cowork/cowork-prompt.md:78-83`

- `my_world_state`, `my_inventory`, `my_buffs`, `my_skill_cooldowns`, `my_action_receipts`: `ViewContext`로 본인 행만 반환.
- `world_actor_view`, `monster_view`, `combat_event_view`: 공개 anonymous view로 만들되 클라이언트가 현재 셀과 인접 셀만 구독.
- view 반환 타입은 Dart 생성기 제약 때문에 반드시 실제 private table의 row 타입이어야 한다. `.cowork/cowork-prompt.md:81-82`

현재의 `SELECT * FROM world_player`는 월드 인구 전체를 모든 접속자에게 전달하므로 수천 명 규모에 적합하지 않다. `lib/spacetime/cyborg_connection.dart:34-41` SpacetimeDB 공식 문서도 사용자별 “near me” view보다 공유 가능한 지역 단위 anonymous view를 권장한다. [SpacetimeDB Views](https://spacetimedb.com/docs/functions/views/)

Laryen의 30Hz 시뮬레이션·15Hz 스냅샷 분리는 private 시뮬레이션 상태와 낮은 빈도로 갱신하는 `ActorReplica` 테이블로 대응할 수 있다. 다만 SpacetimeDB의 모든 상태 갱신은 durable transaction이므로 30Hz 전역 테이블 갱신을 그대로 복사해서는 안 되고 부하 측정이 선행돼야 한다. `~/apps/game/laryen/game-server/zone/internal/sim/constants.go:5-10`

### 클라이언트 역할

[설계 판단] `GameSync`와 `WorldPresence`를 하나의 `AuthoritativeWorldSession`으로 합치고, Flame 컴포넌트는 구독 행과 이벤트를 렌더링하는 adapter가 되어야 한다.

- 자기 이동은 입력 즉시 화면 transform만 예측하고, 서버 replica의 `last_processed_input_seq`를 받으면 확인된 입력을 제거한 뒤 미확정 입력만 재적용한다.
- 예측 위치는 HP·충돌·공격 사거리·드롭·스킬 결과를 절대 변경하지 않는다. 이 범위의 예측은 “렌더링만”이라는 요구와 양립한다.
- 원격 플레이어·몬스터는 100ms 안팎 버퍼로 보간한다. Laryen도 자기 캐릭터는 prediction/reconcile, 원격은 interpolation으로 분리한다. `~/apps/game/laryen/GAME-DESIGN.md:195-199`
- HP/MP 바는 `my_world_state`, 피해 숫자·사망·스킬 FX는 `CombatEvent`, 인벤토리는 `my_inventory`만 읽는다.
- 온라인 입장 실패 시 로컬 전투를 계속하면 안 된다. 현재의 조용한 싱글 플레이 fallback은 서버 권위와 정면 충돌한다. `lib/spacetime/spacetime_world_presence.dart:74-82`, `lib/game/action_rpg_game.dart:1383-1392`
- pause는 Flame 렌더와 입력만 멈추고 서버 시뮬레이션은 계속되어야 하며, 복귀 시 최신 구독 상태로 즉시 수렴해야 한다. 현재 `pauseEngine()`은 로컬 시뮬레이션까지 멈춘다. `lib/game/action_rpg_game.dart:1395-1410`

## 4. 리스크 · 함정

- 서버와 클라이언트 수치가 이미 갈라져 있다. 서버 HP는 100, 클라이언트 HP는 10,000이며 성장 공식도 서버 `+18`과 클라이언트 `+1,000`으로 다르다. 서버 권위만 켜면 플레이 체감이 100배 가까이 바뀐다. `spacetimedb/src/world.rs:141-142`, `spacetimedb/src/world.rs:362-365`, `lib/game/systems/level_system.dart:144-156`
- `WorldPlayer`, `Monster`, `MonsterKill`이 현재 `public`이다. 이는 “모든 테이블 private, 클라이언트는 view만 읽는다”는 프로젝트 원칙과 충돌한다. `spacetimedb/src/world.rs:170-170`, `spacetimedb/src/world.rs:218-264`, `spacetimedb/src/lib.rs:15-16`
- 서버에는 지형 정본이 없다. `teleport_to`도 서버가 지형을 몰라 클라이언트 착지 좌표를 최대 180타일까지 허용한다. 서버 권위 이동 전에 `LevelMap`의 통행·구조물·방화벽 데이터를 Rust로 제공해야 한다. `spacetimedb/src/world.rs:728-766`, `lib/game/level/level_map.dart:169-178`
- Dart 맵은 고정 seed로 생성되지만 Dart `math.Random` 구현을 Rust에서 단순 재현한다고 동일한 지형이 보장되지는 않는다. 정본 바이너리 맵 또는 양 언어가 검증하는 명시적 알고리즘·해시가 필요하다. `lib/game/level/level_map.dart:251-285`
- 30Hz 전역 scheduled reducer가 수천 플레이어·몬스터를 매번 갱신하면 하나의 큰 트랜잭션과 대량 구독 변경이 된다. [판단] 우선 정확성용 전역 틱으로 검증하되, 운영 목표에는 활성 공간 셀별 틱과 AOI가 필요하다. 단, 셀은 부하 파티션이지 월드 인스턴스가 아니어야 한다. `.cowork/cowork-prompt.md:16-20`
- 셀별 scheduled reducer는 경계 PK·발사체·몬스터 추격에서 두 셀이 같은 객체를 갱신할 수 있다. [판단] 객체 소유 셀을 하나로 정하고 경계 피해를 대상 셀의 다음 틱 큐로 넘기거나, 상호작용 셀을 한 트랜잭션으로 묶는 규칙이 필요하다.
- `CombatEvent`는 상태가 아니라 연출 신호다. 재접속·재구독 때 과거 행이 다시 캐시에 들어올 수 있으므로 `tick_id`, `expires_at`, 클라이언트 처리 watermark가 필요하다. `auto_inc` 간격으로 유실 여부를 추론해서도 안 된다. `.cowork/cowork-prompt.md:80-83`
- 현재 generated reducer API는 오프라인 명령 대기를 지원한다. 연결 복구 후 오래된 이동·스킬·포션 명령이 실행되면 사망 후 공격이나 중복 소비가 생길 수 있다. `lib/spacetime/generated/reducers.dart:14-32`
- 현재 연결 해제는 `WorldPlayer`를 즉시 삭제하고 재입장은 중앙에서 완전한 HP로 생성한다. 전투 중 연결 끊기·재접속이 PK와 몬스터 피해 회피 수단이 될 수 있으므로 combat logout 유예와 서버 저장 정책이 필요하다. `spacetimedb/src/lib.rs:207-213`, `spacetimedb/src/world.rs:596-647`
- `rebuild_monsters`는 호출자 제한 없이 모든 공유 몬스터를 삭제한다. 서버 권위 월드에서는 일반 사용자가 호출할 수 없는 운영 경로로 격리해야 한다. `spacetimedb/src/world.rs:471-490`
- 현재 `init`은 `world::bootstrap`만 호출하며, 확인한 `bootstrap`은 몬스터만 삽입한다. schedule table 행을 넣는 코드가 확인되지 않아 새 `WorldTickTimer`는 기존 운영 DB에서 별도이고 멱등적인 활성화 절차가 필요하다. `spacetimedb/src/lib.rs:190-193`, `spacetimedb/src/world.rs:405-459`
- `.cowork`는 플레이어 상한 30과 “몬스터 레벨 없음”을 적고 있지만 실제 서버·클라이언트는 상한 999이며 `Monster.level`을 이미 보유한다. 문서와 배포 코드의 계약 불일치를 정리하지 않으면 HP·스킬 해금·리더보드 마이그레이션 기준이 흔들린다. `.cowork/cowork-prompt.md:68-71`, `spacetimedb/src/leaderboard.rs:37-69`, `spacetimedb/src/world.rs:223-247`
- 배포된 테이블은 새 열을 끝에 추가하고 기본값을 제공해야 한다는 제약이 코드에 명시돼 있다. 큰 구조 변경은 기존 `WorldPlayer` 확장보다 versioned private 테이블과 명시적 backfill이 안전하다. `spacetimedb/src/world.rs:202-209`

## 5. 권고안

| 순위 | 권고 | 범위 | 근거 | 리스크 |
|---|---|---|---|---|
| 1 | 서버 전투 계약을 먼저 고정한다: HP 10,000, 레벨당 HP 성장, defense 공식·반올림, 몬스터 최종 피해, MP/energy, 사망 초기화 규칙을 Rust 정본으로 정의하고 클라이언트는 표시값만 읽게 한다. | 전투 수치·스키마 | `lib/game/entities/player.dart:38-87`, `spacetimedb/src/world.rs:141-142` | 기존 서버 HP·성장 데이터 마이그레이션 필요 |
| 2 | `WorldPlayerState`, 입력·행동 큐, 몬스터 AI, 발사체, 버프, 쿨다운, 인벤토리, 드롭, 이벤트를 모두 private versioned 테이블로 설계한다. | SpacetimeDB 스키마 | `spacetimedb/src/world.rs:166-295`, `spacetimedb/src/lib.rs:15-18` | 행 수와 durable write 증가 |
| 3 | `LevelMap`의 통행·안전지대·방화벽·텔레포트 착지 데이터를 서버 정본으로 옮긴 뒤 `move_to`를 폐기하고 입력 기반 이동·충돌·대시를 구현한다. | 이동·맵 | `spacetimedb/src/world.rs:664-780`, `lib/game/level/level_map.dart:151-178` | 맵 생성 결과가 달라지면 대규모 위치 보정 발생 |
| 4 | scheduled reducer에 결정적 처리 순서를 두고 이동→AI→플레이어 공격/스킬→몬스터 공격→사망/보상→회복을 한 틱 트랜잭션으로 처리한다. | 서버 시뮬레이션 | `~/apps/game/laryen/game-server/zone/internal/sim/sim.go:1103-1188` | 30Hz 전역 트랜잭션 성능은 미검증 |
| 5 | private 상태 위에 본인 view와 공간 셀별 anonymous replica/event view를 만들고, `SELECT * FROM world_player` 전역 구독을 AOI 구독으로 교체한다. | 구독·보안·확장성 | `lib/spacetime/cyborg_connection.dart:34-41`, `.cowork/cowork-prompt.md:78-83` | 셀 전환 시 구독 중첩·이벤트 중복 처리 필요 |
| 6 | `AuthoritativeWorldSession`으로 네트워크 계층을 통합하고 `Player`, `Enemy`, `Projectile`의 gameplay mutation을 제거한다. 자기 이동은 표현용 prediction/reconcile, 원격 객체는 interpolation만 수행한다. | Flutter·Flame 클라이언트 | `lib/game/action_rpg_game.dart:531-546`, `~/apps/game/laryen/GAME-DESIGN.md:195-199` | 보정 계수가 부적절하면 rubber-band 발생 |
| 7 | 서버가 킬·드롭·XP·인벤토리의 유일한 출처가 된 cutover 시점에만 온라인 `report_progress`, `reportDeath`, 로컬 `onEnemyKilled` 보상 경로를 차단한다. | 성장·보상 | `spacetimedb/src/leaderboard.rs:276-287`, `lib/game/action_rpg_game.dart:1225-1267` | 단계 중 두 권위가 동시에 보상을 지급할 위험 |
| 8 | stale/duplicate seq, 벽·안전지대, defense 0 피해, MP 부족, 쿨다운, 동시 막타, PK, 사망·리스폰 원자성, 재접속 이벤트 replay를 서버 테스트로 만들고 1,000명·AOI·틱 p99 부하 검증을 배포 게이트로 둔다. | 테스트·운영 | `test/world_presence_test.dart:46-136`, `spacetimedb/src/world.rs:783-892` | 현재 테스트는 존재·좌표 동기화만 검증함 |
| 9 | `rebuild_monsters`와 scheduler 활성화를 일반 클라이언트 reducer에서 분리하고, 운영 identity 허용 목록 또는 private scheduled 경로로 제한한다. | 운영 보안 | `spacetimedb/src/world.rs:471-496` | 잘못된 권한 설정 시 운영 복구 경로 상실 |

## 6. 불확실 · 미확인

- SpacetimeDB 2.7 maincloud에서 30Hz 전역 scheduled reducer가 실제 몬스터 수와 목표 동접을 감당하는지 확인할 부하 측정 결과가 없다. 30/15Hz 유지 여부와 셀 크기는 측정 후 결정해야 한다.
- 운영 DB의 `monster_tick_timer` 행 존재 여부와 scheduled reducer 실행 로그는 읽지 못했다. 코드상 `init`·`bootstrap`에서 schedule 행 삽입 경로는 확인되지 않는다. `spacetimedb/src/lib.rs:190-193`, `spacetimedb/src/world.rs:288-295`
- 일반화된 스킬 카탈로그는 현재 작업공간에서 확인되지 않았다. 확인된 MP 소비 행동은 plasma 발사이며 dash는 별도 energy를 소비한다. 스킬 대상 방식·시전 취소·캐스팅·장판·파티 효과는 사람의 기획 결정이 필요하다. `lib/game/entities/player.dart:199-245`
- defense 적용 후 최소 피해를 0으로 허용할지 1로 보장할지, 여러 피해 감소 버프의 반올림 순서는 defense 0 규격만으로 결정되지 않는다. `lib/game/entities/player.dart:531-566`
- PK의 선점·킬 크레딧·드롭·사망 페널티·안전지대 경계·전투 로그아웃 시간은 현재 몬스터 규칙만으로 확정할 수 없다. `CLAUDE.md:30-38`
- 접속 종료 후 캐릭터를 즉시 제거할지 일정 시간 공격 가능한 상태로 남길지, HP/MP·위치·쿨다운을 재접속까지 영속할지는 운영 정책 결정이 필요하다. `spacetimedb/src/lib.rs:201-213`
- `.cowork`의 상한 30·몬스터 레벨 부재 설명과 실제 상한 999·`Monster.level` 중 어느 쪽을 최종 계약 문서로 갱신할지 사람의 확인이 필요하다. `.cowork/cowork-prompt.md:68-71`, `spacetimedb/src/leaderboard.rs:37-69`, `spacetimedb/src/world.rs:223-247`
- 읽기 전용 분석 범위이므로 `cargo test`, `flutter test`, `flutter analyze`, maincloud 상태 조회와 배포 검증은 수행하지 않았다.
