<!-- cowork:grok | 2026-08-05 19:31:44 | exit=0 | 641s -->
# grok 분석 — party-follow

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
> 생성: 2026-08-05 19:31:44 · 소요 641s · 읽기 전용 분석(작업공간 미수정)

---



## 1. 결론 요약

**현재 파티 1차는 “근처 초대 → 수락 → 파티장 고정 추종 → 추종 시 자동사냥” 해피패스 코드 경로는 이어져 있으나, 단일 공유 월드 MMORPG 기준으로 ‘올바로 동작한다’고 말할 수 없다.**  
치명 결함은 (1) **AOI 밖 리더 = 즉시 `lost`**(구독 공백을 접속 종료와 동일 취급), (2) **`on_disconnect`/`leave_world`가 파티·`following` 미정리**, (3) **요청된 ‘파티 이끌기’ 전무** + 클라가 `following_character_id`가 아니라 `leaderCharacterId`만 추적, (4) **kick UI 0**이다.  
시나리오 (가)(다)(사)는 코드상 대체로 성립, (나)는 **AOI 안·리더 생존일 때만**, (라)는 leave/disband 서버 정리는 되고 kick은 미노출, (마)는 좀비 멤버십, (바)는 **즉시 리스폰 후 거리(120타일)에 따라** 재개/끊김이다. hunt lead 직전안(Party 열 3 + seq + `set_following(true)` 파티장 고정 폐기)은 타당하되, **좌표 SSOT는 view보다 `world_player` `character_id` 추가 구독이 모듈 설계와 더 맞다.**

---

## 2. 근거

- `spacetimedb/src/party.rs:67-73,190-196` — `MAX_PARTY_SIZE=12`, 초대 TTL 20초; `my_party_invites`는 만료 미필터(표시 클라, 수락 시 서버 재판정).
- `spacetimedb/src/party.rs:241-335,344-391,564-598` — 초대(무파티면 생성·파티장만 초대), 수락, `set_following(true)` → **항상** `leader_character_id`, 파티장 본인 거절.
- `spacetimedb/src/party.rs:112-116,435-463,472-493,725-796` — `following_character_id`는 hunt lead 확장 전제; disband/kick/`remove_member`가 following 정리·리더 승계(leave 시 추종자 **이전 없음**, promote와 다름).
- `spacetimedb/src/party.rs:39-45,722-724` — 좌표를 party view에 실지 말라는 경고; `remove_member` 주석이 “나중에 접속 종료” 공용 처리를 예고하나 **아직 미연결**.
- `spacetimedb/src/lib.rs:236-241` · `world.rs:1307-1309` — disconnect/`leave_world`는 **`world_player`만 삭제**.
- `spacetimedb/src/world.rs:275-291` — `world_player` **public**, `character_id` **unique** → `WHERE character_id = N` 구독 후보.
- `lib/spacetime/cyborg_connection.dart:41-44,82-110,121-125` — 플레이어 청크 74타일·3×3; 파티 view 3종 구독.
- `lib/spacetime/spacetime_world_presence.dart:47-50,206-231` — 청크 히스테리시스 **8타일** + 재구독 쿨다운 **1.5초**.
- `lib/game/action_rpg_game.dart:845-917,889-901` — `_followTarget` = `presence.others` ∩ **`leaderCharacterId`만**; null → `lost` → `set_following(false)`.
- `lib/game/action_rpg_game.dart:766-809,877-884,995-1016,1783-1826` — 추종 `anchor`→`autoHunt`; 공격 `tryMelee`; 추종 시작은 `_runPartyAction` 미사용; 사망 시 자동사냥만 끄고 **즉시** `respawnAt`.
- `lib/game/entities/enemy.dart:535-542` · `spacetime_world_presence.dart:329-333` — 서버 몹 피격 → `attack_monster`.
- `lib/game/ui/party_panel.dart:69-73,422-446,449-496` — 초대 40타일·행 탭=초대/위임; footer=추종·해산·나가기; **kick 없음**; `PartyInviteCard` 자동 표시(첫 미만료 1건).
- `lib/spacetime/spacetime_party.dart:42-47,132-142` — `changes = members+invites` only; `kick` API만 존재.
- `lib/game/systems/party_follow.dart:160-199` — `leader==null` → 즉시 lost; 리더 사망 → `hold`; `giveUpDistanceTiles=120`.
- `lib/game/entities/remote_player.dart:22` — `TapCallbacks` 없음.
- 라리엔 `docs/party.md:303-376` — hunt lead ≠ 파티장, 파티당 1, `leadSeq`, 리더 사망 시 세션 유지.
- `.cowork/party-follow/final-report.md:9-16,107-118` — Party 열 3 + reducer 3 + AOI 우회 + `set_following(true)` 폐기.

