<!-- cowork:grok | 2026-08-04 22:51:46 | exit=0 | 468s -->
# grok 분석 — server-authority

> 요청: 서버 권위 판정을 하도록 해 주세요. 서버 권위 이동, 서버 권이 이벤트, 사망, HP/MP 감소/회복, 스킬, 등등 서버가 판정을 하고 클라에서는 렌더링만 하도록 해 주세요.

참고: 형제 게임 라리엔(~/apps/game/laryen, 읽기 전용 참고만 가능)의 서버 권위 이동 관련 코드/로직을 참고해 주세요. 라리엔은 Go UDP Zone Server 로 30Hz sim tick + 10~15Hz 스냅샷 브로드캐스트 + 클라 예측/서버 reconcile 구조입니다. 다만 Cyborg 는 SpacetimeDB(reducer + 구독 + scheduled reducer) 백엔드이므로 그 차이를 감안한 설계를 제시해 주세요.
> 생성: 2026-08-04 22:51:46 · 소요 468s · 읽기 전용 분석(작업공간 미수정)

---

1차 보고서 인용 근거를 실제 파일로 재검증하고, 놓친 경로를 추가로 조사합니다.근거 재검증을 마쳤습니다. 1차에서 틀린 줄·우선순위·문서 표류를 바로잡아 최종 보고서를 작성합니다.

## 1. 결론 요약

**Cyborg의 “서버 권위 판정”은 라리엔식 30Hz Zone sim + SNAP을 새로 짓는 일이 아니라, 이미 있는 SpacetimeDB `world.rs` reducer·public 표를 진실 공급원으로 키우고, Flame 쪽 로컬 판정(`applyDamage`·`MonsterPopulation`·`report_progress`)을 의도 전송·렌더·예측으로 깎는 일이다.**  
서버에는 `move_to`(속도 클램프)·`attack_monster`(사거리·CD·선점·킬·XP)·`teleport_to`·`WorldPlayer`/`Monster` 표가 있으나, 클라는 `enter_world`/`move_to`·원격 보간만 연결돼 있고 **몬스터 전투·HP/MP·사망·회복·스킬·텔레포트·성장 신고는 전부 클라 권위**다.  
전면 이전은 한 번에 하지 말고 **① 수치 SSOT(클라 HP 1만·피해=몹 레벨 규격으로 서버 상수 정렬) → ② `monster_tick` 타이머 시드 → ③ 몬스터 구독+`attack_monster` 연동 → ④ `report_progress` 제거(성장 단일화) → ⑤ PC 피격·사망·회복 → ⑥ 텔레포트·PK·스킬** 순이 맞다.  
`monster_tick` 시드 없이 킬을 서버로 옮기면 몹이 한 번 죽고 영구 고갈되고, 수치 불일치(서버 max HP≈100 vs 클라 10,000)를 둔 채 연동하면 “맞았는데 안 죽음/죽었는데 서버는 살아 있음”이 즉시 터진다.

## 2. 근거

