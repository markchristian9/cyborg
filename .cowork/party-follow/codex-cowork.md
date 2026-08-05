<!-- cowork:codex | 2026-08-05 19:30:04 | exit=0 | 541s -->
# codex 분석 — party-follow

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
> 생성: 2026-08-05 19:30:04 · 소요 541s · 읽기 전용 분석(작업공간 미수정)

---



## 1. 결론 요약

현재 파티 기능은 **부분 동작**한다. 2인 초대·수락과 서버 몬스터 자동 공격 경로는 성립하지만, 기존 파티에서는 추가 초대를 할 수 없고 추방 UI도 없어 3~12인 파티 운영은 정상적으로 완결되지 않는다.
추종은 `set_following → following_character_id → _followTarget → moveAnchor`로 이어지지만, AOI 이탈·사망·서버 주도 해제에서 끊기거나 마지막 리더 좌표에 자동 사냥 앵커가 남는다.
제안된 `Party` 행 기반 hunt lead 설계는 기본 방향이 타당하다. 다만 target view에 `lead_seq`·`deaths`를 추가하고, 기존 추종 상태 정리·누락 유예·접속 종료 처리까지 포함하지 않으면 같은 결함이 반복된다.
소스 경로를 통한 정적 검증 결과이며, 읽기 전용 제약에 따라 빌드·테스트·실서버 실행은 수행하지 않았다.

## 2. 근거

- `CLAUDE.md:32-43` — 파티는 이동·사냥 동행만 제공하며 보상 공유나 파티원 PK 면역은 제공하지 않는다.
- `spacetimedb/src/party.rs:77-153` — 현재 `Party`·`PartyMember`·`PartyInvite` 구조와 `following_character_id`가 정의돼 있고 hunt lead 필드는 없다.
- `spacetimedb/src/party.rs:157-195` — `my_party`·`my_party_members`·`my_party_invites` view가 호출자 자신의 파티와 초대만 반환한다.
- `spacetimedb/src/party.rs:241-334` — 초대 시 상대의 월드 존재·기존 파티·파티장 권한·12명 정원을 서버에서 검사한다.
- `spacetimedb/src/party.rs:344-391` — 수락 시 대상·만료·중복 가입·파티 존속·정원을 다시 검사하고 가입 후 대상의 모든 초대를 지운다.
- `spacetimedb/src/party.rs:434-599` — 해체·추방·위임·파티장 고정 추종 reducer가 구현돼 있다.
- `spacetimedb/src/party.rs:725-796` — 탈퇴·추방 시 파티장 승계와 사라진 대상을 따르던 멤버의 `following_character_id` 정리를 서버가 수행한다.
- `lib/game/ui/party_panel.dart:125-192` — 파티가 없을 때만 근처 요원 목록을 표시하고, 파티에 들어가면 목록 전체를 파티원 행으로 교체한다.
- `lib/game/ui/party_panel.dart:422-446` — 파티원 행 선택은 위임만 수행하며 추방·추가 초대 진입점은 없다.
- `lib/spacetime/spacetime_party.dart:33-47` — `changes`가 멤버·초대 행만 병합하며 `my_party` 행 변경은 듣지 않는다.
- `lib/game/action_rpg_game.dart:845-915` — 추종 여부를 읽어 리더 탐색·재합류·자동 사냥 앵커 변경·추종 해제를 실행한다.
- `lib/game/action_rpg_game.dart:766-809`, `lib/game/entities/enemy.dart:531-542` — 자동 사냥의 근접 타격은 서버 구동 `Enemy`의 `serverId`를 통해 `presence.attack`으로 전달된다.
- `lib/spacetime/spacetime_world_presence.dart:328-334`, `spacetimedb/src/world.rs:1460-1513` — `presence.attack`은 실제 `attack_monster` reducer를 호출하며 서버가 생사·사거리·쿨다운·피해를 판정한다.
- `lib/spacetime/cyborg_connection.dart:69-110` — 월드 구독은 자기 청크 주변 3×3의 `world_player`·몬스터·전리품으로 제한된다.
- `/Users/thruthesky/apps/game/laryen/docs/party.md:303-375` — hunt lead는 파티장과 독립된 임시 사냥 리더이며, 세션별 수락·종료·사망 후 재개 규칙을 사용한다.

## 3. 상세 분석

### 시나리오별 판정

