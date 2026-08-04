<!-- cowork:grok | 2026-08-04 20:44:43 | exit=0 | 364s -->
# grok 분석 — hp

> 요청: pc 의 HP 를 아주 크게 해 주세요. -> 예를 들면, 기본 1만이고, 기본 방어력 0인 상태에서 공격을 당하면 mob 마다 공격 치가 다르겠지만, 저레벨 몬스터(3 레벨 몬스터) 의 경우 3의 데미지가 입도록 해 주세요. 10레벨 몬스터의 경우 10레벨의 데미지가 입히도록 해 주세요. 그래서 1만 HP 가 모두 소진되면 사망하는 것으로 해 주세요.
> 생성: 2026-08-04 20:44:43 · 소요 364s · 읽기 전용 분석(작업공간 미수정)

---



## 1. 결론 요약

요청 규격(기본 HP 10,000 · 방어 0 · **방어 0·버프 없을 때 최종 피격 피해 = 몬스터 레벨** · HP 0 사망)은 **현재 클라이언트 구조로 구현 가능**하다.  
cowork 프롬프트의 “몬스터 레벨이 없다”는 **코드와 어긋난다** — `MonsterCodex`에 종 레벨 1~200과 명판 `Lv.N`이 이미 있다. 막힌 축은 레벨 부재가 아니라 **`stats.damage` 곡선·개체/웨이브 `damageMultiplier`·피격 무적 0.55초·HP 축에 묶인 회복/성장**이다.  
HP만 1만으로 올리고 피해만 레벨로 바꾸면 저레벨 존은 i-frame 때문에 **사실상 불사**에 가깝다. 규격을 **바꾸지 않고** 살리려면 피격 무적·회복·`LevelGains.maxHp`·hazard를 **같은 패키지**로 손봐야 한다. 서버 전투 권위·배포는 이번 범위에 불필요하다.

---

## 2. 근거

- `lib/game/entities/player.dart:28-29` — 기본 `_hp` / `_maxHp` = **120**. `defense` 필드 없음.
- `lib/game/entities/player.dart:345-360` — `applyDamage`: 무적·대시·안전지대 차단 후 `taken = amount * buffs.damageTakenMultiplier`만 적용. **defense 없음**.
- `lib/game/entities/player.dart:361, 375-380` — 피격 시 `_invulnerable = max(..., 0.55)`; `_hp <= 0` → `onPlayerDied()`.
- `lib/game/entities/player.dart:331` — hazard 틱 피해 **5** / 0.5초, `ignoreInvulnerable: true`.
- `lib/game/entities/enemy.dart:54-55, 301, 324` — `level => species.level`; 근접·발사체 모두 `stats.damage * _damageScale`을 전달.
- `lib/game/systems/monster_codex.dart:217-232, 273-274, 385-398` — 종 레벨 1~200 SSOT; `baseDamage = 6 + (level-1)*1.55` 후 build 배율(0.85~1.35) → **피해 ≠ 레벨** (Lv3 drone ≈ 7.7, Lv10 walker ≈ 22).
- `lib/game/systems/monster_population.dart:178-199` — `regionLevel`로 종 배치; 시드 `damageMultiplier` **0.95~1.15** → “정확히 레벨”과 충돌 가능.
- `lib/game/systems/wave_director.dart:84-86` — 웨이브 `damageMultiplier: 1+(wave-1)*0.008` (문서의 ×0.1과 불일치).
- `lib/game/systems/level_system.dart:30, 50` — 플레이어 만렙 30; 레벨업 `maxHp` **+18 / +34** (2→30 누적 +618).
- `lib/game/entities/pickup.dart:101,110,137` + `300-307` — 포션 heal **45 / 110 / 20**(인벤 보관 후 사용); HP 120 시대 스케일.
- `lib/game/ui/hud.dart:103-157` — `'${hp.ceil()} / ${maxHp.round()}'`, 패널 폭 268·바 186px → 5자리 표시 밀도 문제.
- `lib/game/systems/buff.dart:64-68` — fortify `damageTakenMultiplier: 0.65` (**defense 스탯과 별축**).
- `lib/game/entities/enemy.dart:193-218` — siege 버스트 **3**, sovereign **5**, 탄 간격 0.16초; 현재 i-frame 0.55초면 후속 탄 대부분 면역.
- `lib/game/action_rpg_game.dart:907-919` — 사망 시 안전지대 `respawnAt` (규격의 사망 처리는 이미 충족).
- `spacetimedb/src/leaderboard.rs:145-186` — 서버는 플레이어 **level/xp 신고**만 검증; 전투 HP·피해 권위 없음.
- `GAME-DESIGN.md:279,693,698` — HP 120, `EnemyStats.table` 기술 → 실코드는 `MonsterCodex` (`EnemyStats` 식별자는 문서에만 존재).

