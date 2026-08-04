<!-- cowork:codex | 2026-08-04 20:45:38 | exit=0 | 419s -->
# codex 분석 — hp

> 요청: pc 의 HP 를 아주 크게 해 주세요. -> 예를 들면, 기본 1만이고, 기본 방어력 0인 상태에서 공격을 당하면 mob 마다 공격 치가 다르겠지만, 저레벨 몬스터(3 레벨 몬스터) 의 경우 3의 데미지가 입도록 해 주세요. 10레벨 몬스터의 경우 10레벨의 데미지가 입히도록 해 주세요. 그래서 1만 HP 가 모두 소진되면 사망하는 것으로 해 주세요.
> 생성: 2026-08-04 20:45:38 · 소요 419s · 읽기 전용 분석(작업공간 미수정)

---



## 1. 결론 요약

요구 규격은 구현 가능하지만, 현재 플레이어는 HP 120이고 독립적인 `defense` 스탯이 없으므로 단순 상수 변경으로 끝나지 않는다. `lib/game/entities/player.dart:27-37`  
실제 코드에는 문서 설명과 달리 이미 레벨 1~200의 `MonsterSpecies`가 있으므로, 새 레벨 체계를 만들기보다 이를 피해량의 단일 기준으로 삼아야 한다. `lib/game/systems/monster_codex.dart:217-245`, `lib/game/systems/monster_codex.dart:266-296`  
방어력 0에서 최종 피해가 정확히 몬스터 레벨이 되려면 기존 `MonsterStats.damage`와 지역·웨이브 `damageMultiplier`를 플레이어 피해 경로에서 제거하고, `Player.applyDamage` 한곳에서 방어와 버프를 적용해야 한다. `lib/game/entities/enemy.dart:293-325`, `lib/game/entities/player.dart:345-380`  
사망·즉시 리스폰은 이미 요구대로 동작하지만, HP 성장·포션·방화벽·HUD·피격 표시와 향후 서버 권위 전환은 함께 재설계해야 한다. `lib/game/entities/player.dart:401-425`, `lib/game/action_rpg_game.dart:902-927`

## 2. 근거

- `lib/game/entities/player.dart:27-37` — 플레이어 초기 HP는 120이며 `defense` 필드는 없고, 공격력·에너지·이동 속도만 정의돼 있다.
- `lib/game/systems/monster_codex.dart:217-245` — 실제 코드에는 고유 `level`과 `MonsterStats`를 가진 `MonsterSpecies`가 이미 존재한다.
- `lib/game/systems/monster_codex.dart:266-296` — 레벨 1~200에 각 한 종이 대응하고 `MonsterCodex.maxLevel`은 200이다.
- `lib/game/systems/monster_codex.dart:381-450` — 현재 공격력은 `6 + (level-1) × 1.55`에 골격별 0.85~1.35 배율을 적용하므로 몬스터 레벨과 일치하지 않는다.
- `lib/game/entities/enemy.dart:293-325` — 근접과 원거리 모두 `stats.damage * _damageScale`을 플레이어에게 전달한다.
- `lib/game/systems/monster_population.dart:177-200` — 상주 몬스터는 레벨 외에도 0.95~1.10 범위의 개체별 피해 배율을 가진다.
- `lib/game/systems/wave_director.dart:80-86` — 웨이브 몬스터 피해에는 `1 + (wave-1) × 0.008` 배율이 추가된다.
- `lib/game/entities/player.dart:345-380` — 최종 피해는 현재 `amount * buffs.damageTakenMultiplier`이며 HP가 0 이하가 되면 사망한다.
- `lib/game/entities/player.dart:401-425` — 리스폰 시 현재 최대 HP를 전부 회복하고 2초 무적을 받는다.
- `lib/game/entities/player.dart:321-332` — 방화벽은 0.5초마다 5 피해를 주며 피격 무적을 무시한다.
- `lib/game/systems/level_system.dart:46-57` — 레벨업 최대 HP 상승량은 일반 +18, 5레벨 단위 +34다.
- `lib/game/entities/pickup.dart:93-110` — 실제 포션 회복량은 소형 45, 대형 110이며 문서의 22·60과 다르다.
- `lib/game/ui/hud.dart:146-158`, `lib/game/ui/character_screen.dart:292-312` — HUD와 캐릭터 화면 모두 HP 비율과 숫자 문자열을 Canvas에 직접 표시한다.
- `spacetimedb/src/leaderboard.rs:143-184`, `lib/game/net/spacetime_game_sync.dart:7-11` — 서버에는 전투가 없고 클라이언트가 신고한 플레이어 `level`·`xp`만 저장한다.
- `spacetimedb/src/lib.rs:7-18` — 서버 구현은 `ctx.sender()` 소유권, 비공개 테이블, 서버 시각·난수 원칙을 따라야 한다.

