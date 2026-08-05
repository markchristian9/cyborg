<!-- cowork:codex | 2026-08-04 22:44:38 | exit=0 | 495s -->
# codex 분석 — auto-hunt-verify

> 요청: 방금 추가한 자동 사냥(auto hunt) 기능이 올바로 동작하는지 코드를 분석해서 검증해 주세요.

## 무엇을 만들었나

게임 화면에 자동 사냥 버튼을 표시하고 → 클릭하면 → 자동 사냥을 켠 위치, 또는 마우스로 땅을 클릭한 위치를 중심으로 → 반지름 1m ~ 10m 주위 내에서만 몬스터를 탐색하면서 몬스터가 있으면 사냥을 하도록 하는 기능입니다.

## 실제로 존재하는 관련 파일 (모두 확인된 실재 파일이다)

- lib/game/systems/auto_hunt.dart  — 신규. AutoHuntController<T>. 앵커·반경·타깃 상태와 판단(AutoHuntAction: none/idle/approach/attack/returnToAnchor)만 담당하고 게임 객체는 모른다.
- lib/game/ui/auto_hunt_control.dart — 신규. AutoHuntButton(토글), AutoHuntRadiusButton(±1m), AutoHuntRangeField(월드 바닥에 반경 타원 렌더).
- lib/game/action_rpg_game.dart — 수정. _updateAutoHunt/_steerAutoHunt/toggleAutoHunt/adjustAutoHuntRadius 추가, movePlayerToWorldPoint 에 앵커 이동 분기, onPlayerDied/teleportPlayerTo/restart/onEnemyKilled/_pruneRemoved/몬스터 스트리밍 해제에 정리 코드 추가.
- lib/game/entities/player.dart — 수정. _meleeRange 를 public meleeRange 로 바꾸고 faceTowards(Vector2) 추가.
- test/auto_hunt_test.dart — 신규. 29개 테스트, 현재 전부 통과. flutter test 전체 191개도 통과. flutter analyze 에 신규 코드 관련 이슈 없음.

## 검증해 주었으면 하는 관점

(1) 반경 판정의 좌표계 일관성 — 거리 계산이 그리드(타일) 좌표계로 일관되게 이루어지는가. lib/game/iso.dart 의 kMetersPerTile=1.0, metersToTiles() 를 올바로 쓰는가. 화면(아이소메트릭 투영) 좌표가 거리 비교에 섞여 들어간 곳은 없는가. AutoHuntRangeField 가 그리는 타원(sqrt2 배율)이 실제 판정 반경과 일치하는가.

(2) 타깃 선택·해제의 경계 조건 — 앵커 기준 최근접 선택, 사망·반경 이탈·히스테리시스(releaseMargin 0.5), 추격 타임아웃(pursuitTimeout 4초)과 차단(blockDuration 3초) 로직에 버그나 빠져나가지 못하는 상태가 있는가. 차단 목록(_blocked)이 누수되지 않는가.

(3) 게임 루프 연결과 상태 정리 — _updateAutoHunt 가 매 프레임 실제로 호출되는가(update 안 _applyInput 다음, super.update 전). 사망·리스폰·텔레포트·restart·몬스터 스트리밍 해제·적 처치 시 앵커와 타깃이 올바로 정리되는가. 정리가 빠진 경로는 없는가(예: pauseGame/resumeGame, 화면 전환, 로그아웃).

(4) 기존 입력과의 충돌 — 자동 사냥 중 땅 클릭이 앵커를 옮기는 분기(movePlayerToWorldPoint)가 기존 클릭 이동·조이스틱·키보드 입력과 충돌하지 않는가. suspended(수동 조작 우선) 처리가 맞는가. _steerAutoHunt 가 Player.moveTo 를 매 프레임 부르지 않도록 0.3타일 임계를 둔 것이 Player._stuckTime(벽 끼임 감지)을 무력화하지 않는가. ClickMoveLayer 의 드래그 경로에서도 앵커 이동이 의도대로 동작하는가.