---

## 3. 상세 분석

### 3.1 범위와 경계

| 축 | 권위 위치 | 이번 요청 |
|---|---|---|
| 플레이어 HP·피격 수식 | 클라이언트 `Player` | **핵심 변경** |
| 몬스터 레벨·기본 스탯 | 클라이언트 `MonsterCodex` | 레벨 **유지**, **damage 정의 변경** |
| 난이도 배치 | `MonsterPopulation` / `WaveDirector` | `damageMultiplier` 정리 |
| 성장·회복 | `LevelSystem` / `PickupSpec` | HP 축 동반 스케일 |
| 서버 전투 | 없음 (진행도만) | **배포·스키마 변경 불필요** |
| 플레이어 `level` / 리더보드 | `report_progress` | **의미 유지** (몬스터 레벨과 혼동 금지) |
| 플레이어 공격력·몹 HP | Codex·`meleeDamage` 26 등 | **요청 밖** (비대칭은 별 판단) |

### 3.2 현재 피격 파이프라인

```
Enemy._resolveMeleeStrike / Projectile(owner=enemy)
  → amount = stats.damage * _damageScale
  → Player.applyDamage(amount)
       → (무적·대시·안전지대면 return)
       → taken = amount * damageTakenMultiplier
       → _hp -= taken; i-frame 0.55s
```

규격의 “3레벨 몬스터 → 3”은 **방어 0·버프 없을 때 최종 `taken`** 이다.  
권장 정의(규격 정합, 공식 형태는 사람 결정 가능):

- `rawAttack = species.level` (double)
- `afterDefense = f(rawAttack, defense)` 단 **`defense == 0`이면 `afterDefense == rawAttack`**
- `taken = afterDefense * damageTakenMultiplier` (fortify는 별축 유지)

SSOT 후보: (A) `MonsterStats.damage`를 레벨과 같게 고정하고 배율 제거, 또는 (B) 적 공격 경로에서 `level.toDouble()`을 쓰고 Codex damage는 폐기/다른 용도. **한곳만** 진실이어야 한다. 지금은 Codex 곡선 × build 배율 × 시드/웨이브 배율에 흩어져 있다.

### 3.3 수치 체감 (코드 상수 기반)

| 상황 | 현재 대략 1타 피해 | 120 HP 생존 타수 | 규격 1타(def 0) | 10000 HP 생존 타수 |
|---|---|---|---|---|
| Lv3 drone | ≈7.7 | ≈16 | **3** | **≈3333** |
| Lv10 walker | ≈22 | ≈5.5 | **10** | **1000** |
| Lv100 (base) | ≈159×build | 1타 전후 | **100** | **100** |

**i-frame 하한 TTK** (전면 무적 0.55초 → 이론상 최대 히트율 ≈ 1/0.55 Hz):

- 최소 사망 시간 ≈ `(10000 / level) × 0.55`초  
- Lv3 ≈ **1833초(~30분)**, Lv10 ≈ **550초**, Lv100 ≈ **55초**

