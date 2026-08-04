<!-- cowork:claude | 2026-08-04 22:09:02 | exit=0 | 816s -->
# claude 분석 — combat-hang-freeze

> 요청: 전투 중 PC가 공격을 받거나, 몬스터가 공격을 받거나, 누군가 사망하면 게임이 멈춰버리는(hang/freeze) 현상이 발생합니다. 원인을 코드 근거(파일:줄)와 함께 규명해 주세요. 특히 다음을 검증해 주세요: (1) lib/game/action_rpg_game.dart 의 meleeTargets()/projectileTargetsForPlayer() 가 sync* 지연 순회로 enemies 리스트를 흘려보내던 것이, 호출부(lib/game/entities/player.dart _resolveMeleeHit)가 순회 도중 applyDamage 로 적을 죽여 onEnemyKilled 가 enemies.remove 를 하면서 ConcurrentModificationError 를 일으키고 그 예외가 Flame update 안에서 터져 게임 루프가 멈추는 것이 진짜 원인인가? (2) 플레이어 사망 경로 onPlayerDied() -> _refreshMonsterStreaming() 이 Enemy.update/Projectile.update 순회 도중 enemies 를 add/remove 하는데 여기에도 같은 종류의 hang 위험이 남아 있는가? (3) 그 밖에 hang 을 일으킬 다른 원인(무한 루프, await 교착, 오디오, 네트워크 동기화 spacetime_game_sync.dart 의 while(true), 레벨업 while 루프 등)이 있는가? (4) 이 hang 을 재현하고 회귀를 막을 테스트를 어떻게 작성해야 하는가?
> 생성: 2026-08-04 22:09:02 · 소요 816s · 읽기 전용 분석(작업공간 미수정)

---



## 1. 결론 요약

가설 (1)은 **원인 진단으로는 정확하지만, 이미 고쳐진 상태다.** `meleeTargets()`/`projectileTargetsForPlayer()` 는 현재 `List<Damageable>` **스냅샷**을 돌려주고(`action_rpg_game.dart:764‑775`), 호출부도 스냅샷 전제로 재작성돼 있다(`player.dart:448‑451`). 코드 주석 자체가 그 사고 경위를 기록하고 있으므로, 이 hang 은 과거에 실재했고 지금은 그 경로가 닫혀 있다.

가설 (2)의 **예외 위험은 남아 있지 않다** — Flame 1.38.0 이 `update` 중의 add/remove 를 lifecycle 큐로 미루고(`component_tree_root.dart:27‑55`), 지금 `enemies` 를 순회하는 세 곳 중 어느 것도 순회 도중 리스트를 건드리지 않는다. 다만 **불변식이 코드로 강제돼 있지 않아** 한 줄만 잘못 추가돼도 되살아난다.

여전히 남아 있는 실질적 "멈춤"의 원인은 예외가 아니라 두 가지다 — **히트스톱 누적**(`action_rpg_game.dart:398‑401, 1046, 1096`)이 연속 피격·연속 처치 구간에서 dt 를 계속 0.25배로 끌어내려 체감상 정지를 만들고, **`Enemy._moveToward` 의 O(N²) 분리 스티어링**(`enemy.dart:247‑269`, 활성 상한 140)이 몬스터가 피격돼 일제히 `chase` 로 전환될 때 프레임 시간을 폭증시킨다. `while(true)`·오디오·await 교착은 hang 원인이 아니다.

## 2. 근거

