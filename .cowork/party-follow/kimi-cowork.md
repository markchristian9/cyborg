<!-- cowork:kimi | 2026-08-05 19:30:17 | exit=0 | 554s -->
# kimi 분석 — party-follow

> 요청: 파티 초대, 파티 이끌기, 파티 리더 추종하기, 추종하며 자동 공격, 파티 해체, 파티 초대 등의 기능이 올바로 동작하는지, 수정/보완할 내용이 있으면 수정보완해주세요.

[현재 구현 상태 — 반드시 이 전제로 분석하라]

**구현되어 있는 것(1차, 커밋 a098971·b35398b):**
- 서버 spacetimedb/src/party.rs: 표 3(Party·PartyMember·PartyInvite), reducer 9(create_party·invite_to_party·accept_invite·decline_invite·leave_party·disband_party·kick_member·promote_leader·set_following), view 3(my_party·my_party_members·my_party_invites). MAX_PARTY_SIZE=12, 초대 TTL 20초
- 클라: lib/game/net/party_session.dart(PartySession 추상) · lib/spacetime/spacetime_party.dart(SpacetimePartySession) · lib/game/systems/party_follow.dart(PartyFollowController 5분기 판단) · lib/game/ui/party_panel.dart(PartyPanel + PartyInviteCard) · action_rpg_game.dart 배선
- 추종은 **party.leader_character_id 고정**(set_following(true) → 파티장을 따름). 파티장 본인은 추종 불가
- 초대 진입점은 PartyPanel 의 '근처 요원 목록'(40타일 이내) — 목록에서 눌러 초대

**구현되어 있지 않은 것 — grep 으로 0건 확인됨:**
- '파티 이끌기'(hunt lead) 전혀 없음. hunt_lead 문자열 0건. 즉 '누가 이끌기를 시작하면 다른 팀원에게 follow 버튼이 뜨는' 흐름이 없다
- 원격 PC 클릭 없음(remote_player.dart 에 TapCallbacks 0건). 하단 컨텍스트 액션바 없음
- 교환 기능 없음(서버에 인벤토리/아이템 표 0건)

**직전 라운드에서 검증된 결함 2개(아직 미수정):**
1. **AOI 경계에서 추종이 끊긴다** — lib/spacetime/cyborg_connection.dart 의 worldSubscriptionsFor() 가 world_player 를 '자기 청크 + 이웃 8칸'만 구독하는데, action_rpg_game.dart 의 _followTarget() 은 presence.others 에서 리더를 못 찾으면 lost 로 판정해 추종을 끊는다. 리더가 청크 경계를 넘는 순간 '월드에서 사라졌다'로 오판한다. AOI 는 파티 구현 이후에 들어와서 생긴 결함이다.
2. **spacetime_party.dart 의 changes 가 my_party 를 듣지 않는다** — Listenable.merge([_memberRows, _inviteRows]) 뿐이라 Party 행만 바뀌는 변화는 UI 에 반영되지 않는다.

[이번에 답할 것 — '올바로 동작하는가' 의 실증]

이번 요청의 핵심은 **동작 검증**이다. 위 목록에 없는 결함을 코드를 읽어 찾아내라. 특히 다음 시나리오를 코드 경로로 추적해 실제로 성립하는지 판정하라. 성립하지 않으면 어디서 끊기는지 파일:줄로 지목하라.

(가) A 가 B 를 초대 → B 화면에 초대 카드가 뜨는가? (초대 만료 20초의 화면 처리, 수락 후 양쪽 파티 목록 갱신, 서버 거절 사유가 화면에 보이는가)
(나) B 가 파티장 추종을 켜면 실제로 A 를 따라가는가? (set_following → following_character_id → _followTarget → AutoHuntController.moveAnchor 경로가 끊김 없이 이어지는가)
(다) 추종 중 자동 공격이 실제로 일어나는가? — 자동 사냥이 로컬 Enemy 를 때리는지 서버 몬스터를 때리는지, attack_monster 가 호출되는지, 추종 중 사냥 앵커가 리더를 따라가면서 사냥이 이어지는지
(라) 파티 해체(disband)·탈퇴(leave)·추방(kick) 시 추종 중이던 파티원의 상태가 정리되는가? 서버와 클라 양쪽에서
(마) 파티장이 접속을 끊으면? on_disconnect 는 world_player 만 지운다 — 파티와 following 이 남는가? 남으면 어떤 증상이 되는가
(바) 파티원이 죽었다 살아나면 추종이 재개되는가?
(사) 파티가 12명 정원일 때·이미 다른 파티에 있는 사람을 초대할 때 화면에 무엇이 보이는가