| 시나리오 | 판정 | 코드 경로와 중단점 |
|---|---|---|
| (가) A가 B를 초대 | **조건부 성립** | A에게 파티가 없으면 근처 행 선택이 `invitePlayerToParty`를 호출하고, 서버가 `PartyInvite`를 만든 뒤 B의 `my_party_invites` 구독으로 카드가 온다(`lib/game/ui/party_panel.dart:173-192,422-426`, `spacetimedb/src/party.rs:303-334`). B 수락 시 멤버 삽입과 초대 삭제가 한 reducer에서 일어나므로 양쪽 `my_party_members`가 갱신될 경로도 있다(`spacetimedb/src/party.rs:380-391`). 다만 실서버 양방향 검증 테스트는 없다. |
| (가) 20초 만료 | **화면만 처리, 서버 청소 불완전** | 카드는 매 렌더마다 기기 `DateTime.now()`로 만료된 초대를 숨긴다(`lib/game/ui/party_panel.dart:486-501`). 서버는 수락 시 `ctx.timestamp`로 정확히 거절하지만(`spacetimedb/src/party.rs:359-362`), 만료 행은 같은 대상에게 새 초대가 오거나 수락을 시도할 때만 삭제된다(`spacetimedb/src/party.rs:671-689`). 따라서 한 번 초대받고 다시 활동하지 않은 캐릭터의 만료 행은 무기한 남을 수 있다. 기기 시계가 빠르면 카드가 일찍 사라지고 느리면 만료 뒤에도 보인다. |
| (가) 오류 표시 | **대부분 성립, 성공 표시는 부정확** | `_runPartyAction`이 reducer 오류 문장을 배너로 보여 준다(`lib/game/action_rpg_game.dart:977-991`). 그러나 초대·위임·탈퇴·해체는 서버 응답 전에 성공 문구부터 띄운다(`lib/game/action_rpg_game.dart:936-974`). 추종 시작은 `_runPartyAction`을 거치지 않고 `unawaited(party.setFollowing(true))`를 호출하므로 서버 거절 사유가 화면에 연결되지 않는다(`lib/game/action_rpg_game.dart:1012-1016`). |
| (나) B가 A 추종 | **AOI 안에서만 성립** | `set_following(true)`가 B의 행에 A의 ID를 저장하고(`spacetimedb/src/party.rs:564-598`), 클라이언트는 이를 `party.isFollowing`으로 읽는다(`lib/game/net/party_session.dart:101-109`). 이후 `_followTarget`이 `presence.others`에서 현재 파티장을 찾아 `PartyFollowController`로 넘기고, 가까우면 `moveAnchor`, 멀면 직접 재합류 이동을 지시한다(`lib/game/action_rpg_game.dart:845-902`). 리더가 AOI에서 빠지면 `null → lost → setFollowing(false)`로 잘못 종료된다. 120타일 초과도 즉시 종료 조건이다(`lib/game/systems/party_follow.dart:193-200`). |
| (다) 추종 중 자동 공격 | **실제 서버 몬스터를 공격함** | 런타임 `Enemy`는 `presence.monsters`에서 생성되며 모두 `serverId`를 받는다(`lib/game/action_rpg_game.dart:1244-1301`). 자동 사냥은 이 `enemies` 목록을 골라 `Player.tryMelee(target:)`를 호출하고(`lib/game/action_rpg_game.dart:784-809`), 타격 프레임에 `Enemy.applyDamage → presence.attack → attackMonster`가 이어진다(`lib/game/entities/player.dart:536-581`, `lib/game/entities/enemy.dart:535-542`, `lib/spacetime/spacetime_world_presence.dart:328-334`). 피해·쿨다운·사거리는 서버가 재판정한다(`spacetimedb/src/world.rs:1466-1509`). |
| (다) 동적 앵커 | **공격은 되지만 추격 안전망이 깨짐** | 추종 중 `moveAnchor`가 매 프레임 호출되는데(`lib/game/action_rpg_game.dart:877-884`), `moveAnchor`는 매번 현재 타깃과 추격 시간을 초기화한다(`lib/game/systems/auto_hunt.dart:180-189`). 가까운 몬스터는 다시 선택돼 공격되지만, 벽 뒤 몬스터에 대한 `pursuitTimeout`이 누적되지 않아 같은 대상에 계속 막힐 수 있다. 동적 추종용 앵커 변경은 타깃을 무조건 초기화하지 않는 별도 경로가 필요하다. |
| (라) 해체·탈퇴·추방 | **서버 정리 정상, 클라이언트 정리 불완전** | 서버는 해체 시 전 멤버·초대·파티를 삭제하고, 탈퇴·추방은 `remove_member`로 승계와 follower 정리를 수행한다(`spacetimedb/src/party.rs:434-493,725-796`). 본인이 버튼으로 탈퇴하면 `_stopFollowing`이 앵커를 현재 위치로 돌린다(`lib/game/action_rpg_game.dart:909-915,962-968`). 반면 원격 해체·추방·리더 이탈로 멤버 행이 사라지면 `_updatePartyFollow`는 컨트롤러만 `reset`하고 자동 사냥 앵커를 되돌리지 않는다(`lib/game/action_rpg_game.dart:845-850`). 결과적으로 former leader의 마지막 위치를 중심으로 자동 사냥이 남는다. |
| (라) 추방 조작 | **UI에서 불가능** | `PartySession`과 Spacetime 어댑터에는 `kick`이 있지만(`lib/game/net/party_session.dart:141-145`, `lib/spacetime/spacetime_party.dart:138-148`), 파티원 행을 누르면 위임만 실행되고 추방 선택지는 없다(`lib/game/ui/party_panel.dart:422-431`). |
| (마) 파티장 접속 종료 | **파티와 following이 서버에 남음** | `on_disconnect`는 `world_player`만 삭제한다(`spacetimedb/src/lib.rs:229-241`). 온라인 follower는 대상 행이 사라진 것을 보고 스스로 `set_following(false)`를 보낼 가능성이 높지만, 오프라인 follower의 상태는 남는다(`lib/game/action_rpg_game.dart:888-915`). 파티장은 계속 파티장이라 남은 멤버는 초대·추방·위임·해체를 할 수 없고 탈퇴만 가능하다(`spacetimedb/src/party.rs:270-284,434-500`). |
| (바) follower 사망·부활 | **조건부 재개, 보장되지 않음** | 자기 사망 시 자동 사냥은 꺼지지만 파티의 following 행은 유지된다(`lib/game/action_rpg_game.dart:644-650`). 다음 프레임 대상이 보이고 120타일 이내이면 추종이 자동 사냥을 다시 켠다(`lib/game/action_rpg_game.dart:877-884`). 안전지대 부활로 리더가 AOI 밖이거나 120타일보다 멀면 즉시 추종을 해제하므로 라리엔의 “사망 후 자동 재개”와는 다르다(`lib/game/systems/party_follow.dart:193-200`, `/Users/thruthesky/apps/game/laryen/docs/party.md:369-375`). |
| (바) 리더 사망 | **기존 `hold` 전제가 실제 서버와 맞지 않음** | 서버 사망 처리는 `alive:false`를 외부에 남기지 않고 같은 갱신에서 `alive:true`, 안전지대 좌표, 증가한 `deaths`를 기록한다(`spacetimedb/src/world.rs:2282-2304`). 따라서 follower가 `leader.alive == false`를 관찰해 `hold`로 들어간다는 기존 분석은 보장되지 않는다. 실제로는 리더가 안전지대로 순간이동한 것으로 보여 AOI 누락이나 120타일 판정으로 추종이 끊길 수 있다. |
| (사) 12명·기존 파티 대상 | **서버 방어 정상, 화면 흐름 결함** | 서버는 초대와 수락 양쪽에서 정원을 검사하고 대상이 이미 파티원인지 검사한다(`spacetimedb/src/party.rs:260-284,364-377`). 그러나 파티에 들어간 순간 패널이 멤버 목록으로 바뀌어 추가 초대 후보가 사라지므로 정상 UI로는 3번째 멤버부터 초대할 수 없다(`lib/game/ui/party_panel.dart:125-129`). API를 직접 호출하면 먼저 “초대했다”가 보이고 뒤늦게 “가득 찼다/이미 다른 파티” 오류로 덮인다(`lib/game/action_rpg_game.dart:936-940,982-991`). 파티가 초대 후 가득 찬 경우 수락 오류가 나도 초대 행은 남아 TTL까지 같은 카드가 계속 보인다(`spacetimedb/src/party.rs:368-378`). |