- `spacetimedb/src/lib.rs:7-18, 191-193` — 클라 비신뢰·`ctx.timestamp`/`ctx.random()` 원칙. `init`은 `world::bootstrap`만 호출. 머리말 “모든 테이블 비공개”(`:15-16`)는 아래 public 표와 **문서·구현 불일치**.
- `spacetimedb/src/world.rs:170-211, 218-258, 264` — `world_player`·`monster`·`monster_kill` 이 **public**. 공유 월드 상태는 구독으로 전파하는 모델.
- `spacetimedb/src/world.rs:132-145, 362-372, 629-641` — `MAX_MOVE_SPEED=14`, `BASE_MAX_HP=100`, `max_hp_for_level = 100+18×(lv-1)`, `player_damage = 14+3×(lv-1)`. 입장 시 이 값으로 `WorldPlayer.hp/max_hp` 설정.
- `spacetimedb/src/world.rs:665-705, 743-780, 783-863` — `move_to` 속도 클램프(완전 시뮬 아님), `teleport_to` 목적지+착지 slack, `attack_monster` 의도만 수신·서버 판정·선점 킬.
- `spacetimedb/src/world.rs:130, 289-295, 409-458, 867-891` — `MONSTER_TICK_SECS`·`MonsterTickTimer`·`monster_tick` 리스폰 로직은 있으나 **타이머 행 `insert` 경로 없음**. `bootstrap`은 몬스터만 심음.
- `spacetimedb/src/world.rs:76-108, 418-420` — 몹 레벨 1~200 × 지역 3 × 군집 5~20 → capacity 12,000. `GAME-DESIGN.md:784`의 “240기”와 불일치(문서 표류).
- `spacetimedb/src/leaderboard.rs:37-38, 276-323` — 플레이어 `MAX_LEVEL=999`. `report_progress(total_xp)`는 **클라 신고 누적 XP**를 단조 증가만으로 수용; 주석이 서버 전투 유일 출처 시 제거 예정(`:285-287`).
- `spacetimedb/src/world.rs:912-969` — `award_kill`이 서버에서 `total_xp`·레벨을 올리고 `WorldPlayer.max_hp`도 갱신. 클라 로컬 성장과 **이중 경로**.
- `lib/spacetime/cyborg_connection.dart:39-41` — 월드 구독 = `world_player`만 (`monster` 미구독).
- `lib/spacetime/spacetime_world_presence.dart:74-120` — `enterWorld` + 200ms `moveTo`만. `attackMonster`/`teleportTo` 호출 없음.
- `lib/game/net/spacetime_game_sync.dart:7-15, 96` — 성장 동기화 = `reportProgress(totalXp)`뿐.
- `lib/game/` 전역 검색 — `attackMonster`/`teleportTo` reducer 호출 **0건**(생성 바인딩만 존재). 텔레포트는 `action_rpg_game.dart:1160-1164` 로컬 `player.teleportTo`.
- `lib/game/entities/player.dart:45-79, 538-598, 611-641` — 로컬 `baseMaxHp=10000`, `defense=0`, `damageAfterDefense`, `applyDamage`/`onPlayerDied`/`respawnAt` 전부 클라 판정. MP 5000·energy 100도 서버 필드 없음.
- `lib/game/systems/monster_codex.dart:410-416` · `enemy.dart:296-334` — 몹 피해 **항등식 `damage == level`**. 근접 `_resolveMeleeStrike`·원거리 `_fire`가 로컬 `player.applyDamage`.
- `lib/game/systems/monster_population.dart:47-55, 132+` · `action_rpg_game.dart:227, 761-872` — 클라 시드 장부 + 46m/60m 스트리밍. 서버 `monster` 표와 별개.
- `lib/game/entities/player.dart:501-518` — 방화벽(hazard) 지속 피해 `maxHp×4%/0.5s`, **무적·방어 무시**. 서버에 지형 권위 없음.
- `lib/game/net/world_presence.dart:9-32` · `remote_player.dart:21-68` — 원격 스냅샷에 **hp/maxHp 없음**(name·level·grid·alive만). 서버 `WorldPlayer.hp`가 깎여도 표시 경로가 없음.
- `lib/game/systems/level_system.dart:43-44, 145-152` — 클라 만렙 999, 레벨업 `maxHp +1000` → 레벨 N 최대 HP ≈ `10000+(N-1)×1000`. 서버 `100+18×(N-1)`과 축 자체가 다름.
- `GAME-DESIGN.md:697-803` — 서버 골격·선점 킬 의도·클라 연결이 남은 과제라고 명시. 다만 **13장 “presence 미구현·몬스터 240”은 현재 코드와 어긋남**(`spacetime_world_presence`·`RemotePlayerEntity`·`test/world_presence_test.dart` 존재).
- 라리엔 `constants.go:5-10` · `udp.go:17-20` · `pc_attack.go:17-28` — 30Hz sim, 15Hz SNAP, ATTACK은 의도 플래그→tick 내 resolve. Cyborg는 **리듀서 즉시 resolve + 표 구독 diff**가 대응물.

## 3. 상세 분석

### 3.1 “서버 권위”가 이 코드베이스에서 뜻하는 축