[그리고 미구현 기능]
'파티 이끌기'는 사용자가 이번에도 명시했으므로 만들어야 한다. 직전 라운드 종합의 결론은 다음과 같았다 — 이 설계가 여전히 타당한지 재검증하고, 더 나은 안이 있으면 반증하라:
- Party 행 맨 끝에 hunt_lead_character_id: Option<u64> #[default(None::<u64>)], hunt_lead_seq: u64 #[default(0u64)], hunt_lead_name: String #[default("")] 추가 → 파티당 세션 1개가 구조로 강제되고, 파티원 전원이 이미 my_party 를 구독하므로 행 변경이 곧 방송이다(별도 초대 표 불필요)
- reducer 3: start_hunt_lead(파티원 누구나, seq+1) · stop_hunt_lead(리더만, follower 전원 해제) · accept_hunt_lead(lead_seq 검증)
- set_following(true) 의 파티장 고정은 폐기, accept_hunt_lead 가 대체
- AOI 우회용 view my_hunt_lead_target(리더 좌표·생사만) 추가

[제약]
- CLAUDE.md: DTD 기반 검증, 키보드/클릭 주입 금지, main()/initState() 주입 + 스크린샷·로그
- 이미 배포된 표에 열 추가는 맨 끝 + #[default] 필수
- lib/spacetime/generated/ 는 서버 배포 후 재생성해야 하며 다른 세션과 충돌 위험이 있다
- 라리엔 /Users/thruthesky/apps/game/laryen 는 읽기 전용 참고(docs/party.md §10.5 hunt lead)
> 생성: 2026-08-05 19:30:17 · 소요 554s · 읽기 전용 분석(작업공간 미수정)

---

• 마지막으로 몇 군데를 확인한다.

• 

## 1. 결론 요약

  (가)~(다)의 기본 경로는 **코드상 끊김 없이 이어진다** — 초대 카드 표시·수락·추종·추종 중 서버 몬스터 자동 공격(`attack_monster`)까지 실증됐다. 그러나 시나리오를 끝까지 밀면 새 결함 4개가 나온다: ① **파티가 있는 상태에서는 추가 초대 UI 자체가 없어** 사실상 2인 파티가 상한이다, ② **파티장이 접속을 끊으면 초대·해산·위임을 아무도 못 하는 "얼어붙은 파티"가 된다**, ③ 추방(kick)은 서버·세션 추상까지 있으나 **UI 진입점이 없는 사장 코드**다, ④ 초대·위임이 **낙관적 배너를 먼저 띄워** 서버 거절 시 모순된 안내가 나간다. 직전 라운드 결함 2건 중 `changes` 결함은 **현재 소비자가 없어 무영향**으로 하향 조정한다. '파티 이끌기' 설계는 대체로 타당하나, `_followTarget()` 이 `following_character_id` 를 보지 않는다는 필수 변경이 빠져 있었고, AOI 우회는 서버 view 추가 없이 **공개 표 `world_player` 에 대한 직접 구독**으로 더 간단히 해결할 수 있다(반증 성립).

  

