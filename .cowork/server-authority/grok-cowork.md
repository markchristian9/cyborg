<!-- cowork:grok | 2026-08-05 19:35:08 | exit=0 | 645s -->
# grok 분석 — server-authority

> 요청: 서버 판정, 서버 권위 이동, 클라이언트 보간, pc 별 이벤트/액션/스킬/타격/사망/HP/MP 공유 등이 올바로 동작하는지 확인하고 수정/보완 할 내용이 있으면 수정 보완해주세요. 특히 -> 여러 플레이어 화면에 다른 pc 들의 이동, 몬스터 이동, 스킬 사용, 공격, 피격, 사망, 공격 모션/애니메이션, 스킬 애니메이션, 총알/레이저/미사일 등이 날라가는 장면돈 여러 플레이어 화면에 동일한 애니메이션/이벤트공유/서버가 클라로 이벤트전송/클라화면에서 여러 pc 화면에도 동일하게 보이는 것이 잘 동작하는지 분석하고 수정/보완해주세요.
> 생성: 2026-08-05 19:35:08 · 소요 645s · 읽기 전용 분석(작업공간 미수정)

---



## 1. 결론 요약

**서버 권위 상태 동기화(좌표·HP·MP·선점·킬 크레딧·전리품·사망 누계)는 코드·통합 테스트 기준으로 동작한다.** 다른 PC 이동/스윙 힌트, 서버 몹 위치·HP, 내 vitals 채택이 그 뼈대다.  
**요청하신 “여러 화면에 동일 애니메이션·발사체 궤적·몹 공격 모션·피격 숫자”는 설계상 미구현이다.** 사건은 CombatEvent 스트림이 아니라 `last_attack_at`·HP·`deaths` 같은 **상태 델타**로만 전달되고, 클라 연출 계층이 그중 일부만 재생한다.  
**우선 보완은 (1) 서버 몹 `alive→false` 사망 연출·시체 제거, (2) 서버 XP/레벨→내 Player/HUD 반영, (3) PK 입력 배선, (4) 온라인 로컬 hazard/사망 경로 격리, (5) `last_damaged_at` 기반 피격 연출·원격 스킬 VFX** 이다. 문서(`GAME-DESIGN` §13, cowork-prompt)는 코드보다 뒤처져 있다.

---

## 2. 근거

- `spacetimedb/src/world.rs:1466-1549` — `attack_monster`: 쿨다운·사거리·선점·피해·킬 서버 판정. `last_attack_at`/`attack_dir_*`/`attack_skill` 기록.
- `spacetimedb/src/world.rs:1612-1698` — `cast_skill`(plasma): MP·쿨다운·사거리·원거리 피해 서버 즉시 판정. 발사체 물리 없음.
- `spacetimedb/src/world.rs:1711+` — `attack_player` PK reducer 존재(안전지대·사거리·쿨다운은 `apply_damage_to_player` 경로).
- `spacetimedb/src/world.rs:1766-1952` — `monster_ai`(150ms): 이동·근접 피해(레벨 합산) 서버 전담. 클라 AI와 분리.
- `spacetimedb/src/world.rs:2248-2305` — `apply_damage_to_player`: 사망 시 안전지대 재가동, `deaths++`, `sub_chunk` 갱신, `last_damaged_at` 기록.
- `spacetimedb/src/world.rs:127-128, 2183-2207` — 시체 20초(`RESPAWN_MICROS`) 후 `monster_tick` 리스폰.
- `lib/spacetime/cyborg_connection.dart:82-110` — AOI 3×3: `world_player`·`monster`·`loot`.
- `lib/spacetime/spacetime_world_presence.dart:30, 155-194, 329-352` — `move_to` 200ms 스로틀, `attack`/`castSkill`/`attackPlayer` fire-and-forget.
- `lib/game/action_rpg_game.dart:615-673, 1255-1317, 1411-1414, 1693-1720` — `_adoptServerState`/`_onServerDeath`, 서버 몹 스트리밍, melee에 RemotePlayer 없음, 서버 킬 시 XP·드롭 로컬 스킵.
- `lib/game/entities/enemy.dart:141-164, 180, 247-250, 535-542, 583-600, 605+` — `applyServerState`는 HP 감소 시 `_hitFlash`만; `alive:false`→`_die()` 없음; 서버 몹은 AI/사격 없음; `render`는 `isAlive` 무시.
- `lib/game/entities/remote_player.dart:153-176, 255-325` — 보간 + `lastAttackAt` 스윙 호. 발사체 스폰 없음(plasma는 호 색만).
- `lib/game/entities/player.dart:234-284, 598-615, 641-695, 791-801` — 플라즈마 의도+로컬 연출 탄; hazard는 로컬 `applyDamage`; `adoptServerVitals`는 HP/MP만 조용히 덮어씀.
- `lib/game/net/spacetime_game_sync.dart:56-62` · `leaderboard.rs:286-311` — 클라→서버 `report_progress` 단방향; 서버 킬 XP는 `award_kill`만.
- `lib/main.dart:86-95` — 온라인 시 presence·sync 주입.
- `test/attack_and_loot_sync_test.dart:99-172` — 관찰자 캐시에 공격자 `lastAttackAt` 동일 도착 검증.
- `GAME-DESIGN.md:788-809` — “클라 미사용/원격 미구현/PK 미구현” 서술 → **현재 코드와 불일치**(PK는 서버만 있고 입력 미배선).
- `GAME-SERVER.md:310-318` — CombatEvent insert-즉시-delete 함정; `deaths` 방식 권장.