| 축 | 지금 권위 | 목표 권위 | 현재 경로 |
|---|---|---|---|
| 계정·세션·캐릭터 | 서버 | 서버 | reducer + view |
| 위치(자기) | 클라 이동 + 서버 속도 클램프 | 서버 확정 좌표(절충 유지 가능) | `move_to` |
| 위치(타인) | 서버 표 구독 | 동일 | `world_player` + `RemotePlayerEntity` 보간 |
| 몬스터 존재·HP·킬 | **클라 로컬** (서버 표·`attack_monster` 미연동) | 서버 `monster` | 생성 코드만 존재 |
| PC HP/MP·사망 | 클라 | 서버 `WorldPlayer`(+ 확장) | `applyDamage`·`onPlayerDied` |
| 성장 XP/level | **이중**: 로컬→`report_progress` + 서버 `award_kill` | 서버 킬만 | `SpacetimeGameSync` |
| 회복·포션·버프 | 클라 | 서버 타임스탬프 검증 | `RestRecovery`·`buff.dart`·inventory |
| 텔레포트 | 클라 즉시 | 서버 `teleport_to` 성공 후 스냅 | 로컬만 |
| PK·스킬 | 없음/로컬 | 서버 reducer | — |

### 3.2 이중 세계(실제 구조)

```
[Flame 로컬 루프]                         [SpacetimeDB]
Player.move / applyDamage / respawn       WorldPlayer (hp 있으나 피격 경로 없음)
MonsterPopulation → Enemy                 Monster (킬 판정 준비, 구독 안 함)
로컬 totalXp → report_progress            award_kill (attack_monster 시에만)
presence.move_to (좌표만)                 move_to 속도 클램프
teleportPlayerTo 로컬                     teleport_to (미호출)
```

- **공유되는 것:** 다른 플레이어 좌표·이름·level·alive 표시. 단 `alive`/`hp`는 서버가 바꾸지 않으면 입장값 고정.
- **공유되지 않는 것:** 몬스터 생사, 내 HP/MP, 킬 결과, 실제 전투. A가 잡은 몹이 B 화면에 살아있는 상태는 `GAME-DESIGN.md:704-708` 경고 그대로.

### 3.3 라리엔 vs Cyborg — 이식 가능한 것과 불가능한 것

| 라리엔 (Go UDP Zone) | Cyborg (SpacetimeDB) | 판단 |
|---|---|---|
| 30Hz `sim.Tick` 전 월드 적분 | scheduled reducer 저주파 또는 **이벤트 리듀서만** | 전 몹 30Hz 위치 갱신은 비용·구독 폭주로 1단계 비권고 |
| INPUT dx/dy → 서버 적분 | `move_to` 좌표 보고+속도 가드 | 의도적 절충(`world.rs:132-138`). 중기에 intent+저주파 적분 |
| ATTACK 의도 플래그 → tick resolve | `attack_monster(id)` **즉시** resolve | 이미 “의도만 전송” 설계. 라리엔과 동형 |
| SNAP 15Hz 브로드캐스트 | public 표 구독 diff | AOI 없으면 전 몬스터 행이 전 클라에 감 |
| EVENT hit/death | HP 필드 변경(+ 선택 단기 이벤트 표) | 데미지 숫자는 클라 연출 + 서버 HP 확정 |
| Nakama 메타 + Zone 실시간 | SpacetimeDB 단일 wasm 모듈 | 이중 백엔드 신설 비권고 |

**핵심:** 사용자가 원한 “이동·이벤트·사망·HP/MP·스킬을 서버가 판정, 클라는 렌더”는 **방향이 맞고**, 구현 형태만 라리엔 틱 시뮬이 아니라 **검증된 의도 → 표 갱신 → 구독 → 클라 예측 연출**이어야 한다.

### 3.4 서버에 이미 있는 것 / 없는 것

**재사용 우선순위 높음**  
입장·퇴장·disconnect 정리, 좌표 검증 이동, 텔레포트 목적지·쿨다운, 몬스터 배치·HP·레벨, 근접 공격 한 방 판정, 선점 태그, 킬 시 XP·레벨, public 구독 모델, 생성 Dart 바인딩(`attackMonster` 등).