단일 몹 공격 주기(telegraph+strike+recover, drone ≈ 0.94초)는 더 길어서 **혼자 때리면 더 오래** 산다. 다만 다수 몹·원거리 버스트도 **한 번 맞은 뒤 0.55초 전면 면역**이라, 밀도로 저레벨 TTK를 메울 수 없다. 이것이 규격 유지 시 **필수 동반 수정** 지점이다.

원거리 siege/sovereign은 한 사이클에 3~5발을 0.16초 간격으로 쏘지만, 현재 i-frame이면 **첫 발만 유효**에 가깝다. 무적을 줄이면 “레벨=1발 피해” 규격은 지켜도 **사이클 총 피해 = level × burst**가 되어 체감이 급변한다 — 버스트를 1로 줄이거나, 소스 단위 쿨을 쓰는 선택이 필요하다.

### 3.4 HP 1만에 맞춰 같이 스케일해야 할 값

| 항목 | 현재 | 1만 HP 시 체감 | 방향 (규격 유지) |
|---|---|---|---|
| 포션 heal | 45 / 110 / 20 | 0.45% / 1.1% / 0.2% | maxHp 비율 또는 수천 단위 |
| 레벨업 maxHp | +18/+34 | 만렙 +618 ≈ 노이즈 | 수백~수천대 또는 % |
| hazard | 5 / 0.5s | 무시 가능 | maxHp 비율/틱 등 — **사람 값 확정** |
| fortify 0.65× | 상대 배율 | 유지 가능 | UI `DEF +%`와 스탯 defense **용어 분리** |
| 시드/웨이브 damage 편차 | ±5~15% · wave 배율 | 규격 엄수 시 | 1.0 고정 또는 제거 |
| build damage 배율 | 0.85~1.35 | 레벨≠피해 | 제거; 차별은 속도·사거리·버스트·telegraph |
| 플레이어 공격→몹 HP | 26 vs Codex HP | 요청 밖 | “잡는 속도”는 유지 가능; “맞는 속도”만 붕괴 |
| HUD / 캐릭터 시트 | 3자리 전제 | `10000 / 10618` | 바·폰트; COMBAT에 DEF |
| 피격 SFX | `taken / 40` | 소피해면 항상 최소 볼륨 | 스케일 기준 재조정 검토 |
| 데미지 텍스트 | `amount.round()` | 1단위 표시는 규격과 맞음 | 폭·가독성만 확인 |

참고: `PickupSpec.amount`(22/60)는 라벨·드롭 스케일용이고, 실제 HP 회복은 `PotionEffect.heal`이다. `GAME-DESIGN`의 “HP 22/60”은 코드 heal 45/110과도 어긋난다.

### 3.5 구현 구조 방향 (실행 아님 · 위치만)

1. **`Player`**: `baseMaxHp/hp = 10000`, `defense = 0`, `applyDamage`에서 방어 후 버프 배율. 사망 분기는 유지.
2. **`MonsterCodex._statsFor`**: `damage`를 **레벨 정합**으로 재정의. build damage 배율은 제거하거나 비피해 축으로만.
3. **시드/웨이브 `damageMultiplier`**: 규격 엄수 시 **1.0 고정 또는 제거**. `hpMultiplier` 편차는 유지 가능.
4. **피격 무적**: 규격 유지 시 필수. 후보 — (a) 0.05~0.15초 단축, (b) **동일 소스만** 쿨, (c) 무적 중 누적 허용. 대시 무적·리스폰 2초는 별 정책. 원거리 버스트와 함께 설계.
5. **표시**: `hud.dart` / `character_screen.dart` 5자리 HP; COMBAT에 DEF; `inventory_ui` fortify 문구를 “피해 감소” 등으로 분리.
6. **문서**: `GAME-DESIGN`의 `EnemyStats.table`·웨이브 0.16·HP 120을 Codex/실수치로 정리. 단위 테스트로 “def0·무버프 → taken == level” 고정.
7. **서버**: 지금 단계 변경 불필요. 이후 서버 권위 시 같은 수식을 순수 함수로 묶어두면 이식 용이. `ctx.sender()` 원칙·테이블 비공개 원칙과 충돌 없음.

### 3.6 MMORPG · 보안

