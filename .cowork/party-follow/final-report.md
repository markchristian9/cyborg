# 종합 검토 — party-follow

> 요청: 파티 기능과 파티 리더를 추종 & 사냥하는 기능을 추가해주세요. 형제 게임: 라리엔 폴더를 읽기 전용으로 참고해서 기능을 참고/복사하면 됩니다.
> 분석: claude ✅ · grok ✅(2-pass) · **codex ❌ 제한시간 900s 초과로 제외** · **kimi ❌ 제한시간 초과 — 단 부분 출력이 §3.4 까지 남아 보조 근거로만 사용**
> 종합: 2026-08-04 23:00 · 읽기 전용 분석 — 작업공간 미수정

## 1. 결론

**파티 멤버십·초대는 SpacetimeDB 신규 `party.rs` 모듈(비공개 표 + view)에 두고, 리더 추종과 사냥 실행은 전적으로 클라이언트가 한다.** 서버에 tick 시뮬레이션이 없기 때문이다 — 유일한 주기 작업은 5초 몬스터 리스폰이고(`world.rs:130,867`), 이동 권위는 "클라가 좌표를 보고하고 서버는 속도 상한만 본다"(`world.rs:132-139`)이다. 라리엔의 `updatePartyFollowAnchors`(Zone 30Hz)는 **개념만** 가져오고 실행부는 버린다. 추종의 실체는 `AutoHuntController.moveAnchor(리더 좌표)` 한 줄이며, 이 메서드는 이미 존재한다(`auto_hunt.dart:182`).

**경험치·드롭 분배는 도입하지 않는다.** 선점 태그(`world.rs:818-847`)가 PK 동기와 한 세트인 코어 서사이고, 무엇보다 클라이언트가 `attack_monster` 를 **한 번도 부르지 않아**(호출 0건, 검증됨) `award_kill` 경로 자체가 죽어 있다. 지금 분배를 넣는 것은 아무도 지나가지 않는 길에 표지판을 세우는 일이다. 문서를 "동행 파티 + 솔로 보상"으로 개정한다.

**1차 범위는 "파티장(party leader) 고정 추종"이다.** 사용자 요청 문구가 "파티 리더를 추종"이므로, 라리엔의 party leader ≠ hunt lead 분리(누구나 이끌기)는 상위 집합이라 P2 로 미룬다.

**판정 못 한 것**: 파티 최대 인원, 리더 접속종료 시 파티 유지/해산/자동승계, 파티원 간 PK 허용 여부는 제품 결정이라 코드로 판정할 수 없다(§8).

**⚠️ 이 저장소는 지금 최소 세 세션이 동시에 편집 중이다.** 그 사실이 권고 1순위를 바꿨다(§5).

## 2. 두 AI 의견 대조

| 쟁점 | claude | grok | 검증 결과 |
|---|---|---|---|
| 추종 실행 위치 | 클라이언트 | 클라이언트 | ✅합의 — `world.rs:129-130,664-705` 확인 |
| 멤버십 권위 | 서버 표+reducer | 서버 표+reducer | ✅합의 — `lib.rs:9-18` 클라 불신 원칙 |
| 경험치 분배 | 도입 안 함 | 도입 안 함 | ✅합의 — 근거 3겹 모두 검증됨 |
| 파티 표 공개 여부 | 비공개 + view | 비공개 + view | ✅합의 — `world.rs:33-39` 공개 예외 기준 |
| PMEMB 청크·PINV 재전송 | 버림 | 버림 | ✅합의 — 이유가 UDP MTU/손실(`party.md:131-134,378-384`) |
| leadSeq / invite id | 가져옴 | 가져옴 | ✅합의 — 이유가 stale 수락 차단(`party.md:363`) |
| **1차 범위** | hunt lead 세션 포함(`PartyLead` 표) | **MVP=party leader 고정**, hunt lead 는 P2 | ⚖️**판정: grok** — 요청 문구가 "파티 리더 추종" |
| `attack_monster` 미연결의 무게 | §3.5 판정 근거로만 사용 | **리스크·권고 7순위로 격상** | ⚖️**판정: grok** — 사용자 기대와 직결 |
| 앵커 경쟁 지점 줄번호 | `:662,992,1231,1385` | `:1020-1023,1408-1414` | ❌**둘 다 틀림** — 현재 `:675,938,1176,1436`(§6) |
| 다른 팀 진척도 | "①②③ 이미 완료, ④만 남음" | "presence 이미 존재" | ✅합의 — 직접 확인됨(§3) |

## 3. 합의 — 검증 통과

