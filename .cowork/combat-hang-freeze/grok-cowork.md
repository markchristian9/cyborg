<!-- cowork:grok | 2026-08-04 22:05:28 | exit=0 | 602s -->
# grok 분석 — combat-hang-freeze

> 요청: 전투 중 PC가 공격을 받거나, 몬스터가 공격을 받거나, 누군가 사망하면 게임이 멈춰버리는(hang/freeze) 현상이 발생합니다. 원인을 코드 근거(파일:줄)와 함께 규명해 주세요. 특히 다음을 검증해 주세요: (1) lib/game/action_rpg_game.dart 의 meleeTargets()/projectileTargetsForPlayer() 가 sync* 지연 순회로 enemies 리스트를 흘려보내던 것이, 호출부(lib/game/entities/player.dart _resolveMeleeHit)가 순회 도중 applyDamage 로 적을 죽여 onEnemyKilled 가 enemies.remove 를 하면서 ConcurrentModificationError 를 일으키고 그 예외가 Flame update 안에서 터져 게임 루프가 멈추는 것이 진짜 원인인가? (2) 플레이어 사망 경로 onPlayerDied() -> _refreshMonsterStreaming() 이 Enemy.update/Projectile.update 순회 도중 enemies 를 add/remove 하는데 여기에도 같은 종류의 hang 위험이 남아 있는가? (3) 그 밖에 hang 을 일으킬 다른 원인(무한 루프, await 교착, 오디오, 네트워크 동기화 spacetime_game_sync.dart 의 while(true), 레벨업 while 루프 등)이 있는가? (4) 이 hang 을 재현하고 회귀를 막을 테스트를 어떻게 작성해야 하는가?
> 생성: 2026-08-04 22:05:28 · 소요 602s · 읽기 전용 분석(작업공간 미수정)

---



## 1. 결론 요약

**(1) 커밋 `15fa510` 기준으로, 근접 처치 경로의 `ConcurrentModificationError` 가설은 성립한다.** `meleeTargets()` 가 `sync*` 로 `enemies` 를 지연 순회하고, `_resolveMeleeHit` 이 순회 중 `applyDamage` → `onEnemyKilled` → `enemies.remove` 를 호출하면 다음 `moveNext` 에서 CME 가 난다. 이 예외는 `Player`/`Game` 의 `update` 스택에서 터지므로 전투 중 freeze 로 체감된다.  
**(현재 워킹트리는 이미 `List` 스냅샷으로 이 경로를 막아 두었고, 그 수정은 아직 미커밋이다.)**  
**(2) `onPlayerDied` → `_refreshMonsterStreaming` 은 “같은 즉시 CME”로 단정할 근거가 약하다.** 사망 유발 콜스택은 `for (game.enemies)` 밖이며, 다음 적의 separation 은 변경된 목록으로 새로 시작한다. 다만 update 중 목록 구조 변경 패턴 자체는 남는다.  
**(3) `while(true)`·레벨업 `while`·오디오는 이 hang 의 주원인이 아니다.** 원거리 탄은 명중 후 `return` 이라 **enemies CME 재현 빈도는 근접보다 훨씬 낮다**(1차의 “동일 빈도” 서술은 과하다).  
**(4) 회귀 테스트는 “순회 중 remove 해도 예외 없음”을 `meleeTargets` 계약으로 잠그고, 다수 처치·(옵션) 안티패턴 `sync*` 를 문서화하는 쪽이 맞다.**

## 2. 근거