(5) SpacetimeDB 멀티플레이 상호작용 — 자동 사냥이 서버에 보내는 공격/이동/킬 보고가 과도하거나 중복되지 않는가. 여러 플레이어가 같은 몬스터를 자동으로 노릴 때 킬 크레딧·동기화에 문제가 생기지 않는가. 자동 사냥이 tryMelee 를 매 프레임 부르는 것이 부하나 중복 보고를 만들지 않는가.

(6) 테스트의 실효성 — test/auto_hunt_test.dart 가 실제로 의미 있는 것을 검증하는가, 아니면 통과만 하는 껍데기인가. 빠진 중요한 경계 조건은 무엇인가. 특히 게임 루프 연결부(_updateAutoHunt)와 UI 는 테스트가 전혀 없는데 그 위험이 어느 정도인가.

(7) 게임 디자인 관점 — 이 동작이 CLAUDE.md 와 GAME-DESIGN.md 가 정한 세계관·MMORPG 규칙(솔로 사냥, 공유 월드, PK 허용)에 어긋나지 않는가. 자동 사냥이 밸런스나 다른 플레이어 경험을 해치는 지점은 없는가.
> 생성: 2026-08-04 22:44:38 · 소요 495s · 읽기 전용 분석(작업공간 미수정)

---



## 1. 결론 요약

좌표계·1~10m 반경 제한·아이소메트릭 타원 계산과 매 프레임 호출 연결은 올바르다. 신규 타깃은 앵커 기준 그리드 거리로만 고른다 (`lib/game/systems/auto_hunt.dart:47-50`, `lib/game/action_rpg_game.dart:539-554`).
그러나 닿지 않는 타깃들이 번갈아 선택되는 기아 상태, 자동 사냥이 수동 대시 방향을 바꾸는 충돌, 반경 밖 적까지 근접 광역 피해를 받는 문제가 있어 전체 기능을 “올바르게 동작한다”고 판정할 수는 없다 (`lib/game/systems/auto_hunt.dart:223-285`, `lib/game/action_rpg_game.dart:649-674`, `lib/game/entities/player.dart:325-330`).
사망·텔레포트·restart·스트리밍 해제·처치 경로의 정리는 대체로 충실하지만, 로그아웃 대기 중에는 자동 사냥이 계속 실행될 수 있다 (`lib/game/action_rpg_game.dart:1251-1259`, `lib/game/action_rpg_game.dart:1286-1311`, `lib/game/action_rpg_game.dart:1408-1415`).
서버 이동 보고는 5Hz로 제한되지만 공격·몬스터·킬은 아직 로컬 권위이므로, MMORPG의 공유 몬스터와 단일 킬 귀속 규칙은 현재 자동 사냥 경로에서 성립하지 않는다 (`lib/spacetime/spacetime_world_presence.dart:20-30`, `lib/game/net/spacetime_game_sync.dart:7-24`, `CLAUDE.md:32-38`).

## 2. 근거

