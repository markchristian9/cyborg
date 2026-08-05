<!-- cowork:codex | 2026-08-05 19:32:12 | exit=0 | 469s -->
# codex 분석 — server-authority

> 요청: 서버 판정, 서버 권위 이동, 클라이언트 보간, pc 별 이벤트/액션/스킬/타격/사망/HP/MP 공유 등이 올바로 동작하는지 확인하고 수정/보완 할 내용이 있으면 수정 보완해주세요. 특히 -> 여러 플레이어 화면에 다른 pc 들의 이동, 몬스터 이동, 스킬 사용, 공격, 피격, 사망, 공격 모션/애니메이션, 스킬 애니메이션, 총알/레이저/미사일 등이 날라가는 장면돈 여러 플레이어 화면에 동일한 애니메이션/이벤트공유/서버가 클라로 이벤트전송/클라화면에서 여러 pc 화면에도 동일하게 보이는 것이 잘 동작하는지 분석하고 수정/보완해주세요.
> 생성: 2026-08-05 19:32:12 · 소요 469s · 읽기 전용 분석(작업공간 미수정)

---



## 1. 결론 요약

현재 구현은 다른 PC의 존재·이동, 서버 몬스터 위치·HP, 기본 공격 판정, 내 HP·MP 수렴까지는 서버 상태를 공유한다. 그러나 이동은 좌표 신고형 절충안이며 완전한 서버 권위가 아니다.  
몬스터 공격 예고·타격 모션, 원격 피격·사망, 스킬 발사체, 레이저·미사일, 대시, PK 입력은 여러 화면에 동일하게 재생되지 않는다. 특히 서버 몬스터 사망 연출과 원격 PC 사망은 사실상 누락돼 있다.  
HP·MP도 레벨업 MP, 포션·버프·방화벽 피해가 서버 상태와 연결되지 않아 온라인 플레이에서 되돌아가거나 무효화될 수 있다.  
따라서 현재 상태를 “멀티플레이 전투 동기화 완료”로 판정할 수 없으며, private 전투 이벤트 스트림과 서버 행동 상태를 먼저 보완해야 한다.

## 2. 근거

- `lib/main.dart:86-95` — 실제 온라인 게임은 `SpacetimeWorldPresence`를 주입하므로 서버 월드 연동 경로가 실행된다.
- `lib/spacetime/cyborg_connection.dart:82-110` — PC·몬스터·전리품은 각각 주변 3×3 청크만 구독한다.
- `spacetimedb/src/world.rs:282-440` — `WorldPlayer`에는 좌표·HP·MP·사망 누계·마지막 공격 시각·공격 방향·스킬·시선이 저장된다.
- `spacetimedb/src/world.rs:1312-1379` — 이동은 클라이언트 좌표를 받고 속도 상한만 적용한다. 지형 충돌이나 입력 시뮬레이션은 서버 판정이 아니다.
- `spacetimedb/src/world.rs:1460-1547` — 기본 대몬스터 공격은 사거리·쿨다운·피해·선점·킬을 서버가 판정하고 `last_attack_at`을 남긴다.
- `spacetimedb/src/world.rs:1604-1698` — 서버 스킬은 `plasma` 한 종류이며 몬스터를 대상으로 즉시 피해를 확정한다.
- `spacetimedb/src/world.rs:1703-1753` — PK reducer는 존재하지만 기본 근접 공격만 처리한다.
- `spacetimedb/src/world.rs:1765-1952` — 몬스터 이동과 플레이어 피해는 서버 AI가 처리하지만 공격 단계·발사체·공격 사건은 저장하지 않는다.
- `lib/game/entities/enemy.dart:244-250` — 서버 몬스터는 로컬 AI를 완전히 건너뛰므로 로컬의 예고·사격·타격 경로가 실행되지 않는다.
- `lib/game/entities/remote_player.dart:143-175` — 원격 PC는 `lastAttackAtMicros` 변화로 공격 동작과 HP 바만 갱신한다.
- `lib/game/entities/projectile.dart:83-105` — 발사체 이동·벽 충돌·피격 연출은 클라이언트 로컬 컴포넌트다.
- `lib/game/action_rpg_game.dart:1411-1414` — 플레이어 공격 대상 목록에는 몬스터와 구조물만 있고 원격 PC는 없다.
- `lib/game/net/world_presence.dart:87-112` — 내 상태에는 HP·MP·사망 누계가 있지만, `RemotePlayer`에는 MP와 사망 누계가 없다(`lib/game/net/world_presence.dart:9-65`).
- `spacetimedb/src/world.rs:2032-2061` — 서버 전리품 획득은 행을 삭제할 뿐 인벤토리·회복·버프를 서버에 적용하지 않는다.
- `spacetimedb/src/lib.rs:15-16`과 `spacetimedb/src/world.rs:274-280` — “모든 테이블은 비공개” 원칙과 실제 public `world_player`가 충돌한다.

