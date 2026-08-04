<!-- cowork:claude | 2026-08-04 22:47:36 | exit=0 | 564s -->
# claude 분석 — party-follow

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
> 생성: 2026-08-04 22:47:36 · 소요 564s · 읽기 전용 분석(작업공간 미수정)

---



## 1. 결론 요약

**파티 멤버십·초대·이끌기 세션은 SpacetimeDB 표와 reducer 로 두고, 추종 이동과 자동 사냥의 실행은 전적으로 클라이언트가 한다.** 서버에 tick 시뮬레이션이 없기 때문이다 — `monster_tick` 은 5 초 주기 리스폰 전용이고(`spacetimedb/src/world.rs:130,867`), 이동 권위는 클라 보고 + 속도 상한뿐이다(`world.rs:132-139,669-706`). 라리엔의 `updatePartyFollowAnchors` 는 **개념만** 가져오고 실행부는 버린다.

**경험치 분배는 도입하지 않는다.** 선점 태그(`world.rs:818-847`)와 PK 동기는 이 게임의 코어 서사이고(`world.rs:10-27`, `GAME-DESIGN.md:710-716`), 무엇보다 **클라이언트가 `attack_monster` 를 한 번도 부르지 않아** `award_kill` 경로 자체가 죽어 있다(호출 0건 — 생성 코드에만 존재). 파티는 "함께 다니되 보상은 각자" 로 못 박고 `CLAUDE.md:33-34` · `GAME-DESIGN.md:781` 을 그 문장으로 개정한다.

**파일 충돌은 "같은 추상화 패턴을 우리 파일로 복제" 해서 푼다.** 다른 팀이 `WorldPresence`(인터페이스는 `lib/game/net/`, 구현은 `lib/spacetime/`)로 만든 그 구조를 그대로 따라 `PartySession` 을 신규 파일로 만들면, 기존 파일 수정은 `action_rpg_game.dart` 3~5 줄과 `lib.rs` 1 줄로 끝난다.

⚠️ **분석 중 `action_rpg_game.dart` 가 실제로 바뀌었다** — 처음 읽었을 때 생성자에 `presence` 파라미터가 없었는데(`final WorldPresence presence;` 만 있어 컴파일 불가 상태) 이후 grep 에서는 `WorldPresence? presence,`(64-74행)가 들어와 있었다. 이 파일은 지금 이 순간 편집 중이다.

## 2. 근거

- `lib/game/net/world_presence.dart:40-60` — `WorldPresence` 는 `abstract class` 이고 모든 메서드가 기본 구현을 가진다. 상속만으로 가짜 구현을 만들 수 있다(`OfflineWorldPresence:63-71` 이 그 예시다). 테스트 주입에 다른 팀 파일 수정이 필요 없다.
- `lib/game/action_rpg_game.dart:64-74` — 생성자가 `presence ?? const OfflineWorldPresence()` 로 떨어진다. **분석 시작 시점에는 이 줄이 없었다**(파일이 세션 중 변경됨).
- `lib/game/action_rpg_game.dart:561,572` — `presence.report(player.grid)` 와 `_syncRemotePlayers()` 가 이미 `update()` 에 배선돼 있다. 사용자 프롬프트의 "월드에 전혀 연결돼 있지 않았다" 는 이미 낡은 전제다.
- `lib/spacetime/cyborg_connection.dart:39-41` — `kWorldSubscriptions = ['SELECT * FROM world_player']` 가 이미 존재한다. 프롬프트가 지목한 "28-32 에 world_player 가 없다" 도 낡았다.
- `lib/spacetime/spacetime_world_presence.dart:25,30,63,98` — 좌표 전송 0.2 초 주기·0.15 타일 임계, `subscribe`/`unsubscribe` 동적 구독이 실제로 동작하는 API 임을 확인.
- `lib/game/ui/hud.dart:483-503` — 미니맵의 다른 PC 표시(`game.presence.others`)까지 이미 구현돼 있다. **이 함수는 다른 팀 소유다.**
- `lib/game/systems/auto_hunt.dart:157-162` — `moveAnchor(point)` 는 "중심을 옮기고 쫓던 대상을 놓아준다". 라리엔의 동적 anchor 와 의미가 정확히 같다.
- `lib/game/systems/auto_hunt.dart:85-93` — 경로 탐색이 없어 벽 뒤 대상은 4 초 후 포기(`pursuitTimeout`) + 3 초 차단(`blockDuration`).
- `lib/game/action_rpg_game.dart:992-996, 1231, 1385-1386` — 앵커를 건드리는 곳이 **네 군데**다(땅 클릭 / 텔레포트 / 사망 시 disable / 토글). 앵커 소유권 문제가 여기서 발생한다.
- `spacetimedb/src/world.rs:139` — `MAX_MOVE_SPEED: f32 = 14.0` (타일/초). follower 를 리더 위치로 순간이동시키면 서버가 잘라낸다.
- `spacetimedb/src/world.rs:743-781` — `teleport_to` 는 **목적지 이름**만 받는다(5 곳, 쿨다운 8 초). 임의 좌표 텔레포트가 불가능하므로 "리더 따라 순간이동" 을 좌표로 구현할 길이 없다.
- `spacetimedb/src/lib.rs:207-214` — `on_disconnect` 가 `world_player` 행을 즉시 지운다. 이끌기 세션 정리 훅을 걸 자리다.
- `spacetimedb/src/leaderboard.rs:151-155` — **view 반환 타입은 반드시 `#[spacetimedb::table]` 이어야 한다**(행을 한 줄도 넣지 않는 표를 선언하는 이유). 파티 view 도 이 패턴을 따라야 한다.
- `lib/spacetime/cyborg_connection.dart:44-47` — "순위표는 누가 레벨업하든 다시 계산되어 구독자 전원에게 밀려온다". view 는 의존 표가 바뀔 때마다 재계산·재푸시된다.
- 라리엔 `docs/party.md:131-134` — PMEMB 청크 분할의 이유는 명시적으로 **UDP MTU 1500B** 다.
- 라리엔 `docs/party.md:378-384` — PINV 재전송의 이유는 **UDP 단발 손실**이다.
- 라리엔 `docs/party.md:363` — `leadSeq` 의 이유는 손실이 아니라 **stale/cross-party 수락 차단**이다.
- 라리엔 `game-server/zone/internal/sim/autopilot.go:239-286, 358-380, 389` — follower 앵커를 매 tick 리더 위치로 강제하고, leash 밖이면 **몬스터 탐색보다 먼저** 리더로 복귀하며, 개인 zone lock 은 follower 에서 제외한다("추종이 개인 자동사냥보다 상위 제어권").
- 라리엔 `docs/party.md:369-373` — 리더 **사망 시 세션을 종료하지 않는다**(2026-07-04 재지시). 리더가 safe zone 부활하면 앵커가 그리로 옮겨져 재집결.
- 라리엔 `lib/state/party_controller.dart:19-22` — 비밀 partyId(UUID v4)의 이유는 "외부인이 partyId 를 몰라 난입 불가". SpacetimeDB 는 서버가 초대 행을 검증하므로 이 요구가 사라진다.
- `CLAUDE.md:33-34` / `GAME-DESIGN.md:781` — "There is no party" / "설계상 파티 개념 자체가 없음".
- `test/spacetime_integration_test.dart:31-40` — `InMemoryTokenStore()` 로 매번 새 identity 를 얻는다. **두 client 를 만들면 코드만으로 2 인 파티를 재현할 수 있다.**

