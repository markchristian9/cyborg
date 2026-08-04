<!-- cowork:grok | 2026-08-04 22:45:19 | exit=0 | 427s -->
# grok 분석 — party-follow

> 요청: 파티 기능과 파티 리더를 추종 & 사냥하는 기능을 추가해주세요. 형제 게임: 라리엔 폴더를 읽기 전용으로 참고해서 기능을 참고/복사하면 됩니다.

[⚠️ 가장 중요한 전제 — 다른 팀이 같은 저장소에서 병렬 작업 중이다]
지금까지 actionrpg 클라이언트는 서버 월드에 전혀 연결돼 있지 않았다(구독 목록 lib/spacetime/cyborg_connection.dart:28-32 에 world_player/monster 가 없고, enter_world/move_to/attack_monster reducer 호출이 클라 코드에 하나도 없다. 몬스터는 lib/game/systems/monster_population.dart 가 로컬 생성). 그래서 '플레이어끼리 서로 보이지 않는' 문제가 있었다.

**다른 팀이 바로 지금 이 문제를 해결하고 있다.** 그들의 작업 범위는 다음과 같다:
  1. 월드 접속 연결: enter_world 호출 · 좌표 주기 전송 · world_player 구독
  2. 월드에 다른 플레이어 렌더링
  3. 미니맵에 다른 PC 위치를 다른 색상으로 표시
  4. 화면 확대/축소 버튼 추가

그들이 방금 만든 인터페이스가 lib/game/net/world_presence.dart 다(신규 파일, 아직 git untracked). 반드시 이 파일을 읽고 분석의 출발점으로 삼아라:
  - abstract class WorldPresence { Future<void> enter(); void leave(); void report(Vector2 grid); List<RemotePlayer> get others; Listenable get changes; bool get isAvailable; }
  - class RemotePlayer { int characterId; String name; String kind; int level; Vector2 grid; bool alive; }
  - 현재 OfflineWorldPresence 만 있고 SpacetimeDB 구현체는 다른 팀이 작성 중이다.
  - lib/game/level/world_tree.dart 와 test/world_tree_snapshot_test.dart 도 그들의 신규 파일이다.

따라서 **우리 팀(파티·추종)은 원격 플레이어 동기화를 직접 만들지 않는다.** 이미 존재한다고 전제하고 WorldPresence.others / RemotePlayer.characterId / RemotePlayer.grid 위에 파티와 추종 사냥을 얹는 설계를 하라. '먼저 월드 연결부터 해야 한다'는 결론은 이미 해결 중이므로 반복하지 말라.

**파일 충돌 회피가 매우 중요하다** — 같은 워크트리(main 브랜치)에서 두 팀이 동시에 편집한다. 다른 팀 소유 파일(world_presence.dart, world_tree.dart, 그들이 손댈 action_rpg_game.dart 의 렌더/카메라/미니맵 부분)을 우리가 고치면 충돌한다. 어떤 파일을 우리가 새로 만들고 어떤 기존 파일에 최소한으로만 손대야 하는지 구체적으로 지목하라.

[기술 스택 차이]
actionrpg(Cyborg)는 Flutter + Flame 2.5D 아이소메트릭, 백엔드는 SpacetimeDB(Rust reducer/table). 라리엔은 Nakama + Go Zone 서버(30Hz 권위 시뮬레이션). 특히 라리엔은 서버가 이동/사냥을 시뮬레이션하지만 actionrpg 는 클라이언트가 좌표를 보고하고 서버는 속도 상한만 검증한다(spacetimedb/src/world.rs 의 move_to). 라리엔 코드를 그대로 복사할 수 없는 부분이 어디이고 어떻게 SpacetimeDB reducer/table 모델로 옮겨야 하는지 구체적으로 분석하라.

[라리엔 참고 위치] /Users/thruthesky/apps/game/laryen (읽기 전용, 절대 수정 금지)
  - docs/party.md — 특히 §10.5 '사냥 리딩(hunt lead)' 이 이번 요청의 추종&사냥에 정확히 대응한다. party leader(멤버십 관리)와 hunt lead(임시 사냥 지휘)를 분리한 설계, updatePartyFollowAnchors 로 follower 의 사냥 앵커를 매 tick 리더 위치로 갱신하는 방식, PLEADSTART/PLEADINV/PLEADACCEPT/PLEADSTATE/PLEADEND 프로토콜, 리더 사망/접속종료/부활 시의 안전망을 반드시 읽어라.
  - lib/protocol/party.dart, lib/state/party_controller.dart, docs/party-progress.md, test/party_*.dart