## 3. 상세 분석

**현재 피해 흐름**

현재 몬스터 피해는 다음 세 단계에서 중복 결정된다.

1. `MonsterCodex`가 레벨과 골격 계통으로 `stats.damage`를 계산한다. `lib/game/systems/monster_codex.dart:381-450`
2. 상주 개체와 웨이브가 별도의 `damageMultiplier`를 부여한다. `lib/game/systems/monster_population.dart:191-200`, `lib/game/systems/wave_director.dart:80-86`
3. `Enemy`가 두 값을 곱해 근접 공격이나 발사체에 싣고, `Player`가 `damageTakenMultiplier`를 다시 적용한다. `lib/game/entities/enemy.dart:293-325`, `lib/game/entities/player.dart:345-360`

따라서 현재 3레벨 비행 몬스터의 기본 피해는 `(6 + 2×1.55)×0.85 = 7.735`이고, 상주 개체 배율까지 포함하면 약 7.35~8.51이다. 10레벨 보행 몬스터는 `(6 + 9×1.55)×1.1 = 21.945`로, 각각 요구값 3과 10을 만족하지 않는다. `lib/game/systems/monster_codex.dart:385-415`, `lib/game/systems/monster_population.dart:197-200`

**권장 피해 계약**

[판단] 단일 진실 공급원은 `MonsterSpecies.level`이어야 한다. `MonsterStats.damage`, `Enemy._damageScale`, `MonsterSeed.damageMultiplier`, `WavePlan.damageMultiplier`를 플레이어 피해 계산에서 제거하고, 근접과 발사체 모두 `species.level.toDouble()`을 원시 피해로 전달하는 구조가 가장 명확하다. 몬스터 골격 차이는 공격 속도·사거리·3연사·5연사 같은 행동 패턴으로 이미 표현된다. `lib/game/entities/enemy.dart:146-219`, `lib/game/systems/monster_codex.dart:217-257`

`Player`에는 기본값 0인 독립 `defense`를 추가하고 최종 피해를 한 번만 양자화해야 한다. 권장 수식은 다음과 같다.

`rawDamage = monster.level`  
`afterDefense = rawDamage × 100 / (100 + max(0, defense))`  
`finalDamage = max(1, round(afterDefense × buffs.damageTakenMultiplier))`

이 수식은 방어력 0·버프 없음에서 3레벨은 정확히 3, 10레벨은 정확히 10을 실제 HP에서 차감한다. [판단] 평면 감산식보다 저레벨 몬스터 완전 무효화를 막기 쉽지만, `100`이라는 방어 기준값은 성장·장비 계획과 함께 확정해야 한다.

현재는 소수 피해를 HP에서 차감한 뒤 `DamageText`만 반올림하므로, 버프 적용 시 표시값과 실제 감소량이 달라질 수 있다. 최종 피해를 먼저 정수화한 뒤 HP 차감·텍스트·피격 음량 모두 같은 값을 사용해야 한다. `lib/game/entities/player.dart:357-369`, `lib/game/fx/damage_text.dart:28-42`

방화벽까지 같은 방어 수식을 통과시키면 방어력이 환경 피해도 줄이는 뜻하지 않은 변경이 생긴다. `DamageSource.monster`, `DamageSource.player`, `DamageSource.hazard` 같은 출처를 피해 계약에 포함하고, 기존 의미를 유지하려면 방화벽은 피격 무적과 `defense`만 무시하되 기존 `damageTakenMultiplier` 적용 여부는 명시적으로 결정해야 한다. `lib/game/entities/player.dart:321-332`, `lib/game/entities/player.dart:345-358`

**HP 축과 생존 시간**

120에서 10,000으로의 증가는 정확히 83.33배다. 방어력 0에서 다른 피해가 없다는 조건으로 3레벨 몬스터에게는 3,334회, 10레벨에는 1,000회, 최대 200레벨에는 50회 맞아야 사망한다. 몬스터 피격 뒤에는 0.55초 무적도 생긴다. `lib/game/entities/player.dart:28-29`, `lib/game/entities/player.dart:351-361`, `lib/game/systems/monster_codex.dart:273-296`