---

## 3. 상세 분석

### 3.1 권위 경계 (무엇이 “진실”인가)

| 축 | 권위 | 경로 |
|---|---|---|
| 다른 PC 좌표·facing | 서버 `WorldPlayer` (클라 보고 + 속도 캡) | `move_to` ← `presence.report` |
| 몬스터 좌표·HP·생사·태그 | 서버 `Monster` + `monster_ai` | 구독 → `ServerMonster` → `Enemy.applyServerState` |
| 플레이어→몹 피해 | 서버 reducer | `attack_monster` / `cast_skill` |
| 몹→플레이어 피해 | 서버 `monster_ai` → `apply_damage_to_player` | HP 델타 구독 |
| PK | 서버 `attack_player` | **클라 입력 호출 0건**(테스트·stub 제외) |
| 전리품 | 서버 `Loot` + `pick_loot` | `_syncServerLoot` |
| 성장 XP(서버 킬) | `award_kill` → `PlayerCharacter.total_xp` (+ `world_player.level`/`max_hp`) | **내 Player/HUD 반영 끊김** |
| 성장 XP(신고) | 클라 `report_progress` | 단조 증가만 채택, 완만 인플 가능 |
| 발사체·스킬 궤적 | **로컬 전용** | 관찰자 공유 안 됨 |
| 이동 보간 | 클라 | `RemotePlayerEntity` / `Enemy._followServer` |

이동은 서버 시뮬이 아니라 **클라 좌표 + `MAX_MOVE_SPEED=14` 캡** (`world.rs:174, 1314-1343` 근처).

`lib.rs` 머리말 “모든 테이블 비공개”와 달리 `world_player`/`monster`/`loot` 등은 **`public` 테이블** (`world.rs:275-277` 등). MMORPG 공유 상태를 view-only로만 읽는 모델이 아니라 **공개 표 구독**이다. 설계 원칙 문서와 구현이 어긋난 지점.

### 3.2 잘 되는 것 (다수 화면 “상태” 공유)

