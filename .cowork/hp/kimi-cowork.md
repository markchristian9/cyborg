<!-- cowork:kimi | 2026-08-04 20:44:50 | exit=0 | 371s -->
# kimi 분석 — hp

> 요청: pc 의 HP 를 아주 크게 해 주세요. -> 예를 들면, 기본 1만이고, 기본 방어력 0인 상태에서 공격을 당하면 mob 마다 공격 치가 다르겠지만, 저레벨 몬스터(3 레벨 몬스터) 의 경우 3의 데미지가 입도록 해 주세요. 10레벨 몬스터의 경우 10레벨의 데미지가 입히도록 해 주세요. 그래서 1만 HP 가 모두 소진되면 사망하는 것으로 해 주세요.
> 생성: 2026-08-04 20:44:50 · 소요 371s · 읽기 전용 분석(작업공간 미수정)

---

• 계속해서 나머지 전투 관련 파일들을 읽겠다.

• 핵심 파일은 다 읽었다. 남은 확인 사항(방어력 부재, 테스트 의존, 서버 머리말)을 검색한다.

• 

## 1. 결론 요약

  요구 규격(HP 10,000 · 기본 방어력 0 · 방어력 0 기준 피해 = 몬스터 레벨 · HP 0 사망)은 현재 구조에서 **세 군데만 고치면 성립**한다: ① `player.dart` 의 HP 초기값과 `applyDamage`, ② `monster_codex.dart` 의 피해 곡선, ③ 몬스터에게 붙는 `damageMultiplier` 두 경로. 중요한 사실 하나 — **몬스터 레벨 개념은 이미 코드에 존재한다**(`MonsterSpecies.level` 1~200, `Enemy.level`).cowork 프롬프트의 "몬스터 레벨이라는 개념 자체가 없다"는 전제는 현재 코드와 어긋나며, 덕분에 작업은 "레벨 도입" 이 아니라 **"기존 레벨을 피해 수식의 단일 기준으로 승격"** 하는 일로 줄어든다. 사망 → 안전지대 리스폰은 이미 구현돼 있어 손댈 필요가 없다. 함께 스케일해야 하는 값은 포션 회복량·레벨업 HP 증가분·방화벽 지속 피해 세 곳이며, 서버(SpacetimeDB)는 이번 변경의 영향권 밖이다.

  

## 2. 근거

  - `lib/game/entities/player.dart:28-29` — 플레이어 기본 HP `double _hp = 120; double _maxHp = 120;`
  - `lib/game/entities/player.dart:358` — 피해 적용의 유일한 감소 경로: `final taken = amount * buffs.damageTakenMultiplier;` — 방어력 개념 없음(코드베이스 전체에 `defense` 식별자 없음, grep 확인)
  - `lib/game/entities/player.dart:375-380` — `_hp <= 0` 이면 사망 처리 후 `game.onPlayerDied()` → `lib/game/action_rpg_game.dart:919` `player.respawnAt(map.respawnPoint(_random))` — 요구한 "1만 소진 시 사망" 흐름은 이미 존재
  - `lib/game/systems/monster_codex.dart:184-185, 235` — `MonsterSpecies.level` (1~200) 이 이미 존재. "몬스터 레벨 개념이 없다" 는 프롬프트 전제와 불일치
  - `lib/game/entities/enemy.dart:120` — `int get level => species.level;` — Enemy 가 레벨을 이미 노출
  - `lib/game/systems/monster_codex.dart:342` — 현재 피해 곡선 `baseDamage = 6 + step * 1.55` (레벨 1 = 6, 레벨 10 ≈ 20)
  - `lib/game/systems/monster_codex.dart:353, 369, 386, 402` — 계통별 피해 배율 0.85 / 1.1 / 0.95 / 1.35 — "레벨 = 피해" 를 깨는 첫 번째 요인
  - `lib/game/entities/enemy.dart:366, 389` — 실제 피해 투입 지점 두 곳: 근접 `player.applyDamage(stats.damage * _damageScale, ...)`, 원거리 발사체 `damage: stats.damage * _damageScale`
  - `lib/game/systems/monster_population.dart:200` — 상주 몬스터 개체 편차 `damageMultiplier: 0.95 + random.nextDouble() * 0.15` — "레벨 = 피해" 를 깨는 두 번째 요인
  - `lib/game/systems/wave_director.dart:85` — 웨이브 배율 `damageMultiplier: 1 + (wave - 1) * 0.008` — 세 번째 요인
  - `lib/game/entities/pickup.dart:101, 110, 137` — 포션 회복량 45 / 110 / 20 — HP 10,000 축에서는 사실상 무의미
  - `lib/game/systems/level_system.dart:50` — 레벨업 HP 증가분 `maxHp: milestone ? 34 : 18` — 10,000 축에서 무의미
  - `lib/game/entities/player.dart:331` — 방화벽(hazard) 지속 피해 고정 `applyDamage(5, ...)`
  - `lib/game/ui/hud.dart:157` — HP 표시 `'${player.hp.ceil()} / ${player.maxHp.round()}'` — 비율 기반 바라 바 자체는 무관, 수치 텍스트만 5자리로 늘어남
  - `spacetimedb/src/leaderboard.rs:155` — 서버가 받는 것은 `report_progress(level, xp)` 뿐. HP·방어력·피해는 서버에 개념 자체가 없음
  - `test/monster_codex_test.dart:27-28` — 테스트는 `maxHp` 단조 증가만 검증. 피해 수치를 단언하는 테스트 없음

  