- **다른 팀의 월드 연결 작업은 이미 대부분 코드에 들어와 있다.** 확인: `lib/spacetime/spacetime_world_presence.dart`(22:36 생성)·`lib/game/entities/remote_player.dart`(22:37)·`cyborg_connection.dart:39-41` 의 `kWorldSubscriptions = ['SELECT * FROM world_player']`·`action_rpg_game.dart:545`(`presence.report`)·`:556`(`presence.others`)·`:1400`(`presence.enter()`)·`:1217`(`presence.leave()`). **내가 이 작업을 시작할 때(22:36) 본 것보다 훨씬 진척돼 있다.** 따라서 "월드 연결이 선행 과제"라는 결론은 낡았고 채택하지 않는다.

- **서버에 이동 시뮬레이션이 없다.** 확인: `world.rs:132-139` 가 "완전한 서버 이동 시뮬레이션은 조작에 더 강하지만 예측·롤백을 함께 만들어야 하고, 그 비용은 지금 단계에서 얻는 것보다 크다"고 그 절충을 **명시적으로 선언**한다. `monster_tick` 은 5초 주기 리스폰 전용(`world.rs:130,867-892`). 라리엔식 서버 앵커 갱신은 이식 불가.

- **`attack_monster` 는 클라이언트에서 한 번도 호출되지 않는다.** 확인: `grep -rn "attackMonster" lib/ --include "*.dart" | grep -v generated/` → **0건**. 자동 사냥은 로컬 `Enemy`(`MonsterPopulation.generate`)만 때린다. 즉 지금 추종을 붙여도 "리더 옆으로 따라가 로컬 몹을 잡는" 것이지 **서버가 아는 같은 몹을 함께 잡는 것이 아니다.**

- **view 반환 타입은 반드시 `#[spacetimedb::table]` 이어야 한다.** 확인: `leaderboard.rs:145-155` 가 "클라이언트 코드 생성기가 view 반환 타입의 이름을 **표 목록에서만** 찾기 때문이다. 표가 아니면 생성기가 이름을 잃고 `Type2` 같은 존재하지 않는 클래스를 참조하는 코드를 뱉는다"고 그 함정을 문서화해 뒀다. 파티 view 도 이 패턴 필수.

- **PMEMB 청크 분할·PINV 재전송을 버리는 근거가 확실하다.** 확인: 라리엔 `docs/party.md:131-134` 는 청크 이유를 "32명 풀파티는 한 패킷이 UDP MTU(1500B)를 초과"로, `:378-384` 는 재전송 이유를 "UDP 단발이라 패킷이 손실되면"으로 **명시**한다. SpacetimeDB 는 wss(TCP) 위 행 단위 구독이라 두 문제가 존재하지 않는다. 반면 `:363` 의 `leadSeq` 는 이유가 손실이 아니라 "stale/cross-party 수락 차단"이라 **전송 계층과 무관하게 필요하다** — 이 구분이 두 AI 판정의 핵심이고, 자료가 이를 지지한다.

- **`on_disconnect` 은 `world_player` 만 지운다.** 확인: `lib.rs:207-214`. 세션은 의도적으로 유지한다("앱을 잠깐 백그라운드로 보내거나 네트워크가 끊길 때마다 다시 로그인해야 한다"). 파티 멤버십을 여기서 지울지는 제품 결정이며, 지우지 않으면 "고아 파티 + 추종 좀비"를 클라가 막아야 한다.

## 4. 이견 — 자료로 판정

### 쟁점 A: 1차 범위에 hunt lead 세션(누구나 이끌기)을 넣는가

- claude: `PartyLead` 표(파티당 1세션, `lead_seq`, `leash_tiles`)를 1차 스키마에 포함하고 `start_hunt_lead`/`accept_hunt_lead`/`stop_hunt_lead` reducer 를 만든다.
- grok: MVP 는 `party.leader_character_id` 고정 추종. hunt lead 분리는 P2. 이유는 "요청 문구가 '파티 리더 추종'이고 라리엔 §10.5 는 상위 집합".
- **판정: grok 이 맞다.** 사용자 요청은 "파티 리더를 추종 & 사냥"이며, 라리엔이 party leader 와 hunt lead 를 **분리한 이유**는 `docs/party.md:306` 이 밝히듯 "파티장의 권한 기능이 아니라 파티 내 임시 사냥 지휘"를 원했기 때문이다 — 그것은 라리엔의 추가 요구이지 이번 요청이 아니다. 다만 라리엔이 그 분리에 도달한 것은 실사용 후이므로(`party.md:303` "✅ 구현 완료"), **표 설계에서 확장 여지는 남긴다**: 추종 대상을 `party.leader_character_id` 로 고정하지 말고 `party_member.following_character_id: Option<u64>` 로 두면, P2 에서 "리더가 아닌 사람을 따르기"가 스키마 변경 없이 열린다. 이 점은 claude 의 스키마(`party_member` 행에 추종 상태를 함께 두는 설계)가 우수하다 — **두 안의 좋은 쪽을 결합한다.**