## 3. 상세 분석

### 기능별 판정

| 영역 | 현재 서버 판정 | 여러 화면의 표현 | 판정 |
|---|---|---|---|
| 다른 PC 이동 | 좌표·방향을 200ms 간격으로 신고하고 서버가 속도만 제한한다(`lib/spacetime/spacetime_world_presence.dart:25-41`, `spacetimedb/src/world.rs:1312-1379`). | 원격 PC가 수신 좌표 사이를 보간한다(`lib/game/entities/remote_player.dart:178-235`). | 부분 정상 |
| 몬스터 이동 | 150ms 서버 AI가 좌표와 방향을 갱신한다(`spacetimedb/src/world.rs:132-144`, `spacetimedb/src/world.rs:1765-1894`). | 클라이언트는 300ms마다 몬스터 캐시를 반영한다(`lib/game/action_rpg_game.dart:1115-1122`). | 공유되지만 중간 스냅샷 유실 |
| PC 기본 공격 | 성공한 타격의 시각·방향을 서버 행에 남긴다(`spacetimedb/src/world.rs:1533-1543`). | 원격 PC는 0.26초짜리 단일 스윙을 재생한다(`lib/game/entities/remote_player.dart:91-113`). | 성공한 공격만 부분 공유 |
| PC 스킬 | `plasma`의 MP·쿨다운·사거리·피해를 서버가 즉시 판정한다(`spacetimedb/src/world.rs:1574-1692`). | 시전자 본인만 로컬 발사체를 만들며(`lib/game/entities/player.dart:261-284`), 원격 화면은 색이 다른 스윙 호만 그린다(`lib/game/entities/remote_player.dart:251-284`). | 발사체·스킬 애니메이션 미공유 |
| 몬스터 공격 | 사거리 안의 몬스터 레벨을 합산해 HP를 서버에서 깎는다(`spacetimedb/src/world.rs:1916-1951`). | 서버 몬스터가 로컬 AI를 건너뛰므로 예고·근접 공격·사격이 실행되지 않는다(`lib/game/entities/enemy.dart:244-250`, `lib/game/entities/enemy.dart:375-399`). | 판정만 있고 공격 장면 없음 |
| 피격 | 몬스터 HP 감소는 모든 구독자에게 전달되고 피격 플래시가 켜진다(`lib/game/entities/enemy.dart:155-163`). | 내 서버 HP 반영은 숫자 대입뿐이며 피해 텍스트·흔들림·피격음이 발생하지 않는다(`lib/game/action_rpg_game.dart:615-638`, `lib/game/entities/player.dart:669-694`). 원격 PC도 HP 바만 변한다. | 불완전 |
| 사망 | 플레이어는 같은 트랜잭션에서 안전지대 재가동 후 `deaths`를 증가시킨다(`spacetimedb/src/world.rs:2282-2304`). | 본인은 누계를 감지하지만 원격 모델은 `deaths`를 버린다. `alive`도 즉시 `true`라 원격 다운 연출이 실행되지 않는다(`lib/game/net/world_presence.dart:9-65`, `lib/game/entities/remote_player.dart:293-339`). | 본인만 부분 정상 |
| PK | 서버 reducer는 있다(`spacetimedb/src/world.rs:1711-1753`). | `attackPlayer`의 실제 게임 호출부가 없고 원격 PC도 공격 대상 목록에 없다(`lib/game/action_rpg_game.dart:1411-1414`, `lib/spacetime/spacetime_world_presence.dart:346-352`). | 실제 플레이 불가 |
| HP·MP 공유 | 내 HP·MP는 서버 값으로 즉시 수렴한다(`lib/game/action_rpg_game.dart:619-624`). | 다른 PC는 HP만 표현하며 MP는 폐기한다(`lib/spacetime/spacetime_world_presence.dart:387-405`). | 부분 정상 |
| 총알·레이저·미사일 | 서버에는 `Projectile` 상태나 충돌 판정이 없다. 현재 서버 스킬은 `plasma` 즉시 판정뿐이다(`spacetimedb/src/world.rs:1574-1585`). | 직선 에너지 발사체 하나가 로컬에서만 이동한다(`lib/game/entities/projectile.dart:15-38`). | 미구현 |