## 2. 근거

  - `spacetimedb/src/party.rs:241-335` — `invite_to_party`: 대상 월드 재재·타 파티 소속·정원 검사와 거절 문장이 모두 있다("상대가 이미 다른 파티에 있다." 등).
  - `lib/game/ui/party_panel.dart:126-130` — `_rows`: `party.inParty` 이면 멤버 목록만, 아닐 때만 '근처 요원' 초대 목록. **파티 중 추가 초대 경로 없음.**
  - `lib/game/ui/party_panel.dart:422-432` — `_onRowSelected`: 파티 중 리더의 위임(promote)뿐. kick 호출 없음.
  - `lib/game/ui/party_panel.dart:490-496` — `PartyInviteCard._invite`: 만료 초대를 클라이언트 시계로 매 프레임 걸러 냄. 카드는 Flame render 루프에서 매 프레임 갱신.
  - `lib/game/action_rpg_game.dart:937-941` — `invitePlayerToParty`: reducer 결과 전에 `'$name 님을 초대했다'` 낙관 배너. 거절 시 `_runPartyAction`(982-992)의 오류 배너와 중복·모순.
  - `lib/game/action_rpg_game.dart:845-902` — `_updatePartyFollow` → `_followTarget()`: **presence.others 에서 `party.leaderCharacterId` 를 찾는다**(자기 `followingCharacterId` 를 보지 않음). 못 찾으면 lost.
  - `lib/spacetime/cyborg_connection.dart:41-44, 82-100` — `world_player` 구독은 74타일 청크 자기 칸 + 이웃 8칸. 리더가 이 범위를 벗어나면 `presence.others` 에서 사라진다(AOI 결함 기계적 확인: 재합류 구간 25~120타일 중 ~74타일 이상에서 lost 오판 가능).
  - `lib/game/action_rpg_game.dart:877-884` — anchor 판정 시 `autoHunt.enable/moveAnchor`. 추종의 실체는 자동 사냥 앵커 이동임을 확인.
  - `lib/game/entities/enemy.dart:539-542` — 서버 주도 몹(`isServerDriven`)은 로컬 HP 를 깎지 않고 `game.presence.attack(serverId!)` 만 호출.
  - `lib/spacetime/spacetime_world_presence.dart:329-334` — `attack()` → `attackMonster` reducer 호출(fire-and-forget).
  - `spacetimedb/src/world.rs:1466-1508` — `attack_monster`: 사거리·쿨다운·생사를 서버 좌표로 판정하고 `player_damage(me.level)` 로 피해 계산. 클라이언트 계산 피해량은 무시됨.
  - `spacetimedb/src/lib.rs:235-242` — `on_disconnect` 는 `world_player` 행만 삭제. `Party`·`PartyMember`·`following_character_id` 는 그대로 남는다.
  - `spacetimedb/src/party.rs:279-281` — 초대는 파티장만 가능. 파티장 부재 시 승계는 `remove_member`(명시적 탈퇴·추방)에서만 일어난다(757-780).
  - `lib/game/action_rpg_game.dart:1783-1800` — `onPlayerDied`: 자동 사냥은 끄지만 **추종 상태는 건드리지 않고** 즉시 안전지대 리스폰.
  - `lib/spacetime/spacetime_party.dart:42-47` + `lib/game` 전체 grep — `changes` 는 `_memberRows`·`_inviteRows` 뿐이나, **`party.changes` 의 소비자가 코드베이스에 0건**(leaderboard 는 자체 source). PartyPanel 은 매 프레임 render/update 로 갱신.
  - `lib/game/action_rpg_game.dart:1016` — 추종 시작이 `unawaited(party.setFollowing(true))` 로 `_runPartyAction` 우회. 서버 거절 시 조용히 실패(시작 배너는 이미 출력).
  - `lib/game/action_rpg_game.dart:1653-1656` — 로그아웃 시 `presence.leave()` + `party.detach()` 만. 탈퇴 아님(의도된 설계).

  