전투가 전부 클라이언트인 한, HP·방어 조작 치트 위험은 **기존과 동형**이다. 이번 변경이 서버 이전을 더 어렵게 하지는 않는다.  
공유 월드에서 풀 HP가 커지고 i-frame이 그대로면 **PK·다중 교전 위협이 급감**한다. “존재는 보이지만 전투 긴장이 없다”는 라이브 밀도로도 해결되지 않는다.  
플레이어 `level` 의미는 리더보드와 묶여 있으므로 **몬스터 레벨과 이름을 섞지 말 것**.

---

## 4. 리스크 · 함정

- **피격 i-frame 0.55초 × HP 1만 × 피해=level** → 저·중레벨 난이도 소멸 (최우선 함정).
- **`damageMultiplier`·build damage 배율**을 남기면 “레벨=피해” 수치 검증이 깨짐.
- **무적 축소 + 원거리 버스트 3~5** → 사이클 총 피해가 level×N으로 폭증; 둘을 같이 설계해야 함.
- **포션/성장 미스케일** → 회복·레벨업 보상이 장식화.
- **fortify vs defense** 이중 축: 적용 순서·UI 용어 혼동 시 밸런스·기획 소통 실패. fortify 중에는 taken ≠ level이 **의도**여야 함.
- **문서 구식**(`EnemyStats.table`, 웨이브 배율 0.16 vs 코드 0.01) — 구현자가 잘못된 SSOT를 건드릴 위험.
- **사운드 `taken/40`**: 소피해에선 항상 최소 볼륨 — 기능 문제는 작음.
- 몬스터 HP·플레이어 공격을 안 건드리면 “때리면 잘 죽고 맞아도 안 죽음” 비대칭 — 의도일 수 있으나 액션 긴장 저하.
- 서버에 HP를 안 두므로 **치트 완화는 이번 범위 밖**; 설계 자리만 확보하는 수준이 현실적.

---

## 5. 권고안

| 순위 | 권고 | 범위 | 근거 | 리스크 |
|---|---|---|---|---|
| 1 | **피격 파이프라인 SSOT**: `defense`(기본 0) + `rawAttack=monster.level` + `taken=f(raw,def)*damageTakenMultiplier`, defense=0·무버프 시 taken=level. 위치 `Player.applyDamage` + 적 공격 두 경로(`enemy.dart` 근접/발사체). | 클라이언트 전투 수식 | `player.dart:345-360`, `enemy.dart:301,324`, `monster_codex.dart:385-398` | 버프·방어 적용 순서 문서화 필요 |
| 2 | **기본 maxHp/hp=10000**; 사망·안전지대 리스폰 분기는 유지. | `player.dart` | `player.dart:28-29,375-380`, `action_rpg_game.dart:907-919` | HUD 자릿수 |
| 3 | **`MonsterCodex` damage를 레벨 정합**으로 재정의; 시드/웨이브 `damageMultiplier`는 1.0 고정 또는 제거. | Codex·population·wave | `monster_codex.dart:388`, `monster_population.dart:198-199`, `wave_director.dart:84-86` | 기종별 타격감 차 소실 → 속도·사거리·버스트로 차별 |
| 4 | **피격 무적 재설계**(시간 단축 또는 소스 단위 쿨) + **원거리 버스트와 정합**. 규격 유지 시 필수. | `player.dart` i-frame, `enemy.dart` burst | `player.dart:361`, `enemy.dart:193-218`, TTK 계산 | 연타 피드백 과다; 버스트×짧은 무적 시 순간 폭딜 |
| 5 | **회복·레벨업 HP·hazard를 HP 축에 맞게 스케일**. heal을 maxHp% 또는 수천 단위; `LevelGains.maxHp` 확대; hazard를 의미 있는 %/틱. | `pickup.dart`, `level_system.dart`, hazard | `pickup.dart:101-110`, `level_system.dart:50`, `player.dart:331` | 과회복 시 다시 불사 — %캡 검토 |
| 6 | **HUD/캐릭터 시트**: 5자리 HP, DEF 표시; fortify UI 용어를 스탯 DEF와 분리. | `hud.dart`, `character_screen.dart`, `inventory_ui.dart` | `hud.dart:103-157`, `character_screen.dart:338-349`, `inventory_ui.dart:493-494` | 패널 폭 조정 |
| 7 | **문서 정합 + 단위 테스트**: `GAME-DESIGN`의 `EnemyStats.table`/구 웨이브 배율 제거; “def0 → taken==level” 테스트 추가. | docs/test | `GAME-DESIGN.md:698`, `monster_codex.dart` | 문서만 보면 잘못된 SSOT를 건드림 |
| 8 | (후순위) 순수 함수 `combatDamage(...)`로 묶어 훗날 SpacetimeDB reducer 이식 대비. **지금 서버 배포·테이블 변경 불필요**. | 설계 부채 | `spacetimedb/src/lib.rs:7-18`, `leaderboard.rs:145-186` | 과도 추상화 주의 |

