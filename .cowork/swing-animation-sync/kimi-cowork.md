<!-- cowork:kimi | 2026-08-05 22:21:21 | exit=0 | 898s -->
# kimi 분석 — swing-animation-sync

> 요청: 서버/여러플레이어 화면 동기화 작업이 잘 되는지, 수정보완할 내용이 있으면 수정보완해주세요. 특히, pc 가 몬스터를 공격할 때 스윙/슬래시/칼휘두름 애니메이션이 내 화면에만 보이고, 다른 pc 화면에 보이지 않습니다. 이런 빠져있는 부분들을 수정/보완해주세요.
> 생성: 2026-08-05 22:21:21 · 소요 898s · 읽기 전용 분석(작업공간 미수정)

---

• 다른 AI 의 보고서 파일은 읽지 않고 독립 분석을 계속한다. 남은 검증 지점을 확인한다.

• 

## 1. 결론 요약

  스윙/슬래시 동기화는 **파이프라인 자체는 이미 구현돼 있다** — 서버가 `world_player.last_attack_at`·`attack_dir_*`·`attack_skill` 을 기록하고(`spacetimedb/src/world.rs:1556-1563`), 구독으로 전파되며, `RemotePlayerEntity.applySnapshot` 이 값 변화를 보고 스윙·아크·플라즈마 볼트를 재생한다(`lib/game/entities/remote_player.dart:183-206`). 통합 테스트도 이 경로를 실서버에서 검증한다(`test/attack_and_loot_sync_test.dart:109-184`). 그럼에도 "남의 화면에 안 보인다" 가 실제로 발생하는 원인은 네 가지다: ① 원격 엔티티가 관찰하는 **첫 번째 공격은 무조건 삼켜지는 코드 결함**, ② **로컬 애니메이션은 명중 여부와 무관하게 항상 재생**되지만 서버에 기록되는 것은 서버가 받아들인 공격뿐이라 헛스윙·거절 스윙이 상대 화면에 없음(설계상 한계이나 체감 불일치의 주원인), ③ 서버 몹에는 **데미지 숫자가 어느 화면에도 뜨지 않음**, ④ 포션 회복·버프·대시 무적 등 **로컬 전용 전투 효과가 서버 권위 hp/mp 에 매 프레임 덮여 온라인에서 무효**라는 더 넓은 동기화 공백.

  

## 2. 근거

  - `spacetimedb/src/world.rs:1556-1563` — `attack_monster` 가 공격자 행에 `last_attack_at`·`attack_dir_x/y`·`attack_skill` 을 기록. `cast_skill`(1702-1712), `attack_player`(1764-1771)도 동일.
  - `spacetimedb/src/world.rs:118` — `ATTACK_COOLDOWN_MICROS = 350_000`; `world.rs:115` — `ATTACK_RANGE_TILES = 2.2`(서버가 아는 좌표 기준, 1508-1513).
  - `lib/game/entities/player.dart:171,204` — 클라이언트 근접 쿨다운 0.38초, `player.dart:177` — `meleeRange = 1.5`. `tryMelee` 는 대상이 없어도 애니메이션을 시작한다(198-211).
  - `lib/game/entities/enemy.dart:600-604` — 서버 몹을 때리면 `presence.attack(serverId)` 만 보내고 **로컬 데미지 숫자·넉백 없이 즉시 return** (데미지 텍스트는 622-630 의 로컬 전용 분기에만 있음).
  - `lib/game/entities/remote_player.dart:183-186` — `if (attackAt != _playedAttackAt) { if (_playedAttackAt != 0 && attackAt != 0) { 재생 } }`. 생성자(26-34)는 `_playedAttackAt` 을 시딩하지 않아 0 으로 시작 → **첫 관찰 공격은 항상 미재생**. 같은 패턴이 몹 타격에도 있음(`enemy.dart:173-177`).
  - `lib/game/entities/remote_player.dart:200-203,290-303` — 원격 플라즈마는 연출 전용 볼트(damage 0)와 발사음 재생. 근접 스윙에는 대응하는 SFX 호출이 없음.
  - `lib/spacetime/spacetime_world_presence.dart:340-345` — `attack()` 은 결과를 기다리지 않고 reducer 만 발사. 거절(쿨다운·사거리·사망)되면 아무 일도 남의 화면에 일어나지 않는다.
  - `lib/game/entities/player.dart:582-588` — 로컬 부채꼴 판정 통과 시 서버 응답 전에 HitSpark 를 먼저 띄움 → 서버가 거절하면 "내 화면엔 맞았는데 남의 화면엔 없는" 거짓 명중.
  - `spacetimedb/src/world.rs:2065-2094` — `pick_loot` 는 행 삭제뿐, 회복·버프 등 **효과를 서버 상태에 적용하지 않는다**. 효과는 `lib/game/entities/pickup.dart:394-440` 과 `lib/game/systems/inventory.dart:112`(`player.drinkPotion`)에서 전부 로컬 적용.
  - `lib/game/entities/player.dart:801-811` — `adoptServerVitals` 가 매 프레임 hp/mp 를 서버 값으로 덮음 → 로컬 회복은 다음 갱신에 소거된다.
  - `spacetimedb/src/world.rs:1750-1753` — `attack_player` 는 공격자의 안전지대를 검사하지만, `attack_monster`(1486-1513)에는 그 검사가 없음.
  - `test/attack_and_loot_sync_test.dart:155-183` — 통합 테스트는 **서버 표까지의 도달**만 검증하고, `RemotePlayerEntity` 의 재생 분기 자체를 검증하는 단위 테스트는 없음(`test/server_interpolation_test.dart:241-314` 는 위치·방향 보간만).

  

