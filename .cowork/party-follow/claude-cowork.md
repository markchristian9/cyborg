<!-- cowork:claude | 2026-08-05 19:34:55 | exit=0 | 832s -->
# claude 분석 — party-follow

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
> 생성: 2026-08-05 19:34:55 · 소요 832s · 읽기 전용 분석(작업공간 미수정)

---

계획 파일 쓰기 도구가 없습니다 — 이 세션은 읽기 전용 분석가로 기동되었습니다. 지정된 형식으로 보고서를 출력합니다.

## 1. 결론 요약

**핵심 사슬은 끊김 없이 이어지지만, 파티 기능을 2인 이하로 묶어 버리는 치명적 결함이 하나 있다.** `invitePlayerToParty` 의 유일한 호출부가 "근처 요원" 목록인데, 그 목록은 파티가 **없을 때만** 그려진다 — 즉 3명째를 초대할 방법이 없고 서버 정원 12명은 도달 불가능하다. 추종·자동 공격 사슬(`set_following` → `following_character_id` → `_followTarget` → `autoHunt.moveAnchor` → `attack_monster`)은 실배선이며 서버 몬스터를 때린다. 그 외 결함 8개를 찾았고, 이미 알려진 AOI 끊김은 예상보다 심하다 — 설계된 포기 거리 120타일은 **도달할 수 없는 죽은 상수**다. '파티 이끌기'는 여전히 미구현이며, 직전 라운드 설계는 대체로 타당하되 AOI 우회 view 를 이끌기 전용으로 좁히면 안 된다.

## 2. 근거

- `lib/game/ui/party_panel.dart:126-130` — `if (party.inParty) return _memberRows(party); return _nearbyRows();`. 파티가 생기면 근처 요원 목록이 사라진다.
- `lib/game/ui/party_panel.dart:425` · `lib/game/action_rpg_game.dart:937` — `invitePlayerToParty` 의 호출부는 근처 요원 줄 탭 **한 곳뿐**이다(전체 grep 확인).
- `spacetimedb/src/party.rs:359-362` — `accept_invite` 가 만료 초대를 `delete` 한 뒤 `Err` 를 반환한다. `Err` 는 트랜잭션을 롤백하므로 그 삭제는 무효다.
- `spacetimedb/src/party.rs:676-689` · `:303` — `sweep_expired_invites` 의 호출처는 `invite_to_party` 한 곳뿐이고, 초대 대상 1인분만 훑는다.
- `spacetimedb/src/party.rs:395-412` — `decline_invite` 는 행만 지운다. 초대자에게 통보하는 경로가 없다.
- `spacetimedb/src/lib.rs:235-242` — `on_disconnect` 는 `world_player` 한 행만 지운다. `party.rs:722` 주석이 예고한 "접속 종료" 뒤처리는 아직 연결되지 않았다.
- `lib/spacetime/cyborg_connection.dart:41,82-111` — `world_player` 구독은 74타일 청크 3×3. 중심에서 경계까지 최소 74타일.
- `lib/game/systems/party_follow.dart:161-167` vs `:100` — 리더가 `presence.others` 에 없으면 그 프레임에 즉시 `lost`. 유예 0. `giveUpDistanceTiles = 120` 은 74타일에서 먼저 걸러지므로 사실상 도달 불가.
- `lib/game/action_rpg_game.dart:1016` — `unawaited(party.setFollowing(true))` 만 `_runPartyAction`(`:982-992`) 밖이다. 해제 방향은 `_pushFollowing`(`:922-928`)이 잡는다.
- `lib/game/action_rpg_game.dart:846-851` vs `:912` — 파티 소멸 정리 경로는 `_stopFollowing` 과 달리 `autoHunt.moveAnchor(player.grid)` 를 부르지 않는다.
- `lib/game/systems/party_follow.dart:187-191` — `_bestDistance` 를 ∞로 되돌리는 것은 **리더**가 죽었을 때뿐이다.
- `lib/game/action_rpg_game.dart:1262,1288,1300` · `lib/game/entities/enemy.dart:539-543` · `spacetimedb/src/world.rs:1466` — `enemies` 의 유일한 소스가 서버 `monster` 표이고, 공격은 `attack_monster` reducer 로 간다. `MonsterPopulation.seedsNear/generate` 는 `lib/` 에서 호출되지 않는다(테스트만).
- `lib/spacetime/spacetime_party.dart:139` — `kick()` 구현은 있으나 `lib/` 전체에 호출부 0건.
- `spacetimedb/src/party.rs:725-797` — `remove_member` 가 following 정리·파티장 승계·1명 이하 자동 해체를 모두 처리한다. 서버 뒤처리에는 빈틈이 없다.
- `~/apps/game/laryen/docs/party.md:303-376` — 라리엔 hunt lead 는 Zone 완전 권위라 "AOI 제약 없음"(`:343`)이다. Cyborg 는 전제가 다르다.