**규격을 임의로 바꾸지 말 것.** “피해를 다시 키우자” 대신 **타수 빈도(무적)·동시 교전·고레벨 존(regionLevel 1~200)** 으로 TTK를 맞출 것.

---

## 6. 불확실 · 미확인

- 방어 공식의 구체형(`max(0 또는 1, atk-def)` vs 비율 감쇠 등) — 규격은 **def=0 → 피해=level**만 고정; 성장 방어 곡선은 **사람 결정**.
- fortify와 defense 동시 적용 시 **최소 피해 1 보장 여부**.
- hazard·포션의 목표 체감(최대 HP 대비 몇 %가 “한 모금”) — 밸런스 수치 미정.
- 플레이어 공격력·몬스터 HP를 손볼지 — 요청 밖; 비대칭 난이도를 의도할지 미정.
- 원거리 버스트를 규격 시대에 유지할지(1사이클 N타) — 기획 선택.
- 런타임 실측(DTD 스크린샷)은 읽기 전용 분석에서 수행하지 않음; 수치는 코드 상수 기반.
- 만렙(30) 플레이어가 외곽 Lv200에 들어갈 때 목표 TTK — 기획 값 없음(i-frame 재설계 후 재계산 필요).

---

## 7. 자기 비판으로 바로잡은 것

- ❌ 철회: `test/safe_zone_test.dart:87-96`이 `EnemyStats.table`을 참조한다는 주장 — 다시 읽으면 **`MonsterCodex.all` 어그로 범위 테스트**이며 `EnemyStats`는 없음. `EnemyStats` 잔재는 **`GAME-DESIGN.md:698`에만** 있다.
- 🔁 수정: 적 피해 전달 줄 번호 `enemy.dart:366,389` → 실제 **`301`(근접), `324`(발사체)**. `level` getter는 `119-120`이 아니라 **`54-55`**.
- 🔁 수정: “최소 TTK ~30분”을 **i-frame 상한 히트율의 이론적 하한**으로 명확화. 단일 몹 주기(예: drone ~0.94초)는 더 김. 다만 **다수 몹도 전면 무적 때문에 밀도로 못 메운다**는 결론은 유지.
- ➕ 추가: siege/sovereign **버스트 3~5발·0.16초 간격** (`enemy.dart:193-218`)과 i-frame 상호작용 — 무적 축소 시 사이클 총 피해 = level×N 폭증 위험.
- ➕ 추가: 포션은 즉시 heal이 아니라 **인벤 보관 후 `drinkPotion`** (`pickup.dart:304-307`); 스케일 대상은 `PotionEffect.heal`.
- ➕ 추가: 피격 SFX `taken/40` 스케일(`player.dart:383-386`)이 소피해 시대에 항상 하한 볼륨.
- 유지(검증 통과): HP 120, defense 부재, Codex `baseDamage` 곡선, population/wave 배율, LevelGains +18/+34, 사망 리스폰, 서버는 level/xp만, 규격 유지 시 i-frame 필수 동반 수정.
