<!-- cowork:kimi | 2026-08-04 22:05:32 | exit=0 | 606s -->
# kimi 분석 — combat-hang-freeze

> 요청: 전투 중 PC가 공격을 받거나, 몬스터가 공격을 받거나, 누군가 사망하면 게임이 멈춰버리는(hang/freeze) 현상이 발생합니다. 원인을 코드 근거(파일:줄)와 함께 규명해 주세요. 특히 다음을 검증해 주세요: (1) lib/game/action_rpg_game.dart 의 meleeTargets()/projectileTargetsForPlayer() 가 sync* 지연 순회로 enemies 리스트를 흘려보내던 것이, 호출부(lib/game/entities/player.dart _resolveMeleeHit)가 순회 도중 applyDamage 로 적을 죽여 onEnemyKilled 가 enemies.remove 를 하면서 ConcurrentModificationError 를 일으키고 그 예외가 Flame update 안에서 터져 게임 루프가 멈추는 것이 진짜 원인인가? (2) 플레이어 사망 경로 onPlayerDied() -> _refreshMonsterStreaming() 이 Enemy.update/Projectile.update 순회 도중 enemies 를 add/remove 하는데 여기에도 같은 종류의 hang 위험이 남아 있는가? (3) 그 밖에 hang 을 일으킬 다른 원인(무한 루프, await 교착, 오디오, 네트워크 동기화 spacetime_game_sync.dart 의 while(true), 레벨업 while 루프 등)이 있는가? (4) 이 hang 을 재현하고 회귀를 막을 테스트를 어떻게 작성해야 하는가?
> 생성: 2026-08-04 22:05:32 · 소요 606s · 읽기 전용 분석(작업공간 미수정)

---

• 게임 프로젝트가 `/Users/thruthesky/tmp/games/actionrpg` 에 있음을 확인했다. 핵심 파일들을 읽는다.

• 마지막으로 기존 테스트가 `ActionRpgGame` 을 직접 인스턴스화하는지 확인한다.

• 

## 1. 결론 요약

  가설 (1)은 **사실로 확인됐고, 현재 코드에서는 이미 수정돼 있다.** `action_rpg_game.dart:758-763` 의 주석이 "sync* 지연 순회 → 순회 중 `onEnemyKilled` 의 `enemies.remove` → `ConcurrentModificationError` → Flame `update` 안에서 예외 → 프레임 동결" 이라는 정확히 그 인과를 "전투 중 얼어붙던 원인" 으로 명시하고 있고, 현재 구현은 스냅샷 `List` 를 돌려준다(`action_rpg_game.dart:764,769,772-775`). (2) 플레이어 사망 경로(`onPlayerDied` → `_refreshMonsterStreaming`)는 현재 호출 지점들 어디에서도 `game.enemies` 를 순회 중이 아니므로 동일 종류의 hang 은 남아 있지 않다 — 단 이 안전성은 코드상 명시적 불변식이 아니라 호출 구조에 우연히 의존한다. (3) 지목된 다른 후보들(`while(true)` 동기화 루프, 레벨업 `while`, 웨이브 예산 `while`, 스폰 탐색 루프)은 모두 종료 조건이 있거나 `await` 로 양보해 hang 을 일으키지 않는다. (4) 회귀 테스트는 현재 테스트 스위트에 없으며(`test/` 14개 파일 중 해당 시나리오 없음), 스냅샷 불변식을 못 박는 단위 테스트로 작성 가능하다.

  참고: 지정 작업공간(`/Users/thruthesky/.claude/plugins/cache`)에는 이 게임이 없고, 실제 프로젝트는 `/Users/thruthesky/tmp/games/actionrpg` 에 있었다. 아래 파일 경로는 이 프로젝트 루트 기준이다.

  