### 쟁점 B: `attack_monster` 미연결을 얼마나 무겁게 다루는가

- claude: 경험치 분배를 도입하지 않는 **근거**로만 사용("아무도 지나가지 않는 길").
- grok: 그것과 별개로 **사용자 기대 관리 문제**로 격상 — 권고 7순위 "추종 UI/배너에 '로컬 사냥·서버 킬 미연동' 한계를 드러내라".
- **판정: grok 이 맞다.** 검증 결과 `attackMonster` 호출 0건이 사실이고, 이는 "파티로 함께 사냥"이라는 사용자 기대와 실제 동작 사이에 실질적 간극을 만든다. 리더를 따라다니며 각자 **자기 화면의 로컬 몬스터**를 때리는 것이므로, 두 사람이 "같은 몹"을 잡는 장면은 아직 성립하지 않는다. 이것을 조용히 두면 나중에 "파티 버그"로 오인된다.
- **근거**: `lib/game/action_rpg_game.dart:137,243` 의 `MonsterPopulation.generate`(로컬 개체군) + `attack_monster` 호출 부재 + `world.rs:788-863` 의 서버 판정 경로가 사용되지 않음.

### 쟁점 C: 앵커 경쟁 지점의 위치

- claude: `:662`(토글) `:992`(클릭) `:1231`(텔레포트) `:1385`(사망)
- grok: 1차 자기 주장을 철회하고 `:1020-1023`(클릭) `:1408-1414`(사망)로 정정
- **판정: 둘 다 현재 코드와 맞지 않는다.** 직접 확인한 현재 위치는 `:675`(`autoHunt.toggle`) `:929-938`(클릭→`moveAnchor`) `:1176`(텔레포트→`moveAnchor`) `:1336-1337`·`:1436`(`autoHunt.disable()`). grok 이 자기 비판 라운드에서 줄번호를 고쳤는데도 여전히 어긋난 이유는 **파일이 지금 이 순간에도 편집되고 있기 때문**이다(§5). 결론(앵커 소유권 문제가 존재하며 네 지점에서 경쟁한다)은 유효하나, **줄번호는 구현 직전에 반드시 다시 찾아야 한다.**

## 5. 고유 통찰 — 검증됨

- **claude**: "`lib/spacetime/generated/` 재생성 충돌이 최대 위험." — 확인: 이 디렉토리는 서버 스키마에서 통째로 재생성되며, 다른 팀도 `world_player.dart` 를 위해 이미 한 번 돌렸다. 파티 표를 추가하면 다시 돌려야 하는데, 두 팀이 각자 다른 시점의 스키마로 재생성하면 **서로의 새 표가 조용히 사라진다.** 이것은 컴파일 에러가 아니라 "표가 없다"는 런타임 증상으로 나타나 발견이 늦다.

- **claude**: "파티 view 에 좌표·HP 를 담으면 안 된다." — 확인: `spacetime_world_presence.dart` 가 좌표를 주기적으로 보고하고, `cyborg_connection.dart:44-47` 이 "순위표는 **누가 레벨업하든** 다시 계산되어 구독자 전원에게 밀려온다"며 같은 함정을 이미 기록해 뒀다. view 가 `world_player` 를 읽으면 좌표 보고 하나하나가 전 파티 구독자 재푸시를 부른다. **view 는 멤버십(character_id·name·level·리더 여부)만 싣고, 좌표·생사는 클라가 이미 구독 중인 `presence.others` 에서 `characterId` 로 조인한다.**

- **claude**: "`WorldPresence` 가 abstract 이고 모든 메서드에 기본 구현이 있어 상속만으로 가짜를 만들 수 있다." — 확인: `world_presence.dart:40-60` 의 모든 메서드가 기본 구현을 가지며 `OfflineWorldPresence:63-71` 이 그 예시다. **다른 팀 파일을 한 줄도 고치지 않고** `FakeWorldPresence` 로 추종 로직을 단위 테스트할 수 있다.

