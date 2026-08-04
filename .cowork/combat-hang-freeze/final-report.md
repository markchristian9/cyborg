# final-report — combat-hang-freeze

> 요청: 전투 중 PC가 공격을 받거나, 몬스터가 공격을 받거나, 누군가 사망하면 게임이 멈춰버리는(hang) 현상. 원인 규명 + 수정.
> 종합: 오케스트레이터가 4 AI 분석의 근거를 직접 열어 교차검증했다.
> ⚠️ 이 분석은 **오케스트레이터가 1차 수정을 적용한 뒤** 돌았다. 따라서 claude·kimi·grok 은 "이미 고쳐진 코드"를 읽었고,
> 원본 확인은 grok 의 `git show 15fa510` 이 담당했다.

## 1. 최종 결론

**hang 은 하나가 아니라 두 개다.**

1. **진짜 정지(freeze)** — 몬스터가 죽는 순간 `ConcurrentModificationError` 가 Flame 의 `update()` 안에서 터져 게임 루프가 멈춘다.
   → **1차 수정으로 해결됨.** 커밋 원본이 실제로 `sync*` 였음이 `git show 15fa510` 으로 확정되었다.
2. **체감 정지(무한 슬로우모션)** — 히트스톱이 **덮어쓰기**라, 여러 적에게 둘러싸여 연속 피격당하면
   `_hitStop` 이 계속 리셋되어 `dt *= 0.25` 가 끊기지 않는다. 게임이 1/4 속도로 기어가 "멈춘 것"으로 보인다.
   → **미해결이었음. 이 보고서의 권고로 수정한다.**

사용자 증상 세 가지가 여기에 정확히 갈린다 — grok 의 지적이 결정적이었다:
"**PC 가 (죽지 않고) 공격받을 때**"는 CME 경로가 **아니다**. 그건 2번(히트스톱)이다.
"몬스터가 공격받아 죽을 때 / 사망할 때"가 1번이다.

## 2. 검증한 근거 (직접 열어 확인)