[분석해야 할 것]
1) WorldPresence 위에 파티를 얹는 설계 — SpacetimeDB 에 어떤 표(party, party_member 등)와 reducer(create_party/invite/accept/decline/leave/disband/promote/kick)를 두어야 하는가. 표의 열·인덱스·public 여부·권한 검증을 spacetimedb/src/world.rs 와 auth.rs 의 기존 규칙(require_session, require_world_player, identity 기반 검증, '남의 것을 조작할 수 없게 인자가 아니라 세션에서 도출')에 맞춰 구체적으로 설계하라. 구독 쿼리도 함께 설계하라.
2) 라리엔에서 무엇을 가져오고 무엇을 버릴지 판정하라. 라리엔의 PMEMB 청크 분할(UDP MTU 대응)·PINV 재전송·PartyMemberAccumulator 는 SpacetimeDB 구독 모델에서 불필요해 보이는데 정말 그런지 검증하라. 반대로 라리엔의 leadSeq(stale/cross-party 수락 차단) 같은 안전 장치는 SpacetimeDB 에서도 필요한지 판정하라.
3) '파티 리더 추종(follow) & 자동 사냥' 설계 — 클라이언트에서 할지 서버 reducer 로 할지 판정하라. 라리엔은 서버 autopilot 앵커를 매 tick 갱신하지만 actionrpg 는 서버가 tick 시뮬레이션을 돌리지 않는다(monster_tick 은 5초 리스폰 전용). actionrpg 의 AutoHuntController(lib/game/systems/auto_hunt.dart)에는 이미 moveAnchor(157줄)·enable/disable·pursuitTimeout·blocklist 가 있다. 이것을 어떻게 재사용해 '리더 추종'을 구현할지, 추종 거리(leash)·재추적·장애물(경로탐색 없음)·리더 텔레포트(world.rs teleport_to)·리더 사망·리더 접속종료·follower 사망 처리를 구체적으로 설계하라. 기존 수동 자동사냥과 추종 사냥의 우선순위 충돌(앵커 소유권)을 어떻게 푸는지 반드시 답하라.
4) CLAUDE.md:33-34 'Hunting is solo, not party based. There is no party, no shared damage credit and no party loot rule.' 와 GAME-DESIGN.md:781 '솔로 사냥(파티 없음) — 설계상 파티 개념 자체가 없음' 이 이번 요청과 정면 충돌한다. world.rs 의 선점 태그(tagged_by, TAG_TTL_MICROS) 기반 킬 크레딧과 경험치 지급(award_kill)을 파티 공유로 바꿔야 하는가, 아니면 그대로 두고 '함께 다니되 경험치는 각자'로 갈 것인가? PK 허용 및 '남이 선점한 몹을 뺏으려면 그 사람을 쓰러뜨려라'는 기존 설계 철학과의 정합성을 따져 판정하고, 문서를 어떻게 갱신할지 구체적 문구까지 제안하라.
5) 구현 순서(우선순위)와 각 단계 검증 방법. CLAUDE.md 의 'Always test with DTD. 키보드/클릭 주입 금지, main()/initState() 에 테스트 코드 주입, 스크린샷·로그로 검증' 제약을 반드시 지키는 검증안이어야 한다. 다른 팀의 WorldPresence 구현이 아직 없는 동안 우리 기능을 어떻게 단위 테스트할지(가짜 WorldPresence 주입 등)도 답하라.
> 생성: 2026-08-04 22:45:19 · 소요 427s · 읽기 전용 분석(작업공간 미수정)

---

1차 보고서의 인용 근거를 코드에서 직접 재검증하고, 놓친 파일을 추가로 열어 반증 여부를 확인합니다.근거 재검증이 끝났습니다. 1차의 줄 번호 오류·MVP 범위·`attack_monster` 미연결 함정을 반영해 최종 보고서를 작성합니다.

## 1. 결론 요약