- `lib/game/iso.dart:17-21`, `lib/game/iso.dart:52-77` — 1타일은 1m이며, 미터↔타일 변환과 그리드↔투영 좌표 변환이 분리돼 있다.
- `lib/game/systems/auto_hunt.dart:47-50`, `lib/game/systems/auto_hunt.dart:116-117` — 컨트롤러는 반경만 `metersToTiles()`로 바꾸고 거리 판정은 그리드 좌표로 수행한다.
- `lib/game/systems/auto_hunt.dart:238-279` — 사망·`radius + 0.5` 이탈 시 타깃을 해제하고, 신규 타깃은 앵커에서 가장 가까운 후보로 고른다.
- `lib/game/ui/auto_hunt_control.dart:233-267` — 그리드 원을 `sqrt2`가 적용된 축 정렬 타원으로 렌더링한다.
- `lib/game/action_rpg_game.dart:539-554` — `_applyInput()` 다음 `_updateAutoHunt()`, 그 다음 `super.update()` 순서로 매 플레이 프레임 실행된다.
- `lib/game/action_rpg_game.dart:649-686` — 수동 조작 판정은 `moveInput`만 보며, 공격 시 `faceTowards()`와 `tryMelee()`를 호출한다.
- `lib/game/entities/player.dart:325-369`, `lib/game/entities/player.dart:401-410` — `moveTo()`는 `_stuckTime`을 초기화하고, 이동 불능 0.35초 후 목표를 지운다.
- `lib/game/entities/player.dart:460-492`, `lib/game/action_rpg_game.dart:1050-1061` — 한 번의 근접 공격은 선택된 자동 사냥 타깃만이 아니라 전방의 모든 적·파괴 가능 구조물을 판정한다.
- `lib/game/action_rpg_game.dart:600-609`, `lib/game/action_rpg_game.dart:857-880`, `lib/game/action_rpg_game.dart:1316-1327` — 제거·스트리밍 회수·처치 경로에서 `autoHunt.forget()`을 호출한다.
- `test/auto_hunt_test.dart:6-37`, `test/auto_hunt_test.dart:89-235`, `test/auto_hunt_test.dart:318-368` — 테스트는 `_Mob`과 컨트롤러를 직접 사용하며 반경·선택·히스테리시스·타임아웃을 실제로 검증한다.
- `lib/spacetime/spacetime_world_presence.dart:101-126` — 매 프레임 받은 위치 보고를 200ms 간격·0.15타일 최소 이동·단일 in-flight 요청으로 제한한다.
- `lib/game/net/game_sync.dart:23-30`, `lib/game/net/spacetime_game_sync.dart:55-102` — `reportKill()`의 기본 구현은 비어 있고, 실제 동기화 구현은 누적 경험치만 보고한다.
- `spacetimedb/src/world.rs:783-860`, `spacetimedb/src/world.rs:908-969` — 서버에는 쿨다운·사거리·태그·단일 킬 크레딧을 판정하는 권위 reducer가 이미 존재한다.
- `CLAUDE.md:26-38` — 모든 플레이어가 단일 월드를 공유하며 몬스터 사망과 킬 귀속은 하나여야 하고, 사냥은 파티가 아닌 솔로 방식이다.

## 3. 상세 분석

**(1) 좌표계와 반경 렌더링**

신규 타깃 선택, 타깃 해제, 플레이어-타깃 사거리, 앵커 복귀 거리 모두 `Vector2` 그리드 좌표의 유클리드 거리로 계산된다. 화면 투영 좌표가 컨트롤러에 들어오는 경로는 없다 (`lib/game/systems/auto_hunt.dart:190-235`, `lib/game/systems/auto_hunt.dart:249-272`). 땅 클릭도 월드 투영 좌표를 `screenToGrid()`로 역변환한 뒤 앵커에 전달하므로 일관된다 (`lib/game/action_rpg_game.dart:1004-1027`).

타원 수식도 맞다. `x=(gx-gy)×64`, `y=(gx+gy)×32`인 선형변환에서 그리드 반경 `r`인 원은 화면 반축 `r×64×√2`, `r×32×√2`인 축 정렬 타원이 된다. 구현이 정확히 이 값을 사용한다 (`lib/game/iso.dart:62-77`, `lib/game/ui/auto_hunt_control.dart:233-267`).

다만 표시된 타원은 **신규 타깃 획득 반경**만 표현한다. 이미 잡은 타깃은 `radius + 0.5`까지 유지되므로 화면 경계 밖 적을 계속 쫓을 수 있다 (`lib/game/systems/auto_hunt.dart:73-77`, `lib/game/systems/auto_hunt.dart:249-254`). 또한 근접 공격은 앵커 반경을 다시 검사하지 않고 전방 모든 대상을 때리므로, 경계 근처에서 반경 밖 몬스터가 함께 피해를 받을 수 있다 (`lib/game/entities/player.dart:466-484`). 따라서 “탐색 대상만 반경 제한”이라는 의미에는 맞지만, “자동 사냥으로 피해를 받는 몬스터도 반경 내부만”이라는 강한 의미에는 맞지 않는다.