| 주장 | 검증 방법 | 판정 |
|---|---|---|
| 커밋 원본이 `sync*` 지연 순회였다 | `git show 15fa510:lib/game/action_rpg_game.dart` → 620-629줄에 `sync*` + `yield* enemies.where(...)` 확인 | ✅ **사실** |
| `onEnemyKilled` 가 순회 중 `enemies.remove` 한다 | [action_rpg_game.dart:1078](../../lib/game/action_rpg_game.dart#L1078) 확인 | ✅ 사실 |
| `_resolveMeleeHit` 이 순회 중 `applyDamage` + break 없음 | [player.dart:466](../../lib/game/entities/player.dart#L466) 확인 | ✅ 사실 |
| 현재 코드는 스냅샷 `List` 를 반환한다 | [action_rpg_game.dart:795-806](../../lib/game/action_rpg_game.dart#L795-L806) 확인 | ✅ 수정 반영됨 |
| 원거리 탄은 CME 재현 빈도가 낮다 | [projectile.dart:87-97](../../lib/game/entities/projectile.dart#L87-L97) — 명중 즉시 `_burst(); return;` 이라 다음 `moveNext()` 를 호출하지 않음 | ✅ 사실 (grok 이 1차 주장을 스스로 철회) |
| 히트스톱이 연속 피격 시 무한 갱신된다 | [action_rpg_game.dart:436-439, 1084, 1134](../../lib/game/action_rpg_game.dart#L436-L439) — `=` 덮어쓰기, 쿨다운 없음 | ✅ **사실. 미해결 원인** |
| `spacetime_game_sync.dart` 의 `while(true)` 가 hang 원인 | 92-116줄 — `await` 로 이벤트 루프에 양보하고 `_pending == null` 이면 return | ❌ **무죄** |
| 레벨업 `while` 이 무한 루프 | `_levelUp()` 이 매번 `level++`, `reached ≤ maxLevel` | ❌ 무죄 |
| 레벨 계산 이진 탐색이 오버플로우로 폭주 | Dart 로 직접 실행해 실측(0·10·60·200·1000·100000 전부 정상 종료) | ❌ 무죄 |
| 오디오가 게임 루프를 막는다 | [game_audio.dart:416-445](../../lib/game/audio/game_audio.dart#L416-L445) — `unawaited` + 예외 삼킴 | ❌ 무죄 |

## 3. AI 별 기여와 판정

- **claude** (816s) — 유일하게 **히트스톱 무한 갱신**과 `_moveToward` 의 O(N²) 분리 스티어링(140마리 → 19,600회/프레임)을
  짚었다. 이 보고서 §1-2 는 claude 의 고유 통찰이다.
- **grok** (602s, 2-pass) — 유일하게 **`git show` 로 커밋 원본을 확인**해 "sync\* 였다"를 사실로 못 박았다.
  자기비판(§7)에서 "원거리도 근접과 같은 빈도" 주장을 스스로 철회했고, **"비사망 피격은 CME 경로가 아니다"**
  라는 증상 분리를 해냈다 — 이것이 두 번째 원인을 찾게 한 열쇠다.
- **kimi** (606s) — 안전성이 "**어디에도 적히지 않은 규칙**"(피해 콜백이 있는 코드는 `game.enemies` 를 직접
  for-in 하지 않는다) 위에 서 있다고 지적. 광역 공격을 `for (final e in game.enemies) e.applyDamage(...)` 로
  구현하는 순간 재발한다는 경고가 정확하다.
- **codex** (실패에 준함) — cowork 스크립트의 cwd 버그로 작업공간이 `/Users/thruthesky/.claude/plugins/cache` 로
  잡혀 **게임 소스를 하나도 못 읽었다.** "파일이 없어 미검증"이 분석의 대부분이다. 종합에서 제외한다.
  다만 "테스트가 '예외가 없었다'만 확인하면 freeze 를 놓친다 — 후속 프레임의 진행성을 함께 검사하라"는
  방법론 지적 하나는 채택했다.

## 4. 반증된 주장 (이것을 근거로 고치지 말 것)

- ❌ "플레이어 사망 경로 `onPlayerDied()` → `_refreshMonsterStreaming()` 에 같은 CME 위험이 남아 있다"
  → **반증.** `_refreshMonsterStreaming` 은 `toRelease` 지연 수집 패턴을 쓰고([action_rpg_game.dart:626-643](../../lib/game/action_rpg_game.dart#L626)),
  `onPlayerDied` 의 호출 스택 어디에도 `game.enemies` 의 활성 iterator 가 없다. Flame 1.38.0 은 `update` 중
  add/remove 를 라이프사이클 큐로 미루므로 컴포넌트 트리도 안전하다. grok 이 1차 주장을 2차에서 스스로 낮췄고,
  claude·kimi 도 같은 결론이다. **잔존 위험은 예외가 아니라 "미래에 누가 잘못 짜면 재발" 뿐이다.**
- ❌ codex 의 "실제 프로젝트를 못 찾았으니 다시 분석하라"(권고 1순위) → 작업공간 설정 버그일 뿐, 코드는 정상.

## 5. 남은 위험 (이번에 고치지 않음 — 보고만)

- **`Enemy._moveToward` 의 O(N²)** ([enemy.dart:252](../../lib/game/entities/enemy.dart#L252)) — 활성 상한 140마리에서
  최악 19,600회 순회 + Vector2 약 4만 개 할당/프레임. 몬스터가 피격되면 일제히 `chase` 로 전환되므로
  ([enemy.dart:366](../../lib/game/entities/enemy.dart#L366)) 대규모 교전에서 프레임 스파이크를 만든다.
  공간 해시로 근처만 보게 하는 것이 정답이지만 범위가 크다 — 별도 작업으로 분리한다.
- **`_send` 의 재진입 가드** ([spacetime_game_sync.dart](../../lib/game/net/spacetime_game_sync.dart)) — `_inFlight` 가
  `finally` 에서 즉시 false 가 되어 두 번째 바퀴부터 가드가 풀린다. hang 은 아니고 중복 트랜잭션 여지다(정확성).

## 6. 최종 권고 (작업 지시서)

| 순위 | 권고 | 범위 |
|---|---|---|
| 1 | **완료** — `meleeTargets()`/`projectileTargetsForPlayer()` 를 스냅샷 `List` 반환으로 변경 | CME freeze 차단 |
| 2 | **히트스톱에 쿨다운을 둔다** — 연속 피격/연속 처치에도 슬로우가 끊기지 않는 것을 막는다 | 체감 정지 해소 |
| 3 | **회귀 테스트를 추가한다** — 순회 도중 대상을 죽여도 예외 없이 끝나고, **다음 프레임이 진행되는지**까지 검증(codex 지적 채택) | 재발 방지 |
| 4 | 불변식을 주석으로 못 박는다 — "피해를 줄 수 있는 코드는 `game.enemies` 를 직접 for-in 하지 않는다"(kimi 지적) | 미래 재발 방지 |

## 9. 적용 결과

| 권고 | 결과 | 파일 |
|---|---|---|
| 1. 대상 목록 스냅샷화 | ✅ 적용(1차) | [action_rpg_game.dart](../../lib/game/action_rpg_game.dart), [player.dart](../../lib/game/entities/player.dart) |
| 2. 히트스톱 재발동 잠금 | ✅ 적용 — [HitStop](../../lib/game/systems/hit_stop.dart) 클래스로 분리해 테스트 가능하게 만듦 | `lib/game/systems/hit_stop.dart` (신규) |
| 3. 회귀 테스트 | ✅ 적용 — 9개 | [test/combat_hang_regression_test.dart](../../test/combat_hang_regression_test.dart) (신규) |
| 4. 불변식 명문화 | ✅ 적용 — `enemies` 필드 선언에 "피해를 줄 수 있는 코드는 직접 for-in 금지" 주석 | `action_rpg_game.dart:123` |
| 5. `_moveToward` O(N²) | ⏸️ 보류 — 공간 해시 도입이 필요해 범위가 큼 | — |
| 6. `_send` 재진입 가드 | ⏸️ 보류 — hang 아님(정확성 문제) | — |

### 진단의 결정적 증명

회귀 테스트가 실제로 버그를 잡는지 확인하려고 `_damageableTargets()` 를 **일부러 옛 `sync*` 구현으로
되돌려** 테스트를 돌렸다. 결과:

```
Which: threw ConcurrentModificationError:<Concurrent modification during iteration:
       Instance(length:2) of '_GrowableList'.>
```

3개 테스트가 실패했고, 수정 코드로 복구하니 전부 통과했다. **가설이 아니라 실측으로 확정된 원인이다.**

### 검증

- `flutter analyze lib/ test/` — 신규 문제 없음(남은 24건은 이번 작업과 무관한 기존 lint).
- `flutter test` — **200개 전부 통과**(회귀 테스트 9개 포함).
- ⚠️ **한계**: 프로젝트 지침(`CLAUDE.md`)이 요구하는 DTD 실기기 검증은 하지 않았다. 단위 테스트는
  CME 재현·차단과 히트스톱 잠금 로직까지만 증명한다. 실제 난전에서의 체감은 사람이 확인해야 한다.
- ⚠️ **커밋하지 않았다.** 이 저장소는 지금 다른 세션이 동시에 작업 중이고(분석 도중
  `level_system.dart` 에 `maxLevel` 이 추가되는 등 워킹트리가 바뀌었다), 이미 대량의 미커밋 변경이
  섞여 있다. 내 변경만 골라 커밋할지 사람이 판단하는 편이 안전하다.

## 7. 종합 판정

1차 수정(스냅샷)은 **원인 진단·해법 모두 정확했다.** 다만 그것만으로는 사용자가 말한 세 증상 중
"**PC 가 공격받을 때 멈춤**"이 남는다 — 그건 CME 가 아니라 히트스톱이다. 이 보고서는 그 두 번째 원인을
찾아낸 것이 실질 성과다.