파티는 **SpacetimeDB에 멤버십·초대 상태만** 두고, **추종·자동 사냥 실행은 클라이언트**에서 `WorldPresence.others`의 리더 `grid`로 `AutoHuntController.moveAnchor`를 돌리는 구조가 맞다. 서버는 tick 시뮬레이션이 없어 라리엔식 `updatePartyFollowAnchors`(Zone 30Hz)를 이식할 수 없다. 킬·EXP·loot는 **선점 태그 솔로를 유지**하고, 문서를 “동행 파티 + 보상 비공유”로 고친다. **1차 MVP는 party leader 고정 추종**이면 요청(“파티 리더 추종”)을 충족한다 — 라리엔식 누구나-hunt-lead 분리는 2단계. 다른 팀 presence/렌더/미니맵은 건드리지 말고 신규 `party` 모듈·`PartyService`·`PartyFollow`·Flame HUD로 경계를 나눈다. **지금 자동 사냥은 로컬 `Enemy`만 때리며 `attack_monster`를 호출하지 않는다** — 추종은 “리더 옆으로 이동”만 보장하고, 서버 공유 몹·킬 크레딧과 맞물린 “같이 잡기”는 몬스터 바인딩 이후 문제다.

## 2. 근거

- `CLAUDE.md:33-34` — “Hunting is solo, not party based… no shared damage credit and no party loot rule.”
- `GAME-DESIGN.md:781` — “솔로 사냥 (파티 없음) | ✅ 설계상 파티 개념 자체가 없음” (이번 요청과 문서 충돌)
- `GAME-DESIGN.md:782-784, 794-800` — 문서상 “클라가 world 미사용·몬스터 로컬” 서술; **코드는 presence 쪽만 이미 진행**
- `spacetimedb/src/lib.rs:9-18, 180-186` — 클라이언트 불신, `ctx.sender()`→`require_session`, 표 기본 비공개
- `spacetimedb/src/lib.rs:207-213` — `on_disconnect` 시 `world_player`만 삭제(세션·멤버십 표는 여기서 안 지움)
- `spacetimedb/src/world.rs:10-17, 120-124, 818-859, 908-970` — 선점 태그·`award_kill`은 **owner 1인** EXP
- `spacetimedb/src/world.rs:33-39` — `world_player`/`monster`/`monster_kill`만 **공개 예외**(월드에 드러난 사실); `account_id` 열 금지
- `spacetimedb/src/world.rs:129-130, 664-705, 865-891` — tick=5초 리스폰; `move_to`=클라 좌표+속도 상한; 이동 시뮬 없음
- `spacetimedb/src/world.rs:559-590` 근처 `enter_world` — `require_session` + `selected_character_id` 도출 패턴
- `spacetimedb/src/leaderboard.rs:151-155` — view 반환 타입은 **표 이름**에서만 찾음(`Type2` 함정)
- `lib/game/net/world_presence.dart:9-60, 63-70` — `RemotePlayer`/`WorldPresence`/`OfflineWorldPresence`; DI 가능한 추상 창구
- `lib/spacetime/spacetime_world_presence.dart:15-144` — `enterWorld`·`moveTo`·`kWorldSubscriptions`·`others`(characterId/grid/alive)
- `lib/spacetime/cyborg_connection.dart:39-41` — `kWorldSubscriptions = world_player` **이미 존재**
- `lib/game/systems/auto_hunt.dart:64-93, 125-162, 170-171` — 반경 1~10m, `pursuitTimeout`/`blocklist`, `moveAnchor`, `suspended`
- `lib/game/action_rpg_game.dart:68-74, 102` — `presence` 생성자 주입(가짜 presence 단위 테스트 가능)
- `lib/game/action_rpg_game.dart:552-564, 571-594, 642-675, 1020-1023, 1408-1414, 1478-1479` — auto hunt 실행, presence 동기화, 클릭=`moveAnchor`, **사망 시 `autoHunt.disable()`**, 출격 시 `presence.enter()`
- `lib/game/entities/remote_player.dart:77-80` — 거리>12 스냅(텔레포트 대응)
- `lib/game/` 내 `attackMonster` 호출 **0건** — 생성 바인딩만 있고 전투 루프 미연결
- `lib/game/action_rpg_game.dart:137, 243` — 몬스터는 여전히 `MonsterPopulation.generate`(로컬)
- `test/world_presence_test.dart:46-77` — 2접속 상호 가시 통합 테스트 이미 있음
- 라리엔 `docs/party.md:28-31, 131-137, 303-376` — 멤버십/EXP 하이브리드, PMEMB 청크, **party leader ≠ hunt lead**, leadSeq, 클라 leash 재사용, 리더 사망 시 세션 유지·재집결
- 라리엔 `lib/state/party_controller.dart:11-22` — partyId 로컬 UUID(Nakama SPOF 제거 이력) — **Cyborg는 서버 auto_inc가 맞음**(구독 표가 SSOT)
- 작업공간 `lib/`·`spacetimedb/` grep `party|Party` — **구현 0**(문서 문구만)