- **grok**: "라리엔의 로컬 UUID partyId 를 복사하면 안 된다." — 확인: 라리엔 `party_controller.dart:11-22` 가 밝히듯 그것은 **Nakama WebSocket 이 파티 신청의 단일 실패 지점이던 문제를 우회**하려는 특수사다. SpacetimeDB 는 서버가 초대 행을 검증하므로 `auto_inc` 가 맞다. 라리엔에서 "왜 그렇게 했는지"를 읽지 않고 결과만 복사하면 없는 문제를 흉내 내게 된다.

- **grok**: "`ActionRpgGame` 의 `presence` 생성자 DI." — 확인: `action_rpg_game.dart` 가 `presence` 를 생성자로 받는다. `FakeWorldPresence` 주입 전략의 직접 근거이며, 우리 `PartySession` 도 같은 패턴을 따르면 배선이 한 줄로 끝난다.

## 6. 반증 — 근거가 틀린 주장

- **claude·grok 공통**: 앵커 경쟁 지점 줄번호 — ❌ 직접 열어보니 현재는 `:675,929-938,1176,1336-1337,1436` 이다. 두 AI 가 각각 다른 값을 댔고 grok 은 자기 비판에서 한 번 고쳤는데도 여전히 어긋난다. **파일이 분석 도중에도 계속 바뀌기 때문**이며, 이는 근거의 신선도 자체가 짧다는 뜻이다. 결론은 유지하되 줄번호는 재확인 대상.

- **claude**: "다른 팀 잔여 작업은 ④(줌 버튼)와 안정화뿐" — ⚠️ 부분적으로만 맞다. 확인 결과 `git status` 상 `action_rpg_game.dart`·`hud.dart`·`touch_controls.dart`·`auto_hunt.dart`·`drop_table.dart`·`palette.dart`·`main.dart`·`teleport_destinations.dart`·`character_screen.dart` 가 모두 수정 중이고 `wave_director.dart` 는 **삭제**됐다. 다른 팀의 작업 범위는 claude 가 파악한 4항목보다 훨씬 넓다.

- **claude 보고서 자체의 손상**: `claude-cowork.md:297-310` 에 `## 6. 불확실` 절이 **두 번** 나오고 그 사이 표가 잘려 있으며 깨진 문자(`�`)가 섞여 있다. 297줄 이후 내용은 앞 절과 중복·모순되므로 채택하지 않았다. (예: 뒤쪽 §6 이 "멀티플레이 배선이 선행되어야 한다"고 하는데 이는 자기 §3.1 의 검증 결과와 정면 모순이다.)

- **요청 프롬프트 자체가 낡았다**: 내가 4 AI 에게 준 전제 "구독 목록 `cyborg_connection.dart:28-32` 에 `world_player` 가 없다"는 분석 시작 시점(22:38)에 이미 사실이 아니었다. 현재 `:39-41` 에 `kWorldSubscriptions` 가 있다. 두 AI 모두 이를 스스로 잡아냈다 — 프롬프트의 전제보다 코드를 우선한 판단이 옳았다.

## 7. 최종 권고

**전제 — 이 저장소는 최소 세 세션이 동시에 편집 중이다.** 확인된 사실:
- 팀 A(월드 연결): `world_presence.dart`·`spacetime_world_presence.dart`·`remote_player.dart`·`world_tree.dart` 신규 + `hud.dart` 미니맵 + 카메라/줌
- 팀 B(서버 권위): `.cowork/server-authority/` 에서 **"서버 권위 이동·사망·HP/MP·스킬 판정, 클라는 렌더링만"** 을 분석 중(22:43 시작, 아직 분석 단계)
- 팀 C(자동 사냥): `auto_hunt.dart` 에 차단 시간 지수 백오프를 **지금 추가 중**(`blockDuration` → `blockDurationBase`/`blockDurationMax`)