## 3. 상세 분석

  **정상 동작 경로(이미 갖춰진 것).** 근접 스윙은 `tryMelee`(player.dart:198) → 스윙 중반 35% 에 `_resolveMeleeHit`(543-547) → 명중한 서버 몹의 `applyDamage` → `presence.attack`(enemy.dart:601) → 서버 `attack_monster` 가 사거리·쿨다운·선점·피해를 판정하고 공격자 행에 공격 사건을 기록(world.rs:1556-1563) → 청크 구독(`worldSubscriptionsFor`, cyborg_connection.dart:82-111)으로 전파 → 관찰자의 `applySnapshot` 이 시각 변화를 보고 0.26초 스윙+아크를 재생(remote_player.dart:135,184-206). 플라즈마는 `castSkill`(player.dart:249)로 같은 경로를 타고 관찰자 쪽에 연출 전용 볼트를 띄운다. 몹의 타격도 `Monster.last_attack_at` 으로 같은 방식(world.rs:1949, enemy.dart:173-177). 위치·방향·hp·사망·전리품·레벨 동기화도 모두 같은 "사건을 상태로 전달" 패턴으로 구현돼 있다. 즉 **뼈대는 완성돼 있고, 문제는 가장자리다.**

  **"내 화면에만 보이는" 스윙이 생기는 지점(범위: 클라이언트 전투 연출 ↔ 서버 판정 경계).**

  1. **첫 공격 삼킴(코드 결함).** `_playedAttackAt` 이 0 으로 초기화되고 가드가 `_playedAttackAt != 0` 을 요구하므로, 엔티티 생성 후 관찰하는 **첫 번째** 공격은 무조건 재생되지 않는다. 두 PC 를 나란히 놓고 한쪽이 처음 휘두른 바로 그 스윙 — 즉 사용자가 동기화를 **시험할 때 가장 먼저 보는 한 번** — 이 빠진다. 50명 상한(`_maxRemotePlayers`, action_rpg_game.dart:241,764-765) 경계에서 엔티티가 걷혔다 다시 만들어질 때마다 재발한다.
  2. **예측 연출 vs 확정 사건의 괴리(설계상 한계).** 로컬 스윙은 입력 즉시, 명중과 무관하게 재생된다. 서버에 기록되는 것은 서버가 받아들인 공격뿐이다. 거절 경로: 쿨다운(클라 0.38초 vs 서버 0.35초 — 지터로 가끔 거절), 플라즈마(클라·서버 모두 0.24초로 **동일** — player.dart:240, world.rs:1596 — 왕복 지터만으로도 연사 시 번번이 거절 가능), 서버가 아는 공격자 좌표 기준 사거리 2.2(20 Hz 보고라 최대 ~0.2타일 어긋남), 헛스윙(의도 자체가 전송되지 않음). 거절된 스윙은 내 화면엔 애니메이션·HitSpark 까지 뜨고(player.dart:582-588), 상대 화면엔 아무것도 없다.
  3. **피드백 부재.** 서버 몹은 `applyDamage` 가 즉시 return 해 데미지 숫자가 때린 본인 화면에도 뜨지 않는다. 남이 때리는 것도 hp 비율 하락 시 흰 플래시뿐(enemy.dart:185-190). "함께 때리는 손맛"이 숫자로 읽히지 않는다.
  4. **로컬 전용 효과가 온라인에서 무효(더 넓은 공백).** 포션 회복(`drinkPotion`→로컬 heal), 포션 버프(`damageTakenMultiplier`), 대시 무적(`isDashing`, player.dart:659)은 전부 로컬 판정인데, 온라인에서는 몹→플레이어 피해가 서버에서 계산되고(world.rs:2280-2312) hp/mp 가 매 프레임 서버 값으로 덮인다. **온라인에서 포션을 마셔도 다음 갱신에 체력이 되돌아간다.** `pick_loot` 가 효과를 서버에 적용하지 않으므로 인벤토리 자체도 각 클라이언트 로컬 상태다.
  5. **비대칭 구멍.** `attack_monster` 에는 `attack_player` 에 있는 공격자 안전지대 검사가 없다. 안전지대 경계에서 면역 상태로 경계 밖 2.2타일 내의 몹을 때리는 캠핑이 가능한지는 몹 스폰 분포에 달렸으나, 규칙의 비대칭 자체는 코드상 사실이다.

  