## 3. 상세 분석

### 3.1 범위·경계 (다른 팀과 충돌 회피)

| 영역 | 권위·코드 | 담당 |
|---|---|---|
| 월드 입장·좌표·원격 PC 렌더·미니맵·줌 | `WorldPresence` / `SpacetimeWorldPresence` / `RemotePlayerEntity` / `world_tree` | **다른 팀** — **무수정** |
| 파티 멤버십·초대·(선택) hunt 상태 | SpacetimeDB 신규 `party` 모듈 | **우리** |
| 추종 시 이동·로컬 자동 사냥 | `AutoHuntController` + `PartyFollow` + `action_rpg_game` 최소 배선 | **우리** |
| 킬/EXP/loot | 기존 `tagged_by` + `award_kill` | **변경 금지**(의도) |
| 서버 몬스터 바인딩·`attack_monster` 클라 연결 | 게임 루프에 아직 없음 | **타 과제** — 추종 범위 밖이나 **체감 한계의 원인** |

요청 전제의 “구독 목록에 world 없다”는 **이미 코드와 불일치**다(`cyborg_connection.dart:39-41`, `spacetime_world_presence.dart`, `world_presence_test.dart`). “먼저 월드 연결” 권고는 반복하지 않는다. 다만 `GAME-DESIGN.md:782-784`·§13 과제는 **문서 부채**로 남는다 — 분석·구현 시 **코드 우선**.

### 3.2 설계 가설과 판정

| 가설 | 내용 | 판정 |
|---|---|---|
| H1 | 멤버십+앵커 전부 서버 tick 권위(라리엔 Zone) | **기각** — `monster_tick`은 리스폰만(`world.rs:865-891`), 이동은 `move_to` 보고(`world.rs:664-705`) |
| H2 | 멤버십만 서버, 추종·사냥은 클라 `moveAnchor` | **채택** |
| H3 | 파티 표 없이 클라끼리만 추종 | **기각** — 초대 위조·강제 가입을 `ctx.sender()` 없이 못 막음(`lib.rs:9-11`) |
| H4 | **MVP = party leader 고정 추종**(hunt lead 세션 없음) | **요청 문구와 정합** — “파티 리더를 추종”; 라리엔 §10.5 분리는 P2 |
| H5 | EXP/loot 파티 공유로 `award_kill` 개조 | **기각** — 태그·PK 철학(`world.rs:10-17`)과 정면 충돌, 되돌리기 어려움 |

### 3.3 SpacetimeDB 파티 스키마 (권고)

원칙: 인자로 `account_id`/남의 identity 금지 → `require_session` + `selected_character_id`(및 필요 시 `require_world_player` 패턴, `world.rs:900-906`, `enter_world`). 표는 **private + view**. 공개 예외는 “월드에 드러난 사실”뿐(`world.rs:33-39`) — 전 서버 파티 그래프를 `public party`로 풀 이유는 없다. 미니맵 파티 색은 클라에서 `my_party_members.character_id` ∩ `presence.others`로 충분(다른 팀 미니맵에 색 훅만 요청할 수 있으나 **우리 1차 범위 밖**).

**표 (모두 private)**

1. **`party`**
   - `id: u64` PK `auto_inc`
   - `leader_character_id: u64` + btree
   - `created_at: Timestamp` (`ctx.timestamp`)
   - (선택) `member_count: u32` — view/iter 제약 완화용 캐시
   - **`account_id` 열 금지**

2. **`party_member`**
   - `character_id: u64` PK (**한 캐릭터 = 최대 1 파티**)
   - `party_id: u64` btree (**인덱스 필수** — view가 `iter()` 없이 멤버를 모을 유일한 길)
   - `joined_at: Timestamp`
   - 리더 SSOT는 `party.leader_character_id` 한곳(이중 `is_leader` 플래그는 promote 시 어긋나기 쉬움)

3. **`party_invite`**
   - `id: u64` PK auto_inc → **invite_seq**(라리엔 leadSeq/초대 stale 차단 역할)
   - `party_id`, `from_character_id`, `to_character_id`(to btree)
   - `created_at` + TTL(예: 20s, 서버 시각 비교)
   - 수락 시 `invite_id` 대조 → stale/타 파티 초대 차단

4. **(P2) `hunt_lead_session` / `hunt_follow`**
   - 파티당 세션 1, `seq`, leash, leader
   - **1차 MVP에서는 생략 가능**: follow 대상 = 현재 `party.leader_character_id`