### 서버 권위의 실제 경계

전투 피해·쿨다운·사거리·몬스터 HP·플레이어 HP/MP는 서버에서 판정된다. 특히 클라이언트가 피해량을 보내지 않는 구조는 적절하다(`spacetimedb/src/world.rs:1460-1464`, `spacetimedb/src/world.rs:1604-1607`).

반면 이동은 서버 권위가 아니라 “클라이언트 위치 + 서버 속도 제한”이다. 서버는 벽·통행 가능 지형을 확인하지 않고 좌표를 직접 향해 몬스터를 이동시킨다(`spacetimedb/src/world.rs:1873-1892`). 개조 클라이언트의 벽 통과와 서버 몬스터의 구조물 관통을 막지 못한다.

대시도 클라이언트 전용이다. 클라이언트는 에너지 소비·속도·무적을 로컬에서 적용하지만(`lib/game/entities/player.dart:312-327`, `lib/game/entities/player.dart:415-423`), 서버 피해 판정은 재가동 무적만 확인한다(`spacetimedb/src/world.rs:2255-2268`). 따라서 온라인에서는 대시 중에도 서버 피해를 받을 수 있고, 다른 화면에는 일반 고속 이동으로만 보인다.

### 이벤트와 애니메이션 공유

현재 유일한 공격 사건 저장소는 `WorldPlayer.last_attack_at` 한 칸이다. 성공한 기본 공격과 `plasma`만 기록되며, 빗나간 스윙·대시·몬스터 공격·피격·몬스터 사망·발사체 생성은 사건으로 남지 않는다(`spacetimedb/src/world.rs:393-425`).

또한 로컬 PC는 서버 승인을 기다리지 않고 공격·발사체 연출을 시작하고 reducer 오류를 무시한다(`lib/game/entities/player.dart:198-210`, `lib/spacetime/spacetime_world_presence.dart:328-351`). 서버가 사거리나 쿨다운으로 거절하면 본인 화면에는 공격이 보이지만 타인 화면에는 보이지 않는다.

현재 `plasma`는 서버에서 즉시 피해를 확정하지만 클라이언트 발사체는 이후 벽과 충돌할 수 있다. 따라서 화면에서는 탄이 벽에서 터졌는데 대상 HP는 이미 감소한 장면이 가능하다(`spacetimedb/src/world.rs:1642-1658`, `lib/game/entities/projectile.dart:77-105`).

원격 PC 보간도 실제 게임 경로에 결함이 있다. `_syncRemotePlayers`는 매 프레임 같은 스냅샷에도 `applySnapshot`을 호출하고(`lib/game/action_rpg_game.dart:680-702`), `applySnapshot`은 매번 보간 구간을 다시 시작한다(`lib/game/entities/remote_player.dart:143-145`, `lib/game/entities/remote_player.dart:178-197`). 단위 테스트는 서버 갱신 시점에만 `applySnapshot`을 호출하므로 실제 호출 패턴을 검증하지 않는다(`test/server_interpolation_test.dart:159-179`).

### 사망과 HP·MP

플레이어 본인 사망은 `deaths` 증가로 감지해 폭발·카메라 이동을 실행한다(`lib/game/action_rpg_game.dart:626-674`). 원격 PC에는 이 값이 전달되지 않으므로 다른 화면은 사냥터에서 안전지대로 순간이동한 것만 보게 된다.

서버 몬스터 사망은 더 직접적인 문제가 있다. 기존 컴포넌트는 `alive=false`를 받아도 제거되지 않고(`lib/game/action_rpg_game.dart:1272-1285`), `Enemy.render`도 생사 확인 없이 본체를 그린다(`lib/game/entities/enemy.dart:603-635`). 서버 몬스터에는 로컬 `_die`가 호출되지 않으므로 폭발·처치 연출도 발생하지 않는다(`lib/game/entities/enemy.dart:583-600`).

레벨업 시 서버는 `level`, `max_hp`, `hp`만 갱신하고 `max_mp`와 `mp`를 갱신하지 않는다(`spacetimedb/src/world.rs:2344-2358`). 또한 `MyWorldState`에는 레벨·XP가 없어 현재 게임 인스턴스가 서버 킬로 오른 성장 상태를 채택할 경로가 없다(`lib/game/net/world_presence.dart:87-112`).

