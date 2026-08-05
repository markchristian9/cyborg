<!-- cowork:codex | 2026-08-05 22:12:58 | exit=0 | 395s -->
# codex 분석 — swing-animation-sync

> 요청: 서버/여러플레이어 화면 동기화 작업이 잘 되는지, 수정보완할 내용이 있으면 수정보완해주세요. 특히, pc 가 몬스터를 공격할 때 스윙/슬래시/칼휘두름 애니메이션이 내 화면에만 보이고, 다른 pc 화면에 보이지 않습니다. 이런 빠져있는 부분들을 수정/보완해주세요.
> 생성: 2026-08-05 22:12:58 · 소요 395s · 읽기 전용 분석(작업공간 미수정)

---



## 1. 결론 요약

현재 소스에는 위치·방향·몬스터·공격 사건의 서버 동기화 경로가 끝까지 연결되어 있다(`spacetimedb/src/world.rs:1480`, `lib/spacetime/spacetime_world_presence.dart:409`).
그러나 원격 엔티티가 `0`을 초기 기준으로 쓰는 오류 때문에, 접속 후 첫 PC 공격과 첫 몬스터 공격 애니메이션은 재현되지 않는다(`lib/game/entities/remote_player.dart:123`, `lib/game/entities/remote_player.dart:183`).
기존 통합 테스트는 공격 시각이 상대 캐시에 도착하는지만 확인하고 실제 `isSwinging` 재생은 검사하지 않아 이 결함을 놓쳤다(`test/attack_and_loot_sync_test.dart:155`).
피격·사망·대시·버프·콤보도 아직 완전한 공유 전투 상태가 아니므로, 현재 구현은 “부분적으로 동작하지만 MMORPG 전투 동기화 완료”로 판정할 수 없다.

## 2. 근거

- `CLAUDE.md:30` — 다른 플레이어의 존재·이동·전투가 실시간으로 보여야 하며 PK도 허용된다고 명시한다.
- `spacetimedb/src/world.rs:398` — `WorldPlayer`에 `last_attack_at`, 공격 방향, 스킬 종류를 상태로 저장한다.
- `spacetimedb/src/world.rs:1486` — `attack_monster`가 사거리·쿨다운·피해를 서버에서 판정한다.
- `spacetimedb/src/world.rs:1553` — 성공한 공격은 `last_attack_at`, `attack_dir_*`, `attack_skill`을 갱신한다.
- `lib/spacetime/spacetime_world_presence.dart:409` — 구독 행을 `RemotePlayer`로 변환하면서 공격 시각·방향·스킬을 전달한다.
- `lib/game/entities/remote_player.dart:123` — 재생한 공격의 초기값이 `0`으로 고정돼 있다.
- `lib/game/entities/remote_player.dart:183` — `_playedAttackAt != 0`일 때만 애니메이션을 시작하므로 첫 `0 → 서버 시각` 전이를 버린다.
- `lib/game/entities/remote_player.dart:399` — `isSwinging`일 때만 공격 팔·칼날·슬래시 궤적을 그린다.
- `lib/game/entities/enemy.dart:129` — 몬스터 공격 재생도 같은 `0` 초기값과 조건을 사용해 첫 타격을 누락한다.
- `test/attack_and_loot_sync_test.dart:109` — 통합 테스트는 관찰자 캐시의 공격 시각과 방향만 검증한다.
- `lib/game/net/world_presence.dart:9` — 원격 플레이어 모델에는 `deaths`와 `lastDamagedAtMicros`가 없다.
- `spacetimedb/src/world.rs:2314` — 사망 시 서버는 즉시 부활시키며 `deaths`를 증가시키므로 `alive` 전이만으로는 사망을 관찰할 수 없다.
- `lib/game/entities/player.dart:313` — 대시·에너지 소비·무적은 클라이언트에서만 시작된다.
- `spacetimedb/src/world.rs:2287` — 서버 피해 판정은 서버의 `invulnerable_until`만 보며 클라이언트 대시 상태를 알지 못한다.
- `lib/game/entities/enemy.dart:1164` — 서버 몬스터 체력 바가 서버 비율이 아닌 로컬 `_hp / _maxHp`를 사용한다.

## 3. 상세 분석

PC의 근접 공격 흐름은 다음과 같다.