**Reducer (이름 예시)**

| reducer | 검증 요약 |
|---|---|
| `create_party` | 세션·선택 캐릭터·무소속 → party + self member(leader) |
| `invite_to_party(target_character_id)` | 호출자 멤버(초기: **leader only** `[추측·제품]`), 대상 월드 입장·무소속, cap, invite insert |
| `accept_invite(invite_id)` / `decline_invite` | `to` = 내 캐릭터, TTL·무소속 |
| `leave_party` | 멤버 삭제; leader면 **자동 promote(가장 오래된 member) 또는 disband** — 제품 결정 |
| `disband_party` | leader only, 멤버·초대 일괄 삭제 |
| `promote` / `kick` | leader only, 같은 party, self kick 금지 |
| (P2) `start_hunt_lead` / `accept_hunt_lead(seq)` / `stop_hunt_lead` / `set_hunt_leash` | **상태만**, 이동 시뮬 없음 |

**View·구독**

- `my_party`, `my_party_members`, `my_party_invites`(to=me) — 반환 타입은 **실제 테이블 구조체** 또는 leaderboard처럼 “빈 표+동명 타입”(`leaderboard.rs:151-155`)
- 구독 상수는 **`kPartySubscriptions` 별도 리스트**(`cyborg_connection.dart`에 추가만). 다른 팀의 `kWorldSubscriptions`와 한 배열을 동시에 고치지 말 것
- view도 구독해야 행이 온다(`cyborg_connection.dart:18-21` 주석·실측 전제)

**disconnect**

- 현재: `world_player` 삭제만(`lib.rs:208-213`)
- 권고: **멤버십은 유지**(재접속 후 파티 유지) vs 해산은 제품 결정
- 추종: 리더가 `presence.others`에 없으면 클라 follow 중단; (P2) hunt 세션은 `on_disconnect`에서 서버 종료 훅
- 리더 월드 이탈 ≠ 자동 파티 해산으로 두면 “고아 파티 + 추종 좀비”를 클라 규칙으로 막아야 함

### 3.4 라리엔 이식 판정

| 라리엔 | 판정 | 이유 |
|---|---|---|
| 초대/수락/거절/추방/위임 UX | **가져옴** → reducer 재모델링 | 사용자 흐름 |
| party leader ≠ hunt lead | **개념만 P2** | 요청 1차는 “파티 리더 추종”; 분리는 복잡도↑ |
| invite id / leadSeq | **가져옴** | 구독 지연·더블탭 stale accept |
| autopilot leash 재사용 | **가져옴** | `AutoHuntController`가 동형 |
| 리더 사망 시 세션 유지·안전지대 재집결 | **가져옴(클라 정책)** | `party.md:369-373`; actionrpg도 즉시 안전지대 리스폰 |
| follower 사망 후 추종 재개 | **가져옴(분기 필요)** | 현행 `onPlayerDied`가 `autoHunt.disable()`(`action_rpg_game.dart:1411-1414`) — 수동 자동사냥용 의도(죽인 무리 재진입 방지)와 **추종 모드 분기** |
| PMEMB 청크 / Accumulator | **버림** | Spacetime 구독 행; UDP MTU 없음 |
| PINV 1초×3 재전송 | **버림** | 신뢰 채널+표; invite TTL+UI |
| 로컬 UUID partyId | **버림** | 서버 `auto_inc`+표 SSOT; 라리엔은 Nakama SPOF 회피용 특수사 |
| Zone 30Hz 앵커 갱신 | **버림** | 서버 tick 모델 없음 → 클라 프레임 `moveAnchor` |
| EXP 균등·드롭 RR | **버림** | 태그·PK·`CLAUDE.md` 솔로와 충돌 |
| max 32 / shard | **축소** | 단일 월드; 초기 cap 4~8 `[추측]` |

### 3.5 추종 & 자동 사냥 (클라이언트)

**실행 위치: 클라이언트.** 서버는 “누가 같은 파티이고(및 P2에서 누구를 따르는지)”만 권위.

```
매 프레임(또는 presence.changes 후):
  if following:
    leader = presence.others에서 leaderCharacterId
    if leader == null:  // 월드 이탈·구독 지연
      follow pause (앵커 유지 또는 중단 — 권고: pause + 배너)
    else if !leader.alive:
      moveAnchor 스킵(마지막 자리 사냥 유지)  // 라리엔: 리더 사망 중 정지 없음
    else:
      if !autoHunt.enabled: autoHunt.enable(leader.grid)
      else: autoHunt.moveAnchor(leader.grid)
  기존 _updateAutoHunt 가 approach/attack/returnToAnchor 실행
```