**(2) 타깃 상태 기계**

앵커 기준 최근접 선택, 사망 해제, 획득/해제 히스테리시스, 공격 사거리 도달 시 추격 시간 초기화는 의도대로 구현됐다 (`lib/game/systems/auto_hunt.dart:190-218`, `lib/game/systems/auto_hunt.dart:238-279`).

`_blocked` 자체는 무한 누수되지 않는다. TTL이 매 갱신마다 감소하고, 만료·`forget()`·`disable()`·재활성화 때 제거된다 (`lib/game/systems/auto_hunt.dart:125-141`, `lib/game/systems/auto_hunt.dart:282-297`). 알려진 제거 경로도 모두 `forget()`을 호출한다 (`lib/game/action_rpg_game.dart:600-609`, `lib/game/action_rpg_game.dart:857-880`, `lib/game/action_rpg_game.dart:1316-1327`).

그러나 타임아웃 4초보다 차단 시간이 3초로 짧아 **복수의 닿지 않는 근접 타깃이 더 먼 정상 타깃을 영구 기아시킬 수 있다**. A를 4초 쫓아 차단하고 B를 쫓는 동안 3초 뒤 A가 풀리며, B가 4초 후 차단되면 다시 더 가까운 A가 선택된다. A와 B가 번갈아 선택되면서 더 먼 C는 한 번도 평가받지 못한다 (`lib/game/systems/auto_hunt.dart:84-93`, `lib/game/systems/auto_hunt.dart:223-285`). 기존 테스트는 닿지 않는 타깃 한 개만 사용하므로 이 순환을 잡지 못한다 (`test/auto_hunt_test.dart:318-349`).

`moveAnchor()`는 현재 타깃과 추격 시간만 초기화하고 차단 목록은 유지한다. 새 앵커에서는 경로 조건이 달라졌는데도 이전 앵커에서 실패한 몬스터가 최대 3초간 제외될 수 있다 (`lib/game/systems/auto_hunt.dart:153-162`). 또한 `suspended` 검사보다 `_tickBlocklist()`가 먼저 실행되므로 “수동 조작 중 상태는 그대로”라는 주석과 달리 차단 시간은 계속 흐른다 (`lib/game/systems/auto_hunt.dart:170-188`).

**(3) 게임 루프와 정리**

호출 순서는 요구한 그대로다. 수동 입력을 먼저 반영해 `moveInput`을 만든 뒤 자동 사냥이 양보 여부를 판단하고, 이어지는 `super.update()`에서 플레이어가 실제로 이동·공격한다 (`lib/game/action_rpg_game.dart:539-554`, `lib/game/action_rpg_game.dart:612-629`).

사망은 자동 사냥을 완전히 끄고 안전지대로 리스폰하며, 텔레포트는 새 위치로 앵커를 이동하고, restart는 컨트롤러를 비운다 (`lib/game/action_rpg_game.dart:1251-1259`, `lib/game/action_rpg_game.dart:1408-1425`, `lib/game/action_rpg_game.dart:1501-1522`). 스트리밍 해제·처치·일반 제거도 타깃 참조를 정리한다.

`pauseGame()`/`resumeGame()`은 자동 사냥 상태를 보존한다. 현재 로컬 월드가 함께 멈추는 구조에서는 재개 시 이전 상태를 잇는 동작으로 해석할 수 있다 (`lib/game/action_rpg_game.dart:1482-1497`). 반면 일반 패널은 월드를 멈추지 않는 것이 명시된 설계이므로, 패널을 보는 동안 자동 사냥이 계속되는 것은 문서와 일치한다 (`GAME-DESIGN.md:597-603`).