1. 입력 즉시 `Player.tryMelee`가 로컬 `PlayerState.melee`와 스윙 타이머를 시작한다(`lib/game/entities/player.dart:198`).
2. 애니메이션 진행도 35%에서 대상 판정을 실행한다(`lib/game/entities/player.dart:537`).
3. 서버 몬스터에 닿으면 `Enemy.applyDamage`는 로컬 HP를 깎지 않고 `presence.attack`을 부른다(`lib/game/entities/enemy.dart:596`).
4. 서버 `attack_monster`가 사거리·쿨다운·피해를 확정하고 공격 사건을 `WorldPlayer` 행에 기록한다(`spacetimedb/src/world.rs:1486`, `spacetimedb/src/world.rs:1553`).
5. 관찰자는 구독 행에서 공격 시각·방향·스킬을 읽는다(`lib/spacetime/spacetime_world_presence.dart:409`).
6. `RemotePlayerEntity.applySnapshot`이 시각 변화를 보고 스윙을 재생해야 한다(`lib/game/entities/remote_player.dart:168`).

실패는 6단계에 있다. 엔티티 생성 후 공격이 없을 때 서버 값과 `_playedAttackAt`은 둘 다 `0`이므로 기준 상태가 초기화되지 않는다. 첫 공격으로 값이 `0 → T1`이 되면 변화는 감지하지만 `_playedAttackAt != 0` 조건이 거짓이라 스윙을 시작하지 않고 기준값만 `T1`으로 바꾼다. 두 번째 `T1 → T2`부터는 재생된다(`lib/game/entities/remote_player.dart:183`). 몬스터 공격도 같은 형태다(`lib/game/entities/enemy.dart:173`).

현재 동기화 범위를 행동별로 정리하면 다음과 같다.

| 행동 | 서버·전송 상태 | 다른 화면 결과 | 판정 |
|---|---|---|---|
| 이동·정지 방향 전환 | 좌표와 `facing_*`을 보고·구독(`lib/spacetime/spacetime_world_presence.dart:165`) | 보간 및 방향 반영(`lib/game/entities/remote_player.dart:244`) | 대체로 구현 |
| PC 근접 공격 | `last_attack_at`, 방향, 스킬 기록(`spacetimedb/src/world.rs:1553`) | 첫 공격 누락, 이후에는 일반화된 슬래시 | 결함 |
| 플라즈마 | `attack_skill = plasma` 기록(`spacetimedb/src/world.rs:1702`) | 원격 볼트는 생성하지만 칼 스윙도 함께 표시(`lib/game/entities/remote_player.dart:200`, `lib/game/entities/remote_player.dart:399`) | 연출 불일치 |
| 몬스터 공격 | `Monster.last_attack_at` 기록(`spacetimedb/src/world.rs:1942`) | 첫 타격 누락 | 결함 |
| 다른 PC 피격 | HP 비율만 전달(`lib/spacetime/spacetime_world_presence.dart:421`) | 체력 바만 갱신하고 피격 플래시·숫자는 없음(`lib/game/entities/remote_player.dart:208`) | 미완성 |
| 다른 PC 사망 | 서버 `deaths` 증가 후 즉시 부활(`spacetimedb/src/world.rs:2314`) | `RemotePlayer`가 `deaths`를 받지 않아 사망 사건 없이 위치만 순간 변경 | 미구현 |
| 대시 | 로컬 상태·무적만 존재(`lib/game/entities/player.dart:313`) | 빠른 이동처럼 보이며 서버 무적도 없음 | 서버 판정 미구현 |
| 포션·버프 | `inventory.use`가 클라이언트에 적용(`lib/game/action_rpg_game.dart:1698`) | 다른 PC에게 보이지 않고 서버 피해·공격 수식에도 반영되지 않음 | 서버 권위 미구현 |

로컬 콤보도 서버와 의미가 다르다. 클라이언트는 세 번째 공격에 `1.6` 피해 배율과 다른 스윙을 적용하지만(`lib/game/entities/player.dart:550`), 서버는 플레이어 레벨만으로 고정 피해를 계산한다(`spacetimedb/src/world.rs:807`, `spacetimedb/src/world.rs:1528`). 서버 몬스터는 클라이언트가 전달한 `damage` 값을 무시하므로(`lib/game/entities/enemy.dart:596`), 온라인에서 콤보 마무리는 강하게 보이지만 실제 피해는 강하지 않다.