### hunt lead 설계 재검증

`Party` 행에 `hunt_lead_character_id`·`hunt_lead_seq`·`hunt_lead_name`을 맨 끝 기본값과 함께 추가하는 방향은 여전히 가장 단순하다. 파티당 행 하나라 동시 세션 하나가 구조적으로 강제되고, 전원이 `my_party`를 구독하므로 별도 초대 표 없이 방송할 수 있다(`spacetimedb/src/party.rs:77-94`, `lib/spacetime/cyborg_connection.dart:113-125`). 다만 다음 보완이 필수다.

- `start_hunt_lead`는 initiator 본인뿐 아니라 파티의 기존 `following_character_id`를 모두 해제해야 한다. 그렇지 않으면 배포 전에 파티장 추종을 켠 멤버가 새 hunt lead를 수락하지 않았는데도 옛 파티장을 계속 따른다(`spacetimedb/src/party.rs:557-598`).
- `stop_hunt_lead`의 “리더”는 membership leader가 아니라 현재 `hunt_lead_character_id`여야 한다. follower 개인 중단은 `set_following(false)`를 유지하고, `true`는 stale 클라이언트에 명시적 오류를 주는 호환 경로로 남기는 편이 안전하다.
- `accept_hunt_lead(lead_seq)`는 호출자가 같은 파티원인지, seq가 현재 세션과 같은지, 자신이 hunt leader가 아닌지, hunt leader가 아직 파티와 월드에 존재하는지를 검증해야 한다. 소유자는 계속 세션에서 도출해야 한다(`spacetimedb/src/party.rs:603-650`).
- `promote_leader`는 hunt lead 활성 중 기존 “옛 파티장 follower를 새 파티장으로 이전” 로직을 실행하면 안 된다. 현재 로직은 membership leader와 follow target이 같은 전제에서만 맞다(`spacetimedb/src/party.rs:513-552`).
- `remove_member`·`disband_party`뿐 아니라 `leave_world`·`on_disconnect`에서도 떠난 사람이 hunt leader이면 세션과 follower를 정리해야 한다(`spacetimedb/src/world.rs:1305-1309`, `spacetimedb/src/lib.rs:229-241`).
- `my_hunt_lead_target`는 좌표·`alive`만으로 부족하다. 서버 사망은 `alive:false`를 노출하지 않으므로 `deaths`가 필요하고, view 사이의 늦은 갱신을 구분하려면 `lead_seq`도 포함해야 한다(`spacetimedb/src/world.rs:2282-2304`). 권장 projection은 `lead_seq`, `character_id`, `grid_x`, `grid_y`, `alive`, `deaths`다.
- projection 반환형은 Dart 생성기가 인식하는 비공개 table 타입이어야 한다. 임의 struct를 view에서 반환하면 깨진 타입명이 생성될 수 있다는 작업공간 제약이 있다(`.cowork/cowork-prompt.md:78-83`).
- target view가 잠깐 비어 있는 것을 즉시 “접속 종료”로 판정하면 수락 직후에도 추종 해제가 경쟁할 수 있다. 현재 `leader == null`은 즉시 `lost`이므로, “구독 준비 중/일시 누락/확정 오프라인”을 구분하거나 짧은 누락 유예가 필요하다(`lib/game/systems/party_follow.dart:160-167`).
- `_followTarget()`은 `party.leaderCharacterId`가 아니라 본인 행의 `followingCharacterId`를 사용해야 membership leader와 hunt leader가 독립된다(`lib/game/action_rpg_game.dart:888-901`, `lib/game/net/party_session.dart:101-109`).
- `changes`에는 `my_party`와 target view를 모두 포함해야 한다. 현재 신호는 Party 단독 변경을 누락한다(`lib/spacetime/spacetime_party.dart:33-47`).
- 별도 서버 초대 표는 필수는 아니다. 다만 “거절”을 no-op으로 둘 경우 클라이언트가 `hunt_lead_seq`별 dismissed 상태를 기억해야 같은 활성 세션 카드가 매 프레임 다시 나타나지 않는다. 재접속 뒤에도 거절을 유지해야 한다면 그때는 `PartyMember`의 마지막 처리 seq가 필요하다. `[판단]`