## 4. 리스크 · 함정

  - **배포 상태 미확인이 가장 큰 변수.** 스키마의 공격 열들은 `#[default]` 를 달고 맨 끝에 붙는 규칙으로 추가된 흔적이다(world.rs:390-394, 408-430). maincloud 에 배포된 모듈이 이 열들을 포함하지 않으면 생성 코드와 어긋나 **기능이 통째로 작동하지 않을 수 있고**, 그 경우 "전혀 안 보임" 의 가장 단순한 설명이 된다. 작업공간에서는 배포 시점을 검증할 수 없다.
  - **거절 스윙까지 `last_attack_at` 에 기록하게 하면 안 된다.** "의도만 보내는" 경량 reducer 는 서버 권위 원칙(`spacetimedb/src/lib.rs` 머리말 — 클라이언트를 신뢰하지 않는다)과 충돌하지 않지만, 판정 없는 공격 사건은 타인 화면에 스윙 스팸을 뿌리는 어뷰징 통로가 된다. 헛스윙 동기화를 권고할 때 이 비용을 함께 따져야 한다.
  - **데미지 숫자를 서버가 알려 주지 않는다.** 클라이언트가 추정(hp 비율 차 × maxHp)으로 띄우면 서버 판정과 어긋나는 숫자가 뜰 수 있다. 정확한 값은 `Monster` 에 `last_taken_damage` 같은 열 추가가 필요하고, 이는 이미 배포된 표의 **맨 끝 + 기본값** 규칙(world.rs:390-394)을 따라야 한다.
  - **포션을 서버로 옮기면** `use_potion` reducer 가 hp 상한·쿨다운·보유 수량을 판정해야 하고, 보유 수량 자체가 지금은 로컬 인벤토리라 서버가 검증할 근거가 없다 — 인벤토리까지 서버로 올리는 설계 변경이 뒤따른다. 범위를 "회복량만 서버 적용" 으로 좁힐지, 인벤토리 전체를 올릴지는 사람의 결정이다.
  - **cowork 프롬프트의 전제가 낡았다.** 프롬프트는 "실시간 멀티플레이 동기화는 아직 없다" 고 말하지만, 코드에는 presence·전투·전리품·파티 동기화가 이미 구현돼 있다(git 로그 `84679c5` "서버가 판정한 것을 화면이 다시 말게 한다"). 이 프롬프트를 액면 그대로 전제한 분석은 현재 상태를 과소평가한다.
  - 첫 스냅샷 가드를 그냥 제거하면 "시야에 들어온 사람이 등장하자마자 허공에 한 번 휘두르는" 회귀가 다시 생긴다(remote_player.dart:178-182 주석이 막으려던 것). 수정은 가드 제거가 아니라 **생성자 시딩** 방식이어야 한다.

  