## 3. 상세 분석

### 3.1 지금 코드의 실제 상태 (프롬프트의 전제와 다른 점)

프롬프트는 "다른 팀이 지금 작업 중" 이라 했지만, 실제로는 **네 항목 중 세 개가 이미 코드에 들어와 있다**:

| 다른 팀 작업 범위 | 실제 상태 |
|---|---|
| ① `enter_world` 호출·좌표 주기 전송·`world_player` 구독 | ✅ `spacetime_world_presence.dart:55-127`, `cyborg_connection.dart:39-41` |
| ② 다른 플레이어 렌더링 | ✅ `remote_player.dart` 전체 + `action_rpg_game.dart:568-592`(`_syncRemotePlayers`) |
| ③ 미니맵 다른 PC 표시 | ✅ `hud.dart:483-503` |
| ④ 확대/축소 버튼 | ⚠️ `zoomIn`/`zoomOut`/`zoomScale` 은 있으나(`action_rpg_game.dart:310-336`) `_layoutTouchControls` 에 버튼 컴포넌트가 없다 |

즉 그들의 잔여 작업은 ④ 와 안정화뿐이며, `presence` 파라미터가 방금 추가된 것으로 보아 **지금이 가장 충돌 위험이 높은 시점**이다.

### 3.2 서버 설계 — 표·인덱스·공개 여부

`world.rs` 의 공개 판단 기준은 "월드에 드러난 사실은 공개하되 `account_id` 는 한 열도 두지 않는다"(`world.rs:35-39`)다. 파티에 이 기준을 적용하면 갈린다:

- **파티 구성은 월드에 드러난 사실이 아니다.** 남의 파티가 누구로 이뤄졌는지는 게임 성립에 필요 없다. → 파티 표는 **비공개 + view 노출**이 맞다(`lib.rs:15-16` 원칙 3 유지).
- 다만 "저 사람이 내 파티원인가" 는 화면에 필요하므로, **내 파티의 멤버 목록만** view 로 준다.

```rust
// spacetimedb/src/party.rs (신규 모듈)

#[spacetimedb::table(accessor = party)]          // 비공개
pub struct Party {
    #[primary_key] #[auto_inc] pub id: u64,
    pub leader_character_id: u64,                 // 멤버십 권한(초대·추방·위임)
    pub created_at: Timestamp,
}

#[spacetimedb::table(accessor = party_member, index(accessor = by_party, btree(columns = [party_id])))]
pub struct PartyMember {
    #[primary_key] pub character_id: u64,         // 한 캐릭터는 한 파티만
    pub party_id: u64,
    pub joined_at: Timestamp,
    // hunt lead 상태를 같은 행에 둔다 — 행 수를 늘리지 않고 원자적으로 갱신된다
    pub following_character_id: Option<u64>,
    pub follow_seq: u32,
}

#[spacetimedb::table(accessor = party_invite, index(accessor = by_target, btree(columns = [to_character_id])))]
pub struct PartyInvite {
    #[primary_key] #[auto_inc] pub id: u64,
    pub party_id: u64,
    pub from_character_id: u64,
    pub to_character_id: u64,
    pub created_at: Timestamp,
    pub expires_at: Timestamp,                    // 20초 (라리엔 party.md:104)
}

#[spacetimedb::table(accessor = party_lead)]
pub struct PartyLead {
    #[primary_key] pub party_id: u64,             // 파티당 1 세션 (party.md:376)
    pub leader_character_id: u64,
    pub lead_seq: u32,                            // stale 수락 차단
    pub leash_tiles: f32,
    pub started_at: Timestamp,
}
```