## 3. 상세 분석

  **피해가 흐르는 경로 (현재).** 몬스터 → 플레이어 피해는 정확히 두 통로다. 근접은 `Enemy._resolveMeleeStrike` (`enemy.dart:366`), 원거리는 `Enemy._fire` 가 만든 발사체 (`enemy.dart:389` → `projectile.dart:91` 의 `target.applyDamage(damage, ...)`). 둘 다 최종적으로 `Player.applyDamage` (`player.dart:345`) 에 도달하고, 여기서 무적·대시·안전지대 면역을 거친 뒤 `amount * buffs.damageTakenMultiplier` 가 HP 에서 깎인다. **방어력을 끼워 넣을 위치는 `player.dart:358` 한 줄뿐이다** — 이 구조는 이번 재설계에 유리하다.

  **"피해 = 몬스터 레벨" 을 깨는 세 겹의 배율.** 규격대로라면 방어력 0 일 때 최종 피해가 종의 레벨과 정확히 같아야 하는데, 현재는 ① `MonsterCodex._statsFor` 의 `baseDamage = 6 + step * 1.55` 곡선, ② 계통별 배율(0.85~1.35), ③ 개체·웨이브 `_damageScale`(0.95~1.10, 웨이브당 +0.008) 이 곱해져 레벨 3 몬스터의 실제 피해는 약 8.6~11.5 사이 어딘가다. 규격을 지키려면 이 세 겹을 **피해 축에서는 전부 1 로 수렴**시켜야 한다. 단, 몹마다 공격치가 다른 것은 사용자도 인정한 바("mob 마다 공격 치가 다르겠지만")이고, 그 다양성은 이미 `MonsterCodex.roll` 의 레벨 spread(`monster_population.dart:196` 의 `spread: 4`, `wave_director.dart:73` 의 `spread: 5`) 가 담당하므로 배율을 없애도 다양성은 남는다. 계통 간 개성은 HP·속도·사거리·버스트 수(`enemy.dart:280-284`) 가 이미 나눠 갖고 있어 피해 배율이 사라져도 무너지지 않는다.

  **HP 축이 100배 되면 암묵적으로 깨지는 값.** ① 포션 회복 45/110/20 (`pickup.dart`) — 최대 HP 의 0.45%/1.1%/0.2% 로 사실상 사망. ② 레벨업 HP 증가 18/34 (`level_system.dart:50`) — 30레벨까지 다 더해도 +730 으로 기본값의 7%. ③ 방화벽 틱 피해 5 (`player.dart:331`) — 0.05%. 반대로 **스케일이 필요 없는 것**: 레벨업 완전 회복(`player.dart:523`)·리스폰 완전 회복(`player.dart:403`) 은 비율 개념이라 그대로 유효하고, 적의 HP 곡선(`monster_codex.dart:341`) 과 플레이어 공격력(26/18, `player.dart:35-36`) 은 이번 규격이 건드리지 않는 축이라 TTK(몇 대 때려 잡는가)는 변하지 않는다.

  **체감 수치 (규격 그대로 적용 시).** 방어력 0 기준: 레벨 1 몬스터 = 피해 1 → 10,000 대를 맞아야 사망(사실상 무해). 레벨 10 = 10 → 1,000 대. 레벨 200 소버린 = 200 → 50 대. 피격마다 붙는 0.55초 무적(`player.dart:361`) 이 초당 피격 횟수를 ~1.8 회로 제한하므로 레벨 200 몬스터에게도 약 27초는 버틴다. 즉 프롬프트가 우려한 "3씩 깎이면 3,333 대" 문제는 **규격의 의도된 결과**(저레벨 = 위협 없음)이지 결함이 아니며, 진짜 설계 포인트는 방어력이 커졌을 때의 감산 모델이다. `taken = max(1, monsterLevel - defense)` 같은 차감형이면 방어력이 레벨을 넘는 순간 피해 1 로 고정돼 "무적 빌드" 를 구조적으로 막는다 [판단]. 기존 `damageTakenMultiplier`(곱셈) 와의 합성 순서는 `(amount - defense) * multiplier` 가 자연스럽다 — 차감 후 배율.

  **MMORPG·서버 권위 관점.** 서버는 현재 전투를 시뮬레이션하지 않고 레벨·XP 신고만 받는다(`leaderboard.rs:155-187`). 이번 변경은 전부 클라이언트 로컬 수식이라 **서버 스키마·reducer·view 에 손댈 것이 없고**, 플레이어 `level` 의 의미도 안 바뀌므로 리더보드·`MAX_LEVEL 30` 과 무충돌이다. 나중에 전투를 서버 권위로 옮길 때 걸림돌은 하나다: "피해 = 몬스터 레벨 − 방어력" 수식을 Rust 모듈에 다시 구현해야 하는데, 몬스터 레벨 테이블이 현재 Dart 전용 생성 코드(`MonsterCodex._build`) 라 서버가 같은 레벨을 알 방법이 없다. 수식이 "종 레벨 하나만 입력으로 받는 순수 함수" 로 정리돼 있으면 그때 이식이 한 줄짜리가 된다 — 지금부터 피해 계산을 `Enemy` 에 인라인하지 말고 한 함수로 모아 두는 것이 그 대비다.

  **HUD.** HP 바는 비율 기반이라 그대로고, 수치 텍스트가 `120 / 120` → `10000 / 10000` 으로 늘어난다. 바 폭 186px 에 fontSize 11 텍스트가 우측 정렬이라 물리적으로는 들어가지만 좌측 'HP' 라벨과의 간격이 좁아진다(`hud.dart:146-157`) — Flame 캔버스 기준이므로 텍스트 폭을 재서 좌측 라벨을 생략하거나 폰트를 한 단계 내리는 선택지가 있다.

  