1. **다른 PC 존재·이동·방향** — 청크 구독 + 200ms 보고 + 시간 보간. 통합 테스트가 상호 가시·회전·공격 시각 공유를 검증.
2. **몬스터 공유 상태** — 온라인 몹 `serverId`, 로컬 AI 비활성, HP/위치는 서버 스냅샷. A가 깎은 HP를 B가 봄.
3. **내 전투 의도** — 평타/스킬은 “의도만 전송”. 연출 탄이 서버 몹에 닿아도 `isServerJudged`로 재공격 없음.
4. **플레이어 사망 사건** — `alive` 찰나를 믿지 않고 `deaths` 증가로 `_onServerDeath` (`action_rpg_game.dart:626-631, 644-673`). GAME-SERVER §6.5 함정을 피하는 방식.
5. **AOI** — 면적 3×3 + 표시 상한 50. 인원 SQL 상한을 클라에서 우회.
6. **몹 피격 플래시** — `hpRatio` 감소 시 `_hitFlash` (`enemy.dart:155-159`). “아무 연출도 없다”는 과장이다. **없는 것은 사망 폭발·공격 모션·데미지 숫자·적 탄막**.

### 3.3 깨지거나 빈 것 (요청: 애니메이션/이벤트 동일 공유)

#### A. 원격 PC 전투 연출 불완전

- 공유: `last_attack_at`, 방향, `attack_skill`(0/1), HP 바.
- 미공유: 플라즈마 볼트 비행 궤적(공격자만 `spawnProjectile`), 히트 스파크·카메라 쉐이크·콤보 단계.
- 결과: “A가 쏘는 레이저를 B도 같은 궤적으로 본다” **미구현**. 서버 즉시 거리 판정 설계와 연출 요구가 충돌.

#### B. 몬스터 이동은 공유, 공격 연출은 없음

- 서버 구동 몹 `update`는 `_followServer`만 → 공격 telegraph/strike/발사 없음.
- 피해는 HP만 감소. 관찰자·본인 모두 **몹이 때리는 모션 없이 HP만 줄어듦**.
- 내 피격 숫자: `applyDamage`에만 `DamageText`. `adoptServerVitals`는 덮어쓰기만 → **서버 피격 시 팝업/히트스톱 없음**.
- 서버에 **`last_damaged_at`이 이미 있음** (`world.rs:2277-2278`, 생성 코드 `WorldPlayer.lastDamagedAt`). 그런데 `MyWorldState`/`presence.me`가 노출하지 않음 (`world_presence.dart:87-112`, `spacetime_world_presence.dart:372-383`) → 연출 힌트 필드가 버려짐.

#### C. 서버 몹 사망 연출 단절 (핵심 버그)

- 로컬 `_die()`만 Explosion + `onEnemyKilled` + `removeFromParent` (`enemy.dart:583-600`).
- `applyServerState(alive:false)`는 `_serverAlive=false`만 (`141-164`). **`_die()` 미호출**.
- `isAlive`는 false가 되어 타겟팅·자동사냥 `aliveOf`에서는 제외됨 (`enemy.dart:180`, `auto_hunt.dart:278-279`) → “안 죽는다”보다 **시체가 서 있고 킬 스코어/폭발이 없는** 문제에 가깝다.
- `render`는 `isAlive`를 보지 않고 본체 계속 그림 (`605+`).
- `_refreshMonsterStreaming`은 기존 엔티티에 갱신만; 새 생성만 `!alive` skip (`1273-1285`).
- 리스폰 20초 동안 시체 잔존 가능 → 그 사이 “몹이 안 죽었다”로 오인 가능.

#### D. PK: 서버만 있고 플레이 루프 미연결

- `presence.attackPlayer` / reducer 존재.
- `_damageableTargets` = 적 + 파괴 블록만 (`1411-1414`). **RemotePlayer는 Damageable 아님**.
- 게임 코드에서 `attackPlayer(` 호출 없음(정의·생성 코드·`server_judged_damage_test` stub 제외).
- 선점 규칙(“사람 쳐서 뺏기”)의 실행 수단이 없음.

#### E. 성장 표시 단절 (XP + 레벨 스탯)