포션 사용·버프·방화벽 피해도 로컬 처리다. 포션은 로컬 인벤토리에서 HP와 버프를 바꾸고(`lib/game/systems/inventory.dart:96-113`), 방화벽은 로컬 `applyDamage`를 호출한다(`lib/game/entities/player.dart:598-615`). 다음 프레임의 서버 HP 반영이 이 결과를 덮으므로 온라인에서는 회복이나 지형 피해가 되돌아갈 수 있다.

## 4. 리스크 · 함정

- 기존 통합 테스트는 서버 행의 이동·HP·공격 시각을 확인하지만 Flame 화면의 발사체·피격·사망 애니메이션은 검증하지 않는다(`test/attack_and_loot_sync_test.dart:99-173`, `test/monster_authority_test.dart:174-232`).
- `last_attack_at` 한 값만 관찰하면 지연 중 여러 공격이 캐시에 연속 반영될 때 중간 사건을 잃을 수 있다. 공격 종류·대상·발사체·피격량도 완전하게 복원할 수 없다(`spacetimedb/src/world.rs:393-425`).
- 이벤트 행을 같은 트랜잭션에서 삽입 후 삭제하면 클라이언트에 전달되지 않는다. 별도 만료 시각과 정리 reducer가 필요하다(`GAME-SERVER.md:310-320`).
- `auto_inc` ID는 연속을 보장하지 않으므로 “번호가 하나 건너뛰었으니 이벤트 유실”처럼 판정하면 안 된다(`.cowork/cowork-prompt.md:78-83`).
- 공격·스킬·피격 이벤트를 월드 전체에 보내면 MMORPG 동접 수만큼 fan-out이 커진다. 현재 청크 AOI에 사건도 함께 포함해야 한다(`lib/spacetime/cyborg_connection.dart:69-110`).
- `world_player`, `monster`, `loot`, `monster_kill`이 public이라 임의 클라이언트가 AOI를 무시하고 전체 구독할 수 있다. 이는 작업공간의 비공개 테이블 원칙과 충돌한다(`spacetimedb/src/lib.rs:15-16`, `spacetimedb/src/world.rs:448-461`, `spacetimedb/src/world.rs:549-553`).
- 설계 문서는 클라이언트 월드 연동과 PK가 아직 없다고 기록하지만 실제 코드는 이미 연결돼 있다. 문서의 현재 상태 표를 검증 근거로 사용하면 오판한다(`GAME-DESIGN.md:702-705`, `GAME-DESIGN.md:778-809`, `lib/main.dart:86-95`).
- 서버 판정과 시각 효과가 서로 다른 시간축을 쓰면 “모든 화면에서 같은 사건”은 가능해도 픽셀 단위 동시 재생은 불가능하다. [판단] 목표는 동일한 `event_id`·서버 시각·대상·결과를 재생하는 것으로 정의해야 한다.

## 5. 권고안