## 4. 리스크 · 함정

- 가장 큰 신규 결함은 **기존 파티에서 추가 초대가 불가능한 UI 구조**다. 서버 정원은 12명이지만 정상 패널 경로는 첫 상대 수락 뒤 닫힌다(`lib/game/ui/party_panel.dart:125-129,422-431`).
- 추방 reducer가 존재한다는 사실만으로 기능이 구현됐다고 판정하면 안 된다. 사용자 입력 경로가 없다(`lib/game/net/party_session.dart:141-145`, `lib/game/ui/party_panel.dart:422-446`).
- 서버가 following을 삭제해도 클라이언트 자동 사냥 앵커는 별도 상태라 그대로 남는다. 서버와 클라이언트 양쪽의 정리를 하나의 전이로 다뤄야 한다(`lib/game/action_rpg_game.dart:845-850,904-915`).
- 동적 앵커가 매 프레임 타깃을 초기화해 `pursuitTimeout`을 무력화한다. hunt lead를 추가하면 이 호출 빈도가 더 확실해진다(`lib/game/systems/auto_hunt.dart:180-189,251-263`).
- `my_hunt_lead_target`가 `world_player`를 읽으면 리더 이동 빈도만큼 view가 갱신된다. 최대 11 follower라는 상한은 있지만, 동접 1,000 환경에서 view 재계산이 해당 리더 행 변경에만 제한되는지는 실측되지 않았다.
- 초대 만료 행은 서버에서 주기적으로 삭제되지 않아 장기적으로 누적될 수 있다(`spacetimedb/src/party.rs:671-689`).
- `Party` 열 추가는 이미 배포된 스키마 변경이다. 맨 끝 배치와 타입이 명시된 `#[default]`가 빠지면 기존 행을 읽지 못한다는 규칙이 현재 코드에도 기록돼 있다(`spacetimedb/src/party.rs:118-122`).
- `lib/spacetime/generated/`는 현 서버 스키마만 반영한다. 현재 생성 `Party`에는 `id`·`leaderCharacterId`·`createdAt`만 있어 hunt lead 구현 전 상태임이 확인된다(`lib/spacetime/generated/party.dart:5-24`).
- `.cowork/cowork-prompt.md`는 아직 HP 재설계 분석을 이번 작업이라고 기술한다(`.cowork/cowork-prompt.md:25-41`). 실제 요청·파티 코드와 지침 문서가 어긋난 상태이므로 다음 분석 세션에서도 잘못된 범위가 주입될 위험이 있다.
- `GAME-DESIGN.md`도 원격 플레이어·서버 몬스터 클라이언트 연결을 미구현으로 기록하지만 실제 코드는 이미 사용한다(`GAME-DESIGN.md:786-792`, `lib/game/action_rpg_game.dart:1244-1301`). 문서 상태표를 구현 사실로 사용하면 안 된다.