## 2. 근거

  - `lib/game/action_rpg_game.dart:758-763` — 주석 원문: "지연 순회(`sync*`)로 [enemies] 를 그대로 흘려보내면, 호출부가 순회 도중 `applyDamage` 로 적을 죽이는 순간 `onEnemyKilled` 가 원본 목록에서 그 적을 지워 다음 걸음에서 `ConcurrentModificationError` 가 터진다. 그 예외는 게임 루프의 `update` 안에서 터지므로 프레임이 통째로 멈춘다 — 전투 중 적을 때리거나 죽는 순간 게임이 얼어붙던 원인이 이것이었다."
  - `lib/game/action_rpg_game.dart:764,769` — `List<Damageable> meleeTargets() => _damageableTargets();` / `projectileTargetsForPlayer()` 동일. 반환형이 `Iterable` 이 아니라 `List` 다.
  - `lib/game/action_rpg_game.dart:772-775` — `_damageableTargets()` 는 리스트 리터럴 스프레드(`...enemies.where(...)`)로 즉시(eager) 복사한다.
  - `lib/game/action_rpg_game.dart:1023-1024` — `onEnemyKilled(Enemy enemy) { enemies.remove(enemy); ...` — 원본 목록을 그 자리에서 변경한다.
  - `lib/game/entities/player.dart:448-451` — `_resolveMeleeHit` 가 스냅샷을 순회하며 `if (!target.isAlive) continue;` 로 앞서 죽인 대상을 걸러낸다(주석: "목록은 스냅샷이다").
  - `lib/game/entities/projectile.dart:84-98` — 발사체 충돌도 같은 스냅샷(`projectileTargetsForPlayer()`) 또는 새 리터럴 `<Damageable>[game.player]` 를 순회한다.
  - `lib/game/entities/player.dart:565-570` — 플레이어 사망 시 `game.onPlayerDied()` 는 `Player.applyDamage` 안에서만 호출된다.
  - `lib/game/action_rpg_game.dart:1112-1132` — `onPlayerDied()` 가 `player.respawnAt(...)` 후 `_refreshMonsterStreaming()` 을 동기 호출한다.
  - `lib/game/action_rpg_game.dart:584-631` — `_refreshMonsterStreaming` 이 `enemies.remove(enemy)`(602)와 `enemies.add(enemy)`(628)를 한다. 자체 순회는 `_activeMonsters` 맵 대상이고 `toRelease` 지연 수집 패턴(587-594)을 쓴다.
  - `lib/game/entities/enemy.dart:252` — `game.enemies` 를 직접 순회하는 유일한 장소는 `_moveToward` 의 분리 스티어링이며, 이 루프 안에서는 피해를 주지 않는다(이동 계산만).
  - `lib/game/net/spacetime_game_sync.dart:92-116` — `while (true)` 는 매 회전 `await _client.reducers.reportProgress(...)` 로 양보하고 `_pending == null` 이면 반환한다. `lib/game/action_rpg_game.dart:1010-1014` — 로그아웃 시 `flushProgress().timeout(Duration(seconds: 3))` 로 상한이 있다.
  - `lib/game/entities/player.dart:741-743` + `lib/game/systems/level_system.dart:44,71,123-135` — 레벨업 `while (level < reached)` 는 `totalXp` 가 `maxTotalXp`(4294967295)로 상한되고 `reached ≤ maxLevel(999)`, `_levelUp()` 이 매번 `level++` 하므로 종료한다.
  - `lib/game/systems/wave_director.dart:47-52,70-75` — `_cost` 는 최소 1(drone)이라 `while (spent < budget)` 은 반드시 종료한다.
  - `lib/game/level/level_map.dart:220-232` — `nearestWalkable` 은 `radius < 24` 로 상한된 탐색이다. `wave_director.dart:105` 스폰 탐색도 220회 상한.
  - `test/` 디렉토리(14개 파일)에 `meleeTargets`·스냅샷·`ConcurrentModification` 회귀 테스트는 없다(grep 결과 없음; `test/cyborg_render_snapshot_test.dart` 의 "스냅샷"은 렌더 캡처 용도).

  