---

## 3. 상세 분석

### 3.1 시나리오 코드 경로 판정

#### (가) A 초대 → B 초대 카드

| 단계 | 경로 | 판정 |
|---|---|---|
| A 초대 | 패널 ‘근처 요원’(40타일) → `invitePlayerToParty` → `invite_to_party` | **성립**. 무파티면 서버 생성(`party.rs:287-299`). **파티장만** 초대(`:280`). |
| B 수신 | `kPartySubscriptions`의 `my_party_invites` → `PartyInviteCard` | **성립**. 패널 미개방에도 카드(`party_panel.dart:449-452`). |
| 20초 만료 | 클라 `isExpiredAt`로 숨김; 수락 시 서버 `expires_at` | **표시 성립, 카운트다운 UI 없음**. |
| 수락 후 목록 | 멤버 insert → 양쪽 `my_party_members` | **성립**. |
| 거절 사유 | `_runPartyAction` + `SpacetimeDbReducerException` | **성립**(한국어 문장). |
| 함정 | 초대 직후 낙관 배너(`action_rpg_game.dart:939`) | 실패해도 “초대했다”가 먼저 뜸. |

다중 초대 시 **첫 미만료 1건만** 표시(`party_panel.dart:490-495`).

#### (나) B 파티장 추종 → A 추적

```
togglePartyFollow
  → party.setFollowing(true)          // 서버: following = leader_character_id
  → 매 프레임 _updatePartyFollow
      → _followTarget() = presence.others ∩ leaderCharacterId
      → PartyFollowController → autoHunt.moveAnchor | enable
```

- **AOI 안·리더 생존**: 경로 끊김 없이 성립.
- **리더가 팔로워 3×3 밖**: `_followTarget()==null` → 거리 검사 전에 `lost` → 서버 추종 해제.  
  `giveUpDistance=120`보다 **구독 공백이 먼저** 터질 수 있음. 재구독은 8타일 inset + 1.5s 쿨다운으로 경계에서 더 늦게 따라감.
- **설계 어긋남**: 서버는 `following_character_id`에 “누구”를 담지만, 클라는 **`leaderCharacterId`만** 본다(`:889-901`). 지금은 set_following이 리더만 넣어 우연히 동치. **hunt lead 시 즉시 붕괴.**
- 추종 시작(`:1016`)은 `_runPartyAction`/`_pushFollowing`과 달리 **예외 배너 없음** — 거절·네트워크 실패 시 “시작” 배너만 남고 서버 상태 false.

#### (다) 추종 중 자동 공격

- 후보: 로컬 `enemies` = 서버 몹 스트리밍.
- `AutoHuntAction.attack` → `tryMelee` → `_resolveMeleeHit` → `Enemy.applyDamage` → 서버 몹이면 `presence.attack` → `attack_monster`.
- 추종 `anchor`가 리더 그리드로 이동 → 주변 사냥 이어짐.
- **성립.** 순수 로컬 웨이브 전용이 아님.
- 추종 중 자동사냥 off면 `anchor` 분기에서 **강제 enable**(`:880-883`) — “추종=자동사냥 한 몸”.

#### (라) disband / leave / kick

| 행위 | 서버 | 클라 | 판정 |
|---|---|---|---|
| leave | `remove_member` — following 정리, 승계 또는 해산 | 추종 중이면 `_stopFollowing` 후 leave | **정리 성립**. 낙관 “나왔다” 배너. |
| disband | 멤버·초대·파티 삭제 | 배너+disband; 멤버 소멸로 `isFollowing` false | **성립**. **autoHunt는 남을 수 있음**. |
| kick | `remove_member` 동일 | **UI·`game.kick*` 0** | **기능 미노출**. 추방 전용 배너 없음. |