## 3. 상세 분석

  ### 시나리오 판정

  **(가) 초대 → 카드 → 수락: 성립.** 초대 reducer 의 검증과 거절 문장이 완비돼 있고(`party.rs:244-268`), view 3종이 `kPartySubscriptions`(`cyborg_connection.dart:121-125`)로 구독되며, 카드는 매 프레임 `_invite` 를 다시 읽어 만료를 화면에서 걸러 낸다(`party_panel.dart:490-496`). 수락 시 양쪽 모두 `my_party_members` 행 변화로 갱신된다. 서버 거절 사유는 `_runPartyAction` 이 배너로 띄운다(`action_rpg_game.dart:985-988`). **단, 초대·위임은 성공 배너를 먼저 띄우고**(937-939, 956-958) 실패 시 오류 배너가 뒤따라, 사용자는 "초대했다" + "상대가 이미 다른 파티에 있다" 를 연속으로 본다.

  **(나) 추종: 경로는 성립, 두 곳이 약하다.** `togglePartyFollow`(995-1017) → `set_following` → 멤버 행 → `isFollowing` → `_updatePartyFollow` → `_followTarget` → `autoHunt.enable/moveAnchor` 로 끊김 없이 이어진다. 약점: ① AOI — 리더가 청크 구독 범위(±1 청크, 74타일 단위)를 벗어나면 `presence.others` 에서 사라져 `party_follow.dart:161-167` 의 lost 판정이 실제 단절이 아닌데도 발동한다(직전 결함 1, 기계적으로 재확인). ② 시작 호출이 오류 표면화를 우회한다(1016행) — 파티 행이 아직 구독 캐시에 없는 타이밍에 누르면 "추종 시작" 배너만 남고 조용히 실패한다.

  **(다) 추종 중 자동 공격: 성립.** 화면의 몹은 서버 주도(`serverId` 부여, `action_rpg_game.dart:1291`)이고, 자동 사냥 근접 타격은 `enemy.applyDamage` → `presence.attack` → `attack_monster` 로 이어진다(`enemy.dart:539-542`, `spacetime_world_presence.dart:333`). 피해 판정은 전적으로 서버(`world.rs:1489-1508`). 재합류(rejoin) 중에는 `_updateAutoHunt` 가 `partyFollow.isRejoining` 을 보고 정지하고(789행), anchor 에 붙으면 앵커가 리더를 따라가며 사냥이 계속된다. 선점 태그는 각자 몫이라 파티와 무관하게 일관된다.

  **(라) 해체·탈퇴·추방: 서버 정리는 정확, 클라 알림이 비어 있다.** `remove_member` 가 탈퇴자를 따르던 이들의 `following_character_id` 를 해제하고(`party.rs:784-796`), 파티장 탈퇴 시 승계 + 새 리더의 추종 해제까지 처리한다(757-780). 해산은 전원 삭제(436-464). 클라는 멤버 행 소멸 → `isFollowing == false` → `_updatePartyFollow` 초기화(846-851)로 자연 정리된다. **단, 추방당한 본인에게는 아무 알림이 없다** — 멤버 행이 사라질 뿐이라 패널이 조용히 '근처 요원' 모드로 바뀐다. 그리고 kick 은 UI 가 없어 이 정리 코드에 도달하는 사용자 경로 자체가 없다.

  **(마) 파티장 접속 끊김: 팔로워는 자기치유, 파티는 동결.** 팔로워는 리더가 `presence.others` 에서 사라져 lost → 스스로 `setFollowing(false)` 를 보내 정리된다. 그러나 `on_disconnect` 가 `world_player` 만 지우므로(`lib.rs:240`) 파티는 오프라인 리더를 그대로 모신다. 초대·해산·추방·위임은 전부 파티장 전용(`party.rs:279, 436-438, 473-475, 498-500`)이라, 리더가 돌아오기 전까지 **아무도 아무것도 못 하는 파티**가 된다. MMORPG 전제(수십~수천 명 상주)에서는 방치된 동결 파티가 누적된다.

  **(바) 사망 후 리스폰: 추종은 재개되나, 사망 방지 논리와 충돌 여지.** `onPlayerDied` 는 자동 사냥만 끄고 추종은 유지한다(1786-1789). 리스폰 직후 `_updatePartyFollow` 가 다시 돌며, 리더와의 거리가 120타일 이내면 rejoin/anchor 로 추종·사냥이 재개된다. 이때 25~120타일 구간에서는 **죽인 몹 무리를 가로질러 리더에게 걸어가는데**, 이는 `onPlayerDied` 가 자동 사냥을 끈 이유("자기를 죽인 무리 한가운데로 혼자 걸어 들어간다", 1786-1788 주석)와 정면으로 충돌한다. 120타일 초과 시에는 "너무 멀다" 로 추종이 끊긴다(`party_follow.dart:193-200`) — 안전지대와 사냥터가 멀면 사망 1회 = 추종 해제가 된다. 배너는 "자동 사냥 해제됨" 이라 했는데 anchor 가 곧 사냥을 다시 켜는 안내 불일치도 있다.

  **(사) 정원·타 파티 초대: 서버 문장은 화면에 도달하나, 그 상황에 도달할 UI 가 없다.** 파티 중에는 패널이 멤버 목록만 보여 주므로(`party_panel.dart:126-130`) 3번째 인원을 초대할 진입점이 없다. 즉 MAX_PARTY_SIZE=12 는 UI 상 도달 불가이며 사실상 2인 파티가 상한이다. "이미 다른 파티에 있다" 거절은 2인 파티 상태에서 상대를 초대할 수 없어 발생 경로가 좁고, 발생해도 낙관 배너와 모순된다((가) 참조).

  ### 직전 라운드 결함 2건 재검증

  - **결함 1(AOI 추종 단절): 실재 확인.** 74타일 청크 ±1칸 구독(`cyborg_connection.dart:87-100`) 대비 추종 재합류 구간이 25~120타일(`party_follow.dart:87-100`)이라, 리더가 ~74타일 이상 멀어지는 순간 구독 밖으로 나가 lost 오판이 가능하다.
  - **결함 2(`changes` 가 my_party 를 안 듣는다): 사실이나 무영향으로 하향.** `promote_leader` 처럼 Party 행만 바뀌는 경우(`party.rs:515-518`, 대상이 추종 중이 아니면 멤버 행 불변) `changes` 가 울리지 않는 것은 맞다. 그러나 `party.changes` 의 addListener 소비자가 0건이고 PartyPanel 은 매 프레임 상태를 다시 읽어 그리므로, 현재 증상은 없다. 계약 결함으로만 남긴다.

  ### '파티 이끌기' 설계 재검증

  직전 종합안은 골격이 유효하다 — `following_character_id` 가 처음부터 "누구를 따르는가" 로 설계돼 있어(`party.rs:112-122` 주석이 hunt lead 확장을 예고) 표 변경 없이 리더 외 추종이 가능하고, Party 행 끝 `#[default]` 열 추가도 마이그레이션 규칙에 맞다. 다만 세 군데를 보정해야 한다.

  1. **빠진 필수 변경: `_followTarget()` 의 대상 기준.** 현재 클라는 `party.leaderCharacterId` 를 따라간다(`action_rpg_game.dart:889-891`). hunt lead 가 파티장이 아니면 서버가 `following_character_id` 를 바꿔도 클라는 여전히 파티장을 따라간다. 자기 멤버 행의 `followingCharacterId` 로 바꾸는 변경이 설계안에 없었다.
  2. **`my_hunt_lead_target` view 의 반환 타입 제약.** Dart 생성기는 view 반환 타입을 테이블 목록에서만 찾으므로(cowork 제약), 새 struct 를 반환하면 깨진 코드가 나온다. 공개 표 `WorldPlayer`(`world.rs:282`)를 반환해야 하며, `my_world_player` view 가 이미 그렇게 동작 중이라(`spacetime_world_presence.dart:357` 주석) 전례가 있다.
  3. **더 나은 안(반증): view 신설 없이 공개 표 직접 구독.** `world_player` 는 공개 표라 `worldSubscriptionsFor` 가 직접 SQL 로 조회한다(`cyborg_connection.dart:100`). 따라서 `SELECT * FROM world_player WHERE character_id = <리더>` 구독을 추종 시작 시 추가로 거는 클라이언트 전용 변경으로 AOI 단절(결함 1)과 hunt-lead 좌표 채널을 동시에 해결할 수 있다. 서버 배포·생성 코드 재생성·세션 충돌 위험이 모두 사라진다. 노출 범위는 이미 공개인 world_player 와 동일해 프라이버시 회귀도 없다. 다만 리더가 바뀔 때마다 재구독 비용이 있고, `_maybeResubscribe`(`spacetime_world_presence.dart:206-249`)의 세대 관리와 같은 패턴이 필요하다.
  4. **라이프사이클 공백.** `remove_member` 가 hunt lead 본인의 탈퇴·추방·접속 끊김 시 `hunt_lead_character_id` 를 정리하는 경로, 그리고 lead 본인이 stop 을 부를 수 있는지(직전안은 "리더만")가 명시돼 있지 않다. `promote_leader` 의 팔로워 재지정(537-552)은 `old_leader` 를 따르는 이들만 건드리므로 hunt lead ≠ 파티장과는 충돌하지 않는다.

  