## 5. 권고안

| 순위 | 권고 | 범위 | 근거 | 리스크 |
|---|---|---|---|---|
| 1 | `Party` 끝에 제안된 hunt lead 필드 3개를 기본값과 함께 추가하고 `start_hunt_lead`·`stop_hunt_lead`·`accept_hunt_lead`를 구현한다. 시작 시 기존 follower 전원 초기화, 종료·탈퇴·추방·해체 시 세션 정리까지 하나의 서버 불변식으로 묶는다. | `spacetimedb/src/party.rs` | `spacetimedb/src/party.rs:77-123,434-599,725-796` | 배포 스키마 변경, 구버전 클라이언트 혼재 |
| 2 | AOI 우회 view를 table형 projection으로 만들고 `lead_seq`·`character_id`·좌표·`alive`·`deaths`를 반환한다. follower 본인의 현재 수락 대상에 대해서만 행을 내보낸다. | `spacetimedb/src/party.rs`, 파티 구독 | `.cowork/cowork-prompt.md:78-83`, `spacetimedb/src/world.rs:2282-2304` | 고빈도 view 비용은 부하 실측 필요 |
| 3 | 클라이언트가 본인 `followingCharacterId`와 target projection을 사용하도록 바꾸고, 일시적인 target 누락 유예와 서버 주도 해제 전이를 둔다. 비로컬 해제 시 자동 사냥 앵커를 현재 위치로 되돌리고 한 번만 종료 배너를 표시한다. | `party_session.dart`, `spacetime_party.dart`, `action_rpg_game.dart`, `party_follow.dart` | `lib/game/action_rpg_game.dart:845-915` | 누락 유예가 길면 실제 접속 종료 반응이 늦어짐 |
| 4 | 동적 리더 앵커 전용 API를 만들어 작은 앵커 이동에는 현재 타깃·추격 시간·차단 이력을 보존한다. | `lib/game/systems/auto_hunt.dart`, `action_rpg_game.dart` | `lib/game/systems/auto_hunt.dart:180-189` | 리더가 크게 이동했을 때는 타깃 재선정 필요 |
| 5 | 파티 안에서도 파티장에게 “근처 요원 초대” 목록을 제공하고, 멤버 행에는 위임·추방을 명시적으로 분리한다. 정원 시 초대 버튼을 비활성화하고 성공 배너는 reducer 성공 뒤에만 표시한다. | `lib/game/ui/party_panel.dart`, `action_rpg_game.dart` | `lib/game/ui/party_panel.dart:125-192,422-446` | 12인 Flame 패널의 높이·히트테스트 재검증 필요 |
| 6 | 만료 초대를 서버에서 주기적으로 정리할 수 있도록 만료 인덱스 기반 sweep 또는 scheduled cleanup을 추가한다. 카드에는 남은 시간과 요청 진행 상태를 표시하고 실패한 카드의 반복 클릭을 막는다. | `spacetimedb/src/party.rs`, `party_panel.dart` | `spacetimedb/src/party.rs:359-362,671-689` | 기존 표에 인덱스 추가 가능 여부 확인 필요 |
| 7 | 접속 종료 정책을 정한다. 최소한 hunt lead는 `leave_world`·`on_disconnect`에서 종료하고, membership leader는 즉시 승계·유예 후 승계·그대로 유지 중 하나를 명시해야 한다. 그대로 유지한다면 남은 멤버에게 관리 권한 회복 수단이 필요하다. | `spacetimedb/src/lib.rs`, `world.rs`, `party.rs` | `spacetimedb/src/lib.rs:229-241` | 짧은 네트워크 단절에 즉시 승계하면 리더가 예기치 않게 바뀜 |
| 8 | 서버 reducer 통합 테스트와 2계정 실서버 시나리오를 추가한다: 초대/만료/동시 수락/정원/추방/해체/AOI 횡단/양쪽 사망/접속 종료/리더 교체. 검증은 CLAUDE 지침대로 DTD와 `main()`·`initState()` 주입, 로그·스크린샷으로 수행한다. | `spacetimedb` 테스트, `test/`, DTD 검증 | `CLAUDE.md:52-57`, `test/party_follow_test.dart:31-288` | 생성 바인딩은 서버 배포 후 한 세션에서만 재생성해야 함 |

