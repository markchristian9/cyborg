<!-- cowork:kimi | 2026-08-05 19:36:42 | exit=0 | 739s -->
# kimi 분석 — server-authority

> 요청: 서버 판정, 서버 권위 이동, 클라이언트 보간, pc 별 이벤트/액션/스킬/타격/사망/HP/MP 공유 등이 올바로 동작하는지 확인하고 수정/보완 할 내용이 있으면 수정 보완해주세요. 특히 -> 여러 플레이어 화면에 다른 pc 들의 이동, 몬스터 이동, 스킬 사용, 공격, 피격, 사망, 공격 모션/애니메이션, 스킬 애니메이션, 총알/레이저/미사일 등이 날라가는 장면돈 여러 플레이어 화면에 동일한 애니메이션/이벤트공유/서버가 클라로 이벤트전송/클라화면에서 여러 pc 화면에도 동일하게 보이는 것이 잘 동작하는지 분석하고 수정/보완해주세요.
> 생성: 2026-08-05 19:36:42 · 소요 739s · 읽기 전용 분석(작업공간 미수정)

---

• 세 갈래(서버 모듈·클라이언트 네트워크 계층·게임 엔티티/렌더링)로 나눠 병렬 조사하겠다.

• 핵심 쟁점 몇 곳(원격 플레이어 스킬 연출, 서버 몬스터의 공격 모션/발사체 표시)을 직접 확인한다.

• 서버 몬스터 사망 연출과 PK 발동 경로 부재를 좀 더 확인한다.

• 서버 피격 시 내 화면 연출 경로를 확인한다.

• 

## 1. 결론 요약

  질문의 전제(“실시간 멀티플레이 동기화가 아직 없다”)와 달리, 이 코드베이스에는 **서버 권위 전투와 원격 플레이어/몬스터 동기화가 이미 상당 부분 구현돼 있다** — `.cowork/cowork-prompt.md` 의 서술이 낡은 것이 첫 번째 발견이다. 서버 판정(피해·HP/MP·사망·몬스터 AI)과 이동 보간은 실제로 동작하는 구조다. 그러나 사용자가 물은 “여러 플레이어 화면에 동일하게 보여야 하는 것들” 중 **몬스터의 공격 모션·발사체, 몬스터 사망 연출, 원격 플레이어의 투사체, 내 피격 피드백, PK 발동 경로** 가 비어 있다 — 판정은 서버에 가 있는데 **사건을 연출로 변환하는 다리** 가 없는 것이 공통 원인이다. 대부분 서버 스키마 변경 없이 클라이언트에서 메울 수 있다.

  