| 순위 | 권고 | 범위 | 근거 | 리스크 |
|---|---|---|---|---|
| 1 | private `CombatEvent` 테이블과 public projection view를 두고 `event_id`, AOI `chunk`, source/target, event type, skill, origin/direction, damage, `server_ts`, `expires_at`을 기록한다. 별도 scheduled reducer로 만료하고 클라이언트는 ID로 중복 제거한다. | 서버 스키마·구독·생성 코드 | `GAME-SERVER.md:310-320`, `.cowork/cowork-prompt.md:78-83` | 이벤트 쓰기·구독 트래픽 증가 |
| 2 | 몬스터에 `phase`, `target_character_id`, `action_started_at`, `resolve_at`, `next_attack_at`을 두어 telegraph→strike/fire→recover를 서버가 진행하고 각 전환을 사건으로 발행한다. | `spacetimedb/src/world.rs` 몬스터 AI | `spacetimedb/src/world.rs:1765-1952`, `lib/game/entities/enemy.dart:375-408` | AI 틱과 테이블 갱신량 증가 |
| 3 | 클라이언트가 사건 스트림으로 원격 스윙·스킬·피격·데미지 텍스트·사망·몬스터 폭발을 재생하게 한다. 몬스터 `alive=false` 전환 시 기존 컴포넌트도 즉시 사망 연출 후 제거한다. | `WorldPresence`, `ActionRpgGame`, Flame 엔티티·FX | `lib/game/action_rpg_game.dart:1272-1317`, `lib/game/entities/enemy.dart:583-635` | 지연 사건의 중복·순서 처리 필요 |
| 4 | HP·MP·레벨·XP·인벤토리·포션·버프·방화벽 피해를 서버 상태로 통합한다. 레벨업 시 `max_mp/mp`도 갱신하고 `use_item` reducer에서 아이템 감소와 회복·버프를 원자적으로 처리한다. | 서버 전투·성장·인벤토리, `MyWorldState` | `spacetimedb/src/world.rs:2344-2358`, `spacetimedb/src/world.rs:2032-2061`, `lib/game/systems/inventory.dart:96-113` | 스키마 마이그레이션과 기존 아이템 상태 이전 |
| 5 | 실제 PC 타깃 선택 경로를 추가하되 원격 PC를 로컬 `Damageable`로 처리하지 말고 `attack_player`/PK용 `cast_skill` 의도만 서버에 보낸다. 스킬 대상은 몬스터·PC·좌표형으로 명시적으로 구분한다. | 입력·타기팅·서버 reducer | `lib/game/action_rpg_game.dart:1411-1414`, `spacetimedb/src/world.rs:1703-1753` | 오발·안전지대·파티 공격 정책 결정 필요 |
| 6 | 발사체를 용도별로 분리한다. hitscan 레이저는 origin/end 사건, 즉시 판정형 볼트는 서버 시각 기반 시각 사건, 유도 미사일·벽 충돌형 탄환은 서버 `ProjectileState`와 충돌 판정을 사용한다. | 서버 스킬·발사체·클라이언트 FX | `spacetimedb/src/world.rs:1570-1577`, `lib/game/entities/projectile.dart:47-105` | 유도탄 서버 틱 비용과 지연 보정 |
| 7 | 대시를 서버 행동으로 올려 에너지·쿨다운·무적·이동 예산을 서버가 판정한다. 원격 보간에는 `snapshot_seq/server_ts/velocity`를 전달하고 동일 스냅샷에는 보간 구간을 다시 열지 않는다. | 이동·행동 상태·보간 | `lib/game/entities/player.dart:312-327`, `lib/game/entities/remote_player.dart:143-197` | 입력 지연과 예측·롤백 복잡도 |
| 8 | public 월드 테이블을 private 권위 상태와 최소 projection view로 분리한다. AOI view가 1,000명 규모에서 감당되는지 먼저 측정하고, 위치·전투·이벤트 행을 세로 분할한다. | 서버 보안·AOI·대역폭 | `spacetimedb/src/lib.rs:15-16`, `GAME-SERVER.md:259-271`, `GAME-SERVER.md:428-433` | 사용자별 view 계산량 증가 |
| 9 | 실제 게임 입력을 사용하는 2클라이언트 테스트를 추가해 원격 이동, PK, 스킬 발사체, 몬스터 telegraph/fire, 양측 피격 FX, PC·몬스터 사망, HP·MP·포션을 사건 ID와 Flame 컴포넌트 상태까지 검증한다. | 테스트·문서 | `test/attack_and_loot_sync_test.dart:4-8`, `test/server_interpolation_test.dart:146-210` | maincloud 의존 테스트 시간·데이터 누적 |

## 6. 불확실 · 미확인

- 읽기 전용 규칙 때문에 `cargo test`, `flutter analyze`, `flutter test`와 maincloud 통합 테스트를 실행하지 않았다. 따라서 현재 테스트의 실제 통과 여부와 배포 스키마 일치 여부는 미확인이다.
- 생성 바인딩에는 현재 필드가 반영돼 있지만(`lib/spacetime/generated/world_player.dart:5-35`), maincloud 배포본이 작업공간 소스와 완전히 같은지는 확인하지 못했다.
- private 월드 테이블을 projection view로 노출하면서 현재 청크 AOI 성능을 유지할 수 있는지는 SpacetimeDB 2.7 실측이 필요하다. 사용자별 view는 동접 수만큼 계산될 가능성이 있어 부하 시험이 선행돼야 한다(`GAME-SERVER.md:364-374`).
- 다른 PC의 MP를 실제 HUD에 공개할지, 빈 스윙·실패한 스킬도 타인에게 보여 줄지, 레이저·미사일이 판정형인지 순수 연출형인지는 제품 결정이 필요하다.
- 네트워크 지연이 다른 여러 화면에서 “동일”을 같은 서버 사건과 결과로 볼지, 같은 벽시계 프레임의 재생까지 요구할지는 별도 합의가 필요하다. 후자는 일반 네트워크 환경에서 보장할 수 없다.