**없거나 깨진 것**  
1. 몬스터→PC 피해, hazard, 사망·리스폰 서버 판정  
2. MP/energy, defense, 버프, 포션, 스킬 CD/코스트  
3. `attack_player`(PK)  
4. 클라 `monster` 구독·`attack_monster`·`teleport_to` 호출  
5. 수치 SSOT: 서버 max HP ~100대 vs 클라 1만대; 서버 PC 공격 레벨 선형 vs 클라 melee 26 등  
6. **`monster_tick` 스케줄 행 미생성** → 리스폰 자동화 미작동  
7. AOI 없음: 전역 `monster` 구독 시 수천~1.2만 행 위험  
8. `RemotePlayer`에 hp 미전달 → 피격/PK 시각화 불가  
9. 서버 공격은 **근접 단일 타겟·고정 사거리 2.2** — 클라 부채꼴 근접·원거리 발사체·대시는 미대응

### 3.5 권위 이전 데이터·리듀서 모델 (설계 방향)

**원칙 (기존 서버 원칙 준수)**  
- 소유자 = `ctx.sender()` 세션만. `account_id` 인자 금지.  
- 클라가 보내는 것 = **의도**(이동, 공격 대상 id, 스킬 id, 아이템 슬롯, 텔레포트 목적지+보정 착지).  
- 보내는 것 금지 = 최종 damage, 최종 hp, 획득 xp, 드롭 결과, 난수 시드.

**상태 확장 후보**

| 필드/표 | 용도 |
|---|---|
| `WorldPlayer` | `mp`/`max_mp`, `energy`(필요 시), `defense`, `invulnerable_until`, `next_skill_at` |
| `Monster` | 유지; 저주파 AI용 `ai_target`/`next_action_at` 선택 |
| 단기 `CombatEvent`(선택) | hit 연출; HP diff만으로 충분하면 생략 |
| 인벤/버프 표 | 포션·버프 TTL = 서버 타임스탬프 |

**리듀서 후보**

| reducer | 서버 판정 | 클라 역할 |
|---|---|---|
| `move_to`(강화) | 속도·경계·(선택) 벽 | 예측 이동, 서버 좌표 reconcile |
| `teleport_to` | 목적지·CD·slack | 성공 시에만 연출 |
| `attack_monster` | 사거리·CD·피해·태그·킬·XP | 스윙 애니; HP는 구독 |
| `attack_player` | 안전지대 면역, 사거리, PK | 동일 |
| `use_potion` / `use_item` | 소지·회복량·버프 TTL | 마시 애니 |
| `cast_skill` | MP·CD·사거리·효과 | 이펙트 |
| 사망 시 자동 리스폰 또는 `request_respawn` | 안전지대, HP full, 무적 윈도우 | 카메라 스냅 |
| scheduled `monster_tick`(시드 필수) | 리스폰 | 상태 반영 |
| scheduled 저주파 `monster_ai` / 사거리 도트 | 몹→PC 피해(어그로 몹만) | 피격 연출 |

**MP/HP 감소·회복**  
- 감소: 오직 서버 피해 경로.  
- 회복: 안전지대 rest를 scheduled 또는 이동/입장 시 서버 보정; 포션은 이산 이벤트.  
- 클라 `RestRecovery`·`applyDamage`는 예측 표시 후 완전 권위 단계에서 제거.  
- **defense**와 `BuffSpec.damageTakenMultiplier`는 축을 분리 유지(`player.dart:74-87` vs `buff.dart`).

**스킬**  
- 지금 근접/원거리/대시가 클라 로컬. 서버 스킬 표 없음.  
- `cast_skill(skill_id, target_opt)` + Rust 상수 정본. 히트 판정은 서버 한 번.

### 3.6 Flame 클라 전환

- HUD는 Flame `PositionComponent` 유지 — 서버 row로 바만 갱신. 다섯 자리 HP 레이아웃 점검.  
- `Enemy` 출처: 시드 개체군 → **구독 `Monster` + 활성 반경 스트리밍**(46m/60m 패턴 유지, 출처만 서버).  
- 공격 입력: 로컬 `target.applyDamage` 제거 → `reducers.attackMonster(id)`; 낙관적 플래시 후 서버 HP.  
- 자기 HP: 예측 가능하나 **사망·리스폰 트리거는 서버 `alive`/`hp`**.  
- `report_progress`: 서버 킬이 유일 출처가 되면 제거 또는 오프라인 전용.  
- `RemotePlayer`에 `hp`/`maxHp` 추가해 PK·피격 연출 가능케 함.  
- 오프라인(`OfflineWorldPresence`/`OfflineGameSync`): 로컬 시뮬 유지 여부는 제품 결정.