- `lib/game/action_rpg_game.dart:756‑775` — `meleeTargets()`·`projectileTargetsForPlayer()` 모두 `_damageableTargets()` 를 부르고, 그것은 `<Damageable>[...enemies.where(...), ..._destructibles.where(...)]` 라는 **즉시 소비되는 리스트 리터럴**이다. 주석에 원문 그대로 남아 있다: *"지연 순회(`sync*`)로 enemies 를 그대로 흘려보내면 … `ConcurrentModificationError` 가 터진다. 그 예외는 게임 루프의 `update` 안에서 터지므로 프레임이 통째로 멈춘다 — 전투 중 적을 때리거나 죽는 순간 게임이 얼어붙던 원인이 이것이었다."*
- `lib/game/entities/player.dart:448‑451` — `_resolveMeleeHit` 의 루프 주석: *"목록은 스냅샷이다. 앞선 대상을 때려 죽인 뒤에도 계속 돌기 때문에, 이미 쓰러진 대상은 여기서 걸러야…"* 와 `if (!target.isAlive) continue;` 가지치기.
- `lib/game/action_rpg_game.dart:1024` — `onEnemyKilled` 첫 줄이 `enemies.remove(enemy)`. 이것이 순회 중 변경의 원천이었다.
- `lib/game/entities/enemy.dart:368, 393` — `applyDamage` → `_die()` → `game.onEnemyKilled(this)`. 즉 **피해 적용이 곧 목록 변경**이다.
- `lib/game/entities/projectile.dart:84‑98` — 발사체도 `game.projectileTargetsForPlayer()` 스냅샷을 순회하고, 명중 즉시 `_burst(); return;` 으로 루프를 벗어난다.
- `lib/game/entities/player.dart:565‑570` — `applyDamage` 안에서 `game.onPlayerDied()` 를 호출한다. 이 호출은 `Enemy._resolveMeleeStrike`(`enemy.dart:304`) 또는 `Projectile.update`(`projectile.dart:91`) 스택 안, 즉 **Flame 의 `update` 도중**이다.
- `lib/game/action_rpg_game.dart:1112‑1147` — `onPlayerDied()` 가 `player.respawnAt(...)` 뒤에 `_refreshBlockStreaming()` 과 `_refreshMonsterStreaming()` 을 **동기적으로** 호출한다.
- `lib/game/action_rpg_game.dart:584‑631` — `_refreshMonsterStreaming()` 은 `_activeMonsters.forEach` 로 **수집만** 하고, 실제 `_activeMonsters.remove`·`enemies.remove`·`enemy.removeFromParent()` 는 별도 루프(594‑604)에서 한다. 활성화 단계도 `population.seedsNear()` 가 돌려준 **새 리스트**(`monster_population.dart:98‑120`)를 순회한다. 자기 순회 중 자기 컬렉션을 고치지 않는다.
- `~/.pub-cache/hosted/pub.dev/flame-1.38.0/lib/src/components/core/component_tree_root.dart:27‑55` — `enqueueAdd`/`enqueueRemove`. Flame 은 트리 변경을 큐에 넣고 프레임 경계에서 처리하므로, `update` 중의 `world.add`·`removeFromParent` 는 컴포넌트 트리 순회를 깨뜨리지 않는다.
- `~/.pub-cache/hosted/pub.dev/flame-1.38.0/lib/src/components/core/component.dart:432‑441` — `findGame()` 이 `staticGameInstance` 를 먼저 본다. 따라서 `enemies` 에 먼저 들어가고 마운트는 다음 프레임인 Enemy 라도, 게임 루프 안에서는 `game` getter 가 정상 동작한다(이 경로의 널 예외 가설은 성립하지 않는다).
- `lib/game/entities/enemy.dart:247‑269` — `_moveToward` 가 `for (final other in game.enemies)` 로 **전체 활성 몬스터를 매 프레임 순회**한다. 반복마다 `grid - other.grid` 와 `away.normalized()` 로 `Vector2` 를 새로 만든다.
- `lib/game/action_rpg_game.dart:144` — `_maxActiveMonsters = 140`. 위 순회는 최악 140×140 ≈ 19,600 회/프레임, Vector2 할당 약 4만 개/프레임.
- `lib/game/entities/enemy.dart:366` — `applyDamage` 안의 `if (phase == EnemyPhase.idle) phase = EnemyPhase.chase;`. **피격이 곧 `chase` 전환**이고, `chase` 는 `_moveToward` 를 탄다(178).
- `lib/game/action_rpg_game.dart:398‑401, 1046, 1096` — `if (_hitStop > 0) { _hitStop -= dt; dt *= 0.25; }`. `onEnemyKilled` 이 `_hitStop = enemy.isBoss ? 0.16 : 0.05`, `onPlayerDamaged` 이 `_hitStop = 0.06` 으로 **덮어쓴다**(누적이 아니라 갱신). 연속 피격·연속 처치가 이어지면 슬로우가 끊기지 않는다.
- `lib/game/net/spacetime_game_sync.dart:92‑116` — `while (true)` 는 매 바퀴 `_pending` 을 `null` 로 비우고, 비어 있으면 `return` 한다. 게다가 `await` 를 포함한 async 함수라 UI 스레드를 점유하지 않는다. **hang 이 아니다.** 다만 `_inFlight = true` 가 `if (next > _sentTotalXp)` 블록 안에서만 설정되고 `finally` 에서 즉시 false 로 돌아오므로, 두 번째 바퀴부터는 재진입 가드가 풀린 상태로 돈다(중복 트랜잭션 여지 — 정확성 문제).
- `lib/game/audio/game_audio.dart:416‑445` — `play()` 는 `_ready` 미준비 시 즉시 반환하고, 스로틀(423‑428)을 거쳐 마지막에 `unawaited(_guard(pool.start(...)))` 로 던진다. **게임 루프를 블록하지 않는다.**
- `lib/game/entities/player.dart:741‑743, 787‑809` — `while (level < reached) _levelUp();` 은 `level++` 로 종료가 보장된다. 그러나 **레벨 한 단계마다** `HitSpark` 생성 + `GameAudio.play` + `game.onLevelUp` → `sync.reportLevel` → 서버 트랜잭션이 발생한다. `LevelSystem.maxLevel = 999`(`level_system.dart:44`)이므로 최악 998회다.
- `lib/game/systems/level_system.dart:123‑135` · `lib/game/level/level_map.dart:97, 220‑233, 435` — 이진 탐색·`nearestWalkable`(radius<24)·`respawnPoint`(48회)·크레이트 배치(`attempts < 40000`) 모두 명시적 상한이 있다. **무한 루프 후보가 아니다.**
- `pubspec.yaml:42‑51` — `dev_dependencies` 에 `flutter_test`·`flutter_lints` 뿐. **`flame_test` 가 없다.**
- `test/` 14개 파일(`combat_damage_test.dart` 등) — 전부 순수 함수·정적 테이블 검증이다. `ActionRpgGame` 을 띄워 `update(dt)` 를 한 프레임이라도 돌리는 테스트가 **하나도 없다.**
- `lib/game/action_rpg_game.dart:193‑194` — `onLoad` 안에서 `LevelMap.generate()`(100만 칸)와 `MonsterPopulation.generate(map)` 를 하드코딩으로 만든다. 크기·시드 주입 지점이 없다.