원거리 골격은 공격 한 번에 3발 또는 5발을 0.16초 간격으로 쏜다. `[추측]` 탄 도달 간격이 비슷하면 첫 명중 뒤 0.55초 무적으로 후속탄 상당수가 무시되므로, 표시된 연사 수보다 실질 DPS가 훨씬 낮을 수 있다. `lib/game/entities/enemy.dart:193-219`, `lib/game/entities/player.dart:351-361`

방화벽의 5 피해를 유지하면 2,000틱, 즉 1,000초(16분 40초)가 걸린다. 기존 120 HP에서는 24틱·12초였으므로 체감을 유지하려면 틱당 약 416.7 또는 최대 HP의 약 4.167%로 바꿔야 한다. `lib/game/entities/player.dart:321-332`

레벨업 HP 증가를 그대로 두면 만렙 최대 HP는 10,618에 불과하다. 현재 곡선의 상대 성장폭을 그대로 보존하려면 일반 증가량은 1,500, 강화 구간은 약 2,833이 되어 만렙 최대 HP가 약 61,500까지 올라간다. 어느 쪽도 자동으로 옳지 않으므로, 기본 10,000과 별도로 만렙 목표 HP를 먼저 정해야 한다. `lib/game/systems/level_system.dart:46-57`, `lib/game/entities/player.dart:512-525`

소형·대형·강화 포션은 현재 기본 HP의 각각 37.5%, 91.7%, 16.7%를 회복한다. 같은 비율을 유지하면 약 3,750·9,167·1,667이 된다. 다만 포션은 드롭의 `amountMultiplier`가 아니라 `PickupSpec.potion`의 고정 회복값을 사용한다. 포션 회수 시 인벤토리에는 종류만 저장되기 때문에 `DropTable.amountScale`을 바꿔도 실제 회복량은 변하지 않는다. `lib/game/entities/pickup.dart:93-137`, `lib/game/entities/pickup.dart:300-307`, `lib/game/entities/player.dart:458-467`

플레이어 공격력과 몬스터 HP·XP는 반대 방향의 TTK 축이므로 HP와 함께 83.33배로 올려서는 안 된다. 그대로 두면 몬스터를 잡는 시간은 유지되고 플레이어 생존 시간만 늘어난다. 경험치와 드롭은 수치 단위를 확대하기보다 목표 XP/시간·포션 소비/시간을 기준으로 다시 측정하는 편이 맞다. `lib/game/entities/player.dart:35-36`, `lib/game/systems/monster_codex.dart:385-450`, `lib/game/systems/level_system.dart:60-75`

**표시와 MMORPG 경계**

HP 게이지는 비율로 그려져 10,000에서도 정상 작동하지만, `'10000 / 10000'` 문자열은 폭 186의 Canvas 바 안에서 오른쪽 정렬된다. 실제 글자 폭 측정과 좁은 화면 검증이 필요하다. 캐릭터 화면 역시 고정 좌표이며, `COMBAT` 네 줄에 `DEFENSE`를 추가하면 아래 `UPTIME`·`BUFFS`와 겹칠 수 있다. `lib/game/ui/hud.dart:146-158`, `lib/game/ui/hud.dart:211-269`, `lib/game/ui/character_screen.dart:333-397`

인벤토리는 기존 `fortify`의 35% 피해 감소를 이미 `DEF +35%`라고 표시한다. 새 수치형 `defense`와 다른 축이라는 요구와 충돌하므로 이 문구는 `DMG REDUCTION` 등으로 분리해야 한다. `lib/game/systems/buff.dart:43-44`, `lib/game/systems/buff.dart:64-69`, `lib/game/ui/inventory_ui.dart:483-499`

현재 `Player`와 `MonsterPopulation`은 게임 로드 때 로컬에서 새로 생성되며, SpacetimeDB에는 HP·방어·몬스터 상태가 없다. 현 프로토타입에서는 클라이언트 계산을 유지할 수 있지만, 공유 월드·PK 단계에서는 재접속으로 HP가 초기화되고 각 클라이언트가 서로 다른 몬스터 생사를 계산하는 문제가 생긴다. `lib/game/action_rpg_game.dart:165-177`, `lib/game/action_rpg_game.dart:994-1021`, `lib/game/net/spacetime_game_sync.dart:7-11`

서버 이전 시 클라이언트가 피해량이나 `account_id`를 보내게 해서는 안 된다. 클라이언트는 공격 의도와 대상만 보내고, 서버가 `ctx.sender()`의 캐릭터·몬스터 레벨·공격 시각으로 피해를 계산해야 한다. 전투용 HP·방어·몬스터 상태는 리더보드 `PlayerCharacter`와 분리된 비공개 테이블에 두고, 클라이언트에는 구독한 view로만 제공하는 구조가 적합하다. `spacetimedb/src/lib.rs:7-18`, `spacetimedb/src/leaderboard.rs:143-184`