- `15fa510:lib/game/action_rpg_game.dart` (`git show`) — `meleeTargets()` / `projectileTargetsForPlayer()` 가 `sync*` 이며 `yield* enemies.where(...)` 로 원본 리스트를 지연 순회.
- `lib/game/action_rpg_game.dart:756-775` (현재, `git blame`: Not Committed Yet) — 스냅샷 `List` + 주석이 CME·`update` 안 예외·전투 freeze 를 **동일 원인**으로 명시.
- `lib/game/entities/player.dart:448-466` — `for (final target in game.meleeTargets())` 도중 `target.applyDamage(...)` (break/return 없음 → 다음 대상·iterator 종료까지 계속).
- `lib/game/entities/enemy.dart:337-368`, `377-394` — `applyDamage` → `_die` → `game.onEnemyKilled(this)` → `removeFromParent()`.
- `lib/game/action_rpg_game.dart:1023-1024` — `onEnemyKilled` 가 **즉시** `enemies.remove(enemy)`.
- `lib/game/entities/projectile.dart:84-97` — 플레이어 탄은 `projectileTargetsForPlayer()` 순회 중 `applyDamage` 후 `_burst(); return;` → **iterator 의 다음 `moveNext` 를 호출하지 않음** (enemies CME 조건이 근접과 다름).
- `lib/game/action_rpg_game.dart:1112-1132`, `584-630` — 사망 시 동기 `_refreshMonsterStreaming()` 이 `enemies.remove`/`add` + `removeFromParent`/`world.add`.
- `lib/game/entities/enemy.dart:252-260`, `296-305` — separation 은 `for (final other in game.enemies)` 라이브 순회; 플레이어 처치는 `_resolveMeleeStrike` 경로(separation 밖).
- `lib/game/action_rpg_game.dart:407-411`, `421` — `super.update` 후 `_pruneRemoved`/`_updateStreaming`; 컴포넌트 순회가 끝난 뒤 목록 정리.
- `lib/game/net/spacetime_game_sync.dart:79-116` — `while(true)` 는 `async` + `await` + `_pending == null` 시 return; 게임 `update` 동기 블록 아님.
- `lib/game/entities/player.dart:740-743`, `level_system.dart:123-134` — 레벨 `while` / 이진 탐색은 `reached`·`low < high` 로 유한.
- `lib/game/audio/game_audio.dart:146-147` — 미초기화·비지원 시 재생 무시; “소리 때문에 게임이 멈추는 일은 없다”.
- Flame 1.38.0 `component.dart:32-35` — add/remove 는 “not immediate”, 다음 tick 큐 처리(트리 즉시 CME 보다 앱 리스트 CME 가 증상에 부합).
- `test/combat_damage_test.dart` — 피해 수치 불변식만; **목록 변이/CME/hang 회귀 테스트 없음**.
- 워크스페이스 `/Users/thruthesky/.claude/plugins/cache` 에는 게임 소스 없음; 근거는 `/Users/thruthesky/tmp/games/actionrpg`.

## 3. 상세 분석

### 3.1 범위와 권위

| 구분 | 내용 |
|---|---|
| 분석 요청 경로 | 플러그인 `cache` — 게임 코드 없음 |
| 실제 코드 | `/Users/thruthesky/tmp/games/actionrpg` (Cyborg, Flutter+Flame) |
| 증상 재현 기준 | **마지막 커밋 `15fa510` 의 `sync*` API** |
| “지금 디스크” 기준 | 워킹트리 스냅샷 수정(미커밋) — 가설 코드와 **의도적으로 다름** |

`.cowork/cowork-prompt.md` 는 HP·방어력 재설계용 프롬프트이며 combat-hang 전용 폴더는 없다. 전투 hang 판단의 1차 권위는 **소스·git 이력**이다.

### 3.2 (1) CME 경로 — 주원인 (커밋 기준, 근접)

호출 체인:

1. `ActionRpgGame.update` → `super.update` → `Player.update` → `_updateMelee` → `_resolveMeleeHit`
2. `for (target in meleeTargets())` — 커밋: `Iterable` 이 `enemies`(및 `_destructibles`) 에 묶인 lazy iterator
3. 처치: `Enemy.applyDamage` → `_die` → `onEnemyKilled` → **`enemies.remove`**
4. for 가 **다음** 대상(다른 적·상자)을 위해, 또는 해당 `where` iterator 를 닫기 위해 `moveNext` → Dart 가 목록 수정을 감지 → **`ConcurrentModificationError`**
5. 예외가 `update` 스택을 뚫고 나감 → 해당 프레임(및 이후 전투 판정)이 깨져 hang/freeze 로 보임

**왜 “몬스터를 때리거나 누군가를 죽일 때”에 특히 맞는가**

- 처치가 있어야 `enemies.remove` 가 돈다. 데미지만 넣고 안 죽이면 `onEnemyKilled` 가 안 불린다 (`enemy.dart:368`).
- 근접은 한 스윙에 여러 대상을 **return 없이** 순회한다 (`player.dart:448-474`).
- 단일 적만 있어도, 커밋의 `yield* enemies.where` 가 수정된 뒤 종료/`destructibles` 로 넘어가려면 iterator 가 다시 전진하므로 CME 가 날 수 있다. 다수 처치 시 재현은 더 쉽다.