## 3. 상세 분석

### (1) ConcurrentModificationError — 원인 진단은 맞고, 수정도 되어 있다

메커니즘은 질문에 적힌 그대로다. `Player._resolveMeleeHit` 이 대상 목록을 돌면서 `target.applyDamage(...)` 를 호출하고(`player.dart:462`), 그 안에서 `Enemy._die()` → `game.onEnemyKilled(this)` → `enemies.remove(enemy)` 가 일어난다(`enemy.dart:368→393`, `action_rpg_game.dart:1024`). 목록이 `enemies` 를 지연 순회하는 `Iterable` 이었다면, 다음 `moveNext()` 가 `modCount` 불일치를 보고 `ConcurrentModificationError` 를 던진다.

**범위**: 이 예외는 `Player.update` → `_updateMelee` → `_resolveMeleeHit` 안에서 터지므로 Flame 의 `updateTree` 를 관통해 Flutter 의 프레임 콜백까지 올라간다. 매 프레임 같은 조건이 재현되므로 한 번 걸리면 계속 걸린다 — 사용자가 본 "게임이 멈춘다"와 부합한다. 다만 그 뒤 화면이 정확히 어떻게 되는지(에러 위젯 교체 / 렌더 정지)는 **[추측]** 이다. 실행 로그를 확인하지 않았다.