## 4. 리스크 · 함정

  - **동결 파티 누적**: 리더 접속 종료 시 승계가 없어, 멤버 전원이 수동 탈퇴하기 전까지 초대·해산이 불가능한 파티가 월드에 쌓인다. 세션 유지 설계(`lib.rs:229-234`)와 충돌하지 않는 선에서의 완화책이 필요하다.
  - **낙관 배너의 모순**: 초대·위임은 성공을 먼저 말하고, 추종 시작은 실패를 숨긴다. 세 경로의 일관성이 없어 사용자는 같은 종류의 조작에서 다른 피드백을 받는다.
  - **사망 → 추종 재개의 위험 회랑**: 리스폰 후 rejoin 이 죽은 장소 근처의 리더에게 그대로 걸어간다. giveUp 120타일이 유일한 안전장치다.
  - **2인 파티 상한**: 추가 초대 UI 부재는 "정원 12명" 테스트 자체를 불가능하게 한다. 서버 정원 로직은 검증 경로가 없는 셈이다.
  - **생성 코드 재생성 충돌**: Party 표 변경 시 `lib/spacetime/generated/` 재생성이 필요하고 다른 세션과 충돌 위험이 있다(제약에 명시). world_player 직접 구독안을 택하면 AOI 수정만큼은 서버 변경 없이 갈 수 있다.
  - **view 재계산 비용**: hunt lead 정보를 Party 행에 싣는 것은 멤버십 변경 시에만 밀려오므로 무해하나, 좌표를 view 에 싣는 순간 좌표 갱신마다 파티원 전원 재전송이라는 `party.rs:39-45` 의 설계 원칙 위반이 된다 — 좌표는 반드시 world_player 경로로.
  - **미검증 경로**: 추종 시작 배너 후 서버가 멤버 행을 아직 못 받은 창에 대한 레이스는 코드상 방어가 없다(`_followStopping` 은 해제 방향만 감싼다).

  