## 2. 근거

  - `spacetimedb/src/world.rs:178` — “여기가 전투 수치의 단일 진실 공급원이다”: 피해·HP/MP·사망 판정이 서버에 있음 (`player_damage` world.rs:793, `damage_after_defense` world.rs:819).
  - `spacetimedb/src/world.rs:393-425` — 공격은 `WorldPlayer.last_attack_at` + `attack_dir_x/y` + `attack_skill` **상태 변화로 사건을 전달** (“별도 이벤트 표와 달리 재구독해도 옛 공격이 되살아나지 않는다”).
  - `spacetimedb/src/world.rs:1766, 2248-2306` — `monster_ai`(150ms 틱)가 몬스터 이동과 몹→플레이어 피해를 서버에서 직접 판정.
  - `spacetimedb/src/world.rs:1570-1573` — “발사체를 서버가 시뮬레이션하려면 고주파 틱이 필요하고… 즉시 판정형”: **투사체는 서버에 존재하지 않는다**.
  - `lib/game/entities/remote_player.dart:158-169, 179-197, 219-225` — 원격 플레이어: 서버 갱신 간격 EMA 실측 + 시간 기반 구간 보간, `lastAttackAtMicros` 변화 감지로 공격 모션 1회 재생, 12타일 이상 시 순간이동(207-211).
  - `lib/game/entities/enemy.dart:247-251` — 서버 몬스터는 로컬 AI 를 돌리지 않고 `_followServer` 로 위치만 보간. 따라서 `_resolveMeleeStrike`(491)·`_fire`(502)·telegraph 연출은 **온라인에서 한 번도 실행되지 않는다**.
  - `lib/game/entities/enemy.dart:583-600, 606-636` — `_die()`(폭발 연출)는 로컬 `applyDamage` 경로(574)에서만 호출되고, `render` 에 죽은 상태 분기가 없다 → 서버 몹은 죽어도 멀쩡히 서 있다가 리스폰 때 순간이동.
  - `lib/game/action_rpg_game.dart:615-638, 644-674` — 내 HP/MP/좌표는 `adoptServerVitals`/`reconcileServerGrid` 로 수용하고, 사망은 `deaths` 누계 상승 감지로 폭발 연출 + 서버 지정 위치 텔레포트.
  - `lib/game/entities/player.dart:791-801` — `adoptServerVitals` 는 숫자만 대입. 데미지 텍스트·히트플래시·피격음은 로컬 `applyDamage`(641-685)에만 있어 **온라인 피격 시 아무 피드백이 없다**. `PlayerState.hurt` 는 선언만 있고 전이 없음(player.dart:24).
  - `lib/game/entities/projectile.dart:13, 96-102` — 투사체는 진영 구분(`player`/`enemy`)만 있고 **어느 플레이어의 탄인지 개념이 없으며**, 서버 판정 대상에는 피해를 넣지 않는다(온라인에서 순수 연출).
  - `lib/spacetime/spacetime_world_presence.dart:350` — `attackPlayer`(PK) 구현은 있으나 **게임 쪽 호출처가 0건**; `RemotePlayerEntity` 는 `Damageable` 이 아니다(remote_player.dart:22, `iso_entity.dart:73-86`).
  - `lib/game/action_rpg_game.dart:1255-1318` — 몬스터 스트리밍: 가까운 순 최대 50마리, 죽은 몹은 새로 만들지 않고(1285) 기존 개체는 `alive:false` 를 받아도 화면에 남는다(1270 `seen` 에 포함).
  - `lib/spacetime/generated/client.dart:141` — `monster_kill` 테이블이 생성 코드에 있으나 **구독하는 곳이 없다**(킬 피드 미구현).
  - `lib/game/systems/monster_population.dart` — 호출처 없는 레거시. `wave_director.dart` 파일 자체가 없다. cowork-prompt 의 “전투 수치 관련 파일” 표가 현재 코드와 어긋남.
  - `spacetimedb/src/leaderboard.rs:277-284` — `report_progress` 는 클라이언트 자기 신고를 단조 증가만으로 받는, 코드가 스스로 인정하는 신뢰 구멍(서버 `award_kill` 도 같은 열을 올림).

  