로그아웃에는 틈이 있다. `requestLogout()`은 먼저 기록을 확정하고 `presence.leave()`를 호출하지만 자동 사냥·이동 목표·엔진을 멈추지 않은 채 최대 3초간 전송을 기다린다 (`lib/game/action_rpg_game.dart:1286-1311`). 그 동안 `status`는 계속 `playing`이므로 로컬 사냥과 경험치 획득이 이어질 수 있고, `reportRunFinished()` 이후 발생한 결과가 최종 기록에서 빠질 가능성이 있다 (`lib/game/action_rpg_game.dart:539-559`, `lib/game/action_rpg_game.dart:1338-1352`).

**(4) 기존 입력과의 충돌**

키보드·조이스틱 이동은 같은 프레임에 자동 사냥을 `suspended`시키며, 이어지는 플레이어 갱신에서 이전 자동 이동 목표도 삭제한다. 수동 이동 우선권은 올바르다 (`lib/game/action_rpg_game.dart:649-659`, `lib/game/entities/player.dart:334-347`).

하지만 수동 조작 판정이 `moveInput`뿐이라 대시·근접·원거리 공격 자체는 자동 사냥을 멈추지 않는다. 이동키 없이 대시한 상태에서 타깃이 근접 사거리 안에 있으면 자동 사냥이 먼저 `faceTowards()`로 방향을 바꾸고, 이후 플레이어 대시 갱신이 그 `facing`을 속도로 사용한다. 따라서 모바일 대시 버튼이나 제자리 대시가 타깃 쪽으로 꺾일 수 있다 (`lib/game/action_rpg_game.dart:539-554`, `lib/game/action_rpg_game.dart:649-674`, `lib/game/entities/player.dart:229-244`, `lib/game/entities/player.dart:325-330`).

0.3타일 목적지 임계는 정지한 목표에 대해서는 `_stuckTime` 초기화를 막는다. 다만 `Player`가 0.35초 후 목표를 지우면 다음 프레임 자동 사냥이 다시 같은 목표를 넣으며, 움직이는 적이 0.3타일 이상 이동할 때도 `moveTo()`가 재호출된다 (`lib/game/action_rpg_game.dart:678-686`, `lib/game/entities/player.dart:361-369`, `lib/game/entities/player.dart:401-405`). 따라서 벽 끼임 감지를 완전히 무력화하지는 않지만 실질적인 탈출 책임은 4초 추격 타임아웃에 있다.

`ClickMoveLayer`의 탭·드래그 시작·드래그 갱신은 모두 같은 `movePlayerToWorldPoint()`로 들어가므로, 자동 사냥 중에는 앵커 이동 분기를 정상적으로 탄다 (`lib/game/input/click_move.dart:27-45`, `lib/game/action_rpg_game.dart:1017-1024`). 다만 자동 사냥 버튼은 `TapCallbacks`만 구현하므로 버튼 위에서 시작한 드래그가 하위 `ClickMoveLayer`까지 전달되는지는 Flame 이벤트 통합 테스트가 필요하다 (`lib/game/ui/auto_hunt_control.dart:17-20`, `lib/game/ui/auto_hunt_control.dart:60-65`).

**(5) SpacetimeDB 상호작용**

자동 이동은 매 프레임 `presence.report()`로 전달되지만 실제 reducer 호출은 200ms 간격, 0.15타일 최소 이동, 단일 in-flight로 제한된다. 자동 사냥 때문에 위치가 프레임당 한 번씩 서버 트랜잭션으로 변환되지는 않는다 (`lib/game/action_rpg_game.dart:561-564`, `lib/spacetime/spacetime_world_presence.dart:20-30`, `lib/spacetime/spacetime_world_presence.dart:101-126`).

`tryMelee()` 역시 매 프레임 호출될 수 있지만 로컬 쿨다운과 대시 검사가 첫 줄에서 거르므로 로컬 공격·효과가 중복 발동하지 않는다 (`lib/game/entities/player.dart:184-197`). 현재는 이 호출이 `attack_monster` reducer로 연결되지 않아 서버 공격 부하는 발생하지 않는다. `SpacetimeGameSync`가 전송하는 것은 누적 경험치뿐이고, `reportKill()`은 빈 기본 구현으로 끝난다 (`lib/game/net/game_sync.dart:23-30`, `lib/game/net/spacetime_game_sync.dart:7-24`, `lib/game/net/spacetime_game_sync.dart:55-102`).