## 5. 권고안

  | 순위 | 권고 | 범위 | 근거 | 리스크 |
  |---|---|---|---|---|
  | 1 | 파티 중에도 초대 진입점 추가 — 패널을 '파티원' / '근처 요원' 두 섹션으로 나누거나, 리더 전용 '초대' 모드 전환을 둔다 | 클라 `party_panel.dart` | `party_panel.dart:126-130, 422-432` | 패널 높이 계산(`_resize`)과 탭 판정 y 좌표를 함께 손봐야 한다 |
  | 2 | kick 에 UI 를 단다 — 리더가 멤버 줄을 눌렀을 때 위임/추방 선택지(길게 누르기 또는 2단계 확인) | 클라 `party_panel.dart` + `action_rpg_game.dart` | `party.rs:473-494`(서버는 완비), UI 호출 0건 | Flame 캔버스라 모달이 없어 확인 절차를 자체 구현해야 한다 |
  | 3 | 낙관 배너 폐지 — invite/promote/setFollowing 을 `_runPartyAction` 으로 통일하고 성공 배너는 완료 후에 | 클라 `action_rpg_game.dart:937-959, 1016` | 982-992 의 기존 패턴 재사용 | 왕복 시간만큼 피드백이 늦어진다(수십 ms) |
  | 4 | AOI 추종 단절 수정: 추종 시작 시 `SELECT * FROM world_player WHERE character_id = ?` 추가 구독(세대 관리는 `_maybeResubscribe` 패턴) | 클라 `spacetime_world_presence.dart` + `_followTarget` | `cyborg_connection.dart:100`, `spacetime_world_presence.dart:206-249` | 리더 변경·추종 해제 시 구독 정리 누락 위험 |
  | 5 | 파티장 오프라인 동결 완화 — 예: `my_party` 응답에 리더의 world_player 존재 여부를 포함시켜, 리더 부재 시 멤버도 초대 가능하게 하거나 탈퇴 유도 배너 | 서버 `party.rs` + 클라 패널 | `party.rs:279-281`, `lib.rs:236-241` | "잠깐 자리 비움" 과 "이탈" 의 경계를 어느 시점에 긋느냐는 기획 판단 |
  | 6 | 추방·파티 소멸 시 본인에게 배너 — 멤버 행 소멸을 감지해 "파티에서 나왔다/파티가 해산됐다" 표시 | 클라 `action_rpg_game.dart` | (라) 분석 | inParty false 전이 감지 지점을 새로 만들어야 한다 |
  | 7 | '파티 이끌기' 구현 — Party 끝에 `hunt_lead_*` 3열(#[default]) + reducer 3 + `_followTarget` 을 `followingCharacterId` 기준으로 전환 + 리더 좌표는 4번의 직접 구독 재사용 | 서버 `party.rs` + 클라 | `party.rs:112-122`, `action_rpg_game.dart:889-891` | 생성 코드 재생성 충돌; `remove_member` 에 hunt lead 정리 경로 추가 필수 |
  | 8 | 사망 후 추종 재개 정책 명시 — rejoin 시작 전 "리더가 위험 지역에 있으면 재개하지 않는다" 는 판단(예: 리더 주변 몹 수 또는 안전지대 거리) 추가 검토 | 클라 `party_follow.dart` | `action_rpg_game.dart:1786-1789` vs `party_follow.dart:202-227` | 과하면 파티 사냥의 회복력이 떨어진다 — 수치 튜닝 영역 |
  | 9 | `changes` 에 `_client.myParty` 해당 listenable 추가(계약 정합성) | 클라 `spacetime_party.dart:47` | `party.rs:515-518` | 현재 소비자 0건이라 우선도 최하 |

  

## 6. 불확실 · 미확인

  - **실행 검증 부재**: 본 판정은 전부 코드 경로 추적이며, 두 클라이언트를 띄운 실기기/통합 테스트로 (가)~(사)를 재현하지는 않았다. CLAUDE.md 의 DTD 검증 절차로 실측 확인이 필요하다.
  - `test/` 의 파티 관련 테스트 파일 목록과 커버리지를 확인하지 않았다 — 어느 시나리오가 이미 테스트로 잠겨 있는지 미확인.
  - `RemotePlayer.alive` 가 `world_player` 의 어느 열에서 오는지(생사 판정 정확도)는 확인하지 않았다.
  - 라리엔 `docs/party.md` §10.5 의 존재는 확인했으나 내용 전문을 대조하지는 않았다 — hunt lead 세부(예: 팔로워 이탈 처리)는 참고 여지가 있다.
  - `worldSubscriptionsFor` 의 monster/loot 청크(32타일)와 player 청크(74타일)의 범위 차이가 추종 중 사냥 후보 가시성에 주는 영향(리더 주변 몹이 내 구독에 없는 구간)은 별도 검증이 필요하다 [추측: 25타일 재합류 문턱 이내라면 영향이 작을 것으로 보임].
  - 파티장 오프라인 시 "파티 유지" 가 기획 의도인지(재접속 시 그대로 복귀) 미비인지는 사람 판단이 필요하다.