## 6. 불확실 · 미확인

- 읽기 전용 제약 때문에 `cargo test`, `flutter test`, `flutter analyze`, DTD, 실서버 2계정 검증은 실행하지 않았다. 현재 판정은 실제 코드 경로에 대한 정적 검증이다.
- 현재 파티 테스트는 `PartySession` 파생 getter와 `PartyFollowController`의 순수 판단을 주로 검사한다(`test/party_session_test.dart:51-173`, `test/party_follow_test.dart:31-288`). 9개 reducer와 양쪽 view 갱신을 끝까지 검증하는 파티 통합 테스트는 확인되지 않았다.
- `my_hunt_lead_target`가 특정 리더 행 갱신에만 효율적으로 반응하는지, 아니면 다른 `world_player` 갱신에도 재평가되는지는 부하 실측이 필요하다.
- follower 사망 후 120타일을 넘어도 자동 재집결해야 하는지는 제품 판단이 필요하다. 라리엔 규칙은 자동 재개지만, 현재 Cyborg 코드는 경로 탐색 없는 장거리 횡단을 막기 위해 의도적으로 종료한다(`lib/game/systems/party_follow.dart:95-106`).
- membership leader가 잠깐 접속을 잃었을 때 즉시 승계할지 유예할지 결정되지 않았다. hunt lead 종료와 파티 멤버십 유지 정책은 서로 분리해야 한다.
- hunt lead 초대 거절을 앱 재접속 뒤에도 기억해야 하는지 확인이 필요하다. 세션 내 거절만 필요하면 클라이언트의 `hunt_lead_seq` 기록으로 충분하고, 영속 거절이 필요하면 서버 멤버 상태가 추가로 필요하다.
- maincloud의 실제 배포 스키마와 현재 생성 코드가 완전히 일치하는지는 외부 상태를 조회하지 않아 미확인이다.