현재 코드는 세 겹으로 닫혀 있다: ① 반환 타입이 `List<Damageable>` 로 명시됐고, ② 리스트 리터럴 spread 로 즉시 소비되며, ③ 호출부가 `if (!target.isAlive) continue;` 로 이미 죽은 스냅샷 항목을 걸러낸다. 발사체 경로도 동일하다(`projectile.dart:84‑98`).

남은 지연 순회는 `_destructibles`(`action_rpg_game.dart:634‑640`) 하나인데, 이것은 `_damageableTargets()` 안에서 즉시 소비되므로 generator 가 살아 있는 동안 피해가 발생할 창이 없다.

### (2) 플레이어 사망 경로 — 예외는 없지만 구조가 취약하다

`onPlayerDied()` 는 확실히 `Enemy.update`/`Projectile.update` 스택 **안에서** 실행된다. 그리고 그 안에서 `enemies` 를 add/remove 한다. 그럼에도 지금 터지지 않는 이유는 두 가지다.

첫째, Flame 이 컴포넌트 트리 변경을 큐잉한다(`component_tree_root.dart:27‑55`). `enemy.removeFromParent()` 가 지금 update 중인 그 Enemy 자신이어도 안전하다.

둘째, `enemies` 를 순회하는 코드가 세 곳뿐이고 셋 다 무해하다.

| 위치 | 순회 방식 | 순회 중 변경 여부 |
|---|---|---|
| `action_rpg_game.dart:773` `_damageableTargets` | 즉시 리스트화 | 없음(변경은 스냅샷 소비 후) |
| `action_rpg_game.dart:669` `_updateWaves` 의 `any` | 지연이지만 피해 없음 | 없음 |
| `enemy.dart:252` `_moveToward` 분리 스티어링 | 지연 순회 | **피해를 주지 않으므로** 없음 |

**경계**: 세 번째 항목이 위험 지점이다. `_moveToward` 는 `game.enemies` 를 **지연 순회**하며, 같은 `Enemy._updateAi` 안의 다른 분기(`enemy.dart:194` → `_resolveMeleeStrike` → `player.applyDamage` → `onPlayerDied` → `enemies.remove/add`)는 피해를 준다. 지금은 두 경로가 같은 프레임의 **서로 다른 switch case** 라 겹치지 않을 뿐이다. 몸통 충돌 피해, 자폭 몬스터, 근접 오라 같은 흔한 기능을 `_moveToward` 루프 안에 넣는 순간 (1)과 완전히 같은 예외가 되살아난다. 즉 **안전이 우연에 기대고 있다.**

### (3) 그 밖의 hang 원인

**히트스톱 — 가장 유력한 잔여 원인.** `_hitStop` 은 누적되지 않고 **갱신**된다(`action_rpg_game.dart:1046, 1096`). 플레이어가 여러 적에게 연달아 맞으면 매 피격마다 0.06 초가 다시 채워지고, 그동안 `dt *= 0.25` 가 계속 걸린다(398‑401). 다수 처치 구간도 마찬가지로 0.05초씩 갱신된다. 결과는 **끊기지 않는 4배 슬로우모션** — 프레임은 돌지만 사용자에게는 "멈춤"으로 읽힌다. 사용자가 든 세 트리거 중 "PC가 공격을 받을 때"와 "누군가 사망할 때"가 정확히 이 두 지점이다.

**O(N²) 분리 스티어링 — 두 번째 원인.** 몬스터가 피격되면 `idle → chase` 로 전환되고(`enemy.dart:366`), `chase` 는 `_moveToward` 를 탄다. 한 마리를 때리면 어그로가 번져 주변이 일제히 `chase` 가 되므로, 활성 140기 기준 프레임당 약 2만 회 순회 + 약 4만 개 `Vector2` 할당이 발생한다. 이것이 "몬스터가 공격을 받으면 멈춘다"에 대응한다. 예외가 아니라 프레임 예산 초과 + GC 압박이다.