| 순위 | 권고 | 범위 | 근거 | 리스크 | 검증 방법 |
|---|---|---|---|---|---|
| 1 | **파일 소유권 경계를 지켜 신규 파일 위주로 만든다.** 우리 소유: `spacetimedb/src/party.rs`, `lib/game/net/party_session.dart`, `lib/spacetime/spacetime_party.dart`, `lib/game/systems/party_follow.dart`, `lib/game/ui/party_panel.dart`, `test/party_*.dart`. **절대 수정 금지**: `auto_hunt.dart`(팀 C 편집 중), `world_presence.dart`·`spacetime_world_presence.dart`·`remote_player.dart`·`world_tree.dart`·`hud.dart` 미니맵(팀 A) | 협업 규약 | `git status` 15개 파일 수정 중, `auto_hunt.dart` diff 확인 | 무시하면 rebase 충돌 | `git status` 로 우리 변경이 신규 파일에 몰렸는지 확인 |
| 2 | **문서부터 개정** — `CLAUDE.md:33-34`, `GAME-DESIGN.md:781`. 코드 0줄이라 충돌 위험이 없고, 먼저 해 두어야 이후 작업이 "규칙 위반"으로 보이지 않는다 | 기획 문서 | `CLAUDE.md:33-34` 와 요청이 정면 충돌 | 없음 | 문구 검토 |
| 3 | **서버 `party.rs` 신규 모듈** — 비공개 표 `Party`·`PartyMember`·`PartyInvite` + view `my_party`/`my_party_members`/`my_party_invites`. 모든 reducer 는 `require_world_player(ctx)`(`world.rs:900-906`)로 캐릭터를 **세션에서 도출**한다. 기존 파일 수정은 `lib.rs` 에 `pub mod party;` 한 줄 | `spacetimedb/` | `lib.rs:9-18`, `world.rs:33-39,900-906`, `character.rs` 소유자 검증 패턴 | 새 표라 기존 열 변경 없음 | `cd spacetimedb && cargo test` |
| 4 | **view 에 좌표·HP 를 넣지 않는다.** 멤버십만 싣고 위치·생사는 `presence.others` 와 `characterId` 로 조인. 반환 타입은 행을 넣지 않는 비공개 표로 선언 | `spacetimedb/` | `leaderboard.rs:145-155`(`Type2` 함정), `cyborg_connection.dart:44-47`(재푸시 함정) | 잘못 만들면 되돌리기 어렵다 | `cargo test` + Dart 재생성 후 컴파일 |
| 5 | **`PartySession` 추상화를 `WorldPresence` 와 똑같은 패턴으로** — 인터페이스는 `lib/game/net/`, 구현은 `lib/spacetime/`, 기본값 `OfflinePartySession`. `ActionRpgGame` 생성자에 한 개 추가 | `lib/` | `world_presence.dart:40-71` 이 완성된 예시 | 생성자 줄이 팀 A 와 근접 — 마지막에 짧게 | `flutter analyze` |
| 6 | **`PartyFollow` 를 판단/실행 분리 순수 클래스로** — Flame·네트 비의존. `auto_hunt.dart:28-39` 의 `AutoHuntDecision` 철학을 그대로 복제. **`auto_hunt.dart` 는 한 줄도 고치지 않는다** | `lib/game/systems/` | `auto_hunt.dart` 판단/실행 분리 주석, 팀 C 가 그 파일 편집 중 | 없음(신규 파일) | `flutter test test/party_follow_test.dart` |
| 7 | **추종 판단 순서는 라리엔 분기 순서를 따른다**: ① 리더가 `presence.others` 에 없음 → 추종 중단 ② 리더 `alive == false` → 앵커 갱신만 건너뜀(세션 유지) ③ 거리 > 재합류 임계 → **사냥보다 먼저 리더에게 직행**, 타임아웃 초과 시 중단 ④ 그 안이면 `moveAnchor(리더 좌표)` | `lib/game/systems/` | 라리엔 `autopilot.go` 의 "탐색보다 먼저 복귀"(`party.md:337-342`), 리더 사망 시 세션 유지(`party.md:369-373`) | ③ 의 타임아웃이 A\* 부재의 대체물 — 벽 뒤 리더에겐 못 붙는다(정직하게 배너로 알린다) | 유닛 테스트로 4분기 전부 |
| 8 | **앵커 소유권 가드를 `action_rpg_game.dart` 에 최소 배선(4~5줄)** — 추종 중에는 땅 클릭의 `moveAnchor` 무시, 자동사냥 토글은 추종 해제로 해석, 사망은 추종 플래그 유지. **줄번호는 구현 직전 재확인**(현재 `:675,929-938,1176,1336-1337,1436`) | `lib/game/` | §4 쟁점 C | 팀 A 와 같은 파일 — 가장 마지막에 | `flutter analyze` + 화면 확인 |
| 9 | **경험치·드롭 분배는 하지 않는다.** `award_kill`·`tagged_by` 를 그대로 둔다 | 판정 | `world.rs:10-27`, `attack_monster` 호출 0건, 봇 파티 악용 위험 | 서버 전투 권위가 붙은 뒤 별도 결정 | — |
| 10 | **한계를 UI 에 드러낸다** — 파티 패널·추종 배너에 "경험치는 각자", 그리고 서버 몹 연동 전까지는 "각자 자기 몬스터를 사냥한다"는 취지를 표시 | UX | `attack_monster` 호출 0건 | 숨기면 "파티 버그"로 오인 | 스크린샷 |