### 3.7 이동 권위 현실안

완전 서버 적분 이동은 고주파 tick + 지형 walkable 서버 복제 + 예측·롤백이 필요. 모듈 주석이 이미 속도 상한 절충을 선택.  
1단계: 좌표 보고 + 클램프 유지(텔레포트·대시 예외는 전용 reducer).  
중기: intent + 저주파 적분.  
**라리엔 Zone UDP 병행 신설은 비권고**(이중 백엔드·운영 복잡도).

### 3.8 수치 SSOT — 권위 이전의 선행 조건

사람 규격(HP 1만, 방어 0, 피해=몹 레벨)은 **클라에 이미 구현**돼 있다. 서버가 아직 옛 스케일.

| 축 | 클라 | 서버 |
|---|---|---|
| PC max HP | 10000 + (lv-1)×1000 | 100 + (lv-1)×18 |
| 몹→PC 피해 | level (defense 0 시) | 경로 없음 |
| PC→몹 피해 | melee 26 등 + 버프 | `14+3×(lv-1)` 한 방 |
| 몹 배치 | 시드 `MonsterPopulation` | 레벨 1~200 군집 bootstrap |
| 플레이어 만렙 | 999 (`LevelSystem`) | 999 (`leaderboard`) — **성장 곡선은 정합** |

**SSOT = Rust 상수(판정) + 클라 표시용 미러 테스트.** 사람 규격을 최우선으로 하면 **서버를 클라 규격에 맞추는 방향**이 맞다(기존 서버 100 스케일을 “옳다”고 고수하지 않음).

### 3.9 MMORPG 동시성

- 이동 5Hz × N 접속 + 공격 이벤트: 트랜잭션 부하. 간격·minStep 유지.  
- 전 몬스터 public 구독: N×수천 행 푸시 — **AOI/청크 필수** 전에 전역 구독은 위험.  
- 선점 태그 + 향후 PK: 안전지대 면역·태그 TTL·사망 즉시 리스폰이 서버에서 한 세트로 정의돼야 분쟁.  
- `award_kill`과 `report_progress` 동시 사용 시 조작 클라는 신고로 앞서고, 정상 클라는 이중 가산 또는 단조 가드에 의한 불일치 가능.

## 4. 리스크 · 함정

- **이중 진실:** 로컬 킬 XP(`report_progress`)와 `award_kill` 병행 → 조작·중복 성장. `leaderboard.rs:285-287` 경고.
- **`monster_tick` 미시드:** 서버 몹 영구 사망 → 월드 고갈. 연동 **전** 필수.
- **HP 100 vs 10,000:** 연동 직후 체감·HUD·사망 조건 붕괴.
- **전 몬스터 public 구독:** AOI 없이 capacity 상한까지 가면 대역·메모리 폭주.
- **지형 미소유:** 서버는 walkable 모름(`teleport` slack `world.rs:149-155`). 벽 통과는 속도 가드만으로 미차단. hazard 서버화는 지형 시드 공유 또는 클라 보고 검증 중 선택 필요.
- **scheduled AI 비용:** 수천 몹 매초 AI → wasm 타임아웃 위험. **어그로/근접 슬롯만**.
- **재실행 멱등:** 전역 카운터 금지, 상태 전부 표에(`world.rs` 주석·GAME-DESIGN 직렬화 재실행).
- **문서 표류:** `GAME-DESIGN` 13장·`lib.rs` Overview(“계정·캐릭터 선택까지”)가 presence/몬스터 실제 상태와 불일치 → 잘못된 로드맵.
- **공개 표 vs 원칙 3:** 공유 월드 상태는 의도적 public. 비밀 열을 `WorldPlayer`에 넣지 말 것(이미 account_id 없음).
- **오프라인 모드:** 서버 필수화 시 정책 미정.
- **RemotePlayer hp 부재:** 서버 피격 후에도 타인 HP바 불가.
- **클라 공격 형태 ≠ 서버:** 원거리/AoE/대시를 서버 한 방에 억지로 맞추면 조작감 붕괴 — 스킬 분해 후 단계 이전.