## 4. 리스크 · 함정

  - **프롬프트 전제와 코드의 불일치 (중요).** cowork 프롬프트는 "몬스터 레벨 개념이 없다", "`EnemyStats.table` 에 수치가 있다" 고 전제하지만, 실제로는 `MonsterSpecies.level` (1~200) 이 이미 존재하고 스탯은 `EnemyStats.table` 이 아니라 `MonsterCodex._statsFor` (`monster_codex.dart:339`) 에서 생성된다. 이 전제대로 "레벨을 새로 도입" 하는 구현을 하면 기존 레벨 체계(명판 `enemy.dart:897`, 위협도 색 `enemy.dart:923`, 점수 `action_rpg_game.dart:843`, 웨이브 레벨대 `wave_director.dart:44`) 와 이중 레벨이 생긴다. **기존 레벨을 재사용하는 쪽이 유일하게 옳은 방향이다.**
  - **`_damageScale` 을 그냥 두면 규격이 조용히 깨진다.** 컴파일 에러가 안 나므로 테스트 없이는 놓치기 쉽다. 상주 개체 0.95~1.10 (`monster_population.dart:200`), 웨이브 +0.008/웨이브 (`wave_director.dart:85`) — 피해 배율만 1 로 고정하고 HP 배율은 유지하는 식으로 두 필드를 분리해야 한다.
  - **회복 수단을 스케일하지 않으면 후반부에 죽음이 회복 불가능한 사실상의 영구 페널티가 된다.** HP 10,000 에 회복 45 는 없는 것과 같고, 이 게임은 사망 시 레벨·XP 를 잃지 않고 리스폰만 하므로 "죽음보다 회복 부재" 가 체감 난이도를 결정한다.
  - **레벨업 HP 증가분을 그대로 두면 `LevelGains.maxHp` 가 죽은 코드가 된다.** 단, 증가분을 키우면 만렙 HP 가 기본 10,000 을 얼마나 넘길지가 새 밸런스 변수가 된다 — 사람이 정한 규격은 "기본 1만" 이므로 증가분 스케일은 사람 결정 사항이다.
  - **피격 음량 공식 `0.5 + taken / 40` (`player.dart:385`).** 피해 3 이면 0.575 로 거의 최소 음량 — 큰 문제는 아니지만 "맞았는데 소리가 작은" 체감 변화가 있다. 클램프 상한 1.2 는 피해 200 에서도 안전.
  - **데미지 텍스트는 `amount.round()` (`damage_text.dart:30`).** 피해를 정수(레벨 값)로 정의하면 표시와 실제가 항상 일치해 오히려 깔끔해진다.
  - **회귀 감시용 테스트가 없다.** 피해 수식을 단언하는 테스트가 현재 0 개(grep 확인) — 수식을 바꾼 뒤 "레벨 3 → 3" 을 검증하는 단위 테스트가 없으면 나중에 배율이 다시 끼어들어도 아무도 모른다.
  - **서버 권위 이전 시 이중 구현 함정.** 위 §3 마지막 문단 참조. 지금 수식을 Dart 의 한 함수로 모아 두지 않으면 이식 시 두 벌의 수식이 어긋나는 리스크가 생긴다.

  