#### (마) 파티장 접속 끊김

- 서버: `world_player`만 삭제. **Party / PartyMember / following 유지**.
- 추종자: presence 실종 → `lost` → 로컬 해제 + (성공 시) `set_following(false)`.
- **증상**: 패널에 “접속 중이 아님”(AOI 이탈과 동일 문구), 멤버십 잔존, 재초대 “이미 파티”, 슬롯 점유. 리더 재접속 시 파티 유지·추종은 이미 끊긴 상태일 가능성 큼.
- 로그아웃도 `party.detach()`만, `leave_party` 없음(`action_rpg_game.dart:1654-1656`) — 월드 밖 파티 유지 의도(`party.rs:619-622`)와 강제 종료 좀비가 구분되지 않음.

#### (바) 파티원 사망 → 부활 후 추종

- `onPlayerDied`: 자동사냥 off, **추종 서버 상태 유지**, **같은 호출 안에서** `respawnAt` → 사실상 즉시 생존.
- “죽은 동안 `_updatePartyFollow` skip”은 코드에 있으나(`:854-856`) **유의미한 지속 상태가 아님**(1차 과장).
- 부활 직후 리더가 멀면 `giveUpDistance=120` 또는 rejoin timeout(8s)로 lost. **가까운 경우만 재개.**

리더 사망: `hold`로 앵커 유지·거리 판정 스킵 → 안전지대 재집결 정책과 정렬(라리엔 §10.5.5).

#### (사) 12명 만석 · 이미 파티인 대상

- 서버: `파티가 가득 찼다(최대 12명).` / `상대가 이미 다른 파티에 있다.`
- 클라: `_runPartyAction` 배너. `isFull`은 모델에만 있고 근처 초대 경로에서 **선차단 없음**.
- **성립**(왕복 후 거절).

---

### 3.2 알려진 결함 2개 재확인

1. **AOI 추종 끊김** — **실재·치명.** null = “월드에서 사라졌다” 메시지(`party_follow.dart:163-166`)로 오프라인과 동일 취급.
2. **`changes`에 `my_party` 없음** — 사실. 현재 Flame UI는 `render`마다 poll이라 **당장 초대/멤버 목록은 돌아감**. promote만 하고 팔로워 following 행이 0건이면 Listenable 기반 배너는 못 받음. **hunt lead를 Party 행에 두면 필수 수정.**

---

### 3.3 1차 목록 밖 추가 결함

| 결함 | 근거 | 체감 |
|---|---|---|
| `_followTarget`이 `followingCharacterId` 무시 | `:889-901`; 세션에 self following id 편의 getter 없음 | hunt lead 불가 |
| `togglePartyFollow` 예외 무음 | `:1016` vs `_pushFollowing` `:922-927` | 상태·배너 어긋남 |
| 낙관 배너 | 초대/나가기/해산/추종 시작 | 실패 메시지와 충돌 |
| kick 미연결 | 세션·reducer만 | 난입 대응=해산뿐 |
| 파티원 행 탭=즉시 promote | `party_panel.dart:428-430` | 오탭 위임 |
| AOI 밖 = “접속 중이 아님” | `:149` | 오프라인·거리 구분 불가 |
| 이끌기·PC 탭·교환 | grep / remote_player | 요청 미충족 |
| 파티 중 비파티장 초대 진입점 없음 | 근처 목록은 `!inParty`일 때만 | 멤버가 친구 못 부름(서버도 파티장만) |

---

### 3.4 파티 이끌기 설계 재검증

직전 종합:

- `Party` 맨 끝 `hunt_lead_character_id` / `hunt_lead_seq` / `hunt_lead_name` + `#[default]`
- `start_hunt_lead` / `stop_hunt_lead` / `accept_hunt_lead(lead_seq)`
- `set_following(true)` 파티장 고정 **폐기**
- AOI 우회