모든 반복 공격까지 전혀 보이지 않는다면 현재 소스의 첫 공격 누락만으로는 설명되지 않는다. 성공한 두 번째 공격부터는 `_swingTimer`가 설정되기 때문이다(`lib/game/entities/remote_player.dart:184`). 이 경우 `[추측]` 실행 중인 클라이언트가 이전 빌드이거나 서버가 공격을 거절하고 있을 가능성이 있다. 현재 `SpacetimeWorldPresence.attack`은 reducer 결과를 `.ignore()`로 버려 이를 구분할 진단 정보가 없다(`lib/spacetime/spacetime_world_presence.dart:340`).

## 4. 리스크 · 함정

- `_playedAttackAt != 0` 조건만 제거하면 AOI에 새로 들어온 원격 PC의 과거 공격까지 즉시 재생한다. “첫 스냅샷 기준 확정”과 “그 뒤의 변화 재생”을 nullable 상태나 별도 초기화 플래그로 구분해야 한다(`lib/game/entities/remote_player.dart:178`).
- 짧은 `CombatEvent` 행을 같은 reducer에서 생성한 뒤 삭제하면 최종 상태만 복제되어 이벤트가 전달되지 않는다. 이벤트 표를 도입한다면 별도 만료 reducer가 필요하다(`GAME-SERVER.md:310`).
- 대시·콤보 단계를 클라이언트 인자로 그대로 신뢰하면 공격 속도·무적·피해 조작 경로가 된다. 행동 주체와 콤보 진행은 `ctx.sender()` 및 서버 시각에서 도출해야 한다(`spacetimedb/src/lib.rs:9`).
- `attack`, `castSkill`, `attackPlayer`가 실패 결과를 모두 버리므로 쿨다운·사거리·스키마 불일치가 화면상 “동기화 안 됨”과 구별되지 않는다(`lib/spacetime/spacetime_world_presence.dart:339`).
- 원격 플라즈마는 피해 0 발사체라 이중 피해는 막았지만, 동일한 근접 칼 애니메이션까지 켜져 실제 사용자의 화면과 다르다(`lib/game/entities/remote_player.dart:193`, `lib/game/entities/remote_player.dart:408`).
- 서버 설계 머리말은 모든 테이블을 비공개로 규정하지만 `world_player`와 `monster`는 실제로 `public`이다(`spacetimedb/src/lib.rs:15`, `spacetimedb/src/world.rs:279`, `spacetimedb/src/world.rs:453`). 공격 필드를 이 공개 행에 계속 추가하면 원칙 위반과 행 크기 증가가 함께 커진다.
- 문서도 현재 코드보다 뒤처졌다. `GAME-DESIGN.md`는 클라이언트가 월드 reducer와 원격 렌더링을 아직 쓰지 않는다고 적지만(`GAME-DESIGN.md:704`, `GAME-DESIGN.md:788`), 실제 앱은 `SpacetimeWorldPresence`를 주입한다(`lib/main.dart:86`).

## 5. 권고안