## 5. 권고안

  | 순위 | 권고 | 범위 | 근거 | 리스크 |
  |---|---|---|---|---|
  | 1 | `Player` 에 `double defense = 0;` 스탯을 추가하고 `applyDamage` 의 감산을 `taken = max(0, amount - defense) * buffs.damageTakenMultiplier` 로 변경. 최소 피해 1 보장 여부(`max(1, ...)`)는 사람이 결정 | `lib/game/entities/player.dart:27-37, 358` | `player.dart:358` (유일한 감산 지점) | 버프 곱셈과의 합성 순서가 고정됨 — 순서를 바꾸고 싶으면 지금 정해야 함 |
  | 2 | 피해 곡선을 `damage: level.toDouble()` 로 교체하고 계통별 피해 배율(0.85/1.1/0.95/1.35)을 제거. 계통 개성은 HP·속도·사거리로 유지 | `lib/game/systems/monster_codex.dart:339-417` | `monster_codex.dart:342, 353, 369, 386, 402` | 계통 간 "때리는 맛" 차이가 사라짐 — HP 차이로 상쇄되는지 플레이 확인 필요 |
  | 3 | 상주 개체·웨이브의 `damageMultiplier` 를 피해 경로에서 1.0 으로 고정(HP 배율은 유지). 필드 자체를 지우기보다 분리해 두는 편이 안전 | `monster_population.dart:200`, `wave_director.dart:85`, `enemy.dart:366, 389` | 해당 줄들 | 기존 시드 저장 데이터 없음(로컬 생성)이라 마이그레이션 불필요 |
  | 4 | `_hp`·`_maxHp` 초기값을 `10000` 으로 변경 | `player.dart:28-29` | `player.dart:28-29` | 없음(리스폰·레벨업 회복이 비율 기반) |
  | 5 | 포션 회복량을 HP 축에 맞게 재조정 — 고정값 대신 최대 HP 비율(예: 소형 15%, 대형 40%)로 바꾸면 만렙 HP 증가분과 무관하게 유효 [판단] | `lib/game/entities/pickup.dart:101, 110, 137`, `Player.heal` (`player.dart:432`) | `pickup.dart:101-137` | `PotionEffect.heal` 이 double 고정값이라 비율 방식이면 시그니처 변경 필요 |
  | 6 | `LevelGains.maxHp` 재조정(예: 레벨당 +500, milestone +1500 → 만렙 약 2.4만 [판단]) 또는 삭제. 어느 쪽이든 "기본 1만" 규격과 별개로 사람이 목표 만렙 HP 를 정해야 함 | `lib/game/systems/level_system.dart:50` | `level_system.dart:50` | 만렙 HP 가 리더보드와 무관해 서버 영향 없음 |
  | 7 | 방화벽 틱 피해 5 를 비율(예: 최대 HP 의 0.5%/틱) 또는 몬스터 레벨과 무관한 고정 위협으로 재정의 | `player.dart:331` | `player.dart:321-333` | 안전지대 밖 저레벨 구역에서 방화벽이 몬스터보다 아픈 역전이 생길 수 있음 |
  | 8 | "레벨 N 몬스터 → 방어력 0 피해 N" 을 단언하는 단위 테스트 추가 (`test/` 에 신규) | `test/` | 피해 수식 테스트 부재(grep 확인) | 없음 |
  | 9 | 피해 계산을 `Enemy` 인라인이 아닌 단일 함수(예: `damageToPlayer(species, defense)`)로 모아 서버 이식 대비 | `enemy.dart:366, 389`, `projectile.dart:91` | 서버에 전투 개념 부재 `leaderboard.rs:144-153` | 지금 당장은 순수 리팩터링이라 효과 없음 |

  