**원거리 — 1차 주장 축소**

`projectile.dart:91-96` 은 명중 즉시 `return` 한다. Dart CME 는 보통 **수정 후 같은 iterator 의 다음 전진**에서 터진다. 따라서 플레이어 탄 1킬은 **enemies CME 를 자주 일으키지 않는다.** “원거리도 동일 클래스”는 API 가 lazy 였다는 점에서는 맞지만, **증상 빈도·재현 조건에서는 근접이 본체**다. 탄이 여러 후보를 스치다 **살린 대상 검사 중 앞선 대상이 다른 경로로 목록에서 빠지는** 식의 교차 변이만 남고, 일반 전투 hang 설명으로는 2순위다.

**블록(상자) — 커밋 기준 부가 경로**

`_destructibles` 는 여전히 `sync*` 이며 (`action_rpg_game.dart:634-639`) 청크 `List` 를 중첩 순회한다. 커밋의 lazy `meleeTargets` 가 상자를 yield 한 뒤 `onBlockDestroyed` 가 `chunk.remove` 하면 (`1060-1065`) **청크 리스트 CME** 도 가능했다. 현재 `_damageableTargets` 의 `...` 스냅샷은 이 경로도 함께 막는다.

**워킹트리**

```dart
List<Damageable> _damageableTargets() => <Damageable>[
  ...enemies.where(...),
  ..._destructibles.where(...),
];
```

순회 **전** 복사 → 순회 중 `enemies.remove` 해도 for 는 스냅샷을 돈다. `player.dart:449-450` 주석(죽은 대상 skip)과 맞물린 수정이다.

### 3.3 (2) 플레이어 사망 → 스트리밍

경로: 적 근접/탄/지형 → `Player.applyDamage` → `onPlayerDied` → 리스폰 + `_refreshBlockStreaming` + `_refreshMonsterStreaming`.

| 질문 | 판정 | 근거 |
|---|---|---|
| 사망 콜스택이 `for (enemies)` 안인가? | 아니오 | strike/탄/hazard 는 separation 밖 |
| 그 순간 다른 적이 separation 중인가? | 순차 update 이면 아님 | 싱글 스레드; A 의 strike 중 B 의 for 가 동시에 안 돎 |
| 다음 적 update 의 for | 새 `enemies` 로 시작 | CME 조건(순회 중 수정) 미충족 |
| Flame children CME | 낮음 | add/remove 큐잉 (`component.dart:32-35`) |
| 구조적 취약 | 남음 | 콜백에서 `enemies` 구조 변경; separation 은 여전히 라이브 for (`enemy.dart:252`) |
| 체감 프리즈 | 가능(별 이슈) | 사망 순간 대량 remove/add/world.add — **예외가 아니라 프레임 스파이크** `[판단]` |

**“PC 가 공격을 받을 때” 증상과의 정합**

- **비사망 피격**: `onPlayerDamaged` 만 (`1095-1097`) — `enemies` 변이 없음 → **가설 (1) CME 로는 설명 불가**.
- **사망 피격**: 스트리밍 변이 + UX 상 “맞자마자 멈춤” 혼동 가능.
- 전투 중 플레이어도 스윙 중이면 **피격과 처치가 같은 세션에 겹쳐** “맞을 때마다 멈춘다”로 기억될 수 있음 `[추측: 체감 보고]`.

따라서 (2) 를 “남아 있는 동일 hang 원인”으로 올리면 과하다. **즉시 CME 주원인 아님 / 장기 안전 설계 이슈** 가 정확하다.

### 3.4 (3) 기타 hang 후보

| 후보 | 판정 | 이유 |
|---|---|---|
| `SpacetimeGameSync._send` `while(true)` | 주원인 아님 | async·탈출 조건·`_inFlight` 큐 |
| `gainXp` `while (level < reached)` | 아님 | `level++`, 유한 |
| `levelForTotalXp` while | 아님 | 이진 탐색 |
| 맵 크레이트 while | 아님 | `attempts < 40000` (`level_map.dart:435`) |
| GameAudio | 아님 | 실패 무시 설계 |
| Flame 트리 concurrent | 낮음 | lifecycle 큐 |
| HUD `for (game.enemies)` (`hud.dart:473`) | 낮음 | render 단계; update 와 분리 |
| `_hitStop` (`398-400`) | freeze 아님 | dt 축소(슬로우)일 뿐 |
| **미처리 예외 일반** | 증상 메커니즘 | update 안 CME 가 대표 |