**검증안 (CLAUDE.md 준수 — 키보드/클릭 주입 없음)**

| 단계 | 방법 | 근거 |
|---|---|---|
| 서버 권한·상태기계 | `cd spacetimedb && cargo test` — 초대 TTL, 인원 상한, 비리더 추방 거부, stale invite 거부 | `world.rs:984-1133` 테스트 패턴 |
| 추종 판단 | `flutter test test/party_follow_test.dart` — 좌표만 가진 가짜 리더로 4분기 검사. Flame 불필요 | `test/auto_hunt_test.dart` 의 가짜 객체 패턴 |
| 다른 팀 구현 없이 주입 | `class FakeWorldPresence extends WorldPresence { ... }` — 상속만으로 됨(그들 파일 무수정) | `world_presence.dart:40-71` |
| **2계정 실서버 파티** | `test/party_integration_test.dart` — `InMemoryTokenStore()` 로 client 두 개를 만들어 각각 가입·캐릭터·`enter_world` → A 가 초대, B 가 수락 → 양쪽 `my_party` 가 2명인지 확인. **사람 손이 전혀 필요 없다** | `test/world_presence_test.dart:22-60` 이 이미 이 패턴을 완성해 뒀다 |
| 화면 확인 | `main()`/`initState()` 에 파티 상태를 주입해 패널이 뜬 채로 앱을 띄우고 스크린샷 + 로그 확인 | `CLAUDE.md` DTD 규정, 라리엔도 동형(`party.md:257`) |
| 정적 | `flutter analyze` 무결 | 프로젝트 관행 |

## 8. 미해결 · 사람 판단 필요

- **파티 최대 인원.** 라리엔은 32명이지만 그건 Flutter overlay HUD 기준이고, 여기는 Flame 캔버스라 목록 스크롤·클리핑을 직접 그려야 한다. 초기 4~6명이 현실적이다 — 제품 결정.
- **리더 접속종료 시**: 파티 유지 / 해산 / 자동 승계 중 무엇인가. `on_disconnect`(`lib.rs:207-214`)은 `world_player` 만 지우고 세션은 의도적으로 유지한다. 멤버십도 유지하면 재접속 후 파티가 살아 있어 편하지만 "고아 파티"가 생긴다.
- **파티원 간 PK 허용 여부.** 기존 철학(`CLAUDE.md`)의 기본값은 허용이지만 추종 중 오폭은 체감이 나쁘다.
- **리더 텔레포트 동반 방식.** `teleport_to`(`world.rs:743-781`)는 좌표가 아니라 **목적지 이름 5개**만 받고 쿨다운 8초를 강제한다. follower 를 코드로 순간이동시키면 `move_to` 속도 상한(14타일/초, `world.rs:139`)에 걸려 서버가 좌표를 잘라내 화면과 서버가 갈린다. 권고는 "자동 동반 없음 — follower 본인이 같은 목적지 이름으로 호출"이지만 UX 결정이 필요하다.
- **⚠️ 팀 B 의 서버 권위 전환이 이 설계의 전제를 바꾼다.** `.cowork/server-authority/` 가 "서버 권위 이동·사망·HP/MP·스킬, 클라는 렌더링만"을 분석 중이다(22:43 시작). 그것이 구현되면 "서버에 tick 이 없으니 추종은 클라"라는 §1 판정의 근거가 사라지고, 라리엔식 서버 앵커 갱신이 오히려 정석이 된다. **대응**: `PartyFollow` 를 판단/실행 분리 순수 클래스로 만들어 두면(권고 6) 판단부를 서버로 옮기거나 실행부만 reducer 호출로 바꾸는 이식이 가능하다. 두 팀의 일정 조율은 사람이 해야 한다.
- **`lib/spacetime/generated/` 재생성 순서 합의 필요.** 파티 표 추가 시 재생성해야 하는데 팀 A 도 같은 디렉토리를 건드린다. "서버 배포 → 한 사람이 재생성 → 커밋" 순서를 사람이 합의해야 한다.
- **SpacetimeDB 구독 쿼리의 `WHERE` 지원 여부**를 실측하지 못했다. 가능하면 view 없이 `party_member` 를 좁혀 구독할 수 있어 설계가 단순해진다. view 경로가 확실히 되는 길이라 그쪽을 권고했다.
- **codex·kimi 가 제한 시간 초과로 빠졌다.** 프롬프트가 길고 라리엔까지 읽어야 해 900초를 넘겼다. kimi 부분 출력은 claude·grok 과 같은 결론이라 판정을 뒤집을 내용은 없었으나, 두 AI 의 완전한 반증 기회는 없었다.

