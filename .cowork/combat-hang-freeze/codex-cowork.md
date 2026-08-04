<!-- cowork:codex | 2026-08-04 21:58:09 | exit=0 | 163s -->
# codex 분석 — combat-hang-freeze

> 요청: 전투 중 PC가 공격을 받거나, 몬스터가 공격을 받거나, 누군가 사망하면 게임이 멈춰버리는(hang/freeze) 현상이 발생합니다. 원인을 코드 근거(파일:줄)와 함께 규명해 주세요. 특히 다음을 검증해 주세요: (1) lib/game/action_rpg_game.dart 의 meleeTargets()/projectileTargetsForPlayer() 가 sync* 지연 순회로 enemies 리스트를 흘려보내던 것이, 호출부(lib/game/entities/player.dart _resolveMeleeHit)가 순회 도중 applyDamage 로 적을 죽여 onEnemyKilled 가 enemies.remove 를 하면서 ConcurrentModificationError 를 일으키고 그 예외가 Flame update 안에서 터져 게임 루프가 멈추는 것이 진짜 원인인가? (2) 플레이어 사망 경로 onPlayerDied() -> _refreshMonsterStreaming() 이 Enemy.update/Projectile.update 순회 도중 enemies 를 add/remove 하는데 여기에도 같은 종류의 hang 위험이 남아 있는가? (3) 그 밖에 hang 을 일으킬 다른 원인(무한 루프, await 교착, 오디오, 네트워크 동기화 spacetime_game_sync.dart 의 while(true), 레벨업 while 루프 등)이 있는가? (4) 이 hang 을 재현하고 회귀를 막을 테스트를 어떻게 작성해야 하는가?
> 생성: 2026-08-04 21:58:09 · 소요 163s · 읽기 전용 분석(작업공간 미수정)

---



## 1. 결론 요약

현재 작업공간에는 요청한 게임 코드가 없어 제시된 원인을 코드 근거로 확정할 수 없다.  
(1)의 `sync* → 순회 중 enemies.remove → ConcurrentModificationError`는 조건부로 타당하지만, 실제 구현·스택 트레이스가 없어 “진짜 원인” 또는 영구적인 게임 루프 정지까지는 미확인이다.  
(2)는 단순히 `Enemy.update`/`Projectile.update` 중 목록을 변경했다는 이유만으로 같은 오류가 되지는 않으며, 그 순간 살아 있는 `enemies` iterator가 있어야 한다.  
(3)의 네트워크·레벨업·오디오 경로 역시 자료가 없으며, (4)의 회귀 테스트는 실제 게임 저장소와 Flame 테스트 환경에서 작성해야 한다.

## 2. 근거

- `.cowork/combat-hang-freeze/.prompt.md:29-34` — 지정된 작업공간은 `/Users/thruthesky/.claude/plugins/cache`이며, 개발 매니페스트가 없고 최상위 구조도 플러그인 패키지들이다.
- `.cowork/combat-hang-freeze/.prompt.md:113` — `action_rpg_game.dart`, `player.dart`, `spacetime_game_sync.dart` 및 관련 함수명은 실제 코드가 아니라 분석 요청문에만 등장한다.
- 작업공간 전수 파일명 검색 — 파일 821개 중 `.dart`는 1개, `lib/game/`과 `pubspec.yaml`/`pubspec.lock`은 0개였다.
- 작업공간 전수 정확 문자열 검색 — `.cowork` 요청·로그를 제외하면 `meleeTargets`, `_resolveMeleeHit`, `onEnemyKilled`, `onPlayerDied`, `_refreshMonsterStreaming`, `ConcurrentModificationError`가 모두 0건이었다.
- `thruthesky-skills/currency-skill/1.0.0/scripts/test_frankfurter.dart:1-18` — 유일한 Dart 파일은 Frankfurter 환율 API 테스트이며 게임과 무관하다.
- `RevenueCat/RevenueCat/2.0.0/.claude-plugin/plugin.json:2-13` — `RevenueCat` 인앱 결제 플러그인 패키지다.
- `claude-plugins-official/ralph-loop/1.0.0/.claude-plugin/plugin.json:2-7` — `while-true` AI 반복 실행을 제공하는 `ralph-loop` 플러그인이다.
- `claude-plugins-official/ralph-loop/1.0.0/README.md:3-27` — 이 작업공간에서 확인되는 `while true` 설명은 게임 동기화가 아니라 Claude 반복 작업 기능이다.
- `claude-plugins-official/swift-lsp/1.0.0/README.md:1-10` — 다른 최상위 패키지는 Swift 언어 서버 플러그인이다.
- `thruthesky-skills/flutter-skill/1.0.0/.claude-plugin/plugin.json:2-8` — Flutter 관련 자료도 애플리케이션 코드가 아니라 개발 지침을 제공하는 스킬이다.
- `thruthesky-skills/cowork/2.1.0/.claude-plugin/plugin.json:2-8` — 현재 경로에는 분야 중립 교차 분석용 `cowork` 스킬도 캐시되어 있다.