### 3.5 (4) 테스트 설계 (작성 방향만)

1. **계약 테스트 (권장 1순위)**  
   - 최소 하네스: `enemies` 에 mock/`Enemy` 2+ 와 `meleeTargets()` 순회 중 `onEnemyKilled` 상당 `remove` 를 넣고 `expect(..., returnsNormally)`.  
   - 반환이 **eager `List`(또는 복사본)** 임을 고정하면 lazy 회귀를 막는다.

2. **안티패턴 문서 테스트 (선택)**  
   - 순수 Dart: `sync* { yield* list.where(...) }` + for 중 `remove` → CME 기대.  
   - “왜 스냅샷인가”를 코드베이스에 남긴다. 게임 기동 불필요.

3. **통합 (Flame/`flutter_test`)**  
   - 근접 범위에 적 2+ · 한 스윙 연속 처치 · `game.update(dt)` 예외 없음 · `status == playing`.  
   - 사망: 다수 활성 몹 + 즉사 피해 후 수 프레임 update — CME 없음 확인(스트리밍 스파이크와 분리해 측정).

4. **CLAUDE.md 제약** (`CLAUDE.md:44-46`)  
   - 수동 키보드 주입 금지; `main`/핸들러 주입 또는 순수 단위 테스트.

5. **비목표**  
   - `while(true)` 타임아웃 테스트는 이 hang 의 회귀 잠금에 비효율.

## 4. 리스크 · 함정

- **커밋/배포 불일치**: 스냅샷이 미커밋이면 CI·다른 클론·릴리즈는 여전히 `sync*` hang. “로컬에선 고쳤다”와 “배포 재현”이 갈린다.
- **증상 혼동**: (A) CME 예외 정지 (B) 사망 스트리밍 프레임 스파이크 (C) 비사망 피격의 별 원인. 재현 시 콘솔에 `ConcurrentModificationError` 유무로 갈라야 한다.
- **원거리를 “고쳤다”고 과신**: 탄 경로는 원래 CME 빈도가 낮아, 스냅샷만으로 체감이 안 바뀔 수 있다. 검증 초점은 **근접 다수/단일 처치**.
- **`_destructibles` 는 여전히 `sync*`**: 헬퍼가 `...` 로만 소비하면 안전. 다시 lazy `meleeTargets` 로 되돌리면 **상자 파괴 CME** 도 재개.
- **`Enemy._moveToward` 라이브 for**: 미래 기능이 순회 중 `enemies` 를 건드리면 재발.
- **`onEnemyKilled` → `gainXp` → 레벨업 연출** 이 처치 콜스택에 붙음 — CME 와 별개로 한 스윙 다수 킬 시 비용.
- 플러그인 `cache` 만 보면 근거 제로 — 반드시 actionrpg 트리를 본다.

## 5. 권고안

| 순위 | 권고 | 범위 | 근거 | 리스크 |
|---|---|---|---|---|
| 1 | **스냅샷 `meleeTargets`/`projectileTargetsForPlayer` 유지·커밋.** 다시 `sync*`/lazy `Iterable` 로 되돌리지 말 것 | 전투 판정 API | `756-775` vs `15fa510` sync*; `player.dart:448-466`; `1023-1024` | 없음(수정 유지) |
| 2 | **`test/` 에 목록 변이 회귀**: `meleeTargets` 순회 중 `enemies.remove` 해도 예외 없음 + (옵션) 반환 타입/복사 계약 | `test/` | hang 테스트 부재; `combat_damage_test` 는 수치만 | 구현 세부 결합 시 깨짐 → 공개 API 계약 중심 |
| 3 | **재현 절차 고정**: 커밋 `15fa510` 체크아웃에서 근접 다수 처치 → CME 스택 확인; 워킹트리에서 동일 시나리오 → 예외 없음. 비사망 피격만으로는 가설 (1) 을 기각하지 말 것 | 디버깅 | §3.2–3.3 | 빌드 혼동 |
| 4 | **`Enemy._moveToward` 분리 대상 스냅샷**(또는 공간 구조) | `enemy.dart:252-260` | 라이브 for | 프레임당 복사(상한 140이면 통상 허용) |
| 5 | **사망/스트리밍 목록 변이를 update 끝 큐로 미루기** — “즉시 CME 수정”이 아니라 구조 안전 | `1112-1132`, `584-630` | 콜백 중 변이 | 한 프레임 빈 안전지대 UX; 주석이 이미 경고 |
| 6 | hang 1순위로 `while(true)`/오디오/네트워크를 쫓지 말 것; **update 스택 예외 로그** 먼저 | 절차 | spacetime 92-116; game_audio 146-147 | 시간 낭비 |