**`account_id` 를 어느 표에도 두지 않는다** — `world_player` 와 같은 규율이다(`world.rs:35-39`).

**소유자 도출**: 모든 reducer 는 `require_world_player(ctx)`(`world.rs:900-906`)로 `character_id` 를 얻는다. 이것이 `enter_world` 를 부른 사람만 파티를 만질 수 있게 하고, 동시에 `ctx.sender()` → 세션 → 캐릭터 사슬을 재사용한다.

**`invite_to_party(target_character_id)` 는 원칙 위반이 아니다.** 원칙이 금지하는 것은 "남의 것을 내가 조작" 이지 "남에게 제안" 이 아니다. 대상이 실제로 월드에 있는지(`world_player().character_id().find()`)와 이미 파티가 있는지만 검증하면 되고, 실제 가입은 **대상 본인의 `accept_invite`** 에서 일어난다 — 라리엔의 "PSETPARTY 는 본인 sid 만 바꾼다"(`party.md:136-137`)와 같은 안전 규칙이다.

**`kick_member` 는 라리엔과 다르게 가도 된다.** 라리엔은 Zone 이 남의 sid 를 못 만지는 제약 때문에 "Nakama 가 추방 → 본인이 self-leave"(`party.md:266-272`)라는 우회를 만들었다. SpacetimeDB 는 권위가 하나이므로 리더 자격을 sender 로 검증한 뒤 직접 행을 지우면 된다. 우회를 복사하면 없는 문제를 흉내 내는 셈이다.

**view 설계 — 여기가 가장 조심할 곳:**

```rust
#[view(accessor = my_party, public)]
fn my_party(ctx: &ViewContext) -> Vec<PartyMemberEntry> { ... }
```
- 반환 타입 `PartyMemberEntry` 는 **비공개 표로 선언하되 행을 넣지 않는다** — `LeaderboardEntry`(`leaderboard.rs:151-181`)와 같은 이유. 표가 아니면 Dart 생성기가 `Type2` 같은 깨진 클래스를 참조한다.
- 🛑 **이 view 에 좌표·HP 를 담으면 안 된다.** `world_player` 를 읽는 순간 0.2 초마다 오는 좌표 보고(`spacetime_world_presence.dart:25`) 하나하나가 view 재계산과 전 구독자 재푸시를 부른다 — 리더보드에서 이미 겪은 함정이다(`cyborg_connection.dart:44-47`). **view 는 `character_id`·`name`·`level`·리더 여부·추종 여부만** 싣고, 좌표와 생사는 클라가 이미 구독 중인 `presence.others` 에서 `characterId` 로 조인한다.
- view 도 구독해야 행이 온다(`cyborg_connection.dart:18-22`) → `kPartySubscriptions = ['SELECT * FROM my_party', 'SELECT * FROM my_party_invites']`, 월드 입장 시 함께 건다.
- view 핸들에는 `iter()` 가 없으므로 멤버를 모으는 길은 `by_party` 인덱스 범위 조회뿐이다 — 위 스키마에 그 인덱스를 둔 이유다.

### 3.3 라리엔에서 무엇을 가져오고 무엇을 버리는가 (검증 결과)