**레벨업 while 루프 — 잠재 원인.** 종료는 보장되지만 반복 1회당 이펙트·효과음·서버 보고가 붙는다(`player.dart:787‑809`). `restoreProgress` 는 이 문제를 알고 연출을 건너뛰지만(747‑775), `gainXp` 경로에는 그런 보호가 없다. 만렙이 999 이므로 큰 XP 덩어리가 한 번에 들어오면 수백 번의 서버 트랜잭션이 한 프레임에 쏟아진다.

**hang 원인이 아닌 것들 — 명확히 배제.** `spacetime_game_sync.dart` 의 `while(true)` 는 매 바퀴 `_pending` 을 비우므로 종료하고, async 라 UI 를 막지 않는다. 오디오는 `unawaited` + 스로틀 + 미준비 시 조기 반환이라 블록하지 않는다. `requestLogout` 의 `await` 에는 3초 타임아웃이 있다(`action_rpg_game.dart:1011`). 맵·개체군 생성 루프는 전부 상한이 있다.

### (4) 테스트가 이 부류를 잡지 못하는 구조적 이유

현재 테스트는 `MonsterCodex`·`LevelSystem`·`Player.damageAfterDefense` 같은 **상태 없는 계산**만 검증한다. 순회 중 변경, 재진입, 프레임 예산은 전부 **게임 루프를 실제로 돌려야** 드러나는 성질인데, `flame_test` 가 없어 `ActionRpgGame` 을 띄울 수단 자체가 없다. 게다가 `onLoad` 가 1 km² 맵과 수천 개체를 하드코딩으로 만들기 때문에(`action_rpg_game.dart:193‑194`), 지금 상태로는 띄워도 테스트가 무겁고 불안정하다. **테스트를 쓰려면 먼저 주입 지점이 필요하다.**

## 4. 리스크 · 함정

- **"이미 고쳐졌다"를 "안전하다"로 읽으면 안 된다.** `meleeTargets()` 의 스냅샷 계약은 주석으로만 지켜지고 있다. 반환 타입을 `Iterable` 로 되돌리거나 `sync*` 로 최적화하려는 다음 사람이 그대로 되돌린다. 테스트가 없으면 리뷰만이 방어선이다.
- **`_moveToward` 루프에 피해 판정을 넣는 것이 가장 흔한 재발 경로다.** 몸통 충돌·자폭·근접 오라는 액션 RPG 에서 자연스럽게 추가되는 기능이고, 넣는 순간 (1)과 동일한 예외가 된다.
- **히트스톱을 손대면 타격감이 바뀐다.** 이건 버그가 아니라 의도된 연출(`action_rpg_game.dart:397`)이므로, 상한을 두는 수정은 **게임 디자인 결정**이지 순수한 버그 수정이 아니다. 사람의 판단이 필요하다.
- **O(N²) 를 공간 해시로 바꾸면 분리 스티어링의 결과가 미세하게 달라진다.** 몬스터가 서로 겹치는 정도·밀집 대형의 모양이 바뀌므로, 눈으로 확인해야 하는 변경이다.
- **`_maxActiveMonsters` 를 낮추는 것은 근본 대책이 아니다.** MMORPG 전제(`CLAUDE.md:26‑33`)에서 같은 월드에 다른 PC 까지 들어오면 순회 대상은 더 늘어난다. 상한 조정은 증상 완화일 뿐이다.
- **레벨업 루프에 상한을 두면 성장이 잘린다.** 연출만 묶고 스탯은 전부 반영하는 방식이어야 한다 — `restoreProgress` 가 이미 그 패턴을 갖고 있으므로(`player.dart:760‑775`) 그것을 재사용하는 것이 안전하다.
- **`SpacetimeGameSync._send` 의 `_inFlight` 가드 결함은 hang 이 아니라 중복 트랜잭션이다.** 이것을 hang 원인으로 오인해 고치면 진짜 증상은 그대로 남는다. MMORPG 에서는 접속자 수만큼 곱해지므로 별건으로 다룰 가치는 있다.
- **`flame_test` 추가는 의존성 변경이다.** `flutter test` 가 실서버 통합 테스트를 포함한다는 프로젝트 규약(`.cowork/cowork-prompt.md:131`)이 있으므로, 새 테스트가 그 실행 시간을 얼마나 늘리는지 함께 봐야 한다.