그 대신 현재 클라이언트가 로컬 `MonsterPopulation`과 로컬 `Enemy`를 생성하고 직접 경험치를 지급한다 (`lib/game/action_rpg_game.dart:151-167`, `lib/game/action_rpg_game.dart:243`, `lib/game/action_rpg_game.dart:1316-1352`). 월드 구독도 `world_player`뿐이라 서버 `monster`·`monster_kill`을 받지 않는다 (`lib/spacetime/cyborg_connection.dart:34-41`). 따라서 여러 사용자가 같은 위치에서 자동 사냥하면 같은 서버 몬스터를 경쟁하는 것이 아니라 각자의 로컬 복제본을 죽인다. 이는 공유 몬스터 한 마리의 사망과 킬은 하나여야 한다는 규칙에 맞지 않는다 (`CLAUDE.md:32-38`).

서버 reducer 자체는 동일 몬스터 공격을 직렬화하고, 서버 쿨다운·사거리·선점자를 적용해 경험치를 한 명에게만 준다 (`spacetimedb/src/world.rs:783-860`, `spacetimedb/src/world.rs:908-969`). 다만 현재 근접 공격은 한 스윙에 여러 대상을 때리는 반면 서버 API는 `monster_id` 하나만 받는다. 서버 연결 때 선택 타깃만 보낼지, 실제로 맞은 모든 적을 한 공격 명령으로 판정할지 계약을 먼저 정하지 않으면 로컬 화면과 서버 HP가 갈라진다 (`lib/game/entities/player.dart:460-492`, `spacetimedb/src/world.rs:789-803`).

**(6) 테스트 실효성**

29개 테스트는 껍데기가 아니다. 반경 상하한, 경계 포함, 앵커 기준 최근접, 사망·히스테리시스 해제, 복귀, 수동 일시정지, 타임아웃과 재선택을 구체적으로 검증한다 (`test/auto_hunt_test.dart:39-368`).

그러나 전부 `_Mob`과 `AutoHuntController.update()`만 직접 호출한다. `ActionRpgGame`, `Player`, `Enemy`, UI, 입력 이벤트, 스트리밍, 서버 연동은 전혀 통과하지 않는다 (`test/auto_hunt_test.dart:6-37`). 실제 결함으로 확인된 복수 접근 불가 타깃 기아, 대시 방향 변경, 로그아웃 대기 중 실행, 반경 밖 광역 피해가 모두 이 경계 밖에 있다. 따라서 컨트롤러 단위 위험은 낮췄지만 기능 전체 위험은 여전히 중간 이상이다.

**(7) 게임 디자인**

자동 사냥이 몬스터만 후보로 받고 파티나 공유 피해 크레딧을 만들지 않는다는 점은 솔로 사냥 규칙과 충돌하지 않는다 (`lib/game/action_rpg_game.dart:653-658`, `CLAUDE.md:32-36`). 자동 PK를 하지 않는 것도 별도 정책으로 타당하다.

[판단] 서버 몬스터가 연결되면 자동 사냥은 한 사냥터의 태그를 계속 갱신해 장기간 점유할 수 있다. 서버 태그는 소유자가 때릴 때마다 만료 시각이 갱신되며, 현재 PK는 미구현이라 문서가 상정한 사냥터 분쟁의 대응 수단도 없다 (`spacetimedb/src/world.rs:818-829`, `GAME-DESIGN.md:710-720`, `GAME-DESIGN.md:784-786`). 자동 사냥 허용 시간, 비활성 사용자 판정, 유지 비용 또는 태그 점유 제한이 없으면 수동 플레이어 경험과 성장 경제를 훼손할 위험이 높다.

## 4. 리스크 · 함정