## 3. 상세 분석

### 범위

확정 가능한 범위는 `/Users/thruthesky/.claude/plugins/cache` 내부다. 이곳에는 게임 구현·테스트·Flame 의존성 매니페스트·런타임 스택 트레이스가 없다. 따라서 아래의 원인 평가는 실제 코드 판정이 아니라 조건부 분석이며, 요청문 자체를 코드 증거로 취급하지 않는다.

### (1) melee 순회 중 적 제거

[판단] 다음 조건이 실제 코드에서 모두 성립한다면 제시된 `ConcurrentModificationError` 경로는 강한 원인 후보다.

1. `meleeTargets()`가 `sync*`이고 `enemies`를 복사하지 않은 채 직접 순회한다.
2. `_resolveMeleeHit()`가 반환된 `Iterable`을 지연 순회한다.
3. 순회 본문에서 `applyDamage()`가 동기적으로 적을 죽인다.
4. 사망 콜백이 같은 `enemies` 목록을 즉시 구조 변경한다.
5. 순회가 다음 원소를 요구하고, 중간에 snapshot·중단·지연 제거가 없다.

반대로 `toList()` snapshot, 프레임 종료 시 제거 예약, 첫 타격 후 즉시 `break`, 별도의 적 레지스트리 사용 중 하나라도 존재하면 호출 관계와 오류 발생 조건이 달라진다. 현재는 이 구현을 확인할 파일이 없다(`.cowork/combat-hang-freeze/.prompt.md:113`, 전수 검색 결과).

또한 [판단] `ConcurrentModificationError`가 발생했다는 것과 “Flame 게임 루프가 영구 정지했다”는 것은 별도 검증 대상이다. 실제 예외 스택, Flutter error handler, Flame 버전, 이후 frame callback 발생 여부가 있어야 freeze와의 인과관계를 확정할 수 있다.

### (2) 플레이어 사망과 monster streaming

[판단] `Enemy.update` 또는 `Projectile.update`가 실행되는 동안 `_refreshMonsterStreaming()`이 `enemies`를 변경한다는 사실만으로는 `ConcurrentModificationError`가 성립하지 않는다. 오류가 발생하려면 동일한 `enemies` 목록을 순회하는 iterator가 호출 스택 어딘가에서 아직 활성 상태여야 한다.

Flame component-tree의 update 순회와 게임이 별도로 보유한 `enemies` 목록은 구분해야 한다. 다음 두 경우는 위험도가 다르다.

- `for (final enemy in enemies) { enemy.update → onPlayerDied → refresh → enemies.remove(...) }`: 같은 목록의 활성 iterator를 변경하므로 위험하다.
- Flame이 component tree를 순회하는 중 `Enemy.update → onPlayerDied → refresh`가 실행되고, 그 시점에 `enemies` iterator가 없다: 목록 변경 자체만으로 같은 오류라고 단정할 수 없다.