| 라리엔 요소 | 판정 | 검증 근거 |
|---|---|---|
| PMEMB 청크 분할 · `PartyMemberAccumulator` | **버림 (확인됨)** | 이유가 명시적으로 UDP MTU 1500B(`party.md:131-134`). 이 프로젝트는 wss(`cyborg_connection.dart:13-14`) 위 행 단위 델타 — 문제 자체가 없다 |
| PINV 재전송 3회 | **버림 (확인됨)** | 이유가 UDP 단발 손실(`party.md:378-384`). 행 insert + 구독은 손실이 없고, **오프라인 상대에게도 행이 남아 다음 접속 때 보인다** — 재전송보다 나은 성질이다 |
| 초대 20초 만료 | **가져옴** | 손실 대응이 아니라 UX(`party.md:104`). `expires_at` 열 + 읽는 쪽 판정 |
| **`leadSeq`** | **가져옴 (필수)** | 이유가 손실이 아니라 stale/cross-party 수락 차단(`party.md:363`). SpacetimeDB reducer 도 인자를 그대로 받으므로 "이끌기 중지 → 재시작" 사이에 늦게 도착한 `accept` 가 옛 세션을 수락하는 창이 똑같이 존재한다 |
| party leader ≠ hunt lead 분리 | **가져옴** | `party.md:308-317`. 멤버십 권한과 사냥 지휘는 별개 축이다 |
| 리더 사망 시 세션 유지 | **가져옴** | `party.md:369-373`. actionrpg 도 사망 즉시 안전지대 리스폰(`action_rpg_game.dart:1397`)이라 전제가 동일 |
| 비밀 partyId(UUID v4) | **버림** | 난입 방지 목적(`party_controller.dart:19-22`). 서버가 초대 행을 검증하므로 불필요. `auto_inc u64` 로 충분하되 **정렬 기준으로 쓰지 말 것**(연속 보장 없음) |
| Nakama 소켓·재연결·SPOF 대응 전부 | **버림** | 두 번째 백엔드가 없다 |
| `updatePartyFollowAnchors` **실행부** | **버림** | 서버 30Hz tick 전제(`autopilot.go:239-302`). 여기엔 5초 리스폰 타이머뿐(`world.rs:130`) |
| `updatePartyFollowAnchors` **개념** | **가져옴** | "리더 위치 = follower 사냥 앵커" → `autoHunt.moveAnchor(리더 좌표)` |
| leash 밖이면 **탐색보다 먼저 복귀** | **가져옴 (중요)** | `autopilot.go:358-380`. 이 분기 순서가 없어서 라리엔은 입구에서 좌우 왕복하는 버그를 겪었다 |
| A* 우회 복귀(`autopilotRendezvousToward`) | **가져올 수 없음** | 이 프로젝트에 경로 탐색이 없다(`action_rpg_game.dart:973-975`). 대체 설계 필요(§3.4) |
| eligible 게이트 · EXP 균등 분배 · 드롭 라운드로빈 | **버림** | §3.5 판정 |

### 3.4 추종 & 자동 사냥 — 클라 실행, 서버 상태

**판정: 실행은 클라. 근거는 세 겹이다.**
1. 서버에 이동 시뮬레이션이 없다(`world.rs:132-139`가 그 절충을 명시적으로 선언한다).
2. 유일한 주기 작업은 5초 리스폰(`MONSTER_TICK_SECS: u64 = 5`).
3. 클라에 이미 필요한 부품이 있다 — `moveAnchor`(`auto_hunt.dart:157`), `pursuitTimeout`(88), 차단 목록(93), `forget`(292).

**앵커 소유권 — 반드시 답해야 하는 부분.**

지금 앵커를 쓰는 주체는 하나(수동 자동사냥)뿐이라 소유권 개념이 없다. 추종이 들어오면 넷이 경쟁한다:

| 호출 지점 | 지금 동작 | 추종 중일 때 |
|---|---|---|
| `toggleAutoHunt` (`:662`) | 현재 자리에서 켠다 | **추종을 끄고** 수동으로 전환 (명시적 인간 의사) |
| `movePlayerToWorldPoint` (`:992`) | 앵커를 클릭 지점으로 | **무시** + 배너 "추종 중에는 사냥터를 옮길 수 없다" |
| `teleportPlayerTo` (`:1231`) | 앵커를 도착지로 | 추종 해제(§ 리더 텔레포트) |
| `onPlayerDied` (`:1385`) | `autoHunt.disable()` | 추종 플래그는 유지, 리스폰 후 거리 판정 |

라리엔이 도달한 결론과 같다 — **추종은 개인 자동사냥보다 상위 제어권**(`autopilot.go:269-281`, `:389`). 이것을 `AutoHuntController` 안에 넣지 말고 **소유자 표시를 바깥에 둔다**: 신규 `PartyFollowDriver` 가 `isFollowing` 을 들고, 위 네 지점에는 `if (partyFollow.isFollowing) { ... }` 가드 한 줄씩만 넣는다. `auto_hunt.dart` 는 손대지 않아도 된다.

**추종 루프의 판단 순서** (라리엔의 분기 순서를 그대로 따른다):

```
1. 리더가 presence.others 에 없다        → 세션 종료(접속종료/월드 이탈)
2. 리더 alive == false                   → 앵커 갱신만 건너뜀 (세션 유지)
3. 리더와의 거리 > rejoinDistance(예 25 타일)
   → 사냥 중단, player.moveTo(리더 좌표) 로 직행. autoHunt 는 suspended
   → 이 상태가 rejoinTimeout(예 8초) 넘도록 안 좁혀지면
     → 추종 일시중단 + 배너 "리더를 놓쳤다" (경로 탐색이 없어 벽 뒤면 영영 못 붙는다)
4. 그 안이면 autoHunt.moveAnchor(리더 좌표) → 기존 사냥 로직이 리더 주변을 돈다
```

3 번이 라리엔의 "탐색보다 먼저 복귀" 이고, 그 안의 타임아웃이 **A* 가 없는 이 프로젝트의 대체물**이다. 라리엔은 우회 경로를 찾아 붙지만 우리는 붙지 못한다는 것을 인정하고 사용자에게 알리는 편이 정직하다.