## 3. 상세 분석

**(가) 초대 — 부분 성립.** 서버→view→카드 경로는 온전하고, 거절 사유도 `cleanReducerError` 를 거쳐 배너에 뜬다. 무너지는 곳은 **초대 진입점**이다. 파티가 성립하는 순간 화면에서 초대할 대상을 고르는 유일한 수단이 사라진다. 원격 PC 클릭도 없으므로(`remote_player.dart` 에 `TapCallbacks` 0건) 우회로가 없다. 서버는 12명을 허용하고 정원 초과 오류 문구까지 준비해 두었는데(`party.rs:283`) 그 코드 경로에 닿을 방법이 없다.

**(나)(다) 추종과 자동 공격 — 성립한다.** 추종은 "자동 사냥의 앵커를 리더에게 옮기는 것"으로 구현돼 있고, rejoin 구간만 `suspended`(`action_rpg_game.dart:789`)로 사냥 판단을 미룬다. anchor 구간에서는 사냥이 정상적으로 돌아 "따라가며 그 주변을 때린다"가 실제로 성립한다. 사냥이 꺼져 있으면 추종이 켠다. 클라 접근 거리 1.5타일이 서버 판정 2.2타일보다 좁아 사거리 거절도 없다.

문제는 **입력**이다. `_followTarget()` 이 리더 좌표를 `presence.others` 에서만 얻는데, 그 목록은 AOI 구독 결과다. 74타일 창의 경계를 넘는 순간 리더 행이 사라지고 컨트롤러 ①분기가 "월드에서 사라졌다"로 즉시 끊는다. 유예도, 연속 프레임 확인도 없다. 결과적으로 ③분기(120타일 "너무 멀다")는 거의 실행되지 않는 죽은 코드가 됐다. **AOI 가 파티 구현 이후에 들어오면서 생긴 결함이며, 판단 로직이 아니라 데이터 공급 경로의 문제다.**

**(라)(마) 정리 경로 — 서버는 완전, 클라에 두 곳이 빈다.** 서버 `remove_member` 는 탈퇴·추방을 한 곳에 모아 following 해제와 파티장 승계를 모두 처리하고, `disband_party` 는 행을 통째로 지운다. 클라도 `!party.isFollowing` 을 보고 컨트롤러를 reset 하지만 **앵커를 회수하지 않는다** — 파티가 사라진 순간 자동 사냥이 옛 파티장의 마지막 좌표를 향해 계속 돈다. 그리고 파티장이 접속을 끊으면 파티는 리더 없이 남고, 남은 사람은 해산도 위임도 부를 수 없다(둘 다 리더 전용). 각자 나가면 풀리지만 그 사실을 알려 주는 안내가 없다.

**(바) 부활 후 추종.** 상태는 유지되고 재개된다. 다만 컨트롤러가 **내** 순간이동을 모른다. 리더 옆에서 재던 작은 `_bestDistance` 가 남은 채 안전지대로 튕겨 나가면 `distance < _bestDistance - 0.5` 가 계속 거짓이라 8초 뒤 "닿을 수 없다"로 끊긴다. 기존 테스트 13건은 리더 사망 케이스만 덮는다.

**파티 이끌기 설계 재검증.** `Party` 행에 열 3개를 얹는 안은 타당하다 — 파티당 행이 하나라 "세션 1개"가 스키마로 강제되고, 전원이 이미 `my_party` 를 구독하므로 행 변경이 곧 방송이다. 라리엔이 `PLEADINV` 를 방송한 것은 UDP 라서 행 구독이 없었기 때문이고, 전송 모델이 다른데 그 대응물까지 복사할 이유가 없다.

다만 **AOI 우회 view 를 이끌기 전용으로 만들면 안 된다.** 그러면 일반 파티장 추종은 74타일에서 계속 끊긴다. 추종 대상 1명의 좌표·생사만 담는 view 로 만들어 두 문제를 함께 푸는 편이 맞다 — 대상은 `following_character_id` 로 정하면 이끌기든 파티장 추종이든 같은 경로를 탄다. 반대로 `changes` 에 `my_party` 를 더하는 일은 우선순위를 낮춰도 된다: `party.changes` 를 듣는 리스너가 코드베이스에 하나도 없고(전체 grep 결과 `leaderboard_screen.dart:177,182` 한 쌍뿐) 파티 UI 는 매 프레임 폴링으로 돈다. 인터페이스 정합성 문제이지 이끌기의 전제조건이 아니다.

