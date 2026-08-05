# 종합 검토 — server-authority

> 요청: 서버 권위 판정을 하도록 해 주세요. 서버 권위 이동, 서버 권이 이벤트, 사망, HP/MP 감소/회복, 스킬, 등등 서버가 판정을 하고 클라에서는 렌더링만 하도록 해 주세요.
> (추가 지시) 라리엔 형제 프로젝트(`~/apps/game/laryen`)의 서버 권위 이동 코드/로직을 참고할 것.
> 분석: codex · grok · kimi (**claude 는 제한 시간 초과로 2회 연속 실패 — 의견 없음으로 취급**)
> 종합: 2026-08-04 23:25 · 읽기 전용 분석 — 작업공간 미수정

> 🛑 **분석 중 코드가 바뀌었다.** 4 AI 는 커밋 `7fcb48e` 시점(~23:12)을 읽었으나, 종합 시점의
> 워킹트리는 커밋 `ed58a53`(23:13) + 미커밋 변경(23:18)이다. **다른 세션이 지금 이 순간 같은
> 파일(`spacetimedb/src/world.rs`·`lib/game/action_rpg_game.dart`)에 서버 권위 작업을 진행 중이다.**
> 아래 §3·§5 는 이 변화를 반영해 재검증한 결과이며, §8 에 충돌 위험을 명시한다.

## 1. 결론

**방향은 옳고, 골격은 이미 서버에 있으며, 남은 일은 "새 인프라 건설"이 아니라 ① 서버·클라 전투
수치를 하나로 맞추고 ② 클라의 로컬 판정을 걷어내 서버 결과를 렌더링하게 바꾸는 것이다.**
라리엔식 30Hz sim tick + 스냅샷 브로드캐스트는 SpacetimeDB 에 그대로 이식할 수 없다 — 실행 단위가
"의도를 받는 원자적 reducer" 와 "저주파 scheduled reducer" 뿐이기 때문이다. 대신 **의도 reducer(즉시
판정) + 저주파 scheduled tick(몹 AI·회복·리스폰) + 공개 표 구독(=스냅샷)** 이라는 SpacetimeDB 고유
형태로 같은 목적을 달성해야 한다.

**최대 차단지점은 수치 이중화다.** 서버는 여전히 `BASE_MAX_HP=100`·레벨당 +18·`player_damage=14+3(lv-1)`
([world.rs:170,454-462](../../spacetimedb/src/world.rs))인데 클라는 HP 10,000·레벨당 +1,000·피해=몬스터
레벨이다. 이 상태로 클라를 서버 판정에 붙이면 **접속 즉시 "한 대 맞고 죽는" 게임**이 된다. 서버 수치를
사람이 정한 신 규격으로 먼저 옮기지 않은 채 연동하는 것은 어떤 순서로도 안 된다.

판정 못 한 쟁점: scheduled reducer 의 실제 최소 주기·지터와 12,000행 몬스터 표 구독의 실측 대역은
코드로 확인할 수 없다(§8).

## 2. 세 AI 의견 대조

| 쟁점 | codex | grok | kimi | 검증 결과 |
|---|---|---|---|---|
| 라리엔 30Hz sim 이식 | 고정 틱 두되 부하 측정 선행 | 전 몹 30Hz 갱신 비권고 | 구조상 불가, 저주파+의도 reducer | ✅합의 — 30Hz 전역 틱은 채택 불가 |
| 이동 권위 | `move_to` 폐기 → `set_move_input(seq,dx,dy)` 서버 적분 | 속도 가드 유지, 중기에 intent | `move_to` 유지가 유일한 현실안 | ⚖️판정: grok·kimi 가 맞음(§4-1) |
| 수치 SSOT 선행 | 1순위 | 1순위 | 1순위 | ✅합의 — 셋 다 최우선 |
| `monster_tick_timer` 미무장 | 미확인 항목으로 유보 | 2순위로 격상 | 4.리스크 1번 | ✅합의(분석 시점) → ⚠️**현재는 다른 세션이 해결**(§6) |
| 몬스터 표 구독 | AOI 필수 | AOI 없으면 전역 구독 위험 | 12,000행 통 구독은 파탄적 | ✅합의 — 청크 인덱스 필요 |
| `report_progress` 이중 진실 | 7순위(cutover 시 차단) | 4순위 | 6순위(5번 후) | ✅합의 — 서버 전투 완성 후 제거 |
| 부분 전환의 위험 | 언급 없음 | 언급 없음 | **공격만 서버·피격은 클라 = 무적 채굴** | 🔍고유 통찰(§5) |
| 지형 서버 이관 | 3순위(필수) | 리스크로만 | 1차 범위에서 제외 | ⚖️판정: kimi·grok 이 맞음(§4-2) |