## 5. 권고안

| 순위 | 권고 | 범위 | 근거 | 리스크 |
|---|---|---|---|---|
| 1 | **수치 SSOT:** 서버 `BASE_MAX_HP`·`max_hp_for_level`·`player_damage`·몹 HP/XP를 클라 규격(HP 1만 축, 피해=몹 레벨, defense 승수)에 맞추고 양측 테스트 고정. | `world.rs` 상수 · `player.dart` · `monster_codex.dart` · curve 테스트 | `world.rs:142-372` vs `player.dart:45-87` · `monster_codex.dart:410-416` | 밸런스 일괄 재조정; 기존 서버 월드 캐릭터 max_hp 재계산 |
| 2 | **`monster_tick` 타이머 bootstrap** (`init`/`bootstrap`에 주기 insert) + 리스폰 통합 테스트. | `world.rs` · `lib.rs` init | 타이머 insert 부재 `world.rs:289-295, 409-458` | 없으면 서버 몹 고갈 |
| 3 | **클라를 서버 몬스터 골격에 연결:** `monster` 구독(가능하면 거리/청크 필터), 활성 반경 `Enemy` 스폰, 공격 시 `attackMonster`, 로컬 몹 `applyDamage`/개체군 스폰 비활성. | `cyborg_connection` · 스트리밍 · `player` 근접 히트 · presence | `GAME-DESIGN.md:796-800`, 게임 루프 `attackMonster` 0건 | 연출 지연·사거리 거절; AOI 없으면 대역 폭주 |
| 4 | **성장 권위 단일화:** 서버 킬 XP만 인정. `report_progress` 제거 또는 오프라인 전용. 클라는 `PlayerCharacter`/킬 이벤트로 level/xp 표시. | `leaderboard.rs` · `SpacetimeGameSync` | `leaderboard.rs:276-287` · `award_kill` | 조작 클라 무력화(의도), 오프라인 성장 단절 |
| 5 | **PC 피격·사망·리스폰 서버화:** 몹 공격 scheduled 또는 사거리 도트 → `WorldPlayer.hp`; `hp≤0` → `alive=false` → 안전지대·HP 회복·무적 만료. 클라 `onPlayerDied`를 서버 상태 전이로 교체. | `world.rs` · `player.dart` · `action_rpg_game.dart` | 로컬 사망 `player.dart:583-588` | 지연 사망, 고스트 시체 |
| 6 | **`RemotePlayer`에 hp/maxHp/alive 동기** + HUD/원격 바. | `world_presence.dart` · `remote_player.dart` | 스냅샷에 hp 없음 | 구독 페이로드 증가 |
| 7 | **회복·포션 서버화:** `use_potion` / rest를 서버 타임스탬프 기준. defense와 `damageTakenMultiplier` 축 분리 유지. | buff/inventory 대응 Rust | 클라 전용 버프 | 인벤 스키마 부담 |
| 8 | **텔레포트 서버 경로:** `teleportPlayerTo` → `teleportTo` 성공 후 로컬 스냅. | `action_rpg_game.dart` · `world.rs:743-780` | 현재 로컬만 | 거절 시 UI 피드백 |
| 9 | **이동:** 당분간 속도 가드 유지. 조작 이슈 심화 시 intent+저주파 적분. **라리엔 30Hz Zone 신설 비권고.** | `move_to` | `world.rs:132-139` | 벽 통과 잔존 |
| 10 | **PK:** `attack_player` + `in_safe_zone` 면역 + 선점 경쟁 동기 정합. | `world_player` | `GAME-DESIGN.md:802-803` | 트롤링·밸런스 |
| 11 | **스킬:** Rust 상수 정본 + `cast_skill`; 클라는 입력·이펙트. MP를 `WorldPlayer`에. 원거리/AoE는 스킬 id로 분해. | 신규 reducer | 현재 스킬 서버 부재 | 범위 큼 — 5~7 이후 |
| 12 | **구독 AOI:** 전역 `monster` 구독 회피 — 청크/거리 필터 또는 관심 영역. | 구독 계층 | capacity 1.2만 | 구현 복잡도 |
| 13 | **문서 동기화:** `GAME-DESIGN` 13장·`lib.rs` Overview를 presence/몬스터 실제 상태에 맞게(오케스트레이터). | 문서 | 13장 vs 코드 | 잘못된 로드맵 |