## 3. 상세 분석

  **(1) 가설 검증 — 진짜 원인이 맞고, 이미 고쳐져 있다.** 인과 사슬의 모든 고리가 코드에 남아 있다: (a) 과거 `meleeTargets()` 가 `sync*` 지연 순회로 `enemies` 를 그대로 흘려보냈다는 사실은 758-763 주석이 증언한다. (b) 호출부 `_resolveMeleeHit`(`player.dart:448`)가 순회 도중 `target.applyDamage`(462)를 호출하고, (c) 적이 죽으면 `Enemy.applyDamage → _die → game.onEnemyKilled`(`enemy.dart:368,377,394` 경로)가 `enemies.remove`(`action_rpg_game.dart:1024`)를 하며, (d) Dart 의 `List` 이터레이터는 순회 중 구조 변경을 감지해 다음 `moveNext` 에서 `ConcurrentModificationError` 를 던진다(Dart SDK 표준 동작 — 외부 사실). (e) 이 콜체인 전체가 Flame 의 `update`(`action_rpg_game.dart:406-407` 의 `super.update(dt)` 아래 컴포넌트 갱신) 안에서 돌기 때문에 예외가 처리되지 않으면 그 프레임의 갱신이 중단된다. 현재 코드의 수정 방식은 "호출부를 조심시키기" 가 아니라 **반환값을 스냅샷 `List` 로 바꾼 것**(772-775)이고, 호출부는 스냅샷 특성상 시체 타격을 걸러내는 `isAlive` 검사(451)를 추가로 둔다. 범위: 이 수정은 `enemies` 목록에 대한 것이며, `_destructibles`(`action_rpg_game.dart:634-640`)는 여전히 `sync*` 지만 `_damageableTargets` 의 리스트 리터럴 안에서 즉시 소비되므로 동일 버그는 성립하지 않는다.

  **(2) 플레이어 사망 경로 — 현재는 안전하나, 암묵적 불변식에 의존한다.** `onPlayerDied()`(1112) → `_refreshMonsterStreaming()`(1132)은 `enemies.remove`(602)와 `enemies.add`(628)를 동기적으로 한다. 위험은 "이 호출이 일어나는 순간 누군가 `game.enemies` 를 순회 중인가" 인데, `onPlayerDied` 의 유일한 트리거는 `Player.applyDamage`(`player.dart:570`)이고 그 호출 지점은 세 곳뿐이다: `enemy.dart:304`(적의 근접 타격 — `_updateAi` 의 telegraph 단계, `enemies` 순회 밖), `projectile.dart:91`(적 발사체 — 순회 대상은 새 리터럴 `[game.player]` 로 `enemies` 와 무관), `player.dart:496`(위험 지형 — 자기 자신의 갱신 중). `game.enemies` 를 직접 순회하는 유일한 코드는 `enemy.dart:252` 의 분리 스티어링인데 여기선 `applyDamage` 를 부르지 않는다. 따라서 현재 구조에서는 `ConcurrentModificationError` 가 발생할 수 없다. 다만 이 안전성은 "피해 콜백이 터질 수 있는 코드는 절대 `game.enemies` 를 직접(for-in 으로) 순회하지 않는다" 는 **어디에도 적히지 않은 규칙** 위에 서 있다. 예컨대 광역 공격을 `for (final e in game.enemies) e.applyDamage(...)` 처럼 구현하는 순간 (1)의 버그가 그대로 재발한다. 또한 `_refreshMonsterStreaming` 은 Flame 컴포넌트 트리 갱신 도중(`super.update` 아래에서 죽었을 때) `world.add(enemy)`(629)와 `enemy.removeFromParent()`(603)을 호출하는데, Flame 은 갱신 중 추가·제거를 지연 처리하므로 트리 쪽은 안전하다[외부 지식 — Flame `Component` 라이프사이클; 프로젝트 내에서 별도 검증 수단은 못 찾음].

  **(3) 그 밖의 hang 후보 — 지목된 것들은 모두 무혐의.**
  - `spacetime_game_sync.dart:92` 의 `while (true)`: Dart 단일 isolate 에서 매 회전 `await`(96)가 이벤트 루프에 양보하므로 UI 를 굳히지 않는다. 종료는 `_pending == null`(112-113). 네트워크 무응답 시 `await` 가 영원히 안 돌아오는 교착 가능성은 클라이언트 라이브러리 타임아웃에 달렸지만[미확인], 게임 루프를 막지는 않는다(루프에서 `await` 없이 발사하고 잊는다 — `tick` 의 `_send(_totalXp)`(62)는 unawaited).
  - 레벨업 `while`(player.dart:741): 위 근거대로 상한이 있다. 다만 `gainXp` 한 번에 최대 998회 `_levelUp` 이 도는 극단(만렙 직행)은 hang 이 아니라 수 프레임 정지로 나타날 수 있다[추측 — 실제 발생하려면 maxTotalXp 급 XP 를 한 번에 받아야 함].
  - 웨이브 예산 `while`(wave_director.dart:70): `_cost ≥ 1` 로 종료 보장.
  - `level_system.dart:126` 이진 탐색, `level_map.dart:435`(`attempts < 40000`), `level_map.dart:220`(`radius < 24`), `wave_director.dart:105`(220회): 전부 상한 있음.
  - 오디오: `GameAudio.play` 는 전투 경로 곳곳에서 호출되나(`player.dart:479,567,573` 등) 구현 파일(`lib/game/audio/`)은 읽지 않았다 — §6 참고.
  - 한 가지 주목할 잔여 리스크: `_updateWaves` 의 `enemies.any(...)`(`action_rpg_game.dart:669`)와 `_pruneRemoved` 의 `enemies.removeWhere`(421)는 지연/즉시 순회지만, 이들이 실행되는 시점(게임 `update` 의 408-409행)에는 `super.update`(407)가 이미 끝나 콜백이 새어 들어올 경로가 없다. 즉 현재 update 순서상 안전하다.

  **(4) 테스트 전략.** 기존 테스트는 전부 순수 단위 테스트(`combat_damage_test.dart` 는 수치 불변식만 검증)이고 게임 객체를 띄우는 하네스가 없다. 회귀 방지는 두 겹이 맞다: (a) **구조적 불변식 테스트** — `meleeTargets()`·`projectileTargetsForPlayer()` 의 반환값이 `List` 인지(`is List` 단언) 검사해 `sync*` 로 되돌리는 회귀를 즉시 탐지. 이것은 Flame 하네스 없이 가능하도록 두 메서드의 의존성(`enemies`, `_loadedBlocks`)을 주입 가능한 단위로 분리하거나, Flame 의 `FlameGame` 을 테스트에서 직접 인스턴스화해 `onLoad` 없이 목록만 채워 호출하는 방식이 있다. (b) **시나리오 테스트** — 살아 있는 적 2기를 범위 안에 두고, 반환된 목록을 순회하면서 첫 대상에 `applyDamage` 로 치명상을 입혀 `onEnemyKilled` 까지 실제로 타게 한 뒤, 예외 없이 루프가 끝나고 두 번째 대상이 `isAlive` 검사에 걸러지는지 단언한다. 같은 골격으로 "플레이어에게 치명상 → `onPlayerDied` → 스트리밍 갱신 후 `enemies` 일관성" 테스트를 추가한다.

  