| 순위 | 권고 | 범위 | 근거 | 리스크 |
|---|---|---|---|---|
| 1 | `RemotePlayerEntity`와 `Enemy`의 공격 기준값을 nullable 또는 명시적 초기화 상태로 바꾸고, 첫 실제 `0→T1` 공격은 재생하되 생성 시 이미 존재한 `T1`은 재생하지 않도록 한다. | 클라이언트 렌더 | `lib/game/entities/remote_player.dart:123`, `lib/game/entities/enemy.dart:129` | 초기 스냅샷 구분을 잘못하면 과거 공격이 재생됨 |
| 2 | “초기 스냅샷은 미재생, 첫 후속 공격은 재생, 같은 시각은 중복 재생하지 않음, 두 번째 공격도 재생” 단위 테스트를 추가한다. 통합 테스트도 캐시 값뿐 아니라 `RemotePlayerEntity.isSwinging`까지 확인한다. | 테스트 | `test/attack_and_loot_sync_test.dart:155`, `test/server_interpolation_test.dart:259` | 실서버 테스트만으로 렌더 결함을 검사하면 느리고 불안정함 |
| 3 | 공격 reducer 결과를 관찰 가능하게 만들고, 성공·쿨다운·사거리·이미 사망을 구분해 개발 로그 또는 제한된 UI 진단으로 남긴다. 로컬 예측 스윙은 즉시 유지하되 원격에는 서버가 인정한 행동만 보낸다. | 네트워크 진단 | `lib/spacetime/spacetime_world_presence.dart:340` | 실패 메시지를 매 공격마다 표시하면 화면과 로그가 과도해짐 |
| 4 | 기존 `WorldPlayer.deaths`와 `last_damaged_at`을 `RemotePlayer`에도 전달해 원격 피격 플래시·데미지 숫자·사망 폭발·재가동 연출을 재생한다. 새 서버 필드는 필요 없다. | 원격 PC 연출 | `spacetimedb/src/world.rs:363`, `spacetimedb/src/world.rs:372`, `lib/game/net/world_presence.dart:9` | 첫 구독에서 과거 피격·사망을 재생하지 않도록 기준값 필요 |
| 5 | 대시를 서버 reducer로 승격해 에너지·쿨다운·`invulnerable_until`을 서버가 확정하고, 원격 화면에는 대시 사건과 잔상을 전달한다. | 서버 전투·원격 렌더 | `lib/game/entities/player.dart:313`, `spacetimedb/src/world.rs:2287` | 스키마 마이그레이션·지연 보정·생성 코드 재생성이 필요 |
| 6 | 서버가 콤보 단계를 직접 계산하거나 온라인 콤보 피해 배율을 제거한다. 공격 종류·변형을 서버가 확정한 뒤 원격 근접 스윙과 플라즈마 사격 자세를 별도로 렌더링한다. | 전투 수식·애니메이션 | `lib/game/entities/player.dart:550`, `spacetimedb/src/world.rs:807` | 전투 밸런스와 프로토콜이 함께 바뀜 |
| 7 | 서버 몬스터 체력 바를 `_serverHpRatio` 또는 `hp / maxHp` 게터로 계산하도록 정합시킨다. | 몬스터 UI | `lib/game/entities/enemy.dart:185`, `lib/game/entities/enemy.dart:1164` | 낮음 |
| 8 | 포션·버프·인벤토리 소비를 서버 판정으로 옮기고, 전투에 영향을 주는 버프만 원격 시각 상태로 투영한다. | 서버 전투·인벤토리 | `lib/game/action_rpg_game.dart:1698`, `lib/game/entities/player.dart:111` | 기존 로컬 인벤토리 저장과의 마이그레이션 필요 |
| 9 | `public` 월드 테이블과 “모든 테이블 비공개” 원칙의 충돌을 먼저 결정하고, 이후 행동 필드는 비공개 정본과 구독용 view/projection으로 분리한다. | 서버 보안·AOI | `spacetimedb/src/lib.rs:15`, `lib/spacetime/cyborg_connection.dart:99` | 사용자별 view 비용과 SpacetimeDB view 제약을 부하 시험해야 함 |

## 6. 불확실 · 미확인

- 읽기 전용 규칙에 따라 `flutter test`, `cargo test`, 빌드, maincloud 조회·배포는 실행하지 않았다. 따라서 현재 배포된 서버 스키마와 사용자가 실행한 앱 바이너리가 이 소스와 같은 버전인지는 미확인이다.
- 반복해서 두 번 이상 성공한 공격도 전혀 보이지 않는다면 서버 reducer 거절 또는 구버전 클라이언트 가능성이 있다 `[추측]`. 현재는 결과를 `.ignore()`하므로 실행 로그를 추가하기 전에는 확정할 수 없다(`lib/spacetime/spacetime_world_presence.dart:340`).
- 허공 스윙이나 서버가 거절한 공격까지 다른 사용자에게 보여 줄지는 제품 판단이 필요하다. 현재 프로토콜은 성공한 서버 판정만 공유한다(`spacetimedb/src/world.rs:1491`).
- 원격 공격·피격·사망 사건의 동시 접속 1,000명 기준 전송량과 프레임 비용은 실측 자료가 없다. 특히 안전지대에서는 구독 행이 많아도 화면에는 가까운 50명만 만든다(`lib/game/action_rpg_game.dart:236`).
- `GAME-DESIGN.md`와 `.cowork/cowork-prompt.md`의 구현 현황이 실제 코드보다 오래되어, 어느 문서를 현재 운영 기준으로 갱신할지는 사람의 판단이 필요하다.