**리더 텔레포트** — 가장 까다로운 지점이다. `move_to` 속도 상한이 14 타일/초(`world.rs:139`)라서 follower 를 코드로 순간이동시키면 **화면과 서버 좌표가 갈린다**(서버가 갈 수 있는 데까지만 당겨 받는다 — `world.rs:686-696`). 그런데 `teleport_to` 는 좌표가 아니라 **목적지 이름 5 개**만 받는다(`world.rs:712,743-781`). 그래서:
- 리더가 텔레포트하면 `PartyLead` 에 목적지 이름을 기록(선택)하고,
- follower 에게 "리더가 `north` 로 이동했다 — 따라가겠는가" 를 띄워 **follower 본인이 같은 이름으로 `teleport_to`** 를 부르게 한다. 쿨다운 8 초는 서버가 강제한다.
- 자동으로 끌고 가지 않는다. 그것이 서버 규약을 우회하지 않는 유일한 길이다.

**follower 사망** — 안전지대 리스폰이므로 리더가 사냥터 깊숙이 있으면 거리가 수백 타일이 된다. 라리엔은 "부활 후 자동 재개"(`party.md:375`)지만 그건 A* 와 서버 권위가 있어서다. 여기서는 **리스폰 직후 거리 판정 → `rejoinDistance` 를 크게 넘으면 추종 일시중단**이 맞다. 그러지 않으면 안전지대에서 사냥터까지 무방비로 자동 횡단하다 다시 죽는다 — `onPlayerDied` 가 자동 사냥을 끄는 이유와 같은 이유다(`action_rpg_game.dart:1383-1386`).

### 3.5 문서 충돌 — 판정과 개정 문구

**판정: 선점 태그와 `award_kill` 을 그대로 둔다. 파티는 동행·추종 전용.**

세 가지 이유가 겹친다.

1. **서사 정합성** — "남이 선점한 몹을 뺏고 싶으면 그 사람을 쓰러뜨려라"(`world.rs:16-17`, `GAME-DESIGN.md:715-716`)가 PK 의 유일한 동기다. 파티 분배를 넣으면 파티가 곧 상호 PK 면제 구역이 되어 이 동기가 소멸한다.
2. **기술적 공허함** — `award_kill`(`world.rs:912-970`)은 `attack_monster` 경로 위에 있는데 클라이언트는 그것을 부르지 않는다. 실제 경험치는 클라 로컬 `onEnemyKilled` → `player.gainXp` → `sync.reportLevel` → `report_progress`(`leaderboard.rs:288`)로 흐른다. **지금 파티 분배를 넣으면 아무도 지나가지 않는 길에 표지판을 세우는 일이다.**
3. **MMORPG 규모에서의 악용** — 자동 사냥 + 추종은 "여러 계정이 한 사람 뒤를 따라다니는 봇 파티" 를 매우 쉽게 만든다. 서버는 전투를 보지 않으므로(`leaderboard.rs:276-284`가 그 한계를 명시한다) 이를 막을 수단이 없다. **분배가 없으면 버스 태우기의 이득 자체가 사라진다** — 각자 자기 몹을 자기가 때려야 하므로 계정 수만큼 노동이 늘 뿐이다. 분배를 도입하지 않는 판단이 이 위험의 최선 방어다.

**개정 문구 제안:**

`CLAUDE.md:33-34` 를 아래로 교체:
```markdown
- A party is for travelling and hunting together, not for sharing rewards.
  Kill credit stays solo: the first attacker owns the monster and the experience
  goes to that owner alone. There is no shared damage credit and no party loot rule.
- Any member may lead a hunt; the others may follow that leader and auto-hunt
  around them. Each follower still earns only their own kills.
```
`CLAUDE.md:38` 뒤에 한 줄 추가:
```markdown
- PK stays allowed between party members. Membership grants no protection —
  it shares position and a follow anchor, nothing else.
```
`GAME-DESIGN.md:781` 행을 아래로 교체:
```markdown
| 솔로 보상 (파티는 동행 전용) | ✅ 선점 태그 기반 단독 크레딧. 파티는 위치 공유·추종만 제공하며 경험치·드롭을 나누지 않는다 |
```
`world.rs` 머리말(`:10-27`)에 한 단락 추가 — "파티가 생겨도 이 규칙은 그대로다. 파티는 함께 다니게 할 뿐 크레딧을 나누지 않으므로, 사냥터 다툼과 PK 동기가 파티 안에서도 유지된다."

## 4. 리스크 · 함정