## 4. 리스크 · 함정

  - **수정 완료 사실을 "아직 버그 있음" 으로 오독하기 쉽다.** 현상 보고(사용자 질문)는 현재형이지만 코드는 이미 고쳐져 있고 주석까지 있다. 실행 중인 빌드가 이 소스와 같은 커밋인지 확인하지 않으면, 이미 수정된 원인을 다시 고치려 하거나 다른 원인을 억지로 찾게 된다(git 로그는 `15fa510 updating the cyborg game` 등 2건만 보여 이력 판별 불가 — §6).
  - **안전성이 암묵 규칙에 의존한다.** "피해 콜백 경로에서는 `game.enemies` 를 직접 순회하지 않는다" 는 규칙이 주석·테스트 어디에도 없다. 신규 기능(광역기, 도트 데미지 장판 등)이 `for (final e in game.enemies)` 를 쓰는 순간 동일 hang 이 재발한다.
  - **스냅샷의 부작용.** 스냅샷은 죽은 대상을 여전히 담고 있으므로, 호출부가 `isAlive` 검사를 빼먹으면 hang 대신 "시체 타격/시체 흡수" 버그가 된다. 이 검사는 현재 `player.dart:451`, `projectile.dart:88` 두 곳에만 있고 강제되지 않는다.
  - **Dart 예외 ≠ 응용 hang.** `ConcurrentModificationError` 가 실제로 "게임이 멈추는" 형태로 보이려면 예외가 매 프레임 반복되거나 첫 프레임에서 루프가 깨져야 한다[추측 — Flame 의 예외 처리 경로(미확인)에 따라 한 프레임 스킵으로 끝날 수도 있다]. 주석의 진술("프레임이 통째로 멈춘다")과 일치하지만, 재현 로그 없이는 "멈춤" 의 정확한 메커니즘(매 프레임 재발인지, 상태 꼬임인지)은 미확인이다.
  - **분석 범위 경계.** 이 판단은 `/Users/thruthesky/tmp/games/actionrpg` 의 현재 소스 기준이며, 지정 작업공간(플러그인 캐시)과는 무관하다. 다른 사본/배포본이 있으면 결론이 달라질 수 있다.
  - **`_refreshMonsterStreaming` 의 부수 효과.** 사망 순간 스트리밍 갱신은 `Enemy` 생성·`world.add`·`GameAudio`·이펙트를 한 프레임에 몰아 넣어, hang 은 아니지만 사망 프레임의 순간 끊김(스파이크) 원인이 될 수 있다[추측].

  