- **leash**: `radiusMeters` 1~10(`auto_hunt.dart:64-71`). 경로탐색 없음 → `pursuitTimeout` 4s / `blockDuration` 3s 재사용
- **텔레포트**: 리더 `teleport_to` 후 remote는 distance>12 스냅(`remote_player.dart:77-80`); follower 앵커는 다음 presence로 점프
- **presence 보고 주기 0.2s**(`spacetime_world_presence.dart:25`) → 앵커 갱신 해상도 상한 ≈5Hz(프레임마다 읽어도 데이터는 그 주기)

**앵커 소유권 (`AnchorOwner`)**

| 모드 | 땅 클릭 | auto hunt 토글 |
|---|---|---|
| 수동 자동사냥 | `moveAnchor(클릭)` (`action_rpg_game.dart:1020-1023`) | on/off |
| **파티 추종** | 클릭 `moveAnchor` **무시**(“추종 중” 배너) | off = 추종 중단 |
| 조이스틱 수동 | 기존 `suspended` 유지 — 손 떼면 재개 | 추종 플래그는 유지 권고 |

**사망 (1차 단순 권고를 정교화)**

- 수동 자동사냥: 현행대로 disable — 안전지대 리스폰 후 죽인 무리로 혼자 걸어가 연사 사망 방지(`action_rpg_game.dart:1411-1412` 주석)
- **추종 중 본인 사망**: follow 세션 **유지**, autoHunt는 respawn 후 리더 앵커로 재enable. 단 리더가 맵 반대편이면 경로 없이 장거리 직선 이동 → 시간·중간 위협. UI로 “리더에게 합류(텔레포트 목록)” 유도는 제품 선택 `[판단]`
- **리더 사망**: 라리엔과 같이 follow 유지 → 리더가 안전지대 리스폰하면 멤버가 그쪽으로 재집결(의도된 “다 같이 안전지대”)

### 3.6 보상 철학 — 문서 개정

**판정: `award_kill`/태그/loot를 파티 공유로 바꾸지 않는다.**

이유: (1) PK 동기와 한 세트(`world.rs:16-17`) (2) 파티 EXP는 태그 무력화 (3) eligible 반경·동시성은 Zone tick 전제(라리엔 §6)라 Spacetime reducer-only에 비용 큼 (4) 요청 핵심은 **동선 공유**

**문서 문구 제안**

`CLAUDE.md` Multiplayer:

```markdown
- Party membership and leader-follow (auto-hunt leash) are allowed for co-travel.
- Hunting credit remains solo: first-tag owns the kill, no shared damage credit,
  no party XP split, no party loot rule. Each player earns only what they tag.
- PK remains allowed; contesting a tagged monster still means fighting its owner.
```

`GAME-DESIGN.md:781` 부근:

```markdown
| 파티 (동행·추종) | ✅ 멤버십·리더 추종. 보상은 솔로(선점 태그) |
| 솔로 킬 크레딧 | ✅ 파티여도 EXP/loot 비공유 |
```

동시에 §13의 “클라이언트가 world 안 씀”(782-784, 794-795)은 **presence 기준으로 갱신**해야 문서가 다시 신뢰된다.

### 3.7 파일 소유권

**신규**

- `spacetimedb/src/party.rs` + `lib.rs` `mod party`
- `lib/game/net/party_service.dart` (abstract + Offline)
- `lib/spacetime/spacetime_party_service.dart`
- `lib/game/systems/party_follow.dart` (`AnchorOwner` + leader 추적)
- `lib/game/ui/party_hud.dart`, `party_invite_toast.dart` (Flame `PositionComponent`)
- `test/party_*_test.dart`, `test/party_follow_test.dart`

**최소 터치**

- `action_rpg_game.dart`: 생성자 DI, `update`에 `partyFollow.tick`, 클릭/사망 분기 — **카메라·미니맵·`_syncRemotePlayers` 본문 금지**. 파티 로직은 파일 하단 섹션 또는 별 클래스로 격리
- `cyborg_connection.dart`: `kPartySubscriptions` **추가만**
- 게임 진입 DI: `PartyService` 주입(`presence`와 동일 패턴, `action_rpg_game.dart:68-74`)

**수정 금지(다른 팀)**