## 4. 리스크 · 함정

- **B단계 서버 변경은 되돌리기 어렵다.** 이미 배포된 `Party`·`PartyInvite` 에 열을 추가하고 `lib/spacetime/generated/` 를 재생성해야 한다. 다른 세션이 같은 디렉토리를 건드리면 서로의 표가 조용히 사라진다 — 직전 라운드가 최대 위험으로 기록한 지점이다.
- **view 반환 타입 함정.** Dart 코드 생성기는 view 반환 타입 이름을 **테이블 목록에서만** 찾는다. 테이블이 아닌 타입을 반환하면 `Type2` 같은 존재하지 않는 클래스를 참조하는 깨진 코드가 나온다. AOI 우회 view 는 실제 테이블 타입을 반환해야 한다.
- **view 도 구독해야 행이 온다.** 새 view 를 `kPartySubscriptions`(`cyborg_connection.dart:121-125`)에 넣지 않으면 reducer 는 성공하는데 캐시는 비어 있고, 이는 "파티가 없는 것"과 구별되지 않는다.
- **A1 을 고칠 때 파티장 검증을 함께 넣어야 한다.** `invite_to_party` 는 파티장만 허용한다(`party.rs:279-281`). 파티원에게도 초대 구역을 보이면 누를 때마다 "파티장만 초대할 수 있다"만 뜬다.
- **`PartyFollowController` 는 건드리지 않는 편이 낫다.** 판단 규칙이 순수하고 테스트 13건이 지킨다. 무수정 통과가 곧 회귀 없음의 증거다. 부활 처리(A4)는 진전 기록만 초기화하는 최소 추가로 끝낸다.
- **`set_following` 의 파티장 고정을 폐기하면 구버전 클라와 의미가 어긋난다.** 배포 후 재생성 전까지의 구간에 주의가 필요하다.
- **낙관적 배너가 실패 사유를 덮는다.** 배너 슬롯이 콤보 텍스트와 공유되고 1.6초뿐이라(`action_rpg_game.dart:1329-1332`), 연속 동작 시 서버가 준 사유가 보이지 않을 수 있다.
- **`accept_invite` 의 `Err` 롤백 전제는 SpacetimeDB 표준 동작에 기댄 판단이다.** 이 프로젝트에서 실측된 기록은 찾지 못했다.

## 5. 권고안