**골격은 여전히 타당.** 지지: `following_character_id` 확장 주석, 파티당 1행=세션 1, 전원 `my_party` 구독=방송, `lead_seq`≈초대 id.

**좌표 경로만 수정 강화:**

| 항목 | 직전안 | Pass2 판정 |
|---|---|---|
| AOI 우회 | `my_hunt_lead_target` view 우선 | **공개 `world_player` + `character_id` unique 추가 구독을 1순위**로. party 머리말이 좌표 view 재전송을 경고(`:39-45`). view는 Type2·recompute 부담. 대상 변경 시 구독 갱신은 필요. |
| disconnect | 언급 | **구현 필수.** 멤버면 following/hunt clear(멤버십 유지 vs leave는 제품 선택). |
| `set_following(true)` | 폐기 | **동의.** false만 개별 해제. |
| promote following 이전 | 조건부 | **동의.** hunt 활성 중 이전 금지. |
| 누구나 이끌기 | 채택 | 라리엔·주석 일치; 제품 확인. |

**기각:** UI 라벨만 “이끌기”로 바꾸기 — 비파티장 지휘·follow 버튼 흐름과 불일치.

---

### 3.5 범위 경계

| 영역 | 권위 | 비고 |
|---|---|---|
| 멤버십·초대·following 의사 | 서버 reducer | 클라 신뢰 안 함 — 올바름 |
| 이동·사냥 실행 | 클라 `PartyFollow`+`AutoHunt` | 서버 시뮬 없음 — 전제 수용 |
| 몹 피해·킬 | 서버 `attack_monster` | 추종 사냥 동일 |
| 리더 좌표 | 현재 AOI `world_player` | 추종 SSOT 아님 → 결함 |

---

## 4. 리스크 · 함정

- **AOI×추종**: 미수정 시 청크 경계에서 “추종 고장”으로 인식. hunt lead만 넣으면 동일 결함 재발.
- **disconnect 좀비**: 정원 점유·재초대 불가·following 잔존.
- **스키마 배포**: Party 열 추가 = maincloud publish + `generated/` 재생성; 세션 간 충돌.
- **좌표 view**: 모듈이 경고한 recompute; Type2 함정.
- **낙관 배너·setFollowing 비대칭 에러 처리**.
- **kick 부재·promote 오탭**.
- **실서버·DTD 미실행**(읽기 전용) — 경로 추론.
- **문서 불일치**: cowork-prompt Overview의 “실시간 멀티 없음” 등과 달리 파티·presence·서버 몹 존재 — **코드 기준**.

---

## 5. 권고안

| 순위 | 권고 | 범위 | 근거 | 리스크 |
|---|---|---|---|---|
| 1 | **추종 좌표 SSOT** — 대상 `character_id`로 `world_player` 추가 구독(권장) 또는 `my_hunt_lead_target`. `_followTarget`은 **`followingCharacterId`(없으면 leader)** + presence 폴백. null만으로 즉시 lost 금지(타임아웃·giveUp·마지막 좌표 grace). | 클라 구독 + `action_rpg_game.dart` · 선택적 서버 view | AOI, `:889-901`, `world.rs:287-291`, `party.rs:39-45` | 구독 트래픽; 대상 변경 시 resub |
| 2 | **disconnect/leave_world 훅** — `remove_member` 공용 경로 연결 또는 멤버십 유지+following/hunt clear. | `lib.rs`, `party.rs` | `:236-241`, `:722-724` | 제품(파티 유지 여부) |
| 3 | **hunt lead 서버** — Party 끝 열 3 + start/stop/accept(+seq); remove/disband 정리; `set_following(true)` 파티장 고정 제거 | `party.rs` | 직전 final-report, 라리엔 §10.5 | 배포 되돌리기 어려움 |
| 4 | **클라 이끌기 UX** — footer 상태, HuntLeadCard, `_followTarget` 교체, 서버 주도 해제 배너 | `party_panel`, `action_rpg_game`, `spacetime_party` | 사용자 요구 | UI 높이·12인 |
| 5 | **신뢰성** — 초대/leave/추종을 `_runPartyAction` 통일(성공 후 배너); `changes`에 `my_party.rows` | `spacetime_party`, `action_rpg_game` | `:939`, `:1016`, `:47` | 낮음 |
| 6 | **kick UI** + 추방 감지 배너; promote 확인 | `party_panel` | kick API만 | 오터치 |
| 7 | **PC 클릭 + 컨텍스트 바**(이끌기 다음) — `RemotePlayerEntity` TapCallbacks, 교환 “준비 중” | `remote_player`, UI 신규 | final-report §7 | 히트박스 회귀 |
| 8 | **검증** — `cargo test` → publish → generate(1인) → `flutter test` → DTD `main()` 주입 2계정: 초대/추종/AOI 횡단/disconnect | CLAUDE.md | — | generated 충돌 |