## 5. 권고안

  | 순위 | 권고 | 범위 | 근거 | 리스크 |
  |---|---|---|---|---|
  | 1 | `RemotePlayerEntity` 생성자에서 `_playedAttackAt = snapshot.lastAttackAtMicros` 로 시딩하고, `applySnapshot` 의 `_playedAttackAt != 0` 조건을 제거(`attackAt != 0` 만 유지). `Enemy._playedAttackAt` 도 같은 방식으로 | `lib/game/entities/remote_player.dart:26-34,183-186`, `lib/game/entities/enemy.dart:130,173-177` | 첫 관찰 공격 삼킴 결함 | 등장 즉시 재생 회귀 방지 로직이 시딩으로 대체되는지 단위 테스트 필요 |
  | 2 | 서버 몹 피격 시 데미지 숫자 표시: 단기안은 `applyServerState` 의 hp 비율 하락 폭 × `_maxHp` 로 추정 `DamageText`(enemy.dart:185-190 지점), 정확안은 `Monster` 표 맨 끝에 피해량 열 추가 | `lib/game/entities/enemy.dart:185-190,600-604`, `spacetimedb/src/world.rs:1528` | 데미지 숫자가 어느 화면에도 없음 | 추정안은 추정 오차, 열 추가는 마이그레이션 규칙(맨 끝+기본값) 준수 필요 |
  | 3 | 포션 회복의 서버 적용: `use_potion` reducer 를 추가해 hp/mp 회복을 서버가 판정하게 하는 방향 검토. 동시에 `pick_loot` 에 효과 적용이 없음을 문서에 명시 | `spacetimedb/src/world.rs:2065-2094`, `lib/game/systems/inventory.dart:99-113`, `lib/game/entities/player.dart:801-811` | 온라인에서 회복이 매 프레임 소거됨 | 인벤토리 수량을 서버가 검증할 수 없어 설계 변경이 커짐 — 범위 결정은 사람 몫 |
  | 4 | `attack_monster` 에 `attack_player` 와 같은 공격자 안전지대 검사 추가(또는 몹 스폰·로밍이 안전지대 2.2타일 이내에 닿지 않음을 증명하고 주석으로 명시) | `spacetimedb/src/world.rs:1486-1513` vs 1750-1753 | 규칙 비대칭 | 몹 배치에 따라 무해할 수 있음 — 추가 전 스폰 분포 확인 필요 |
  | 5 | 원격 근접 스윙에 타격음 추가(플라즈마는 이미 있음, remote_player.dart:302) — PK 가 허용되는 월드에서 "누가 치고 있는지" 의 청각 단서 | `lib/game/entities/remote_player.dart:184-206` | 근접 재생 경로에 SFX 없음 | 없음에 가까움 |
  | 6 | 재생 분기 단위 테스트 추가: 첫 공격 재생, 같은 시각 반복 무시, 스킬별 분기. 통합 테스트는 표 도달만 보므로 클라이언트 절반이 무방비다 | `test/` (신규), 참고 `test/server_interpolation_test.dart:241-314` | `attack_and_loot_sync_test.dart:155-183` | 없음 |
  | 7 | 헛스윙·거절 스윙의 미동기화는 **수용 가능한 위험으로 명시**하고, 로컬 HitSpark 를 서버 확정 후로 미루는 것(거짓 명중 제거)만 검토. 판정 없는 "스윙 의도" reducer 는 스팸 어뷰징 통로가 되므로 권고하지 않음 | `lib/game/entities/player.dart:582-588` | 서버 권위 원칙(`spacetimedb/src/lib.rs` 머리말) | HitSpark 지연은 타격감 저하와 트레이드오프 |

  

## 6. 불확실 · 미확인

  - **maincloud `withcenter-cyborg` 에 실제 배포된 모듈 버전** — 작업공간에 배포 시각 기록이 없어, 공격 열이 포함된 스키마가 라이브인지 확인하지 못했다. "전혀 안 보임" 이면 이것부터 확인해야 한다(`spacetime describe`/재배포로 검증 가능).
  - **대시 속도 대 서버 `MAX_MOVE_SPEED = 14`(world.rs:179)** — 대시가 이보다 빠르면 서버 좌표가 뒤처져 공격 사거리 거절이 잦아진다. 대시 속도 값을 확인하지 못했다 [미확인].
  - 몹 스폰 슬롯 분포가 안전지대 경계 2.2타일 이내에 근접하는지 — 권고 4 의 실효성 판단에 필요 [미확인].
  - `test/` 의 나머지 통합 테스트(`aoi_subscription_test.dart` 등 20여 개) 전부를 열지 않았다. 위에서 인용한 것 외의 동기화 검증이 더 있을 수 있다.
  - 자동 사냥(`auto_hunt.dart`)이 `tryMelee` 를 부르는 경로는 동일하다고 전제했다 [추측] — 호출부를 직접 열지 않았으나, `_resolveMeleeHit` 이 공통 경로라 결론에 영향은 없다.
