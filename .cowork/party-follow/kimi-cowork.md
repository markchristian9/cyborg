<!-- cowork:kimi | 2026-08-04 22:53:14 | 실패(exit=124) | 902s -->
# ⚠️ kimi 분석 실패

- 종료 코드: `124` (제한 시간 900s 초과)
- 명령: `sandbox-exec + kimi -p -m kimi-code/k3 --output-format text (OS 읽기 전용)`
- 로그: `.cowork/party-follow/.logs/kimi.log`

이 파일은 분석 결과가 아니다. 종합(final-report.md) 시 kimi 의견은 **없는 것으로** 취급하고,
그 사실을 final-report.md 에 명시하라. 재시도: `COWORK_ONLY=kimi bash .claude/skills/cowork/scripts/cowork.sh party-follow "..."`

<details><summary>부분 출력</summary>

```


• 

## 1. 결론 요약

  파티 기능은 **서버(SpacetimeDB)에 `party.rs` 신규 모듈(테이블 3개 + reducer 8개 내외)을 추가하고, 클라이언트에는 `PartyController`(판단/실행 분리, `AutoHuntController` 패턴)와 파티 HUD(PositionComponent)를 추가** 하는 방향이 이 프로젝트 구조에 맞다. 라리엔에서 가져올 핵심 지식은 ① 파티 상태 기계(초대 검증 순서·cap·해산 분기)와 ② hunt lead 의 "동적 앵커" 패턴이다 — 단 라리엔은 서버가 매 tick 앵커를 갱신하지만, actionrpg 는 서버가 이동을 시뮬레이션하지 않으므로(`world.rs:132-138`) **추종은 클라이언트 측에서 `AutoHuntController.moveAnchor` 를 리더 위치로 갱신하는 방식**으로 옮겨야 한다. PMEMB 청크 분할은 UDP/MTU 대응이라 SpacetimeDB 구독 모델에서 불필요한 것이 맞다. 가장 큰 선행 과제는 **원격 플레이어 동기화 자체가 아직 없다**는 점(`world_player` 테이블·바인딩은 있는데 클라이언트가 구독도 호출도 안 함)이며, 파티 추종은 이것 위에 서야 한다. 킬 크레딧(`tagged_by` 선점)은 1단계에서는 유지하고, 파티 경험치 분배는 서버 권위 XP 전환(GAME-DESIGN.md 13장 과제)과 함께 2단계로 미루는 것이 리스크가 적다.

  

## 2. 근거

  - `spacetimedb/src/lib.rs:20-23` — 모듈은 `auth/character/leaderboard/world` 4개뿐. 파티 테이블·reducer 없음.
  - `spacetimedb/src/world.rs:170-211` — `WorldPlayer` 공개 테이블에 `name/level/grid_x/grid_y/hp/max_hp/alive` 가 이미 있음. 파티원 목록·추종에 필요한 데이터가 서버 스키마에 존재.
  - `spacetimedb/src/world.rs:132-139` — "클라이언트가 좌표를 보내고 서버는 **속도 상한만** 본다"(MAX_MOVE_SPEED=14.0). 서버 이동 시뮬레이션 부재가 명시된 설계 결정.
  - `spacetimedb/src/world.rs:669-706` — `move_to` reducer: 이동 예산 초과 시 거절이 아니라 절단 수용.
  - `spacetimedb/src/world.rs:788-863, 912-970` — `attack_monster`/`award_kill`: 선점(`tagged_by`, TTL 30초 `world.rs:124`) 기반 킬 크레딧과 XP 지급이 **서버에 이미 구현**돼 있음.
  - `lib/game/net/spacetime_game_sync.dart:96` — 클라이언트가 실제로 호출하는 게임 reducer 는 `reportProgress` 뿐. `enter_world`/`move_to`/`attack_monster` 호출 코드가 앱 어디에도 없음(GAME-DESIGN.md:699-700, 782 도 동일 명시).
  - `lib/game/systems/auto_hunt.dart:100-101, 157-162` — `_anchor` 필드와 `moveAnchor(point)` 메서드. 앵커 이동 시 타깃·추격시간 리셋. 라리엔 hunt lead 의 "동적 앵커"를 그대로 얹을 수 있는 접점.
  - `lib/game/action_rpg_game.dart:1142, 903-907, 1292-1293` — 텔레포트 시 `moveAnchor`, 자동사냥 중 클릭은 `moveAnchor` 로 해석, 사망 시 `disable()`. 앵커 갱신의 기존 선례 3곳.
  - `lib/game/entities/` 목록 — 원격 플레이어 엔티티 없음(block, cyborg_*, enemy, iso_entity, pickup, player, projectile 뿐).
  - `lib/spacetime/generated/world_player.dart` — `world_player` 테이블의 Dart 바인딩은 이미 생성돼 있어 구독 코드만 작성하면 됨.
  - `CLAUDE.md:33-34` — "Hunting is solo, not party based. There is no party, no shared damage credit and no party loot rule." / `GAME-DESIGN.md:781` — "솔로 사냥 (파티 없음) ✅ 설계상 파티 개념 자체가 없음". 이번 요청과 정면 충돌하는 설계 선언.
  - `CLAUDE.md:49-52` — "Always test with DTD… 키보드/클릭 주입 금지, 테스트 코드를 main()/initState() 에 주입, 스크린샷·로그로 검증". 실제 구현은 `lib/dev/dev_login.dart`(환경변수 자동 로그인)와 `scripts/run.sh:207-215`(N개 클라이언트 바둑판 배치).
  - 라리엔 `game-server/zone/internal/sim/party.go:37-132, 484-507` — 초대 검증 순서(self→noparty→offline→range→already/busy→full)와 파티장 이탈 시 전원 해산. Go→Rust reducer 로 거의 1:1 대응 가능한 상태 기계.
  - 라리엔 `autopilot.go:239-286` — `updatePartyFollowAnchors`: 매 tick(30Hz) follower 의 autopilot 앵커를 리더 위치로 갱신. 서버가 모든 PC 위치를 아는 전제에서만 가능.
  - 라리엔 `party.go:618, 627-670` — `PMembChunk = 6` 청크 분할은 "멤버당 ~66B × 32명 > UDP MTU 1500B" 대응. 전송 계층 제약이 원인.

  

## 3. 상세 분석

  ### 3.1 파티 기능을 끼워 넣을 위치 (파일:줄)

  **서버 — `spacetimedb/src/party.rs` 신설.** 기존 패턴을 그대로 따라:

  - 테이블(모두 비공개 원칙, `lib.rs:15-16`): `Party`(party_id PK, leader_character_id, created_at), `PartyMember`(character_id PK — 한 캐릭터는 한 파티, party_id 인덱스, is_leader, joined_at), `PartyInvite`((to_character_id PK — 1인 1초대, from_character_id, party_id, expires_at). 라리엔의 `pendingInvite`(types.go:1032-1043)와 동형.
  - reducer: `party_invite`(초대자를 리더로 자동 편입 — party.go:99-116 의 "리더 PSETPARTY 유실 대비"를 SpacetimeDB 에서는 트랜잭션으로 원자 해결), `party_accept`, `party_decline`, `party_cancel_invite`, `party_leave`, `party_kick`, `party_promote`, `party_disband`. 호출자는 전부 `ctx.sender()` → `Session.selected_character_id` 로 도출 — `world.rs:900-906` 의 `require_world_player` 패턴 재사용. `account_id`/character_id 를 인자로 받는 reducer 는 만들지 않는다(lib.rs:9-11 원칙).
  - 초대 만료(라리엔 20초 TTL)는 SpacetimeDB 의 스케줄 테이블(`MonsterTickTimer` 선례, world.rs:289-295)로 `party_invite_tick` 을 두어 정리.
  - 클라이언트 노출: 파티원 목록은 "내 파티의 멤버"만 보여주는 **view** 가 원칙에 맞다(lib.rs:15-16). 단 cowork 프롬프트 §4 의 제약 — view 반환 타입은 반드시 테이블이어야 Dart 생성기가 깨지지 않는다 — 때문에, `PartyMemberView` 용 **공개 테이블**(world_player 와 같은 "월드에 드러난 사실" 예외, world.rs:33-39 주석의 논리)을 두고 reducer 가 멤버십 변동마다 유지하는 방식이 생성 코드 관점에서 안전하다. 파티원의 실시간 위치/HP 는 어차피 `world_player` 구독으로 오므로 이 뷰에는 party_id·character_id·이름·레벨·is_leader 면 충분하다.

  **클라이언트.**

  - `lib/game/net/` 에 `PartySync`(가칭) — `SpacetimeGameSync`(`spacetime_game_sync.dart:56-117`)와 같은 패턴: 게임은 추상 인터페이스만 알고, 구독 생애는 `SpacetimeLeaderboard.attach/detach`(generation 가드) 패턴을 따라 게임 화면 생애에 맞춘다. 구독 초기화 지점은 `lib/spacetime/cyborg_connection.dart:28-32` 의 구독 목록 또는 화면 진입 시 동적 구독.
  - `lib/game/systems/party_controller.dart`(가칭) — Flame/네트 무관한 순수 상태 기계. `AutoHuntController`(auto_hunt.dart:25-27 의 "테스트 가능 설계" 주석)와 `test/auto_hunt_test.dart` 의 가짜 객체 패턴이 프로젝트 관행.
  - 파티 HUD — `lib/game/ui/hud.dart:14-15, 261-320` 패턴(PositionComponent + priority + canvas 직접 렌더)으로 `PartyHud` 별도 컴포넌트를 만들어 `action_rpg_game.dart:294-396` 의 `_addTouchControls` 에서 `camera.viewport` 에 add. 메뉴 진입점은 같은 함수 내 `WorldMenu` 엔트리 배열(358-384)에 "파티" 항목 추가. 좌상단 생존 패널은 `TapShield`(action_rpg_game.dart:446-449)와 맞물려 있으므로 배치는 우측 또는 하단이 무난.

  ### 3.2 라리엔에서 가져올 것 / 버릴 것

  **가져올 것:**
  - 초대 상태 기계와 검증 순서(party.go:37-132), 1인 1초대, 정원 cap, 파티장 이탈 시 해산/위임 분기(party.go:445-507). `mu.Lock` 직렬화는 SpacetimeDB reducer 트랜잭션에 자연 대응.
  - partyId 를 예측 불가한 값으로 하는 발상 — 단 라리엔처럼 클라이언트 로컬 UUID 발급(party_controller.dart:36-45)은 **가져오면 안 된다.** SpacetimeDB 에서는 `auto_inc` party_id 를 서버가 발급하는 것이 "클라이언트 불신" 원칙에 맞고, auto_inc 비연속성(프롬프트 §4)은 party_id 를 정렬 기준으로 안 쓰면 무관.
  - `convertFollowToSoloHuntLocked`(party.go:900-932)의 개념 — 리더 이탈/죽음 시 follower 를 멈추게 하지 말고 그 자리 독립 자동사냥으로 전환.
  - 멤버별 leading/following/idle HUD 상태(party.go:986-1022).
  - 초대 거절·실패 사유 코드(PERR: self/full/busy/declined…) → 한글 토스트 매핑.

  **버릴 것:**
  - Nakama 관련 전부(소켓 소유/재연결/세대) — 라리엔 자신도 퇴역시켰고 SpacetimeDB 에 대응물이 없다.
  - **PMEMB 청크 분할 — 불필요가 맞다.** 근거: 청크의 존재 이유가 UDP MTU 1500B(party.go:618 주석)이고, SpacetimeDB 는 WebSocket(TCP) 위에서 테이블 행 단위로 구독 전송하므로 애플리케이션이 MTU 를 관리하지 않는다. 행 갱신(파티원 HP 1초 재방송, party.go:674-685)도 구독이 자동 처리하므로 클라이언트의 `PartyMemberAccumulator` 조립 로직까지 통째로 불필요. 다만 32명 정원 개념 자체는 난이도·UI 관점에서 유지할 가치가 있다 [판단].
  - UDP 손실 방어 재전송(PINV/PDISBAND 1초×3회, party.go:353-405) — TCP 라 불필요. 대신 SpacetimeDB 의 "구독하지 않으면 캐시가 비어 있다"(프롬프트 §4 실측)는 새로운 신뢰성 함정이므로 구독 확인 로직으로 치환.
  - shard 격리·파티 인지 shard 배정 — 단일 모듈이라 무의미.

  ### 3.3 추종(follow) & 자동 사냥 설계 — 클라이언트 vs 서버

  **판정: 추종 이동은 클라이언트 측, 단 멤버십·추종 상태(누가 누구를 따르는지)는 서버 테이블이 진실.**

  라리엔의 `updatePartyFollowAnchors` 가 서버에서 가능한 이유는 Go Zone 서버가 30Hz 로 모든 PC 를 시뮬레이션하기 때문이다. actionrpg 의 서버는 "속도 상한만 보는" 좌표 접수처(world.rs:132-138)이고, 서버가 이동을 결정해 클라이언트에 먹이는 경로 자체가 없다. reducer 에 추종 시뮬레이션을 넣는 것은 ① reducer 는 이벤트 구동이라 30Hz tick 이 스케줄 테이블로는 비현실적이고 ② 몬스터 개체군 자체가 아직 클라이언트 로컬(`monster_population.dart`)이라 서버는 follower 가 싸울 대상을 모른다. 따라서:

  - **선행 과제**: `world_player` 구독 + 원격 플레이어 엔티티(없음 — 신규 제작, `CyborgRenderer` 재사용 가능). 파티원이든 아니든 위치는 이 경로로 온다(라리엔도 파티원 위치 별도 채널 없이 일반 브로드캐스트 재사용).
  - **추종 메커니즘**: following 상태인 로컬 플레이어는 기존 `AutoHuntController` 를 켠 채로, **리더의 `world_player` 행이 갱신될 때(또는 0.5~1초 스로틀) `moveAnchor(리더 위치)` 를 호출**. 이렇게 하면 ① leash 안 몹 사냥 ② 리더가 반경 밖이면 `returnToAnchor`(auto_hunt.dart:199-209)로 복귀 ③ 추격 타임아웃·블록리스트(84-93) 같은 기존 판단을 전부 재사용한다. 라리엔의 "별도 추종 이동 로직 없이 기존 autopilot leash 재사용"(party.md §10.5)과 정확히 같은 구조가 클라이언트에서 재현된다.
  - **우선순위 충돌**: 라리엔은 서버가 매 tick 추종 상태를 강제 덮어써서(autopilot.go:264-280) 개인 자동사냥을 하위로 눌렀다. 클라이언트 구현에서는 규칙이 단순하다: following 중에는 (a) 수동 이동 입력이 들어오면 추종 일시 정지(기존 suspended 메커니즘, auto_hunt.dart:188), (b) 클릭 이동의 `moveAnchor` 해석(action_rpg_game.dart:903-907)을 추종 모드에서는 금지하거나 "추종 해제 후 이동"으로 명시 처리, (c) 사망 시 `disable()`(1292-1293) 후 리스폰하면 추종 자동 재개(라리엔과 동일 규칙).
  - **리더 위치를 못 보는 경우**: 원격 플레이어 구독은 전 월드가 대상이라 AOI 제한이 없어 라리엔의 "AOI 30m 제약 없음" 장점이 그대로다. 리더 행이 사라지면(접속 종료 — `lib.rs:207-213` 이 즉시 삭제) follower 는 `convertFollowToSoloHunt` 와 동일하게 그 자리 솔로 자동사냥으로 전환.
  - **리더 사망**: 라리엔은 anchor 갱신 skip + 세션 유지(autopilot.go:250-256). 클라이언트 구현도 마찬가지로 `alive == false` 면 `moveAnchor` 를 건너뛰고, 리스폰(안전지대) 후 갱신 재개 — follower 가 안전지대로 재집결. 안전지대 내 몹 부재(action_rpg_game.dart:779)와 무적(player.dart:555)은 이미 게임 측에 있어 컨트롤러 변경 불필요.
  - **장애물**: 라리엔은 셀 A* 로 우회. actionrpg 의 이동은 축 분리 슬라이딩(player.dart:427-444) + 벽 끼임 0.35초 시 목표 포기(363-371)가 전부다. 추종 시 끼임 → `returnToAnchor` 반복 우려가 있으나, 기존 자동사냥이 같은 제약으로 돌아가고 있으므로 1단계에서는 그대로 두고, A* 는 필요 실측 후 과제로 남긴다 [판단].

  ### 3.4 "솔로 사냥" 선
```

</details>