- `blockDuration(3초) < pursuitTimeout(4초)`라서 복수의 접근 불가 근접 타깃이 서로 번갈아 풀리며 더 먼 정상 타깃을 영구 기아시킬 수 있다 (`lib/game/systems/auto_hunt.dart:84-93`, `lib/game/systems/auto_hunt.dart:223-285`).
- 화면의 타원은 신규 획득 반경만 표시한다. 유지 반경은 0.5타일 더 넓고 실제 근접 공격은 앵커 반경을 검사하지 않는다 (`lib/game/systems/auto_hunt.dart:249-254`, `lib/game/ui/auto_hunt_control.dart:250-267`, `lib/game/entities/player.dart:466-484`).
- 수동 대시·공격은 `suspended` 조건에 포함되지 않아 자동 `faceTowards()`가 대시 방향이나 수동 전투 의도를 덮을 수 있다 (`lib/game/action_rpg_game.dart:649-674`, `lib/game/entities/player.dart:229-244`).
- 로그아웃은 자동 사냥을 끄거나 엔진을 멈추지 않은 채 서버 전송을 기다린다. 월드 퇴장 뒤에도 로컬 사냥이 잠시 지속될 수 있다 (`lib/game/action_rpg_game.dart:1286-1311`).
- 현재 근접 광역 판정과 서버의 단일 `monster_id` 공격 계약은 직접 호환되지 않는다. 단순 연결하면 일부 타격이 서버에서 사라지거나 쿨다운 거절이 대량 발생할 수 있다 (`lib/game/entities/player.dart:460-492`, `spacetimedb/src/world.rs:789-856`).
- 문서가 현재 코드를 따라오지 못했다. `GAME-DESIGN.md`는 `world_player` 클라이언트 사용과 다른 플레이어 렌더링이 미구현이라고 적었지만 실제 코드는 위치 보고·원격 플레이어 동기화를 수행한다 (`GAME-DESIGN.md:782-801`, `lib/game/action_rpg_game.dart:561-594`). HUD·조작 표에도 자동 사냥 버튼이 없다 (`GAME-DESIGN.md:588-617`).
- 매우 낮은 화면에서 `autoHuntY` 하한이 52인데 `+` 버튼은 그보다 52 위에 중심을 두므로 중심 y가 0이 된다. 버튼 반경이 15라 상단 절반이 잘릴 수 있으며 UI 테스트가 이를 감시하지 않는다 (`lib/game/action_rpg_game.dart:492-497`, `lib/game/ui/auto_hunt_control.dart:127-134`).

## 5. 권고안