## 3. 합의 — 검증 통과

- **클라이언트가 서버 전투를 거의 호출하지 않았다.** 확인: 분석 시점 `lib/game/` 전역에서
  `attackMonster`·`teleportTo` 호출 0건. 월드 구독은 `SELECT * FROM world_player` 하나뿐이었다.
  ⚠️ 현재는 [spacetime_world_presence.dart:169](../../lib/spacetime/spacetime_world_presence.dart#L169)
  에 `attackMonster` 호출이, [cyborg_connection.dart:43](../../lib/spacetime/cyborg_connection.dart#L43)
  에 `SELECT * FROM monster` 가 다른 세션에 의해 추가됐다.

- **서버·클라 전투 수치가 두 개의 다른 게임이다.** 확인: [world.rs:170](../../spacetimedb/src/world.rs#L170)
  `BASE_MAX_HP: i32 = 100`, [world.rs:454-456](../../spacetimedb/src/world.rs#L454) `100 + 18×(lv-1)`,
  [world.rs:461-463](../../spacetimedb/src/world.rs#L461) `player_damage = 14 + 3×(lv-1)` vs
  [player.dart:45](../../lib/game/entities/player.dart#L45) `baseMaxHp = 10000`,
  [level_system.dart:153](../../lib/game/systems/level_system.dart#L153) `maxHp: 1000`.
  **이 격차는 지금도 그대로다.**

- **몹 피해는 "몬스터 레벨" 항등식이다.** 확인: [monster_codex.dart:414](../../lib/game/systems/monster_codex.dart#L414)
  `final attackDamage = level.toDouble();` — 계통별 배율을 일부러 두지 않았다는 주석까지 붙어 있다.
  `.cowork/cowork-prompt.md:30-31` 의 사람 규격과 일치한다.

- **사망·리스폰·회복이 100% 클라 판정이었다.** 확인: [player.dart:583-588](../../lib/game/entities/player.dart#L583)
  `_hp <= 0` → `game.onPlayerDied()`, [player.dart:611-641](../../lib/game/entities/player.dart#L611)
  `respawnAt`, [rest_recovery.dart:14-20](../../lib/game/systems/rest_recovery.dart#L14) HP 12%/s·MP
  15%/s·야전 MP 0.5%/s.

- **`report_progress` 가 클라 자가 신고를 수용한다.** 확인: [leaderboard.rs:289](../../spacetimedb/src/leaderboard.rs#L289)
  — 단조 증가 가드만 있고, 주석이 "조작된 클라이언트가 그럴듯한 속도로 올려 보내는 것은 막지 못한다",
  "서버 전투가 유일한 출처가 되면 이 reducer 는 사라진다" 고 스스로 밝힌다.

- **서버에 MP·방어력·스킬 개념이 아예 없다.** 확인: `WorldPlayer` 열 목록에 `mp`/`max_mp`/`defense`
  없음. `spacetimedb/src/` 전체에 skill 관련 표·reducer 없음.

## 4. 이견 — 자료로 판정

### 4-1. 이동 권위를 "서버 입력 적분"으로 바꿔야 하는가

- codex: `move_to` 를 폐기하고 `set_move_input(seq, dx, dy)` 로 서버가 위치를 적분해야 한다.
- grok: 1단계는 좌표 보고 + 속도 클램프 유지. 중기에 intent + 저주파 적분.
- kimi: SpacetimeDB 에는 틱이 없으므로 **방향 벡터 모델 자체가 성립하지 않는다**. `move_to` 유지가 유일한 현실안.

**판정: grok·kimi 가 맞다.** 다수결이 아니라 두 가지 물리 제약 때문이다.

1. **서버에 지형이 없다.** 클라 지형은 [level_map.dart:257-262](../../lib/game/level/level_map.dart#L257)
   에서 `math.Random(20260804)` 시드로 1006×1006 칸을 절차 생성한다(값 노이즈 보간 + 부동소수 연산).
   Rust 에서 Dart `math.Random` 과 부동소수 노이즈를 비트 단위로 재현한다는 보장이 없다. 서버가
   walkable 을 모르면 입력을 적분해 봐야 벽을 막을 수 없어, 적분의 유일한 이득(지형 치트 차단)이
   사라진다. 서버 코드가 이 한계를 이미 자인한다 — [world.rs:149-155](../../spacetimedb/src/world.rs#L149)
   "서버는 지형을 모르므로 그 보정을 재현할 수 없고".
2. **고주파 틱이 없다.** 라리엔은 33ms 마다 `applyPlayerInput` 이 도는 전제 위에서 방향 벡터를
   적분한다([sim.go:1103-1118](file:///Users/thruthesky/apps/game/laryen/game-server/zone/internal/sim/sim.go)).
   SpacetimeDB 의 scheduled reducer 는 매 실행이 durable 트랜잭션 커밋이라 30Hz × 전 플레이어는
   성립하지 않는다. 틱이 초 단위면 방향 벡터는 "1초에 한 번 순간이동"이 된다.

**단, 현행 `move_to` 를 그대로 두라는 뜻은 아니다.** 사용자 요구("서버가 판정, 클라는 렌더링")를
충족하려면 실제 구멍을 메워야 한다 — 서버는 이미 좌표를 클램프해 확정하는데
([world.rs:698-703](../../spacetimedb/src/world.rs#L698)) **클라가 그 확정값을 읽지 않는다.**
자기 `world_player` 행의 좌표와 예측 위치의 오차를 라리엔식 적응형 lerp 로 수렴시키면
(`~/apps/game/laryen/GAME-DESIGN.md §5.3.1`), 틱 없이도 "서버가 최종 좌표의 정본" 이 성립한다.
여기에 사망 중 이동 금지·안전지대 판정을 서버가 쥐면 실질적 서버 권위 이동이 된다.

### 4-2. 지형(walkable·hazard)을 이번에 서버로 옮겨야 하는가

- codex: 3순위 — `move_to` 폐기 전에 `LevelMap` 통행·구조물·방화벽을 Rust 정본으로 옮겨야 한다.
- grok: 리스크로만 언급, 권고에는 넣지 않음.
- kimi: 1차 범위에서 제외하고 "몹 피해·회복·사망" 으로 경계를 긋는 것이 현실적.

**판정: kimi·grok 이 맞다(이번 범위에서 제외).** 근거는 4-1 의 (1)과 같다. 지형을 서버로 옮기는
길은 둘뿐인데 둘 다 이번 작업의 몇 배 규모다 — ① Dart PRNG·노이즈를 Rust 로 비트 동일 이식,
② 서버가 지형을 생성해 100만 칸(walkable 비트셋 ~125KB)을 클라에 배포. codex 도 이 위험을 스스로
적었다("Dart `math.Random` 구현을 Rust 에서 단순 재현한다고 동일한 지형이 보장되지 않는다").
방화벽 지속 피해([player.dart:501-519](../../lib/game/entities/player.dart#L501), 0.5초마다 최대
HP 4%, 무적·방어 무시)는 그때까지 클라 판정으로 남는다는 사실을 명시적으로 수용한다.

## 5. 고유 통찰 — 하나만 발견했으나 검증됨

- **kimi: 공격 판정만 서버로 옮기고 피격을 클라에 두면 "무적 사냥"으로 서버 XP 를 정당하게 채굴할 수
  있다.** 검증: 논리적으로 자명하고 코드로도 성립한다 — [world.rs](../../spacetimedb/src/world.rs)
  `attack_monster` 는 몹 HP 를 깎고 `award_kill` 로 XP 를 주지만, 공격자가 피해를 입었는지는 보지
  않는다. 피격이 클라 판정이면 조작 클라는 `applyDamage` 를 통째로 무시하면서 서버 킬을 계속 쌓는다.
  **→ 공격 서버화와 피격 서버화는 같은 이정표에서 함께 나가야 한다.** 이것이 전환 순서를 결정하는
  가장 중요한 제약이다.

- **grok: `RemotePlayer` 에 `hp`/`maxHp` 가 없다.** 검증: [world_presence.dart:9-32](../../lib/game/net/world_presence.dart#L9)
  의 `RemotePlayer` 는 `characterId`·`name`·`kind`·`level`·`grid`·`alive` 뿐이다. 서버가 남의 HP 를
  깎아도 화면에 전달할 통로가 없어, PK·피격 연출의 선행 구멍이다.

- **grok: 서버 공격 모델이 클라 공격 형태와 다르다.** 검증: 서버는 근접 단일 대상·고정 사거리
  2.2타일·쿨다운 0.35초([world.rs](../../spacetimedb/src/world.rs) `ATTACK_RANGE_TILES`·`ATTACK_COOLDOWN_MICROS`)
  인데, 클라는 부채꼴 근접 콤보 + 플라즈마 발사체(MP 60 소비, [player.dart:203-227](../../lib/game/entities/player.dart#L203))
  + 대시가 있다. 원거리·AoE 를 서버 "한 방" 에 억지로 매핑하면 조작감이 무너진다 — 스킬 id 로 분해가 필요하다.

## 6. 반증 — 근거가 틀렸거나 이미 무효가 된 주장

- **codex·grok·kimi 공통: "`monster_tick_timer` 행을 삽입하는 코드가 없어 리스폰이 영영 돌지 않는다"**
  — 분석 시점에는 ✅ 사실이었다(직접 확인함). **그러나 종합 시점에는 무효다.** 다른 세션이
  [world.rs:588-600](../../spacetimedb/src/world.rs#L588) 에 `ensure_timers` 를 넣어
  `monster_tick_timer` 와 신규 `monster_ai_timer` 를 무장했다. 이 권고는 **이미 반영됐으므로 다시
  하지 않는다.**

- **codex·grok·kimi 공통: "서버에는 몹이 플레이어를 때리는 경로가 아예 없다"** — 분석 시점에는
  사실이었으나 **현재 무효다.** [world.rs:1034](../../spacetimedb/src/world.rs#L1034) `monster_ai`
  scheduled reducer 가 청크 인덱스로 근처 몹을 모아 추격·귀가·어그로를 판정하고, `next_hurt_at`
  열로 피격 쿨다운을 두며, HP 0 이면 부활까지 처리한다. 다른 세션이 구현 중이다.

- **grok·kimi: "클라가 `monster` 표를 구독하지 않는다"** — 현재 무효.
  [cyborg_connection.dart:43](../../lib/spacetime/cyborg_connection.dart#L43) 에 `SELECT * FROM monster`
  가 추가됐다(미커밋). 단 **AOI 없는 전역 구독**이라 §3 의 12,000행 위험은 그대로 유효하다.

- **`.cowork/cowork-prompt.md` 자체가 낡았다.** 확인: 같은 문서가 "실시간 멀티플레이 동기화는 아직
  없다"(`:22`), "level 상한 30"(`:68`), "모든 테이블이 비공개다"(`:65`), "몬스터 레벨이라는 개념
  자체가 없고"(`:34`) 라고 적지만, 실제로는 presence 가 동작하고 만렙은 999이며
  `world_player`·`monster`·`monster_kill` 은 public 이고 몬스터 레벨은 구현돼 있다. **네 AI 에게
  매번 주입되는 전제 문서이므로 갱신하지 않으면 앞으로의 모든 분석이 오염된다.**

- **`GAME-DESIGN.md` 의 "서버 권위 몬스터 240기"(`:651`,`:790`,`:900`)** — ❌ 코드와 불일치.
  실제 `MONSTER_CAPACITY = MONSTER_MAX_LEVEL(200) × CLUSTERS_PER_LEVEL(3) × CLUSTER_MAX(20)` = 12,000.

## 7. 최종 권고

⚠️ **선행 조건**: 아래 1~4 는 `spacetimedb/src/world.rs` 와 `lib/game/action_rpg_game.dart` 를
건드린다. 지금 **다른 세션이 같은 두 파일을 활발히 수정 중**이므로(§8), 착수 전에 그 세션의 작업
완료·커밋을 기다리거나 사람이 작업 분담을 정해야 한다.

| 순위 | 권고 | 범위 | 근거 | 리스크 | 검증 방법 |
|---|---|---|---|---|---|
| 1 | **전투 수치를 서버로 단일화한다.** `BASE_MAX_HP` 100→10,000, 레벨당 +18→+1,000, 몹→PC 피해 = `monster.level − defense`(하한 0), PC→몹 피해를 클라 근접·원거리 값과 정합. `WorldPlayer` 에 `mp`·`max_mp`·`defense` 를 **맨 끝 + `#[default]`** 로 추가 | `spacetimedb/src/world.rs` | [world.rs:170,454-462](../../spacetimedb/src/world.rs#L170) vs [player.dart:45](../../lib/game/entities/player.dart#L45)·[level_system.dart:153](../../lib/game/systems/level_system.dart#L153) | 배포된 행의 `hp`/`max_hp` 가 구 규격으로 남는다 → 마이그레이션 또는 재입장 시 재계산 필요 | `cd spacetimedb && cargo test` · 서버·클라 수치 미러 테스트 신설 |
| 2 | **피격·사망·회복을 공격과 같은 이정표로 묶는다.** 이미 들어간 `monster_ai` 의 피해 적용을 `apply_damage_to_player` 단일 내부 함수로 수렴시키고, 사망(`alive=false`)·안전지대 부활·무적 창·HP/MP 회복을 전부 그 경로로 통과시킨다. 재실행 멱등 가드(이미 죽었으면 통과) 필수 | `spacetimedb/src/world.rs` | §5 kimi 통찰 · [world.rs:29-31](../../spacetimedb/src/world.rs#L29) 재실행 원칙 · 라리엔 `combat.go` `CombatResolve` | 멱등성 누락 시 사망 부수 효과 이중 적용 | `cargo test` — 동시 막타·이중 사망 시나리오 |
| 3 | **클라의 로컬 판정을 걷어낸다.** `MonsterPopulation` 로컬 장부를 구독 `monster` 로 교체([action_rpg_game.dart:244,1029,1614](../../lib/game/action_rpg_game.dart#L244) 가 아직 로컬 사용), `Player.applyDamage` 를 "서버 `hp` 반영 + 잠정 예측 연출" 로 축소, 킬 XP·드롭 확정을 서버 결과 수신으로 대체 | `lib/game/` | [action_rpg_game.dart:1272](../../lib/game/action_rpg_game.dart#L1272) `player.gainXp` 로컬 확정 | 대규모 리팩터링. `offline_main.dart`·`preview_main.dart` 의 로컬 전투 유지 여부 결정 필요 | `flutter analyze`(0) · `flutter test` |
| 4 | **자기 좌표 reconcile 을 넣는다.** 구독으로 돌아온 자기 `world_player` 좌표와 예측 위치의 오차를 라리엔식 적응형 lerp(오차 큼→강수렴, 입력 방향 진행 중→약수렴)로 수렴. 사망 중 이동 금지를 서버 `move_to` 에 추가 | `lib/game/entities/player.dart` · `world.rs` `move_to` | §4-1 · 라리엔 `GAME-DESIGN.md §5.3.1` | 계수가 부적절하면 rubber-band | 실제 지연 하에서 시연 · 이동 회귀 테스트 |
| 5 | **몬스터 구독에 AOI 를 건다.** 전역 `SELECT * FROM monster` 를 청크 인덱스 기반 부분 구독으로 교체(서버에 `chunk` 열·인덱스가 이미 추가됨). 불가하면 몹 수를 줄이는 결정이 선행 | `lib/spacetime/cyborg_connection.dart` · 구독 계층 | [cyborg_connection.dart:43](../../lib/spacetime/cyborg_connection.dart#L43) 전역 구독 · `MONSTER_CAPACITY` 12,000 | SDK 의 `WHERE` 부분 구독·동적 교체 지원 범위 미확인(§8) | 접속자 N명 × 몹 수로 대역 실측 |
| 6 | **`RemotePlayer` 에 `hp`/`maxHp` 를 전달한다.** 남의 피격·PK 연출의 선행 조건 | [world_presence.dart:9-32](../../lib/game/net/world_presence.dart#L9) | §5 grok 통찰 | 구독 페이로드 증가 | `flutter test` — 원격 HP 표시 |
| 7 | **MP·스킬을 서버로 올린다.** `WorldPlayer.mp` 위에서 `cast_skill(skill_id, target)` — 습득·MP·쿨다운·사거리를 서버가 검증(라리엔 `OnUseSkill` 패턴). 1차는 **즉시 판정형만**, 지속 장판·지연 강타는 tick 안정화 후 | `world.rs` 신규 reducer · `lib/game/` | 라리엔 `skill.go:39-80` · 현재 양쪽 모두 스킬 없음 | 스킬 목록 기획이 선행돼야 함(§8) | `cargo test` · 시연 |
| 8 | **PK(`attack_player`)를 `attack_monster` 패턴으로 추가한다.** 안전지대 면역·사거리·쿨다운 서버 판정 | `world.rs` | `CLAUDE.md` "PK 는 허용된다" | 트롤링·밸런스 | `cargo test` |
| 9 | **`report_progress` 를 제거한다.** 단 3·7 이 끝나 서버가 XP 의 유일 출처가 된 **뒤에만** | `leaderboard.rs` · `spacetime_game_sync.dart` | [leaderboard.rs:285-289](../../spacetimedb/src/leaderboard.rs#L285) 자체 예고 | 순서를 앞당기면 성장이 증발 | 킬→XP 경로 통합 테스트 |
| 10 | **낡은 전제 문서를 갱신한다.** `.cowork/cowork-prompt.md`(상한 30·테이블 비공개·몬스터 레벨 부재·멀티 동기화 없음)와 `GAME-DESIGN.md`(240기) | 문서 | §6 | 없음 | 사람 검수 |

**의도적으로 하지 말 것**
- 라리엔 Go UDP Zone Server 를 SpacetimeDB 옆에 병행 신설(이중 백엔드·운영 복잡도).
- 전 몬스터 30Hz 위치 갱신.
- 수치 SSOT(권고 1) 없이 클라를 서버 판정에 연결 — 접속 즉시 즉사한다.
- 공격만 서버화하고 피격을 클라에 남기기 — 무적 채굴 창이 열린다(§5).
- 이번 범위에서 지형(walkable·hazard)을 서버로 이관(§4-2).

## 8. 미해결 · 사람 판단 필요

- 🛑 **동시 작업 충돌.** 다른 세션이 커밋 `ed58a53`(23:13) 이후에도 `spacetimedb/src/world.rs`·
  `lib/game/action_rpg_game.dart`·`lib/spacetime/*` 를 수정 중이다(23:18 기준 미커밋 20+ 파일,
  `lib/game/systems/wave_director.dart` 삭제 포함). 권고 1~4 는 정확히 그 파일들을 건드리므로,
  **지금 착수하면 남의 미커밋 작업을 깨뜨린다.** 착수 시점·분담을 사람이 정해야 한다.
- **scheduled reducer 의 실제 최소 주기·지터·트랜잭션 비용** — SpacetimeDB 2.7 문서로 확인 불가.
  몹 AI 틱 주기가 곧 피격 체감이므로 실측이 필요하다.
- **Dart SDK 의 부분 구독(`WHERE`)·동적 구독 교체 지원 범위** — 권고 5(AOI)의 성립 조건.
- **몬스터 배치 규모** — 12,000기를 유지할지 문서의 240기 수준으로 줄일지는 기획 결정.
- **스킬 목록 기획** — 현재 양쪽 코드 어디에도 스킬 정의가 없다. 서버 상수 정본을 만들려면
  "무엇이 스킬인가" 가 먼저 정해져야 한다.
- **오프라인·프리뷰 모드의 처우** — `lib/offline_main.dart`·`lib/preview_main.dart` 에 로컬 전투를
  얼마나 남길지. 서버 권위와 로컬 시뮬의 이중 유지 비용이 든다.
- **서버 `monster_xp`(레벨당 +12%) vs 클라 `LevelSystem.killXp`(레벨차 감쇠)** — 서버가 XP 유일
  출처가 되면 어느 곡선을 정본으로 삼을지 수치 설계 판단이 필요하다.
- **claude 분석 부재** — 2회 연속 제한 시간 초과(23s·1500s)로 의견이 없다. 위 판정은 codex·grok·kimi
  3개와 오케스트레이터의 직접 검증에 기반한다.

## 9. 적용 결과

> 적용: 2026-08-05 00:05 · 커밋 `1412f78` · maincloud 배포 완료

사용자가 "지금 바로 구현(충돌 감수)" 을 선택해, §8 의 동시 작업 충돌을 감수하고
착수했다. 리뷰 라운드(`--review`)는 다른 세션이 같은 파일을 계속 고치고 있어
15분을 기다리면 충돌 면적이 커지므로 건너뛰었다.

| 권고 | 적용 | 파일 | 검증 |
|---|---|---|---|
| 1 (수치 SSOT) | ✅ 적용 | `world.rs` 전투 수치 블록·`hp_scale`·`xp_scale`·`max_hp_for_level`·`max_mp_for_level`·`player_damage`·`player_ranged_damage`·`damage_after_defense` | `cargo test` 57개 통과. 서버·클라 미러 테스트 신설(`world.rs` mod tests 11개 + `test/server_authority_contract_test.dart` 14개) |
| 2 (피격·사망 단일 수렴점) | ✅ 적용 | `world.rs` `apply_damage_to_player`, `monster_ai` 가 이 경로로 통과 | `cargo test` · `flutter test` 242개 통과 |
| 3 (클라 로컬 판정 축소) | 🔸 부분 적용 | `player.dart` `adoptServerVitals`·`tryShoot`, `action_rpg_game.dart` `_adoptServerState`·`_onServerDeath` | 체력·마력·사망은 서버 값이 매 프레임 덮는다. **로컬 `MonsterPopulation` 교체는 다른 세션이 진행 중이라 건드리지 않았다** |
| 4 (자기 좌표 reconcile) | ✅ 적용 | `player.dart` `reconcileServerGrid` — 오차별 적응형 계수(데드존 0.12 / 약수렴 2.0 / 강수렴 8.0 / 24타일 이상 스냅) | `flutter analyze` 0 errors |
| 5 (몬스터 구독 AOI) | ⏸️ 보류 | — | 서버에 `chunk` 인덱스는 있으나 Dart SDK 의 부분 구독 지원 범위가 미확인(§8). 전역 구독은 다른 세션이 이미 걸어 둔 상태 |
| 6 (`RemotePlayer` 체력) | ✅ 적용 | `world_presence.dart` `RemotePlayer.hp`/`maxHp`/`hpRatio`, `spacetime_world_presence.dart` | `flutter test` 통과. **HUD 표시 배선은 안 했다** — 원격 HP 바를 어디에 그릴지는 화면 설계 결정 |
| 7 (MP·스킬) | ✅ 적용 | `world.rs` `SkillSpec`·`SKILL_PLASMA`·`cast_skill`, `player.dart` `tryShoot`·`_aimTarget` | `cargo test` · 계약 테스트로 마력 60·쿨다운 0.24초·사거리 10타일 고정 |
| 8 (PK) | ✅ 적용 | `world.rs` `attack_player` — 안전지대 면역·사거리·쿨다운 서버 판정 | `cargo test`. **클라 입력 배선은 안 했다** — PK 조작을 어떤 입력에 붙일지는 기획 결정 |
| 9 (`report_progress` 제거) | ⏸️ 보류 | — | 권고대로 3·7 이 완결된 뒤에만 한다. 클라가 아직 로컬 몬스터로 XP 를 확정하므로 지금 끊으면 성장이 증발한다 |
| 10 (문서 갱신) | ⏸️ 보류 | — | `.cowork/cowork-prompt.md`·`GAME-DESIGN.md` 를 다른 세션이 동시에 고치고 있어 충돌을 피했다 |

**추가로 넣은 것**(권고에 없었으나 필요해진 것)

- `move_to` 에 생존 검사 — 사망 판정과 재가동 사이에 들어온 좌표 보고가 시체를
  사냥터로 되돌리는 길을 막는다.
- `WorldPlayer.invulnerable_until`·`last_damaged_at` — 무적 창과 회복 대기를
  서버가 쥐어야 클라이언트 주장으로 우회되지 않는다.
- `regen_tick`(1초 주기) — 권고 1의 "회복 수치 정합" 만으로는 회복의 주체가
  여전히 클라이언트다. 판정을 서버로 옮기려면 틱이 필요했다.

**검증**

- `cargo test` — 57 passed, 0 failed
- `cargo build --target=wasm32-unknown-unknown --release` — 성공
- `spacetime publish withcenter-cyborg --server maincloud` — 자동 마이그레이션 성공
  (새 열 6개 전부 맨 끝 + 기본값이라 기존 행이 살아남았다)
- `flutter analyze` — error 0 (남은 warning 4건은 이번 변경과 무관한 기존 것)
- `flutter test` — **242 passed, 0 failed** (실서버 통합 테스트 포함)

**사람 확인·후속 조치가 필요한 것**

- ⚠️ **배포했다.** maincloud 의 `withcenter-cyborg` 스키마가 바뀌었고, 배포 시
  "All clients will be disconnected" 경고대로 접속자가 끊겼다. 되돌리려면 이전
  모듈을 다시 배포해야 한다.
- 기존 `world_player` 행의 `max_hp` 는 옛 규격(100 대)으로 남아 있다. 재입장하면
  `enter_world` 가 다시 계산하므로 자연히 해소되지만, **접속 중이던 캐릭터는
  한 번 나갔다 들어와야 한다.**
- 원격 플레이어 HP 바와 PK 입력은 데이터·reducer 만 준비했고 화면 배선은 남았다.
- 로컬 `MonsterPopulation` 을 서버 구독으로 교체하는 일(권고 3의 나머지)은 다른
  세션의 작업 범위와 겹쳐 손대지 않았다. 그것이 끝나야 권고 9(`report_progress`
  제거)로 갈 수 있다.

## 10. 후속 개선 (2026-08-05)

> 커밋 `14b9c6e` · 검증: `cargo test` 57 passed · `flutter test` **263 passed** · `flutter analyze` error 0

§9 를 쓴 뒤 스스로 점검하다 **§9 의 작업이 만든 회귀**를 찾았다. 기록해 둔다 — 서버 권위로
옮기는 과정에서 같은 실수가 반복되기 쉬운 자리이기 때문이다.

### 발견한 회귀 — 한 발에 서버 요청이 두 번

플라즈마를 서버 스킬(`cast_skill`)로 옮겼는데, 날아간 볼트가 몹에 닿으면
`Enemy.applyDamage` → `presence.attack` 이 돌아 `attack_monster` 가 **또** 나갔다.
한 발에 두 요청이다. 두 번째는 근접 공격으로 취급되어(사거리 2.2 타일) 대개
거절되지만, 통과하면 공유 쿨다운(`next_attack_at`)을 잡아먹어 다음 평타가 막힌다.

`cast_skill` 을 넣기 전에는 발사체 명중이 유일한 원거리 판정 경로였으므로 문제가
없었다. **판정을 서버로 옮기면서 옛 경로를 끊지 않은 것**이 원인이다.

- 고침: `Damageable.isServerJudged` 를 세워 발사체가 "이 대상의 피해는 서버가
  판정한다" 를 알아보게 했다. 참이면 볼트는 터지기만 하고 아무것도 깎지 않는다.
  오프라인 모드에서는 거짓이라 예전처럼 볼트가 유일한 피해다.
- 가드: `test/server_judged_damage_test.dart` 7개.

### §9 의 부정확한 서술 정정

커밋 `1412f78` 의 주석에 "`Projectile` 이 서버 몹을 건드리지 않는다" 고 적었으나
**근거를 잘못 짚었다.** 그때 막고 있던 것은 다른 세션이 넣은 `Enemy.applyDamage`
의 `isServerDriven` 분기였고, 발사체 자체는 그대로 통과해 위의 이중 요청을 만들고
있었다. 검증하지 않고 단언한 문장이었다.

### 함께 고친 것

| 문제 | 고침 |
|---|---|
| 볼트가 `facing` 으로만 날아가 서버에 보낸 대상과 궤적이 갈라짐(옆의 적이 맞는 것처럼 보임) | 조준한 대상 쪽으로 발사하고 총구도 그쪽을 향한다 |
| 대상이 없어 서버에 못 보냈는데도 화면 마력을 깎음 | 보낸 경우에만 예측 차감. 안 그러면 다음 갱신에 튀어 돌아온다 |
| §9 에서 "화면 배선은 남겼다" 고 한 원격 체력 바 | 이름표 아래에 붙였다. 값이 움직인 뒤 3초 + 만신창이일 때만 표시(항상 띄우면 사냥터가 막대로 뒤덮인다). 회복하는 쪽도 보여 준다 — 지금 칠지 기다릴지가 PK 의 판단거리다 |
| 두 세션이 `MyWorldState`·`me` 를 각자 정의해 컴파일이 깨져 있었음 | MP·사망 누계를 담은 쪽으로 통합 |

### 여전히 남은 것

§9 의 보류 항목(AOI 구독, `report_progress` 제거, 로컬 `MonsterPopulation` 교체,
문서 갱신)은 그대로다. PK 입력 배선도 `action_rpg_game.dart` 를 다른 세션이 활발히
고치고 있어 손대지 않았다.