- 서버 몹 처치 XP: `award_kill`만. 로컬 `gainXp` 스킵 (`1693-1700`).
- `award_kill`은 `PlayerCharacter.total_xp`뿐 아니라 **`world_player.level`/`max_hp`/`hp`도 갱신** (`world.rs:2344-2358`).
- 게임 루프가 `my_characters` 또는 서버 레벨을 `player.restoreProgress`로 옮기는 코드 **없음**. `restoreProgress`는 출격 시 1회 (`action_rpg_game.dart:306`).
- `SpacetimeGameSync`는 **클라 totalXp → 서버** 방향만 (`spacetime_game_sync.dart:56-62`).
- 결과: 온라인 사냥 시 **서버/리더보드는 오르고 HUD 레벨·XP 바·로컬 스탯은 정체**할 수 있음. 재접속 시에야 캐릭터 선택 값으로 맞춤.

#### F. 이중 권위 잔재 (온라인)

| 경로 | 문제 |
|---|---|
| hazard `_updateHazard` → `applyDamage` | 서버에 지형 피해 없음. 로컬만 깎이다가 `adoptServerVitals`가 되돌리거나, 로컬 `onPlayerDied`로 클라 리스폰 후 서버 좌표와 어긋날 수 있음 |
| `onPlayerDied` vs `_onServerDeath` | 로컬 사망은 클라 `respawnAt`, 서버 사망은 `deaths` 기반. presence 있어도 hazard 경로 공존 |
| 로컬 콤보 1.6 (`player.dart:552-553`) | 서버 몹은 `presence.attack`만 → **연출 피해 ≠ 서버 `player_damage`** |

#### G. 스킬/액션 범위

- 서버 스킬: plasma 하나.
- 버프 포션·대시·로컬 콤보는 서버 상태 머신 밖.
- MP/HP 회복: 서버 `regen_tick` + 클라 예측 (`player.dart:368-371`).

### 3.4 문서 vs 코드

| 문서 | 코드 현실 |
|---|---|
| cowork-prompt: “실시간 멀티 동기화 아직 없음”, HP 120, 몹 레벨 없음 | presence·remote·server monster·BASE_MAX_HP 10000·몹 레벨 동작 |
| GAME-DESIGN §13: 클라 미사용, 원격 미구현, PK 미구현, 로컬 개체군 | 원격·서버 몹 동기화 구현. PK는 **서버만**. 로컬 `MonsterPopulation`은 오프라인/잔재 경로 |
| GAME-SERVER: 서버 권위·연출 함정 문서화 | 구현과 대체로 정합. 일부 줄 앵커는 낡음 |

**분석 기준은 코드다.** 문서만 보면 이미 있는 동기화를 “없다”고 다시 짜거나, 연출만 손대다 판정을 되돌릴 위험이 있다.

### 3.5 MMORPG 관점

- 동일 월드·AOI·서버 몹·선점 킬 골격은 성립.
- 연출 비공유는 “같은 전투를 본다” 체감을 깎음(원거리 스킬·몹 타격).
- 서버 XP 미수신 + `report_progress` 잔존 → HUD/리더보드 신뢰 이원화.
- CombatEvent 도입 시 insert-즉시-delete 금지(`GAME-SERVER.md:310-318`). 현 `last_attack_at`/`deaths`/`last_damaged_at` 확장이 더 안전.

---

## 4. 리스크 · 함정