(분석 전용: 파일 수정·테스트 실행 없음. 방향·위치만.)

## 6. 불확실 · 미확인

- **실기기/플레이 로그**에 실제 `ConcurrentModificationError` 스택이 있는지 — 코드·git·작성자 주석과 정합하나 런타임 로그는 미확인.
- Flutter/Flame 이 update 예외 후 **루프를 완전히 멈추는지**, 매 프레임 재throw 로 “사실상 freeze” 인지는 플랫폼/zone 설정에 따라 다를 수 있음 — “멈춘 것처럼 보인다” 수준으로 한정.
- 워킹트리 스냅샷 **이후에도** hang 이 남는다면 CME 외(스트리밍 스파이크, 다른 예외, 플랫폼 오디오 등) — **재현 빌드가 커밋인지 워킹트리인지** 가 갈림.
- 비사망 PC 피격만으로 재현되는 hang 이 있다면 가설 (1) 단독으로는 부족 — 추가 스택 필요.
- 이 세션에서 순수 Dart CME 재현 스크립트는 **실행하지 않음**(읽기 전용). 판정은 Dart 순회 의미론 + 코드 경로 + 저장소 주석에 의존.
- 멀티플레이 원격 엔티티 목록 동시 수정 hang — `.cowork/cowork-prompt.md` 상 실시간 동기화 없음, 현 범위 밖.
- 캐시 워크스페이스 내 타 AI combat-hang 교차 보고 — 해당 산출물 폴더 없음.

## 7. 자기 비판으로 바로잡은 것

- ❌ 철회: “원거리 `projectileTargetsForPlayer` 도 근접과 같은 빈도로 CME hang 의 주경로” — `projectile.dart:91-96` 을 다시 보면 명중 후 `return` 으로 iterator 를 더 돌리지 않는다. lazy API 위험은 공유하나 **재현 본체는 근접**.
- ❌ 철회: “Dart 재현 실험으로 확정” 을 1차 근거 목록에 동급으로 둔 것 — Pass 2 에서는 재실행하지 않았고, **코드 경로 + Dart 순회 의미론 + 미커밋 수정 주석** 만 근거로 남긴다.
- 🔁 수정: “(2) 구조적 취약 유지 = hang 위험 잔존” 의 어조 → **즉시 CME hang 은 반증에 가깝고**, 남아 있는 것은 콜백 중 목록 변이·프레임 스파이크·미래 교차 순회 위험. “같은 종류의 hang 이 남아 있다” 는 과대.
- 🔁 수정: 사용자 증상 “PC 가 공격을 받을 때” 를 가설 (1) 에 뭉뚱그림 → **비사망 피격은 CME 경로 아님**; 사망·동시 스윙·스파이크와 구분.
- ➕ 추가: 커밋 기준 **상자(`_destructibles`/`onBlockDestroyed`) CME** 가능성 — `634-639`, `1060-1065`, lazy melee 순회.
- ➕ 추가: update 순서상 `_pruneRemoved` 는 `super.update` **이후** (`407-421`) 라, 컴포넌트 순회 중 prune 으로 인한 CME 는 1차 시나리오와 별개로 낮음.
- ➕ 추가: Flame 1.38.0 공식 주석(`component.dart:32-35`)으로 “트리 즉시 CME” 반증을 재확인 — 1차의 pub-cache 인용과 일치, hang 직접 원인은 앱 `List enemies`.
- 🔁 수정: 권고 3순위를 “separation 스냅샷”보다 앞선 **재현 절차(커밋 vs 워킹트리 분리)** 로 올려, 미커밋 수정 착각을 줄임.