## 9. 적용 결과

> 적용: 2026-08-04 23:20 · 커밋 `ed58a53`

| 권고 | 적용 | 파일 | 검증 |
|---|---|---|---|
| 1 (파일 소유권 경계) | ✅ 지킴 | 신규 4 + 공유 3(최소) | `auto_hunt.dart`·`world_presence.dart`·`remote_player.dart`·`hud.dart` 를 **한 줄도 고치지 않았다** |
| 2 (문서 개정) | ✅ 적용 (커밋 보류) | `CLAUDE.md`, `GAME-DESIGN.md:786` | 작업 트리에는 반영. 다른 세션 변경이 같은 파일에 섞여 커밋에서 제외 |
| 3 (서버 `party.rs`) | ✅ 적용 | `spacetimedb/src/party.rs`(표 3·reducer 9·view 3), `lib.rs` 1줄 | `cargo test` 40 통과 |
| 4 (view 는 멤버십만) | ✅ 적용 | `party.rs` 의 세 view | 좌표·HP·이름을 한 열도 싣지 않음. 클라가 `presence.others` 와 조인 |
| 5 (`PartySession` 추상화) | ✅ 적용 | `lib/game/net/party_session.dart` | `WorldPresence` 와 같은 모양. `flutter analyze` 무결 |
| 6 (`PartyFollow` 순수 클래스) | ✅ 적용 | `lib/game/systems/party_follow.dart` | Flame·네트 비의존. `flutter test` 12 통과 |
| 7 (라리엔 분기 순서) | ✅ 적용 | `party_follow.dart` 의 5단계 | 거리 판정이 사냥보다 먼저. 히스테리시스로 경계 진동 제거 |
| 8 (앵커 소유권 가드) | ✅ 적용 (커밋 보류) | `action_rpg_game.dart` 5곳 | 배선·가드 완료, 186 테스트 통과. 다른 팀 변경 혼재로 커밋 제외 |
| 9 (경험치 분배 안 함) | ✅ 지킴 | — | `award_kill`·`tagged_by` 를 건드리지 않았다 |
| 10 (한계 표시) | ⏸️ 부분 | `action_rpg_game.dart` 배너 | 추종 시작 시 "경험치는 각자 몫" 배너. 파티 패널 UI 자체는 미구현 |

**구현하지 않은 것과 이유**

- **`SpacetimePartySession`(서버 구현체)** — Dart 바인딩(`lib/spacetime/generated/`)에 `party` 표가 없어 작성해도 컴파일되지 않는다. 바인딩 재생성은 SpacetimeDB 모듈 **배포**가 선행돼야 하고, 그 디렉토리는 다른 세션이 방금 수정했다(작업 중 `generated/client.dart`·`reducers.dart`·`reducer_args.dart` 가 변경됨). §5 가 최대 위험으로 지목한 재생성 충돌 구간이라 **사람의 조율 없이 진행하지 않았다.**
- **파티 패널·초대 토스트 UI** — 위와 같은 이유로 서버 데이터가 아직 클라에 닿지 않아, 지금 만들면 검증할 수 없는 화면이 된다.
- **2계정 통합 테스트** — 서버 배포 후에만 의미가 있다. 패턴은 `test/world_presence_test.dart:22-60` 을 그대로 복제하면 된다.

**커밋 범위**

단독 소유 파일만 커밋했다(`party.rs`·`lib.rs`·`party_session.dart`·`party_follow.dart`·`party_follow_test.dart`·본 분석 폴더). `action_rpg_game.dart`·`CLAUDE.md`·`GAME-DESIGN.md` 는 다른 세션의 미완성 변경이 같은 파일에 섞여 있어 제외했다 — 특히 `action_rpg_game.dart` 는 팀 A 의 미커밋 신규 파일을 import 하므로 단독으로 커밋하면 그 커밋이 컴파일되지 않는다. 작업 트리에는 모두 반영돼 있고 전체 검증을 통과한 상태다.

**사람 확인·후속 조치 필요**

1. **SpacetimeDB 모듈 배포 + 바인딩 재생성 순서 합의** — 파티가 실제로 동작하려면 필수이며, 두 팀이 같은 디렉토리를 건드리므로 "서버 배포 → 한 사람이 재생성 → 커밋" 순서를 정해야 한다. 배포는 되돌리기 어렵다.
2. **공유 파일 통합 커밋 시점** — 위 세 파일을 언제 누가 커밋할지.
3. **push 는 하지 않았다** — 다른 팀의 미완성 작업이 원격에 올라가는 것을 피했다.
4. **제품 결정 3건**(§8) — 파티 정원(현재 6), 리더 접속종료 시 처리(현재 유지+자동승계), 파티원 간 PK(현재 허용).