- **시체 잔존·사망 FX 누락**: 서버 킬 UX 핵심 결함. “안 죽는다” 오인.
- **XP/레벨 HUD 고갈**: 서버만 성장, 화면은 출격 시점 고정 → 자동사냥·난이도 판단 왜곡.
- **PK 미배선**: 선점 다툼의 사람 간 해결 수단 없음.
- **이중 사망/로컬 hazard**: 온라인에서 서버 좌표와 클라 리스폰 불일치 가능.
- **연출용 CombatEvent**: 같은 reducer에서 insert 후 즉시 delete면 구독자 미수신. TTL+스케줄 삭제 필수.
- **이동 보고 RTT 백프레셔**: `_inFlight`로 실효 ≤5Hz → 관찰자 보간 끊김·사거리 거절 증가.
- **표시 상한 50**: 밀집 시 “안 보인다” ≠ 서버에 없음.
- **문서 노후**: 구현자가 GAME-DESIGN §13만 보면 중복 구현 또는 판정 계층 역행.
- **보안**: 피해량 조작은 서버 판정으로 막힘. `move_to` 속도 캡 내 텔레포트성 이동·`report_progress` 완만 인플은 여전히 가능(주석이 인정).
- **`last_damaged_at` 미연결**: 새 필드 없이도 피격 연출 가능 — 신규 스키마부터 가면 낭비.

---

## 5. 권고안

| 순위 | 권고 | 범위 | 근거 | 리스크 |
|---|---|---|---|---|
| 1 | **서버 몹 `alive` false 전이 시 로컬 `_die` 상당 처리**: 폭발 FX, `removeFromParent`, `onEnemyKilled`(XP/드롭은 기존 `isServerDriven` 분기로 서버 유지), `_activeMonsters` 제거 | 클라 `enemy.dart` / `action_rpg_game.dart` | `applyServerState` 미연동 (`enemy.dart:141-164`, `_die` 583-600) | 리스폰 직전 재생성 타이밍; 이중 `onEnemyKilled` 방지 |
| 2 | **서버 XP·레벨을 내 Player에 반영**: `my_characters.totalXp` 또는 `world_player.level` 구독 변화 → `restoreProgress`/레벨업 연출(스탯 중복 없이). 장기적으로 온라인 시 `report_progress` 축소 | 클라 sync + 서버 계약 | `award_kill` vs 로컬 `gainXp` 스킵 (`1693-1700`, `world.rs:2312-2358`) | 이중 적용·레벨업 연출 폭주 |
| 3 | **PK 입력 배선**: 근접 후보에 다른 PC 포함 → `presence.attackPlayer(characterId)`. 안전지대 UI 피드백. 원격은 Damageable 피해가 아니라 **의도 전송**만 | 클라 입력·타겟팅 | reducer 있음, 호출 없음 | 오타겟·파티 오인 공격 UX |
| 4 | **온라인 시 로컬 권위 피해 차단**: presence 시 hazard/`applyDamage`→`onPlayerDied` 억제, 또는 hazard를 서버 `apply_damage_to_player`로 이전 | `player.dart` + (선택) `world.rs` | hazard 서버 부재 (`598-615`), 로컬 사망 (`1783+`) | 오프라인 분기 실수 |
| 5 | **내 피격 연출**: `MyWorldState`에 `lastDamagedAt`(또는 HP 감소분) 노출 → DamageText/hurt SFX/`onPlayerDamaged`. **신규 last_hit 필드보다 기존 열 연결 우선** | presence + `action_rpg_game` / `player` | `last_damaged_at` 서버 기록, 클라 미노출 | 회복·예측으로 오탐 → timestamp 기준 사건 재생 |
| 6 | **원격 스킬 연출**: `attack_skill==plasma` 시 관찰자도 짧은 볼트(판정 없음, `isServerJudged` 대상) | `remote_player.dart` | 스킬 코드만 공유 (`1688-1690`, remote 280-283) | 지연으로 탄이 빈 곳 비행 |
| 7 | **몹 공격 연출 힌트**: 최소 — 내 HP 감소/`lastDamagedAt` 시 최근접 몹 스윙 추정, 또는 서버에 몹 `last_attack_at` | 클라 추정 또는 `world.rs` | `monster_ai`가 좌표·피해만 갱신 | 추정 오연출 vs 쓰기 비용 |
| 8 | **문서 정합**: GAME-DESIGN §12.5·§13·cowork-prompt를 “상태 동기화 완료 / 연출·PK 입력·XP UI 미완”으로 갱신 | 문서만 | 코드와 충돌 | 없음 |
| 9 | (후순위) **CombatEvent 표** — 발사체·광역용. TTL+스케줄 삭제, 청크 인덱스. 상태 필드 방식과 역할 분리 | 서버+클라 | `GAME-SERVER.md:310-318` | egress·스팸 |