## 3. 상세 분석

  **동기화 아키텍처(현재)**. 서버(SpacetimeDB 모듈)가 전투 판정·몬스터 AI·HP/MP·사망·리스폰을 소유하고, 클라이언트는 ① 내 입력을 reducer 로 보내고(`moveTo` 200ms, `attackMonster`, `castSkill`), ② 공개 표 `world_player`/`monster`/`loot` 을 청크 3×3 AOI 구독으로 받아, ③ 상태 변화를 보간·연출로 변환한다. 사건 전달은 ephemeral 이벤트 표가 아니라 **상태 열의 값 변화**(last_attack_at, deaths) 방식으로 통일돼 있어 재구독 안전하다 — 설계 일관성은 좋다.

  **잘 동작하는 것**(판정·공유 경로 존재): 다른 PC 의 이동(EMA 기반 시간 보간), 방향, HP 바, 생사(`_renderDowned`), 근접/스킬 공격 모션(스윙 아크, 플라즈마는 색 구분), 몬스터 이동 보간, 몬스터 피격 플래시(누가 때렸든 hpRatio 하강으로 표시, enemy.dart:155-160), 내 사망 연출, 전리품 공유, 리더보드.

  **무너져 있는 곳은 전부 “서버가 판정만 하고 사건을 상태로 남기지 않는” 지점** 이다:

  1. **몬스터의 공격이 어느 화면에도 보이지 않는다.** 서버 `monster_ai` 가 피해를 직접 HP 에서 깎을 뿐, “이 몹이 이 플레이어를 때렸다” 는 상태가 `monster` 표에 없다. 클라이언트의 서버 몹은 AI 를 껐기 때문에(enemy.dart:247) telegraph·strike·`_fire` 연출이 전부 죽어 있다. 결과: 모든 플레이어 화면에서 몹은 조용히 다가와 서 있고, 맞는 쪽은 **HP 숫자만 소리 없이 줄어든다**(`adoptServerVitals` 가 값만 대입, player.dart:797-800).
  2. **몬스터 사망이 사건으로 처리되지 않는다.** `alive: true→false` 전이를 감지하는 코드가 없어 폭발·경험치 텍스트·시체 표현이 없고, `render` 에 dead 분기가 없어 죽은 몹이 서 있는 애니메이션 그대로 최대 20초(서버 리스폰 주기, world.rs:2169) 방치된다.
  3. **투사체 비행 장면은 발사한 본인 화면에만 있다.** 서버에 투사체가 없고(world.rs:1570-1573), `Projectile` 에 소유자 개념이 없어(projectile.dart:13) 원격 플레이어의 플라즈마는 색 다른 아크 하나로 대체된다(remote_player.dart:280-282). “총알/레이저가 날아가는 장면이 여러 화면에 동일하게” 라는 요구는 미충족.
  4. **PK 는 서버만 준비됐다.** `attack_player` reducer(world.rs:1711)와 클라 송신부(spacetime_world_presence.dart:350)는 있는데, 원격 플레이어를 타깃으로 고르는 입력 경로가 없다(`RemotePlayerEntity` 가 `Damageable` 미구현, 근접 타깃 목록에 미포함).

  **범위와 경계**: 1번은 서버(`monster` 표에 공격 사건 열 추가)와 클라 양쪽을 함께 바꿔야 한다. 2·3번은 **클라이언트만** 으로 메울 수 있다(이미 오는 상태 변화에서 전이를 감지하면 된다). 4번도 클라이언트만으로 가능하다.

  