- **`lib/spacetime/generated/` 재생성 충돌 (최대 위험).** 파티 표를 추가하면 코드 생성을 다시 돌려야 하는데 이 디렉토리는 통째로 다시 쓰인다. 다른 팀도 `world_player.dart` 를 위해 이미 한 번 돌렸다. 두 팀이 각자 다른 시점의 서버 스키마로 재생성하면 **서로의 새 표가 조용히 사라진다**. 반드시 "서버 배포 → 한 사람이 재생성 → 커밋" 순서를 합의해야 한다.
- **`action_rpg_game.dart` 가 실시간으로 바뀌고 있다.** 이 분석 도중 생성자가 바뀌었다. 우리 배선은 3~5 줄로 묶고, 그들이 만지는 `update()` 꼬리(`presence.report`·`_syncRemotePlayers`)·`_updateCamera`·`_zoomForSize`·`_layoutTouchControls` 를 피해 `_updateAutoHunt` 앞에 한 줄만 넣는다.
- **파티 view 에 좌표를 담으면 서버가 죽는다.** `world_player` 는 접속자 수 × 초당 5회로 갱신된다. view 가 그것을 읽으면 매 갱신마다 전 파티 구독자에게 재푸시된다. 리더보드 주석(`cyborg_connection.dart:44-47`)이 같은 함정을 이미 기록해 뒀다.
- **`auto_inc` id 를 정렬·순번에 쓰지 말 것** — 연속이 보장되지 않는다. 파티 목록의 순서 기준은 `joined_at` + `character_id` 로 정한다(`leaderboard.rs:191-197` 의 동점 처리 패턴과 같은 이유).
- **RemotePlayerEntity 는 다른 팀 파일이다**(`lib/game/entities/remote_player.dart`, untracked). 파티원 왕관·색 구분을 이 파일 안 `_renderNameplate`(`:149-185`)에 넣으면 확실히 충돌한다. → 파티 표식은 **별도 오버레이 컴포넌트를 world 에 add** 해 파티원 좌표 위에 마커를 얹는 방식으로 우회한다.
- **`hud.dart` 미니맵도 다른 팀 구역이다**(`:483-503`). 파티원을 미니맵에 다른 색으로 찍고 싶어도 지금은 손대지 말고, 그들 작업이 커밋된 뒤 별도 턴으로.
- **속도 상한 위반** — follower 를 코드로 텔레포트시키면 서버가 좌표를 잘라(`world.rs:686-696`) 화면과 서버가 갈린다. 눈에 보이는 증상이 "다른 사람 화면에서만 내가 뒤처져 있다" 라 발견이 매우 늦다.
- **파티 인원 상한 미정.** 라리엔은 32명(`party.md:13`)이지만 그건 Flutter overlay HUD 기준이다. 여기는 Flame `PositionComponent` 캔버스라(`world_menu.dart:37`) 목록 스크롤·클리핑을 직접 그려야 한다. 초기엔 4~6 명이 현실적이다.
- **파티원 PK 허용 여부는 사람이 정할 문제다.** 기존 철학(`CLAUDE.md:38`)의 기본값은 "허용" 이지만, 추종 중 오폭이 일어나면 체감이 나쁘다.
- **`world_player` 전량 구독은 파티와 무관한 공통 과제**다. `SELECT * FROM world_player` 는 접속자 전원의 좌표를 받는다. 수천 명 월드에서는 AOI 필터가 필요해지지만 이는 다른 팀 영역이며, 파티가 그 문제를 만들지도 해결하지도 않는다.

## 5. 권고안

| 순위 | 권고 | 범위 | 근거 | 리스크 |
|---|---|---|---|---|
| 1 | **파일 경계를 먼저 문서로 합의**한다 — 우리 소유: `spacetimedb/src/party.rs`, `lib/game/net/party_session.dart`, `lib/spacetime/spacetime_party.dart`, `lib/game/systems/party_follow.dart`, `lib/game/ui/party_panel.dart`, `test/party_*.dart`. 다른 팀 소유: `world_presence.dart`, `spacetime_world_presence.dart`, `remote_player.dart`, `world_tree.dart`, `hud.dart` 미니맵, `action_rpg_game.dart` 의 카메라·줌·렌더 | 협업 규약 | 세션 중 `action_rpg_game.dart:64-74` 가 실제로 변경됨 | 합의 없이 진행하면 rebase 지옥 |
| 2 | **문서부터 개정**한다(`CLAUDE.md:33-34,38`, `GAME-DESIGN.md:781`, `world.rs` 머리말). §3.5 의 문구를 그대로 쓴다 | 기획 문서 | `CLAUDE.md:33-34` 와 요청이 정면 충돌 | 코드 0줄이므로 충돌 없음. 먼저 해 두어야 이후 리뷰가 "규칙 위반" 으로 반려되지 않는다 |
| 3 | **서버 `party.rs` 신규 모듈** — §3.2 의 4 표 + `create_party`/`invite_to_party`/`accept_invite`/`decline_invite`/`leave_party`/`disband_party`/`promote_leader`/`kick_member`/`start_hunt_lead(leash)`/`accept_hunt_lead(seq, leader_id)`/`stop_hunt_lead`. 기존 파일 수정은 `lib.rs` 에 `pub mod party;` 한 줄과 `on_disconnect` 에 lead 세션 정리 한 줄 | `spacetimedb/` | `world.rs:900-906` `require_world_player` 패턴, `character.rs:109-137` 소유자 검증 패턴 | 스키마 마이그레이션 — 새 표라 기존 열 변경은 없다 |
| 4 | **view 는 멤버십만.** `my_party` → `Vec<PartyMemberEntry>`(비공개 표로 선언, 행 미삽입), `my_party_invites`. 좌표·HP 는 절대 넣지 않고 클라가 `presence.others` 와 `characterId` 로 조인 | `spacetimedb/` + 구독 | `leaderboard.rs:151-181`, `cyborg_connection.dart:44-47` | view 를 잘못 설계하면 되돌리기 어렵다(구독자 전원 재푸시) |
| 5 | **클라 `PartySession` 추상화** — `WorldPresence` 와 **똑같은 패턴**으로 인터페이스는 `lib/game/net/party_session.dart`, SpacetimeDB 구현은 `lib/spacetime/spacetime_party.dart`. `ActionRpgGame` 생성자에 `PartySession? party` 한 개 추가(기본값 `OfflinePartySession`) | `lib/game/net/`, `lib/spacetime/` | `world_presence.dart:40-71` 이 그 패턴의 완성된 예시 | 생성자 한 줄이 다른 팀의 `presence` 추가와 같은 줄 근처 — 커밋 타이밍 조율 |
| 6 | **`PartyFollowDriver` 신규 파일** — `auto_hunt.dart` 처럼 **판단만 돌려주고 실행은 호출부**가 한다(Flame 비의존 → 순수 유닛 테스트 가능). §3.4 의 4 단계 판단 순서를 그대로 구현. `auto_hunt.dart` 는 수정하지 않는다 | `lib/game/systems/` | `auto_hunt.dart:23-39` 판단/실행 분리 철학, `autopilot.go:358-380` 분기 순서 | 없음(신규 파일) |
| 7 | **`action_rpg_game.dart` 최소 배선 (3~5줄)** — `update()` 안 `_updateAutoHunt(dt)` 바로 앞에 `_updatePartyFollow(dt)` 한 줄, `toggleAutoHunt`·`movePlayerToWorldPoint`·`teleportPlayerTo`·`onPlayerDied` 에 가드 한 줄씩 | `lib/game/` | 앵커 경쟁 지점 `:662,992,1231,1385` | 다른 팀과 같은 파일 — 마지막에 짧게 |
| 8 | **Flame 파티 UI 신규 파일** — `WorldMenu`(`world_menu.dart:37-120`)의 `PositionComponent + TapCallbacks + _MenuScrim` 패턴을 복제. 파티원 표식은 RemotePlayerEntity 를 고치지 말고 별도 오버레이 컴포넌트로 | `lib/game/ui/` | `world_menu.dart:33-36` "Flutter 위젯이 아니라 viewport HUD" | 히트테스트가 `ClickMoveLayer` 와 겹치면 탭이 월드로 샌다 — `TapShield`(`action_rpg_game.dart:492-506`) 패턴 필요 |
| 9 | **경험치 분배는 하지 않는다.** `award_kill`(`world.rs:912-970`)·`tagged_by` 를 그대로 둔다 | 판정 | `world.rs:10-27`, `attack_monster` 클라 호출 0건, 봇 파티 위험 | 나중에 서버 전투 권위가 붙은 뒤 별도 결정 사항으로 남긴다 |