## 4. 리스크 · 함정

- `.cowork/cowork-prompt.md`와 `GAME-DESIGN.md`는 몬스터 레벨이 없고 4종 고정 스탯만 있다고 설명하지만, 실제 코드는 이미 1~200 레벨 도감을 사용한다. 문서 전제대로 새 체계를 중복 구현하면 두 개의 몬스터 레벨 체계가 생긴다. `.cowork/cowork-prompt.md:34-36`, `GAME-DESIGN.md:343-352`, `lib/game/systems/monster_codex.dart:217-296`
- `stats.damage`만 레벨로 바꾸고 `_damageScale`을 남기면 3레벨 상주 몬스터나 후반 웨이브가 다시 3이 아닌 소수 피해를 준다. `lib/game/systems/monster_population.dart:191-200`, `lib/game/systems/wave_director.dart:80-86`
- 평면 감산식 `max(0, level-defense)`을 채택하면 방어력 3만으로 모든 1~3레벨 몬스터를 무효화할 수 있다. `[판단]` 최소 피해와 방어 성장 상한을 함께 정하지 않으면 저레벨 지역이 영구 안전지대가 된다.
- “몬스터 공격 한 번”이 발사체 한 발인지 3·5발 전체인지 불명확하다. 현재 구현은 각 발사체가 독립 피해를 전달한다. `lib/game/entities/enemy.dart:193-219`, `lib/game/entities/projectile.dart:83-97`
- 포션의 `PickupSpec.amount`와 실제 `PotionEffect.heal`이 서로 다르므로 잘못된 필드를 스케일하면 UI상 드롭량만 변하고 회복량은 그대로 남는다. `lib/game/entities/pickup.dart:73-88`, `lib/game/entities/pickup.dart:93-110`
- `DamageText`의 레이어 폭은 120픽셀 고정이다. 수천 단위 회복량이나 향후 5자리 피해가 나오면 Canvas에서 잘릴 수 있다. `lib/game/fx/damage_text.dart:28-42`, `lib/game/fx/damage_text.dart:61-69`
- 피격 음량은 `taken / 40`에 맞춰져 있어 최종 피해 28 이상부터 사실상 최대값으로 고정된다. 새 1~200 피해 축에 맞춘 음향 매핑 검토가 필요하다. `lib/game/entities/player.dart:381-386`
- 플레이어 `level`은 상한 30의 리더보드 성장 단계이고 몬스터 레벨은 1~200 도감 색인이다. 둘을 같은 서버 필드나 상한으로 통합하면 리더보드 의미가 깨진다. `lib/game/systems/level_system.dart:27-32`, `spacetimedb/src/leaderboard.rs:26-30`, `lib/game/systems/monster_codex.dart:266-296`
- 현재 몬스터 도감 테스트는 레벨·이름·HP·XP만 검사하고 “방어력 0에서 최종 피해=레벨” 불변식은 검사하지 않는다. `test/monster_codex_test.dart:7-64`

## 5. 권고안