## 10. 보완 (2026-08-04 23:45 · 사용자 지시)

**요청**: 파티 정원 12 명. 그리고 파티·파티장·추종 기능에 수정할 것이 있으면 보완.

### 10.1 정원

`MAX_PARTY_SIZE` 6 → **12**(`party.rs`). 클라이언트에도 `kMaxPartySize` 를 두어 서버와 맞췄다(`party_session.dart`) — 두 값이 어긋나면 화면에서 초대해 놓고 서버에 거절당하거나, 들어갈 수 있는 사람을 화면이 먼저 막는다. §8 의 미해결 항목 하나가 사람 결정으로 닫혔다.

### 10.2 스스로 찾아 고친 결함 셋

구현한 코드를 다시 읽어 세 가지를 찾았다. 모두 **테스트를 먼저 쓰고 고쳤다**.

| 결함 | 증상 | 원인 | 수정 |
|---|---|---|---|
| ① 위임 시 추종 대상이 옛 파티장에 묶인다 | 파티장이 자리를 넘기면, 화면은 새 파티장을 따라가는데 서버 기록은 옛 파티장을 가리킨다. 다른 파티원에게는 누가 누구를 따르는지가 거짓으로 보인다 | `promote_leader` 가 **새 파티장 본인의** 추종만 풀고 나머지 follower 는 그대로 뒀다 | 옛 파티장을 따르던 사람들을 새 파티장에게 넘긴다. 이들의 의사는 "저 사람" 이 아니라 "파티장" 이었다. 단 파티장이 **나가는** 경우는 그대로 해제한다 — 파티가 깨진 상황에서 동의한 적 없는 사람을 자동으로 따라가게 하지 않는다 |
| ② 따라갈 사람이 바뀌면 곧바로 놓친 것이 된다 | 위임 직후, 또는 파티장이 쓰러졌다 안전지대에서 되살아난 직후 추종이 즉시 끊긴다 | 진전을 재는 `_bestDistance` 가 이전 대상 기준으로 남아, 새 대상이 그보다 멀면 첫 프레임부터 "다가가지 못하고 있다" 로 읽혔다 | `FollowTarget.characterId` 가 바뀌면 진전 기록을 새로 시작한다. 쓰러진 동안에도 함께 지운다 — 되살아나는 자리는 쓰러진 자리가 아니므로 그 사이 거리 변화는 따라붙기의 진전과 무관하다 |
| ③ 추종 해제가 서버에 닿지 못해도 조용하다 | 화면은 멈췄는데 다른 파티원에게는 계속 따라다니는 것으로 보인다. 아무도 눈치채지 못한다 | `unawaited(party.setFollowing(false))` 가 실패를 삼켰다 | 실패를 잡아 배너로 알린다 |

②는 **①을 고치면서 새로 생긴 위험**이기도 하다. 위임으로 추종 대상이 바뀌는 길을 열었으니, 바뀔 때 무슨 일이 생기는지 확인해야 했다.

### 10.3 검증 보강

- 서버: 파티장 승계 규칙을 `pick_next_leader` 순수 함수로 분리해 데이터베이스 없이 검사한다. **훑는 순서가 달라도 같은 사람이 이어받는지**를 못 박았다 — 표를 훑는 순서는 보장되지 않으므로 동점 규칙이 없으면 같은 상황에서 다른 답이 나온다. `cargo test` 40 → **44**.
- 클라: 위임·부활 회귀 3건 추가. `flutter test` 186 → **189**(추종 12 → 15).
- `flutter analyze` 무결(남은 2건은 다른 팀의 기존 코드).

### 10.4 검토했으나 고치지 않은 것

- **1인 파티가 남는다** — 초대를 보내면 파티가 만들어지는데 상대가 거절해도 그 파티는 남는다. 같은 캐릭터는 기존 파티를 재사용하므로 캐릭터당 하나 이상 쌓이지 않고, 그 상태에서 다시 초대할 수 있어야 하므로 지우는 것이 오히려 손해다.
- **`_followTarget()` 의 선형 탐색** — 매 프레임 접속자 목록을 훑는다. 접속자가 수백 명이 되면 다듬을 가치가 있으나 지금 고치면 근거 없는 최적화다.
- **추방·해산을 당했을 때의 알림** — 서버 상태는 정확히 정리되지만 사람에게 알리는 화면이 없다. 파티 UI 와 함께 만들어야 할 몫이다.