## 5. 권고안

  | 순위 | 권고 | 범위 | 근거 | 리스크 |
  |---|---|---|---|---|
  | 1 | "피해 콜백 경로에서 `game.enemies` 직접 순회 금지 — 대상 목록은 반드시 스냅샷 API(`meleeTargets` 등)로" 라는 불변식을 `enemies` 필드 선언부와 `_damageableTargets` 주석에 명문화 | `lib/game/action_rpg_game.dart` (`enemies` 선언, 772행 부근) | `action_rpg_game.dart:758-763`(같은 교훈이 메서드 주석에만 있음), `enemy.dart:252`(유일한 직접 순회) | 없음 — 주석 추가뿐 |
  | 2 | 회귀 테스트 2종 추가: (a) 두 타깃 API 의 반환형이 `List` 임을 단언하는 구조 테스트, (b) "근접 일격으로 첫 대상 사망 → 두 번째 대상까지 무예외 순회" 시나리오 테스트. 사망 경로(`onPlayerDied` 후 스트리밍 갱신)도 같은 파일에 | `test/` (신규 파일, 예: `combat_iteration_safety_test.dart`) | 회귀 테스트 부재(§2 마지막 근거), `test/combat_damage_test.dart` 의 순수 단위 스타일을 따르되 게임 객체 조립이 필요 | Flame 컴포넌트를 테스트에서 띄우는 비용 — `onLoad` 없이 목록만 채우는 최소 조립으로 억제해야 함[판단] |
  | 3 | 실제 hang 이 재현되는 빌드가 이 소스와 동일한지 확인(증상 재현 시 스택 트레이스/`ConcurrentModificationError` 로그 확보). 로그가 이 예외가 아니면 원인을 새로 조사 | 운영/재현 환경 | 주석(758-763)이 과거형("~였다")이고 현재 코드는 수정됨 | 확인 전에 추가 수정을 하면 엉뚱한 곳을 고칠 수 있음 |
  | 4 | `Enemy` 의 분리 스티어링(`enemy.dart:252`)처럼 순수 조회용 직접 순회는 허용하되, 그 루프 안에서 콜백성 호출(피해·스폰·제거)을 하지 못하게 코드 리뷰 체크리스트/CLAUDE.md 규칙으로 고정 | `lib/game/entities/enemy.dart`, 프로젝트 지침 문서 | `enemy.dart:252` | 규칙 문서화는 강제력이 없음 — 순위 2 의 테스트가 실질 방어선 |
  | 5 | (낮음) 만렙 직행 등 대량 `gainXp` 입력이 들어올 수 있으면 `_levelUp` 반복에 프레임당 상한을 두는 방안 검토 | `lib/game/entities/player.dart:741` | `level_system.dart:44`(최대 999레벨) | 실제 발생 조건이 희박[추측] — 과잉 대응 금지, 관측 후 결정 |

  

## 6. 불확실 · 미확인

  - **재현 로그 부재.** 실제 hang 당시의 스택 트레이스를 보지 못했다. 주석이 원인을 자백하고 있지만, 그 주석이 쓰인 시점 이후 다른 hang 이 새로 생겼을 가능성은 배제 못 한다. 우선순위 3 의 확인이 필요하다.
  - **`GameAudio` 구현 미열람.** `lib/game/audio/` 내부(사운드 풀링, `await` 유무)를 읽지 않아 오디오 경로의 hang 가능성은 판단 보류다.
  - **Flame 의 `update` 중 예외 처리 경로 미확인.** 예외가 발생하면 Flame/Flutter 엔진이 다음 프레임을 계속 도는지, 게임이 영구 정지 상태로 보이는지는 프로젝트 코드만으로는 확인 불가(엔진 동작, 외부 지식에 의존).
  - **SpacetimeDB 클라이언트 타임아웃 미확인.** `reportProgress` 의 `await` 가 영구 미완료될 수 있는지는 `spacetimedb` 라이브러리 설정을 봐야 한다. 게임 루프와는 비동기로 분리돼 있어 hang 과 무관하지만 로그아웃 시 `flushProgress` 는 3초 타임아웃(`action_rpg_game.dart:1011`)으로 방어돼 있다.
  - **git 이력 부족.** 로컬 로그가 2개 커밋뿐이라 스냅샷 수정이 언제 들어왔는지, 실행 중인 앱에 포함됐는지 판별하지 못했다.
  - **작업공간 불일치.** 지정된 분석 대상은 `/Users/thruthesky/.claude/plugins/cache` 였으나 게임 소스는 `/Users/thruthesky/tmp/games/actionrpg` 에 있었다. 의도한 대상이 이 프로젝트가 맞는지는 요청자 확인이 필요하다(다른 사본이 있으면 결론을 다시 내려야 한다).