또한 component 추가·제거가 즉시 처리되는지 다음 tick으로 예약되는지도 실제 Flame API 사용법을 봐야 한다. 관련 코드가 전혀 없어 잔존 위험 여부는 미확인이다.

### (3) 다른 hang 후보

- `spacetime_game_sync.dart`의 `while(true)`: 파일이 없으므로 미검증이다. [판단] 루프 본문에 항상 대기하는 `await`, backoff, 취소 조건이 있는지와 즉시 완료되는 Future만 반복해 event queue를 굶기는지를 확인해야 한다.
- 레벨업 `while`: 관련 코드가 없다. [판단] 매 반복마다 XP 감소 또는 다음 요구 XP 증가가 보장되는지, 0·음수·overflow 값에서 진행성이 깨지는지 확인해야 한다.
- `await` 교착: Future 의존 관계와 update 경로에서의 대기 여부를 확인할 수 없다.
- 오디오: 게임 오디오 호출이 존재하지 않아 동기 차단·완료되지 않는 Future·플랫폼 예외 여부를 평가할 수 없다.
- 현재 캐시의 `while true`는 `ralph-loop` 플러그인 설명일 뿐 게임 hang 근거가 아니다(`claude-plugins-official/ralph-loop/1.0.0/README.md:3-27`).

### (4) 재현·회귀 테스트 설계

다음은 실제 프로젝트에서 적용할 [판단] 기반 테스트 설계다.

1. **적 사망 중 iterator 변경 재현**
   - `enemies`에 최소 2~3개 적을 넣고 첫 번째 또는 중간 적의 HP를 한 번의 공격으로 사망하도록 설정한다.
   - 실제 `_resolveMeleeHit()` 경로를 실행한다.
   - `game.update(dt)`가 예외 없이 반환되고 이후 적도 정상 처리되는지 검증한다.
   - 제거된 적이 registry와 component tree 양쪽에서 한 번만 제거됐는지도 확인한다.

2. **Projectile 대상 순회 회귀**
   - `projectileTargetsForPlayer()`의 실제 소비자인 projectile 충돌 경로에서 중간 적을 사망시킨다.
   - 첫 frame뿐 아니라 여러 후속 frame을 실행해 update counter가 계속 증가하는지 확인한다.

3. **플레이어 사망 경로**
   - 각각 `Enemy.update`와 `Projectile.update` 안에서 치명타를 발생시킨다.
   - `_refreshMonsterStreaming()`이 먼 적 제거와 새 적 추가를 모두 수행하도록 경계 조건을 만든다.
   - 예외 부재, 다음 frame 진행, 중복 적·고아 component·registry 불일치 부재를 검증한다.

4. **루프 진행성**
   - 동기화 transport를 fake로 교체해 즉시 실패·즉시 완료·영구 미완료 Future를 주입한다.
   - event-loop heartbeat가 진행되고 dispose/cancel 후 재접속 루프가 끝나는지 검증한다.
   - 레벨업에는 0, 경계 XP, 매우 큰 XP를 넣어 종료와 예상 레벨 수를 검증한다.

5. **오디오 격리**
   - 오디오 Future가 예외를 던지거나 완료되지 않아도 `update()`가 이를 기다리지 않고 후속 frame을 진행하는지 fake audio backend로 검증한다.

## 4. 리스크 · 함정