## 4. 리스크 · 함정

  - **문서-코드 불일치가 크다**: cowork-prompt 는 “멀티플레이 동기화 없음”, “몬스터 레벨 개념 없음”, “HP 120” 을 전제하지만 실제로는 서버 권위 동기화, 몬스터 레벨 1~200(world.rs:911), `baseMaxHp = 10000`(player.dart:46-49)이 이미 있다. 이 문서를 전제로 한 이후 분석·작업은 엉뚱한 곳을 고칠 위험이 있다 — 문서 갱신이 선행돼야 한다.
  - **몬스터 공격 사건을 `monster` 표에 열로 추가하면** 생성 코드 재생성(`dart run spacetimedb_sdk:generate`)과 `spacetime publish` 재배포가 필요하고, 표 스키마 변경은 기존 행·구독 SQL 에 영향을 준다. 12,000기(world.rs:108) 갱신 주기와 곱해지는 대역폭 증가도 계산해야 한다.
  - **피격 피드백을 `adoptServerVitals` 의 delta 감지로 만들 때**: 회복(regen_tick, world.rs:2122)도 delta 로 오므로 감소만 피격으로 취급해야 하고, 리스폰 직후 HP 리셋·텔레포트 직후 갱신처럼 큰 점프를 피격으로 오인하지 않게 걸러야 한다.
  - **죽은 몹을 즉시 제거하는 방식으로 2번을 메우면** 리스폰(같은 id 가 홈에서 `alive:true` 로 부활)과 충돌하지 않는지 확인해야 한다 — 현재는 같은 엔티티가 살아난 채 재사용되는 구조(action_rpg_game.dart:1272-1281).
  - **루트 효과 미검증**: 서버 `pick_loot` 은 행 삭제만 하고 회복량을 서버 HP 에 적용하지 않는다는 서버 측 주석(world.rs:2033 부근, agent 보고)이 있다. 사실이라면 온라인에서 체력 보급품이 **서버 HP 를 올리지 못해** regen 외 회복 수단이 서버 권위 밖에 놓인다.
  - **재연결 복구 부재**: 앱 수준 끊김 감지가 없고 SDK autoReconnect(spacetimedb_sdk 2.4.0)에 위임한다. 재연결 후 월드 청크 구독·`enter_world` 가 자동 복구되는지 실측 근거가 없다 — 복구가 안 되면 끊김 뒤 “혼자만 보이는 월드” 가 된다.
  - `report_progress` 의 자기 신고 경로(leaderboard.rs:277-284)는 서버 전투 경험치(`award_kill`)와 같은 열을 올리는 이중 출처다. 서버 전투가 주 경로가 된 지금, 클라 신고분이 서버분을 덮지 않는지(단조 증가만 채택이므로 방어되지만 상한 클램프 외 검증 없음) MMORPG 어뷰징 관점에서 재검토 대상이다.
  - 레거시(`MonsterPopulation`, `wave_director` 잔재, `GameSync.reportKill/reportDeath` no-op)를 남겨 두면 다음 작업자가 “로컬 난이도 곡선이 살아 있다” 고 오해한다 — cowork-prompt 의 표가 이미 그 오해를 만들었다.

  