**검증안 (CLAUDE.md:49-52 준수 — 키/클릭 주입 없음)**

| 단계 | 검증 방법 | 근거 |
|---|---|---|
| 서버 순수 함수·권한 | `cd spacetimedb && cargo test` — 초대 만료·인원 상한·비리더 추방 거부·`leadSeq` 불일치 거부 | `character.rs:169-197` 테스트 패턴 |
| 추종 판단 | `flutter test test/party_follow_test.dart` — 좌표만 가진 가짜 리더로 4 단계 분기를 전부 검사. Flame 불필요 | `test/auto_hunt_test.dart:6-37` 의 `_Mob` 패턴 그대로 |
| **다른 팀 구현이 없는 동안의 주입** | `class FakeWorldPresence extends WorldPresence { List<RemotePlayer> others = []; ... }` — `WorldPresence` 가 abstract 이고 모든 메서드에 기본 구현이 있어 **그들 파일을 한 줄도 고치지 않고** 상속만으로 된다. `PartySession` 도 같은 방식 | `world_presence.dart:40-71` |
| 2 인 파티 실서버 | `test/party_integration_test.dart` — `InMemoryTokenStore()` 로 client 두 개를 만들어 서로 다른 identity 확보 → 각각 가입·캐릭터·`enter_world` → A 가 `create_party`+`invite` → B 가 `accept` → 양쪽 `my_party` 가 2 명인지 확인. **사람 손이 전혀 필요 없다** | `test/spacetime_integration_test.dart:31-40` |
| 화면 확인 | `main()`/`initState()` 에 `debugSeedParty()` 를 주입해 파티 패널이 뜬 상태로 앱을 띄우고 스크린샷 + `flutter run` 로그 확인. 클릭·키 입력 주입 없음 | `CLAUDE.md:49-52`, 라리엔도 동형(`party.md:257` `party_dtd_inject.dart`) |
| 정적 | `flutter analyze` error/warning 0 | 프로젝트 관행 |

## 6. 불확실 · 미확인