- `world_presence.dart` 인터페이스 확장 요구 금지 — `characterId`/`grid`/`alive`면 충분
- `spacetime_world_presence.dart`, `remote_player.dart`, `world_tree.dart`, 미니맵/줌 UI

### 3.8 구현 순서·검증 (DTD)

| 단계 | 내용 | 검증 |
|---|---|---|
| P0 | 서버 party 표·reducer·view, `cargo test` | 수락/중복 가입 거부/kick 권한 |
| P1 | `PartyService` + Offline + generate 바인딩 | `flutter test test/party_*` |
| P2 | Flame 초대 토스트·멤버 패널 | DTD: `main`/`initState`에 fake 멤버 inject → 스크린샷·로그 (`CLAUDE.md:49-52`) |
| P3 | `PartyFollow` + `AutoHuntController`, AnchorOwner | `auto_hunt_test` 확장: 프레임마다 앵커 이동 시 return/approach; **FakeWorldPresence**를 `ActionRpgGame(presence: …)`에 주입 |
| P4 | 2계정 실서버(멤버십+좌표 수렴) | 로그: invite accept; follow 중 양측 `move_to` 좌표 접근; `world_presence_test` 패턴 재사용 |
| P5 | CLAUDE/GAME-DESIGN 문구 | 리뷰 |

키보드/클릭 에뮬 주입 금지. Fake presence 예시는 1차와 동일 취지 — `WorldPresence` 기본 구현 오버라이드 + `ValueNotifier`로 `changes` 통지.

## 4. 리스크 · 함정

- **문서 vs 코드:** GAME-DESIGN §13은 presence를 “미구현”으로 두지만 코드·통합 테스트는 이미 존재. 구현 판단은 **코드 우선**.
- **`attack_monster` 미연결:** 추종 자동 사냥 = 로컬 `MonsterPopulation`/`Enemy` + `tryMelee`일 뿐. 서버 킬·EXP·공유 몹과 **아직 무관**. “같이 사냥” UX 기대와 어긋남 — 몬스터 바인딩은 타 과제이나 **함정으로 문서·UI에 명시**할 것.
- **`award_kill` 파티화:** PK 경제 붕괴·되돌리기 어려움 — 1차 범위 금지.
- **view 반환 타입/`Type2`:** `leaderboard.rs:151-155` 패턴 준수 필수.
- **공개 표 남용:** party public → 전 서버 파티 그래프 노출; 원칙·`world.rs:33-39` 취지와 충돌.
- **`action_rpg_game.dart` 핫스팟:** 양팀 동시 편집 충돌 — 파티 블록 격리.
- **사망 시 일괄 `disable()`:** 추종과 충돌; 모드 분기 필수. 반대로 추종 유지 시 장거리 재합류 비용.
- **리더 disconnect:** `world_player`만 삭제 → 멤버십 잔존 + follow 좀비; 클라 타임아웃 + (선택) 서버 훅.
- **치팅:** 좌표·타격이 클라 권위인 한 가짜 이동 가능 — 기존과 동일 수준; 멤버십 위조만 서버로 차단하면 1차 수용(`cowork` 원칙 5).
- **presence 0.2s + 무경로:** 리더가 벽 너머·고레벨 지대로 가면 follower가 같이 위험 지역으로 끌려감 — leash/반경 UI로만 완화.

## 5. 권고안

| 순위 | 권고 | 범위 | 근거 | 리스크 |
|---|---|---|---|---|
| 1 | 멤버십·초대 **상태만** SpacetimeDB(`party` 모듈); 이동/사냥 실행은 클라 | 서버 신규 + `PartyService` | `lib.rs:9-18`, `world.rs:129-130,664-705` | 스키마·view 설계 실수 |
| 2 | **MVP 추종 = party leader**의 `grid` → `autoHunt.moveAnchor`; `AnchorOwner`로 수동 자동사냥과 배타 | `party_follow.dart` + game 최소 배선 | `auto_hunt.dart:157-162`, `world_presence.dart:9-60`, 요청 문구 | 사망/텔레포트/장거리 재합류 |
| 3 | **EXP/loot/태그 공유 금지**; 문서만 “동행 파티 + 솔로 크레딧” (+ §13 presence 서술 정정) | CLAUDE.md, GAME-DESIGN.md | `CLAUDE.md:33-34`, `world.rs:908-970`, 실제 presence 코드 | 라리엔 UX 기대 차이 — UI에 “경험치 비공유” |
| 4 | 라리엔: 초대 흐름·invite seq·사망 안전망 **개념만**; PMEMB/PINV/EXP분배/Zone앵커 **폐기**; hunt lead 분리 **P2** | 설계 | `party.md` §5·§6·§10.5 vs Spacetime | 과이식 시 복잡도 |
| 5 | P0→P5; FakeWorldPresence+`ActionRpgGame(presence:)`로 P3까지 단독 테스트; DTD inject UI | 테스트 | `action_rpg_game.dart:68-74`, `CLAUDE.md:49-52`, `auto_hunt_test.dart`, `world_presence_test.dart` | 실서버 2계정은 presence 안정 후 |
| 6 | 타팀 파일 무수정; `kPartySubscriptions` 분리; `action_rpg_game` 파티 섹션 격리 | 프로세스 | 병렬 워크트리 | 한 줄 상수 병합 충돌 가능 |
| 7 | 추종 UI/배너에 **“로컬 사냥·서버 킬 미연동”** 한계를 드러내 기대 관리 | UX·문서 | `lib/game`에 `attackMonster` 0건, `MonsterPopulation` | 무시 시 “파티 버그”로 오인 |