| 순위 | 권고 | 범위 | 근거 | 리스크 |
|---|---|---|---|---|
| 1 | 접근 불가 타깃을 앵커 세대별 실패 집합이나 지수형 backoff로 관리하고, 여러 실패 타깃보다 아직 시도하지 않은 후보를 우선한다. `moveAnchor()` 때 이전 차단 상태도 초기화한다. | `AutoHuntController` 타깃 생명성 | `lib/game/systems/auto_hunt.dart:153-162`, `lib/game/systems/auto_hunt.dart:223-285` | 일시적으로 막힌 몬스터를 너무 오래 무시할 수 있으므로 재시도 상한이 필요하다. |
| 2 | 자동 사냥의 수동 양보 조건에 `player.isDashing`과 수동 공격 의도를 포함하고, 대시 중에는 최소한 `faceTowards()`를 호출하지 않는다. | 입력 우선권·Player 상태 | `lib/game/action_rpg_game.dart:649-674`, `lib/game/entities/player.dart:229-244`, `lib/game/entities/player.dart:325-330` | 수동 공격 후 자동 사냥 재개 시점이 늦어질 수 있다. |
| 3 | “반경은 타깃 획득만 제한”인지 “자동 공격 피해도 반경 내부만”인지 규격을 확정한다. 후자라면 자동 스윙의 피해 대상도 앵커 반경으로 필터링하고, 전자라면 0.5m 유지 외곽선을 별도로 표시한다. | 전투 판정·월드 UI | `lib/game/systems/auto_hunt.dart:249-272`, `lib/game/ui/auto_hunt_control.dart:250-267`, `lib/game/entities/player.dart:466-484` | 자동 사냥과 수동 근접 공격의 광역 범위가 달라질 수 있다. |
| 4 | 로그아웃 확정 직후 `autoHunt.disable()`, 이동 목표 삭제, 게임 갱신 정지를 먼저 수행한 뒤 기록 확정·월드 퇴장·flush 순서로 처리한다. | 게임 생명주기 | `lib/game/action_rpg_game.dart:1286-1311`, `lib/game/action_rpg_game.dart:539-559` | 정지 시점을 잘못 잡으면 마지막 정상 타격의 경험치가 누락될 수 있다. |
| 5 | 서버 `monster`·`monster_kill` 구독과 서버 ID 기반 타깃을 도입하고, 공격은 매 프레임 판단 시점이 아니라 실제 허용된 스윙/명중 이벤트에서 서버로 보낸다. 로컬 `gainXp()`와 서버 `award_kill()`의 이중 지급 경로도 하나로 통합한다. | SpacetimeDB 전투 권위·클라이언트 동기화 | `lib/game/action_rpg_game.dart:1316-1352`, `lib/spacetime/cyborg_connection.dart:34-41`, `spacetimedb/src/world.rs:783-860` | 가장 큰 구조 변경이며 네트워크 지연에 대한 예측·보정이 필요하다. |
| 6 | 두 접근 불가 타깃+한 정상 타깃, 대시 중 근접 타깃, 반경 밖 광역 피격, 로그아웃 대기, 스트리밍 회수, 대각선 경계, 반경 축소를 통합 테스트로 추가한다. UI에는 타원 golden test와 버튼 탭·드래그·최소 화면 크기 테스트를 둔다. | 테스트 | `test/auto_hunt_test.dart:6-37`, `test/auto_hunt_test.dart:318-368`, `lib/game/input/click_move.dart:27-45` | Flame 게임 하네스와 캔버스 golden 유지 비용이 생긴다. |
| 7 | 서버 공유 몬스터 연결 전에 자동 사냥의 장시간 점유 정책을 결정한다. 태그 유지 시간, 비활성 사용자 제한, 자동 사냥 유지 비용을 서버 기준으로 검증해야 한다. | MMORPG 밸런스·운영 | `CLAUDE.md:32-38`, `spacetimedb/src/world.rs:818-829`, `GAME-DESIGN.md:710-720` | 제한이 과하면 편의 기능의 가치가 사라지고, 약하면 사냥터 독점이 발생한다. |

## 6. 불확실 · 미확인

- 요청에 기재된 `flutter test` 191개 통과와 `flutter analyze` 결과는 읽기 전용·비실행 규칙에 따라 재실행하지 않았으며, 현재 소스 스냅샷에 대해서는 직접 확인하지 않았다.
- Flame의 실제 포인터 라우팅에서 자동 사냥 버튼 위에서 시작한 드래그가 `ClickMoveLayer`에도 전달되는지는 코드만으로 확정하지 못했다. 실제 컴포넌트 이벤트 테스트가 필요하다 (`lib/game/ui/auto_hunt_control.dart:17-20`, `lib/game/input/click_move.dart:19-45`).
- 반경 규격이 “신규 타깃 탐색만 제한”인지 “추격·실제 피해까지 절대 경계 안으로 제한”인지는 사람의 결정이 필요하다. 현재 구현은 전자에 가깝다 (`lib/game/systems/auto_hunt.dart:249-254`, `lib/game/entities/player.dart:466-484`).
- 앱 백그라운드 전환이나 `GameScreen`이 로그아웃 이외의 이유로 제거되는 경로에서 자동 사냥·월드 presence를 어떻게 정리할지는 별도 생명주기 정책이 확인되지 않았다.
- 서버 권위 몬스터가 클라이언트에 연결된 뒤의 지연·거절·타깃 소실 동작은 아직 구현되지 않아 검증할 수 없다. 현재 월드 구독은 `world_player`만 포함한다 (`lib/spacetime/cyborg_connection.dart:34-41`).