**의도적으로 하지 말 것**  
- SpacetimeDB 옆 라리엔 Zone UDP 병행 신설.  
- 클라가 damage/hp/xp를 보내는 검증 없는 “동기화”.  
- 전 몬스터 30Hz 위치 갱신.  
- `monster_tick` 시드·SSOT 없이 `attack_monster`만 붙이기.

## 6. 불확실 · 미확인

- maincloud 운영 DB의 몬스터 실건수·`monster_tick_timer` 행 존재 여부(로컬 코드상 insert 없음만 확인, 원격 실측 안 함).
- SpacetimeDB 2.7에서 수천 행 public 표 구독의 실측 대역·지연 — 부하 테스트 없음.
- 지형 walkable/hazard를 서버로 옮길지, 이동·지형 치트 잔존을 수용할지 — **제품 결정**.
- 오프라인 플레이를 MMORPG 본선과 병행할지.
- 몹→PC 피해를 풀 AI 틱으로 둘지, 초기엔 “근접 플레이어에게 주기 도트”로 단순화할지.
- 방어력 성장(장비/레벨) 곡선 — 클라 `defense=0` 고정 주석만 존재(`player.dart:77-78`).
- 서버 `attack_monster` 한 방 모델에 클라 콤보·원거리를 어떻게 매핑할지(스킬 테이블 설계) — 미정.
- 라리엔 파티·거래·인벤 OCC 등은 Cyborg 범위 밖 — 참고만.

## 7. 자기 비판으로 바로잡은 것

- 🔁 수정: 1차 권고에서 **`monster_tick` 시드를 4순위·클라 연동(2) 뒤**에 둠 → **SSOT 직후 2순위**로 올림. 연동 후 킬이 발생하면 리스폰 불가로 월드가 고갈된다(`world.rs:867-891`, insert 부재).
- 🔁 수정: 1차 “`enemy.dart`에서 damage==level” 표현 → **정의는 `monster_codex.dart:410-416`, 적용은 `enemy.dart:304`** 로 분리 명시.
- 🔁 수정: `GAME-DESIGN` “몬스터 240”을 불확실로만 둠 → **로컬 bootstrap은 1~200×3×(5~20), capacity 12,000**이며 240은 **문서 오류**로 판정(`world.rs:76-108` vs `GAME-DESIGN.md:784`).
- 🔁 수정: `lib.rs` “모든 테이블 비공개”를 설계 사실처럼 인용 → 원칙 문구는 남아 있으나 **`world_player`/`monster`/`monster_kill`은 public** — 공유 월드 예외를 명시.
- ➕ 추가: **`RemotePlayer`에 hp 필드 없음** — 서버 피격·PK 연출의 선행 구멍(`world_presence.dart:9-32`).
- ➕ 추가: 방화벽 hazard(`player.dart:501-518`), energy/mp 이중 자원, 서버 공격=근접 단일 vs 클라 AoE/원거리 불일치.
- ➕ 추가: 클라 **HP 1만·defense·피해=레벨은 이미 구현됨** — 이번 작업의 병목은 “전투 수식 발명”이 아니라 **서버 상수 정렬 + 권위 연결**.
- ➕ 추가: 통합 테스트 `test/world_presence_test.dart`로 **presence 연결은 실측 검증됨** — 13장 “클라이언트가 아직 안 씀” 중 presence 부분은 반증.
- ❌ 철회 없음에 가까운 유지: 가설 3(하이브리드 이중 세계), 라리엔 30Hz 비복제, `report_progress` 이중 진실, `attack_monster` 미호출 — 재검증에서 유지.
- 🔁 수정: 1차 `leaderboard` 줄 `276-287` → 실제 `report_progress`는 **`289-323`**(주석 블록은 270대). 주장 자체는 유효.