**구현 순서:** 1→2(기존 파티장 추종 고정) → 3→4 → 5→6 → 7.  
hunt lead만 넣고 AOI를 안 고치면 이끌기도 즉시 깨짐.

---

## 6. 불확실 · 미확인

- **실서버·DTD 런타임 미실행** — 초대 카드·추종·`attack_monster`는 경로 추론.
- **disconnect 시 멤버십 유지 vs 자동 leave** — 코드 주석=유지, 좀비 방지=leave. **사람 결정**.
- **`WHERE character_id = N` 구독 실측** — unique 등식은 스키마상 가능, 배포 환경 미검증 `[추측]`.
- **view 좌표 recompute 빈도** — 모듈 주석 수준.
- **‘누구나 이끌기’ vs 파티장만** — 설계 권고는 누구나.
- **클라 시계 오차**와 초대 카드 표시 오차 실측.
- **12명 전원 following** 시 전송·자동사냥 부하 실측 없음.

**한 줄 판정:** 1차는 “근처 초대 + 파티장 추종 + 자동사냥 연동”까지이나 **AOI·disconnect·kick·이끌기**가 비어 요청 세트는 아직 올바르지 않다. 우선순위는 **추종 좌표 경로 고정 → disconnect 정리 → hunt lead**.

---

## 7. 자기 비판으로 바로잡은 것

- ❌ **철회/약화:** “사망 중 `_updatePartyFollow` skip이 의미 있는 상태” — `onPlayerDied`가 같은 호출에서 `respawnAt`을 호출(`action_rpg_game.dart:1783-1800`)하므로 지속 사망 구간은 사실상 없다. 실체는 **즉시 안전지대 이동 후 거리 의존 재개/끊김**.
- ❌ **철회:** 근거 `party_panel.dart:…936-991` — 해당 줄은 `party_panel`에 없음. 낙관 배너·`_runPartyAction`은 `action_rpg_game.dart:936-991` 근처.
- 🔁 **수정:** “히스테리시스 1.5s”만 → **8타일 inset + 1.5s 재구독 쿨다운**(`spacetime_world_presence.dart:47-50,219-230`).
- 🔁 **수정:** AOI 우회 1순위를 `my_hunt_lead_target` view 단독 권장 → **`world_player` `character_id` 추가 구독 우선**(표 public·unique, party 좌표 view 경고와 정합). view는 대안.
- 🔁 **수정:** `changes` “치명도 낮음” 유지하되, 현재 poll UI 한정; **hunt lead Party 필드에는 필수**로 격상.
- ➕ **추가:** 추종 시작 `setFollowing(true)` 예외 무음(`:1016`) vs 해제 시 `_pushFollowing` 배너 — 비대칭 신뢰성 결함.
- ➕ **추가:** 멤버 행 탭=확인 없는 즉시 `promote`(`party_panel.dart:428-430`); 파티 중 비파티장 초대 진입점 부재.
- ➕ **추가:** `remove_member` 주석이 disconnect 공용 처리를 예고(`party.rs:722-724`)하나 `on_disconnect` 미연결 — 설계 부채가 코드에 명시됨.
- ➕ **추가:** disband 후 **autoHunt 잔존** 가능(추종 플래그만 서버/멤버십 소멸로 꺼짐).
- ✅ **유지(재검증 통과):** AOI null→lost, disconnect 좀비, hunt lead 0, kick UI 0, 자동공격→`attack_monster` 경로, 직전 hunt lead 스키마 골격.