- **SpacetimeDB 구독 쿼리의 `WHERE` 지원 여부** — 코드에는 `SELECT * FROM x` 만 있다(`cyborg_connection.dart:28-51`). 필터 구독이 되면 view 없이 `party_member` 를 직접 좁혀 구독할 수 있어 설계가 단순해지지만, 파라미터 바인딩이 가능한지 실측하지 못했다. **view 경로가 확실히 되는 길**이라 그쪽을 권고했다.
- **view 재계산 트리거의 정확한 규칙** — "누가 레벨업하든 재계산" 은 주석(`cyborg_connection.dart:44-47`)에서 읽은 것이고, 어떤 표 변경이 어떤 view 를 무효화하는지 실측하지 못했다. §4 의 "view 에 좌표 넣지 말라" 는 이 주석에 근거한 보수적 판단이다.
- **`flutter analyze` / `cargo test` 현재 통과 여부** — 읽기 전용이라 실행하지 못했다. 특히 `action_rpg_game.dart` 는 분석 도중 변경됐으므로 현재 상태를 보장할 수 없다.
- **다른 팀의 잔여 작업 범위** — ①②③ 은 코드에 있으나 ④(줌 버튼 컴포넌트)는 없다. 그들이 `_layoutTouchControls`·`_addTouchControls` 를 더 만질 것이므로 우리 UI 버튼도 그 함수에 넣지 말고 자체 컴포넌트가 스스로 자리를 잡게 해야 한다(`InventoryPanel`·`BuffBar` 가 그렇게 한다 — `action_rpg_game.dart:473`).
- **`GAME-DESIGN.md:784` 의 "몬스터 240기" 와 `world.rs:108` 의 `MONSTER_CAPACITY = 12,000`** 이 어긋난다. 파티와 직접 관계는 없지만 문서가 코드보다 낡았다는 신호이므로 문서 개정 시 함께 확인할 가치가 있다.
- **사람이 정해야 하는 것 세 가지** — ⓐ 파티 최대 인원(권고 4~6), ⓑ 파티원 간 PK 허용 여부(기존 철학상 기본값은 허용), ⓒ 리더 텔레포트 시 follower 동반 방식(권고: 자동 아님, 같은 목적지 이름으로 본인이 호출).
- **`.cowork/party-follow/.grok-pass1.md` · `.grok-pass2-prompt.md`** 에 다른 AI 의 선행 분석이 이미 있다. 그 문서들은 "월드 연결이 선행 과제" 라는 전제로 쓰였는데 §3.1 에서 확인했듯 그 전제는 이미 낡았다 — 종합 시 그 부분은 채택하지 않는 편이 맞다.
�� `DEV_PARTY_ROLE=leader|follower` 같은 주입 변수를 `lib/dev/dev_login.dart:32-46` 패턴으로 더해, 앱이 스스로 파티 초대/수락/추종 시작 핸들러를 호출하게 한다 |
| 결과 확인 | 로그 + 스크린샷 | `devLog`(`dev_login.dart:103-107`)에 파티 단계를 찍고 `grep DEV-PARTY build/run-logs/*.log`. 창이 바둑판으로 배치되므로(`run.sh:212-214`) 리더 창과 follower 창을 한 화면에서 비교할 수 있다 |

---

## 6. 불확실 · 미확인

- **`world_player` 구독의 공간 필터링 가능 여부.** SpacetimeDB 2.7 의 구독 SQL 에 `WHERE grid_x BETWEEN ... ` 같은 범위 조건을 걸어 시야 밖 플레이어를 제외할 수 있는지 확인하지 못했다. 불가능하다면 동시접속이 늘 때 전 플레이어 델타를 다 받게 되어 파티 이전에 이 문제가 먼저 터진다. **파티 설계보다 먼저 확인해야 할 사항이다.**
- **파티 최대 인원.** 라리엔은 32명(`protocol/party.dart:13`)이지만 actionrpg 에 맞는 값은 사람이 정해야 한다. view 결과 크기와 HUD 표시 밀도가 여기에 걸린다.
- **사용자가 기대한 범위.** 요청은 "파티 + 추종 사냥" 이지만, 이 코드베이스에서 그것이 실제로 보이려면 §5 권고 1(멀티플레이 배선)이 선행되어야 한다. **그 선행 작업까지 이번 범위에 포함하는지, 아니면 파티 스키마만 먼저 얹고 배선은 다음으로 미루는지는 사람의 판단이 필요하다.**
- **라리엔 Zone 서버 Go 코드(`sim/party.go`·`sim/autopilot.go`)를 직접 열지 않았다.** `docs/party.md` 의 서술과 클라이언트 쪽 `protocol/party.dart`·`party_controller.dart` 만 읽었다. `updatePartyFollowAnchors` 의 구현 세부(앵커 갱신 주기·리더 사망 판정의 정확한 조건)는 문서 서술에 의존한 것이므로, 그 부분을 그대로 옮기려면 원본 확인이 필요하다.
- **`lib/game/ui/hud.dart` 전체를 읽지 않았다.** 클래스 구조(`Hud extends PositionComponent`, `hud.dart:14`)와 렌더 진입점만 확인했다. 파티 패널을 어느 레이어·어느 우선순위에 넣을지는 실제 레이아웃을 열어 봐야 정할 수 있다.
- **`lib/game/entities/player.dart` 의 벽 끼임 감지 동작**을 직접 확인하지 않았다(`action_rpg_game.dart:560-562` 의 주석으로만 알고 있다). 추종 중 리더가 벽 너머에 있을 때 follower 가 스스로 포기하는지는 그 구현을 열어야 판정할 수 있다 — `[추측]` 으로 남긴다.
- **`server/` 디렉토리는 보지 않았다.** 시스템 프롬프트가 "쓰이지 않는 옛 스캐폴드" 라고 명시했으므로 근거에서 제외했다.