구현 시 **판정 수식/reducer 권위를 클라로 되돌리지 말 것.** 연출은 결과 복제 뒤에 얹는다.

---

## 6. 불확실 · 미확인

- maincloud 실서버 동시 2클라 **화면** 검증은 이 세션에서 실행하지 않음. 통합 테스트는 reducer/캐시 수준.
- 서버 시체가 20초 동안 실제로 그려지는지 프레임 실측 미실시(코드 경로상 유력; 화면 밖이면 스트리밍 제거 가능).
- `my_characters` 캐시가 게임 중 갱신된 뒤 다른 UI가 간접 반영하는지 전수 미추적 — HUD Player 필드는 미연결로 판단.
- `monster_ai`의 홈 `by_chunk` vs 현재 `pos_chunk` 경계에서 추격 누락 실측 여부.
- 파티 추종·초대 × 전투 동기화 교차 시나리오 깊이 미검토.
- 콤보 1.6 연출 vs 서버 단일 피해의 체감 괴리 정도.
- cowork-prompt의 HP 재설계 트랙과 본 질문(멀티 동기화)은 별개; 서버 HP 10k/방어/몹레벨은 반영된 상태로 보이나 전 클라 상수 일치 전수는 계약 테스트 밖 일부 가능.

---

## 7. 자기 비판으로 바로잡은 것

- 🔁 **수정**: 1차 “서버 몹 피격/사망 연출이 사실상 없다” → **HP 감소 시 `_hitFlash`는 있음** (`enemy.dart:155-159`). 빠진 것은 **사망 폭발·공격 모션·데미지 텍스트·적 탄막**.
- 🔁 **수정**: 1차 “autoHunt forget 지연”을 사망 버그의 핵심처럼 서술 → `aliveOf`가 `isAlive`를 보므로 죽은 서버 몹은 타겟에서 빠짐 (`auto_hunt.dart:278-279`). 핵심은 **시각 시체 + kills/score/FX 미발동**.
- 🔁 **수정**: 권고 “서버에 `last_hit` 신규 필드” → **`last_damaged_at`이 이미 서버에 있음**. `MyWorldState`에 안 실려 미사용 (`world_presence.dart:87-112`). 신규 스키마보다 노출·연출 연결이 먼저.
- ➕ **추가**: `award_kill`이 `world_player.level`/`max_hp`까지 올리는데 클라 Player 스탯/HUD는 미반영 (`world.rs:2344-2358`) — XP 바만이 아니라 **레벨 축 전체** 단절.
- ➕ **추가**: `lib.rs` “모든 테이블 비공개” vs `world_player` 등 `public` 테이블 불일치 — 문서 원칙과 월드 구현 모델이 다름.
- 🔁 **수정**: 1차 “피격 연출 전무 → DamageText만 문제” 뉘앙스 → 원격 PC 스윙 호·몹 hit flash는 부분 구현. 요청 스펙(동일 탄 궤적·몹 공격 애니) 기준으로 미완이 정확.
- ❌ **철회하지 않음(유지)**: 상태 동기화 뼈대 존재, 발사체/스킬 궤적 비공유, 서버 몹 `_die` 미연결, PK 입력 0건, 서버 XP→HUD 끊김, hazard 로컬 이중 권위, GAME-DESIGN §13 노후 — 줄 재확인 후 유지.

**한 줄 판정:** 서버 권위 **상태 동기화는 동작한다.** 요청하신 **동일 애니메이션·발사체·이벤트 공유는 설계적으로 미완**이며, 서버 몹 사망 연출·XP UI·PK 입력은 “보완”이 아니라 **빠진 배선**에 가깝다. (읽기 전용 — 수정하지 않았다.)