## 5. 권고안

| 순위 | 권고 | 범위 | 근거 | 리스크 |
|---|---|---|---|---|
| 1 | **`meleeTargets()`/`projectileTargetsForPlayer()` 의 스냅샷 계약을 테스트로 못 박는다.** 반환값이 `enemies` 와 다른 인스턴스인지, 반환 목록을 순회하는 도중 `enemies` 를 수정해도 예외가 없는지 검증한다. 주석이 아니라 실패하는 테스트가 계약이어야 한다. | 클라이언트 / 테스트 계층 | `action_rpg_game.dart:756‑775`, `test/` 에 해당 테스트 부재 | 게임 인스턴스가 필요해 `flame_test` 의존성이 늘어난다 |
| 2 | **히트스톱에 상한과 쿨다운을 둔다.** `_hitStop` 을 무조건 갱신하지 말고 "직전 히트스톱 종료 후 최소 X초 경과" 또는 "프레임당 1회" 로 제한한다. 연속 피격·다수 처치 구간에서 슬로우가 이어지지 않게 한다. | 클라이언트 / 게임 루프 (`ActionRpgGame.update`·`onEnemyKilled`·`onPlayerDamaged`) | `action_rpg_game.dart:398‑401, 1046, 1096` | 타격감이 바뀐다 — 수치는 사람이 정해야 한다 |
| 3 | **`Enemy._moveToward` 의 분리 스티어링을 공간 분할로 바꾼다.** 청크/그리드 해시로 인접 개체만 조회하고, `Vector2` 새 할당 대신 재사용 버퍼를 쓴다. 활성 상한 140 을 유지한 채 O(N²)→O(N·k) 로 내린다. | 클라이언트 / `Enemy` AI | `enemy.dart:247‑269`, `action_rpg_game.dart:144`, `enemy.dart:366` | 몬스터 밀집 대형의 모양이 미세하게 달라진다 |
| 4 | **`ActionRpgGame` 에 테스트용 주입 지점을 연다.** `onLoad` 가 하드코딩으로 만드는 `LevelMap`·`MonsterPopulation` 을 생성자 파라미터(또는 protected 팩토리)로 받게 해서, 작은 맵·소수 개체로 게임 루프를 돌릴 수 있게 한다. 이것이 없으면 1·5번 테스트가 실용적이지 않다. | 클라이언트 / `ActionRpgGame` 구성 | `action_rpg_game.dart:193‑194` | 생성자 표면이 넓어진다 |
| 5 | **사망 경로 회귀 테스트를 추가한다.** 적 1기가 플레이어에게 치사 피해를 주는 상황을 실제 `update(dt)` 한 프레임 안에서 재현해, `onPlayerDied` → `_refreshMonsterStreaming` 이 예외 없이 끝나고 플레이어가 안전지대에 리스폰되는지 확인한다. `FlutterError.onError` 로 삼켜진 예외까지 잡는다. | 클라이언트 / 테스트 계층 | `player.dart:565‑570`, `action_rpg_game.dart:1112‑1147, 584‑631` | 4번 선행 필요 |
| 6 | **`gainXp` 의 다중 레벨업에서 연출·서버 보고를 묶는다.** 스탯은 `_applyGains` 로 전부 반영하되, 이펙트·효과음·`onLevelUp` 은 마지막 한 번만 내보낸다. `restoreProgress` 가 이미 쓰는 패턴이다. | 클라이언트 / `Player`·`LevelSystem` | `player.dart:722‑745, 760‑775, 787‑809`, `level_system.dart:44` | 여러 레벨이 한 번에 오를 때 연출이 한 번으로 줄어든다(의도된 변경) |
| 7 | **`_moveToward` 계열 루프에 "피해를 주지 말 것" 을 명시적 계약으로 남긴다.** 주석만이 아니라, 피해 판정을 프레임 말미의 별도 단계(수집→적용)로 분리하는 구조가 근본적이다. | 클라이언트 / 전투 파이프라인 | `enemy.dart:247‑269` vs `enemy.dart:194→304` | 전투 흐름 리팩터링이라 범위가 크다 |
| 8 | **`SpacetimeGameSync._send` 의 `_inFlight` 가드를 루프 바깥으로 올린다.** hang 과는 별개지만, 접속자 수만큼 곱해지는 중복 트랜잭션이다. | 클라이언트 / 네트워크 동기화 | `spacetime_game_sync.dart:84‑116` | 서버 부하 관점의 별건 — 이번 hang 수정과 섞지 말 것 |