## 6. 불확실 · 미확인

- 파티 **최대 인원**·초대 권한(leader only vs 전원): 제품 미지정 → 초기 leader only, max 4~8 `[추측]`
- 리더 disconnect 시 **파티 유지 vs 해산 vs 자동 promote**: 미결정
- leave 시 leader 처리(자동 승계 vs 해산) 세부
- hunt lead(누구나 이끌기)를 로드맵 어디에 둘지 — 요청은 리더 추종에 가깝고 라리엔 완전체는 공수 큼
- SpacetimeDB view 매크로로 **party_id btree filter → Vec\<Member\>** 조인 패턴의 컴파일 가능성 — 구현 시 `cargo` 확인(본 분석은 읽기 전용·미컴파일)
- 서버 `attack_monster` 클라 연결·로컬 개체군 폐기 일정(타팀) — 추종 “같이 때리기” 서버 정합 시점
- 라리엔 `sim/party.go` 라인 단위 레이스·TC-PARTY 전부 동등성 — 문서·컨트롤러 머리 위주, Go 전량 미개봉 `[미확인]`
- 미니맵 파티원 색을 다른 팀이 넣을지, 우리 HUD 점만으로 갈지

## 7. 자기 비판으로 바로잡은 것

- ❌ 철회: 1차 `action_rpg_game.dart:992-995` 클릭=`moveAnchor` — 다시 열면 **1020-1023**. 줄 번호 오류.
- ❌ 철회: 1차 `1406-1412` — 실제 사망 처리·`autoHunt.disable()`는 **1408-1414**.
- 🔁 수정: “presence 동기화 533-566” → **552-564, 571-594** 등 실줄로 정정. presence 존재 사실 자체는 `spacetime_world_presence.dart`·`world_presence_test.dart`로 **유지**.
- 🔁 수정: 1차가 hunt lead 세션을 1차 스키마 핵심처럼 서술 → **MVP는 party leader 고정 추종**, hunt lead 분리는 **P2**. 이유: 사용자 요청 문구가 “파티 리더 추종”; 라리엔 §10.5는 상위 집합.
- 🔁 수정: 사망 시 “추종 중 disable 금지” 단순 처방 → **모드 분기 + 장거리 재합류 비용**을 명시. 수동 자동사냥 disable 의도 주석(`1411-1412`)과 충돌을 무시하면 안 됨.
- ➕ 추가: **`lib/game`에서 `attackMonster` 호출 0건** — 추종이 서버 킬/EXP와 무관하다는 한계를 1차가 약하게만 취급. 리스크·권고 7순위로 격상.
- ➕ 추가: `ActionRpgGame`의 **`presence` 생성자 DI**(`68-74`) — FakeWorldPresence 전략의 직접 근거.
- ➕ 추가: `world.rs:33-39` 공개 표 예외 철학 — party private 권고를 “습관”이 아니라 **프로젝트 문서화된 예외 기준**으로 강화.
- ➕ 추가: 라리엔 `party_controller.dart`의 **로컬 UUID partyId**는 Cyborg에 복사하면 안 됨(서버 표 SSOT·구독 모델). 1차는 “Nakama createParty 버림” 정도만 언급.
- 🔁 유지(강화 근거): 가설 2(멤버십 서버·추종 클라), EXP 솔로 유지, PMEMB/PINV 폐기, 파일 소유권 분리 — 재검증 후에도 반증되지 않음.