| 순위 | 권고 | 범위 | 근거 | 리스크 |
|---|---|---|---|---|
| 1 | `MonsterSpecies.level`을 유일한 원시 공격 피해로 삼고, 방어·버프·반올림을 한 함수에서 처리한다. 기본 HP 10,000, 기본 `defense` 0을 명시적 상수로 둔다. | `player.dart`, `monster_codex.dart`, 공용 전투 수식 | `lib/game/entities/player.dart:27-37`, `lib/game/systems/monster_codex.dart:217-245` | 방어 수식과 최소 피해 정책을 먼저 확정해야 한다. |
| 2 | `MonsterStats.damage`, `Enemy._damageScale`, `MonsterSeed.damageMultiplier`, `WavePlan.damageMultiplier`를 플레이어 피해 경로에서 제거한다. `hpMultiplier`는 몬스터 체력 편차용으로 유지할 수 있다. | 몬스터 생성·근접·발사체 | `lib/game/entities/enemy.dart:25-49`, `lib/game/entities/enemy.dart:293-325`, `lib/game/systems/wave_director.dart:80-86` | 저장·생성자·테스트 호출부를 함께 바꾸지 않으면 컴파일 오류나 잔존 배율이 생긴다. |
| 3 | `DamageSource` 또는 피해 이벤트 구조를 도입해 몬스터·PK·방화벽의 방어 적용 여부를 명시한다. 안전지대·대시·피격 무적은 기존 순서를 유지한다. | 피해 계약·환경 피해 | `lib/game/entities/player.dart:321-360`, `lib/game/entities/iso_entity.dart:72-79` | 공용 `Damageable` 계약 변경은 적·구조물·발사체에도 파급된다. |
| 4 | 만렙 목표 HP를 먼저 정한 뒤 `LevelGains.maxHp`를 비율 기반 상수로 재작성하고, 포션은 고정 수치 또는 최대 HP 비율 중 하나로 통일한다. 방화벽은 목표 사망 시간 기준으로 조정한다. | 성장·회복·환경 밸런스 | `lib/game/systems/level_system.dart:46-57`, `lib/game/entities/pickup.dart:93-137`, `lib/game/entities/player.dart:321-332` | 기존 비율을 그대로 보존하면 만렙 HP가 약 61,500까지 증가한다. |
| 5 | 실제 포션 회복량과 드롭 표시량의 이중 구조를 정리하고, 회복량 변경 뒤 확정 드롭·웨이브 보상 빈도를 다시 조정한다. | 포션·드롭 경제 | `lib/game/entities/pickup.dart:73-110`, `lib/game/systems/drop_table.dart:119-148` | 비율 회복을 유지하면서 현재 드롭률까지 유지하면 회복 자원이 지나치게 풍부해질 수 있다. |
| 6 | HUD·캐릭터 화면에 5자리 HP와 `DEFENSE`를 배치하고, `fortify`의 `DEF +35%` 표기를 별도의 피해 감소 용어로 바꾼다. `DamageText`는 실제 글자 폭으로 레이어를 잡는다. | Flame Canvas UI·FX | `lib/game/ui/hud.dart:146-158`, `lib/game/ui/character_screen.dart:333-397`, `lib/game/ui/inventory_ui.dart:483-499` | 고정 좌표 패널의 하단 항목과 겹칠 수 있다. |
| 7 | 3·10레벨 예시와 1~200 전체 불변식, 방어·버프·방화벽·정확히 0 HP 사망·리스폰을 단위 테스트하고 10,000 및 만렙 HP 상태를 Canvas 골든 테스트로 검증한다. | 테스트 | `test/monster_codex_test.dart:7-64`, `lib/game/entities/player.dart:345-425` | 현재 `Player`가 게임 객체에 강하게 결합돼 있어 순수 전투 수식 분리가 선행돼야 테스트가 쉽다. |
| 8 | 서버 권위 단계에서는 전투 상태를 리더보드와 분리된 비공개 테이블에 두고, reducer가 `ctx.sender()`와 서버 시각으로 판정하도록 한다. 주변 상태 view는 테이블 반환형·인덱스 범위 조회·명시적 구독 제약을 지킨다. | SpacetimeDB·MMORPG 동기화 | `spacetimedb/src/lib.rs:7-18`, `spacetimedb/src/leaderboard.rs:101-114`, `.cowork/cowork-prompt.md:78-83` | 클라이언트 전투와 서버 전투를 장기간 병행하면 판정 불일치가 발생한다. |

## 6. 불확실 · 미확인

- 방어력의 성장 경로와 공식은 요구에 정의돼 있지 않다. 비율 감소식을 권장했지만, 평면 감산식을 원한다면 최소 피해·관통·저레벨 완전 면역 규칙을 사람이 결정해야 한다. `.cowork/cowork-prompt.md:28-32`
- “피해=몬스터 레벨”이 발사체 한 발 기준인지 3·5연사 전체 기준인지 확인이 필요하다. 현재 계약은 한 발마다 별도 `applyDamage` 호출이다. `lib/game/entities/enemy.dart:193-219`, `lib/game/entities/projectile.dart:83-97`
- 기본 HP 10,000 외에 만렙 목표 HP, 방화벽 목표 사망 시간, 포션 목표 회복 비율, 기대 피격 횟수는 지정돼 있지 않다.
- 재접속·로그아웃 시 현재 HP와 방어력을 유지할지, 안전지대에서 전부 회복할지는 MMORPG 운영 규칙으로 별도 결정해야 한다. 현재 로드·재시작은 새 `Player`를 만든다. `lib/game/action_rpg_game.dart:165-177`, `lib/game/action_rpg_game.dart:994-1021`
- 정적 읽기·검색만 수행했으므로 `flutter analyze`, `flutter test`, 서버 빌드 결과와 실제 Canvas 클리핑은 미확인이다.