- 요청문에 적힌 호출 관계를 실제 코드로 간주하면 존재하지 않는 줄번호와 이미 수정됐을 수 있는 과거 구현을 지어내게 된다.
- `ConcurrentModificationError`와 사용자에게 보이는 freeze를 같은 사건으로 단정하면 별개의 렌더링·스케줄러·디버거 문제를 놓칠 수 있다.
- `enemies` registry와 Flame component tree를 동일 컬렉션으로 취급하면 플레이어 사망 경로의 위험을 과대평가할 수 있다.
- 모든 대상 반환값을 무조건 `toList()`로 바꾸면 적 수에 비례한 frame당 할당과 오래된 snapshot을 사용하는 의미 변화가 생길 수 있다.
- streaming 변경을 다음 frame으로 미루면 현재 frame의 충돌·보상·targeting 순서가 달라질 수 있다.
- 테스트가 “예외가 없었다”만 확인하면 update가 실제로 중단된 freeze를 놓친다. 반드시 후속 frame의 진행성과 상태 변화를 함께 검사해야 한다.
- 캐시에 있는 `ralph-loop`의 `while true`를 `spacetime_game_sync.dart`의 증거로 오인하면 전혀 무관한 원인을 추적하게 된다.

## 5. 권고안

| 순위 | 권고 | 범위 | 근거 | 리스크 |
|---|---|---|---|---|
| 1 | 실제 게임 프로젝트 루트에서 분석을 다시 수행하고 지정된 세 파일, `pubspec.yaml`, 관련 테스트 및 freeze 스택 트레이스를 함께 제공한다 | 작업공간 선택 | `.cowork/combat-hang-freeze/.prompt.md:29-34`, 전수 검색 결과 | 잘못된 저장소이면 원인 규명이 계속 불가능 |
| 2 | `_resolveMeleeHit`부터 `onEnemyKilled`까지 실제 동기 호출 순서를 추적하고, 활성 iterator와 `enemies.remove`가 같은 목록을 공유하는지 확인한다 | melee 전투 경로 | `.cowork/combat-hang-freeze/.prompt.md:113`의 검증 대상 | snapshot·예약 제거가 있으면 초기 가설이 반증될 수 있음 |
| 3 | live iterable이 확인되면 대상 계산 시 snapshot을 만들거나 사망 제거를 순회 종료 이후에 처리하도록 책임 위치를 정한다 | targeting/사망 처리 경계 | §3의 조건부 오류 경로 | 할당 증가 또는 전투 처리 순서 변화 |
| 4 | `onPlayerDied → _refreshMonsterStreaming`의 모든 진입점을 찾아 registry 순회와 component update 순회를 분리하고, 필요하면 streaming 변경을 안전한 frame 경계에 예약한다 | 사망·streaming 계층 | §3의 활성 iterator 조건 | 한 frame 늦은 spawn/despawn이 게임 규칙에 영향 |
| 5 | melee kill, projectile kill, Enemy발 플레이어 사망, Projectile발 플레이어 사망을 각각 독립 테스트하고 여러 후속 frame의 진행성을 검증한다 | 전투 회귀 테스트 | §3 테스트 설계 | lifecycle 초기화가 실제 게임과 다르면 거짓 양성 가능 |
| 6 | 동기화·레벨업·오디오에는 진행성 및 취소 가능성 테스트를 추가하고, update 구간별 시간·예외·frame counter를 계측한다 | 보조 시스템 진단 | 현재 관련 코드 부재; [판단] 기반 검증 방향 | 계측 자체의 성능 영향과 시간 기반 테스트의 불안정성 |

## 6. 불확실 · 미확인

- 실제 게임 프로젝트의 위치와 현재 소스 버전.
- `meleeTargets()`와 `projectileTargetsForPlayer()`가 현재도 `sync*`인지, 이미 snapshot 반환으로 변경됐는지.
- `_resolveMeleeHit()`, `applyDamage()`, `onEnemyKilled()`의 실제 동기·비동기 호출 순서.
- `onPlayerDied()`를 호출하는 모든 경로와 `_refreshMonsterStreaming()` 내부의 정확한 add/remove 방식.
- Flame 및 Flutter 버전, component 변경 예약 정책, uncaught update 예외 이후 ticker 동작.
- freeze 당시 `ConcurrentModificationError` 스택 트레이스와 이후 frame이 실제 중단됐다는 관측 자료.
- `spacetime_game_sync.dart`, 레벨업, 오디오 구현과 기존 테스트의 존재 여부.