## 5. 권고안

  | 순위 | 권고 | 범위 | 근거 | 리스크 |
  |---|---|---|---|---|
  | 1 | 몬스터 공격을 사건으로 전달: `Monster` 에 `last_attack_at`·`attack_target`(또는 방향) 열을 추가하고 `monster_ai` 가 피해 판정 시 갱신. 클라는 `applyServerState` 에서 값 변화를 감지해 telegraph/strike 연출과(근거리) 발사체 연출(원거리)을 재생 | 서버 `world.rs` + `enemy.dart` + 생성 코드 재생성 | world.rs:2248-2306, enemy.dart:247-251, 기존 패턴 world.rs:393-425 | 스키마 변경·재배포 필요; 12,000기 × 150ms 틱의 갱신 트래픽 증가 — 공격 시에만 열을 바꾸면 증가분은 미미 [추측] |
  | 2 | 내 피격 피드백: `_adoptServerState` 또는 `adoptServerVitals` 에서 HP 감소분을 감지해 `DamageText`·히트플래시·`hurt` 상태·피격음·히트스톱을 로컬 `applyDamage` 와 같은 수위로 재생 | 클라이언트만 (`action_rpg_game.dart:615`, `player.dart:791`) | player.dart:641-685(로컬 경로에만 있는 연출), player.dart:24(미사용 hurt) | 회복·리스폰 점프를 피격으로 오인하지 않는 필터 필요 |
  | 3 | 몬스터 사망 연출: `applyServerState` 에서 `alive true→false` 전이를 감지해 `Explosion`·(내가 선점한 몹이면) XP 텍스트 재생 후 시체 표현 또는 제거. 리스폰 재사용 경로와 정합성 확보 | 클라이언트만 (`enemy.dart:141-164`, `action_rpg_game.dart:1272-1285`) | enemy.dart:583-600(로컬 전용 `_die`), 606-636(dead 분기 없음) | 같은 id 부활 시 엔티티 재사용 여부 결정 필요 |
  | 4 | 원격 플레이어 투사체 연출: `attack_skill == plasma` 감지 시 `RemotePlayerEntity` 가 연출 전용 `Projectile` 을 스폰(피해 판정 없음, `isServerJudged` 대상엔 이미 피해 안 들어감) | 클라이언트만 (`remote_player.dart:158-169`, `projectile.dart:96-102`) | remote_player.dart:280-282(현재는 아크뿐), projectile.dart:13(소유자 개념 없음) | 스킬 종류가 늘면 연출 매핑 표가 필요; 서버 스키마 변경 없음 |
  | 5 | PK 발동 경로: `RemotePlayerEntity` 에 타깃팅(탭/근접 부채꼴 포함)을 추가하고 `presence.attackPlayer` 호출. 안전지대 면역·쿨다운은 이미 서버 판정(world.rs:1711)에 맡긴다 | 클라이언트만 (`remote_player.dart:22`, `player.dart:550` 타깃 선정부) | spacetime_world_presence.dart:350(호출처 0건), iso_entity.dart:73-86 | `Damageable` 구현 시 `isServerJudged = true` 필수 — 아니면 로컬에서 HP 를 깎는 이중 판정 |
  | 6 | 재연결 복구: 연결 상태를 감시해 복구 시 `enterWorld` 재호출 + 청크 재구독 + `_lastServerDeaths` 등 누계 기준점 리셋 | `cyborg_session.dart` + `spacetime_world_presence.dart` | cyborg_gate.dart:180(초기 실패만 처리) | SDK autoReconnect 의 구독 복구 범위를 먼저 실측해야 중복 구독을 피함 |
  | 7 | 킬 피드: `monster_kill` 구독으로 “누가 무엇을 잡았다” 표시(선택) | `cyborg_connection.dart` 구독 목록 + HUD | generated/client.dart:141, world.rs:608-609 | AOI 밖 킬까지 오는 표이므로 구독 범위 결정 필요 |
  | 8 | 레거시 정리 및 문서 갱신: `MonsterPopulation`·`wave_director` 잔재·`GameSync` no-op 경로를 삭제하거나 명시적으로 폐기 표시하고, cowork-prompt 의 전투 파일 표를 현재 구조로 고친다 | 문서 + `lib/game/systems/` | monster_population.dart(호출처 0건), game_sync.dart:15-46 | 없음(읽기 전용 보고서 범위 밖의 삭제는 오케스트레이터 판단) |

  

## 6. 불확실 · 미확인

  - **SDK autoReconnect 후 구독 자동 복구 여부**: spacetimedb_sdk 2.4.0 의 재연결 시 기존 subscription 이 재적용되는지 소스를 끝까지 확인하지 못했다. 6번 권고의 범위(앱이 다시 걸어야 하는가, SDK 가 해주는가)가 여기에 달렸다.
  - **루트 회복량의 서버 반영**: `pick_loot` 가 회복을 서버 HP 에 적용하지 않는다는 것은 서버 측 보고이고, 클라이언트 `pickup.dart:380` 의 await 이후 로컬 회복 적용 여부와의 정합성은 미확인. 사실이면 “온라인에서 포션/보급품이 서버 HP 를 못 올리는” 구조적 결함이다.
  - **서버 `monster_ai` 의 원거리 몹 처리**: `apply_damage_to_player` 가 사거리 개념으로 즉시 판정하는지, 종류별 구분이 있는지는 세부를 읽지 못했다 — 1번 권고에서 원거리 발사체 연출에 필요한 사건 정보(방향/종류)의 범위가 이에 달렸다.
  - **몬스터 공격 열 추가의 트래픽 영향**: 150ms 틱에서 실제로 상태가 바뀌는 몹 수(어그로 중인 몹만 갱신되는지)를 실측하지 못해 대역폭 증가분은 [추측] 이다.
  - **오프라인 모드의 몬스터 부재**: `OfflineWorldPresence.monsters` 가 빈 목록이라 오프라인 실행이 빈 월드라는 보고가 있으나, 오프라인 모드가 현재 지원 대상인지(GAME-DESIGN.md 기준)는 확인하지 못했다.