## 6. 불확실 · 미확인

  - **최소 피해 하한(0 vs 1)**: `max(0, ...)` 이면 방어력 ≥ 레벨일 때 피해 0 이 되는데, 사용자 규격은 방어력의 감산 방식(차감/비율) 자체를 정하지 않았다. 사람 결정이 필요하다.
  - **만렙(30) 시 목표 HP**: "기본 1만" 만 정해졌고 성장분은 미정. 권고 6 의 수치는 [판단] 이다.
  - **`action_rpg_game.dart` 1000~1274 행 미독**: `restart()` 이후 구간에 HP 관련 초기화가 더 있는지 확인하지 못했다. `restart()` 가 `Player` 를 새로 만드는 구조라면 영향 없을 것으로 [추측].
  - **HUD 수치 텍스트 실제 렌더 폭**: `10000 / 10000` 이 186px 바 안에서 'HP' 라벨과 겹치는지는 실행해 봐야 안다 [추측].
  - **`EnemyStats.table` 언급 건**: 프롬프트의 파일 표에 있는 이 심볼은 현재 코드에 존재하지 않는다. 제거된 것인지 이름이 바뀐 것인지 git 이력은 확인하지 않았다(읽기 전용 범위에서 현재 코드 기준으로만 판단).
  - **PK(플레이어 간 전투)**: 프롬프트는 PK 허용을 전제로 하지만 현재 코드에 플레이어 → 플레이어 피해 경로가 없어(grep 상 `ProjectileOwner.player` 의 대상은 적과 구조물뿐, `projectile.dart:84-86`), 방어력이 PK 에 미치는 영향은 검토 대상이 아직 존재하지 않는다.