## 6. 불확실 · 미확인

- **사용자가 지금도 hang 을 겪는지 확인하지 못했다.** 코드상 (1)의 경로는 닫혀 있다. 증상이 여전하다면 ① 실행 중인 빌드가 이 수정 이전 버전이거나, ② 원인이 히트스톱·성능 쪽이거나, ③ 내가 못 본 제3의 경로다. **재현 시점의 콘솔 로그(예외 타입·스택)** 를 보면 셋 중 무엇인지 즉시 갈린다 — 이것이 가장 가치 있는 추가 자료다.
- git 이력을 확인하지 못했다(이 세션에 셸 접근이 없다). `meleeTargets()` 스냅샷 수정이 **언제** 들어갔는지, 사용자가 관측한 hang 이 그 이전인지 이후인지 확정하지 못했다.
- "Flame update 안에서 예외가 터지면 게임 루프가 어떻게 멈추는가" 의 정확한 동작(에러 위젯 교체 / 렌더 정지 / 매 프레임 재발)은 **[추측]** 이다. Flame 의 예외 전파 경로를 직접 열어 확인하지 않았다.
- 히트스톱과 O(N²) 가 **실제로** 사용자가 본 정도의 정지를 만드는지 수치로 확인하지 못했다. 프로파일링(DevTools 타임라인) 없이는 "프레임 예산 초과"가 어느 정도인지 단정할 수 없다. `CLAUDE.md:42‑48` 이 지시하는 DTD 기반 계측이 이 지점에 정확히 필요하다.
- 활성 몬스터가 실제로 140기에 도달하는 상황이 얼마나 흔한지 확인하지 못했다. `_monsterActivationRadius = 46` 타일 안의 실제 개체 밀도(`MonsterPopulation.generate` 의 청크당 3~13기)를 계산하면 추정할 수 있으나, 지형에 따른 `findFootingNear` 실패율을 몰라 정확한 값을 내지 못했다.
- 다른 PC 가 같은 월드에 보이는 멀티플레이 동기화는 **아직 구현되지 않았다**(`.cowork/cowork-prompt.md:22`). 따라서 "다른 플레이어의 캐릭터·발사체까지 포함한 순회" 는 이번 분석 범위 밖이며, 구현될 때 1·3·7번 권고가 다시 검토돼야 한다.
- `lib/game/ui/hud.dart:464, 473` 이 `game.pickups`·`game.enemies` 를 순회하지만 `render` 단계라 안전하다고 판단했다. Flame 의 `renderTree` 가 `updateTree` 와 완전히 분리돼 있다는 전제인데, 이 파일의 전체 내용은 읽지 않았다 — 만약 HUD 가 `update` 에서도 같은 순회를 한다면 재검토가 필요하다.