| 순위 | 권고 | 범위 | 근거 | 리스크 |
|---|---|---|---|---|
| 1 | **파티 중에도 초대할 수 있게 한다** — 파티원 목록 아래에 "근처 요원" 구역을 이어 붙이되 **파티장일 때만**. 이미 파티원인 사람은 제외. 높이 계산·탭 라우팅을 구역 단위로 분리 | 클라 `party_panel.dart:126-130,196-205,423-431` | 위 §2 첫 두 항목 | 패널 높이가 늘어 12인 파티에서 화면을 가림 — `maxVisibleRows` 조정 필요 |
| 2 | **추종 대상 좌표를 파티 view 로 받는다** — `my_follow_target`(반환 타입은 실제 테이블) 추가, `kPartySubscriptions` 에 등록. `_followTarget()` 이 이 view 를 먼저 보고 없을 때만 `presence.others` 폴백 | 서버 `party.rs` + 클라 `action_rpg_game.dart:889-902`, `cyborg_connection.dart:121` | `cyborg_connection.dart:41` vs `party_follow.dart:100,161-167` | 배포 필요. view 재계산 빈도(대상 1명분) |
| 3 | **파티 이끌기 구현** — `Party` 맨 끝에 `hunt_lead_character_id`·`hunt_lead_seq`·`hunt_lead_name` (`#[default]` 필수). reducer 3개(`start_hunt_lead` 파티원 누구나·`stop_hunt_lead` 이끄는 본인만·`accept_hunt_lead(seq)`). `remove_member`·`disband_party` 에 세션 정리 추가. `set_following(true)` 의 파티장 고정은 폐기 | 서버 `party.rs` + 클라 패널 푸터·`HuntLeadCard` | 라리엔 `docs/party.md:303-376`, `party.rs:113-121` 확장 의도 | 배포·바인딩 재생성. 2·3을 한 번에 묶어 배포 |
| 4 | **파티 소멸 시 앵커 회수 + 배너** — 정리 경로가 `_stopFollowing` 과 같은 마무리를 하도록 공통 함수로 뽑는다 | 클라 `action_rpg_game.dart:846-851` | `:912` 와의 비대칭 | 없음 |
| 5 | **부활 시 진전 기록 초기화** — 컨트롤러에 `noteSelfTeleported()`(진전만 초기화, `_targetId` 유지) 추가, `_onServerDeath`·`onPlayerDied` 에서 호출 | 클라 `party_follow.dart` + `action_rpg_game.dart:644,1783` | `party_follow.dart:187-191` 이 리더 사망만 처리 | 컨트롤러 수정 — 테스트 13건 무수정 통과로 검증 |
| 6 | **추종 시작 실패를 알린다** — `_runPartyAction` 으로 감싸고 실패 시 상태를 되돌린다 | 클라 `action_rpg_game.dart:1016` | 해제 방향(`:922-928`)과의 비대칭 | 없음 |
| 7 | **추방 UI 추가** — 파티장이 남의 줄에서 추방을 부를 수 있게. `promotePartyMember`(`:956`) 패턴 그대로 | 클라 `party_panel.dart:429-431` | `spacetime_party.dart:139` 호출부 0건 | 오조작 — 확인 단계 필요 |
| 8 | **파티장 접속 없음 안내** — 푸터에 "파티장이 접속 중이 아니다 — 나가면 자리가 넘어간다". 서버 규칙(`party.rs:758-770`)상 실제로 그렇게 된다 | 클라 `party_panel.dart` | `lib.rs:235-242` | 없음. 서버 설계(월드 밖에서도 파티 유지)를 지키는 최소 보완 |
| 9 | **만료 초대 정리** — `accept_invite` 는 `Err` 만 반환(삭제는 어차피 롤백), `sweep_expired_invites` 를 `decline_invite`·`accept_invite` 진입부·`leave_party` 에도 건다 | 서버 `party.rs:359-362,676-689` | §2 3·4항 | 배포 필요. 2·3과 함께 |
| 10 | **거절 통보** — `PartyInvite` 맨 끝에 `declined_at: Option<Timestamp>`, `decline_invite` 가 행 대신 이 값을 찍는다. view `my_sent_invites` 추가 → 초대자가 배너를 본다 | 서버 `party.rs` + 클라 | 라리엔 `docs/party.md:107-108` | 배포 필요. 우선순위 하위 |
| 11 | **초대 카드 카운트다운 · 낙관적 배너 순서** | 클라 `party_panel.dart:518`, `action_rpg_game.dart:937-975` | §4 마지막 항목 | 없음 |
| 12 | **`changes` 에 `my_party` 추가** | 클라 `spacetime_party.dart:47` | 인터페이스 정합성 | 현재 폴링으로 가려져 있어 체감 변화 없음 |

**순서**: 1·4·5·6·7·8·11 은 배포 없이 먼저 끝낸다(`flutter test` + `flutter analyze` + 가짜 파티 상태 주입 스크린샷). 2·3·9·10 은 서버 변경을 **한 번에 모아** 배포한다 — `cargo test` → `cargo build --target=wasm32-unknown-unknown --release` → `spacetime publish` → 바인딩 재생성(한 사람이 1회) → `flutter test` → 2계정 실서버 확인.

## 6. 불확실 · 미확인

- **`Err` 반환 시 트랜잭션 롤백**이 이 SpacetimeDB 2.7 배포에서 실제로 그렇게 도는지 실측 기록을 찾지 못했다. 표준 동작에 근거한 판단이므로, 9번 권고 전에 간단한 reducer 로 확인하는 편이 안전하다.
- **`cargo test` 실행 가능 여부** — `Cargo.toml:6-7` 이 `crate-type = ["cdylib"]` 단독이다. 링크 방식에 제약이 있을 수 있으나 CI 설정이나 관련 주석을 확인하지 못했다.
- **`my_follow_target` view 의 재계산 비용** — 대상 1명분이라 부담이 제한적이라고 판단했으나, 리더가 200ms 주기로 좌표를 갱신할 때 view 가 얼마나 자주 재계산되어 구독자에게 밀리는지는 실측이 필요하다. 같은 월드에 파티가 수십 개면 합산 부하가 달라진다.
- **패널 높이** — 12인 파티 + 근처 요원 구역이 함께 뜰 때의 최종 배치는 화면 해상도별로 DTD 스크린샷으로 확정해야 한다.
- **이끌기 권한** — '파티원 누구나' vs '파티장만' 은 제품 결정이다. 라리엔 선례(`docs/party.md:305-306`)와 `party.rs:113-116` 의 확장 의도로 '누구나'를 권했으나 사람의 판단이 필요하다.
- **`test/spacetime_integration_test.dart`** 가 파티 view 구독 조합을 검증하지 않는다는 점만 확인했고, 그 파일이 실제로 어떤 조합을 지키는지는 열어 보지 않았다.
