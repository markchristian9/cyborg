<!-- cowork:kimi | 2026-08-04 22:45:45 | exit=0 | 562s -->
# kimi 분석 — auto-hunt-verify

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
> 생성: 2026-08-04 22:45:45 · 소요 562s · 읽기 전용 분석(작업공간 미수정)

---

• 문서 쪽 설계 규칙만 확인하면 보고서를 쓸 수 있다.

• 

## 1. 결론 요약

  자동 사냥의 **판단 코어(`AutoHuntController`)는 설계대로 올바르게 동작한다** — 좌표계는 그리드(타일)로 일관되고, 앵커 기준 최근접 선택·히스테리시스·추격 타임아웃·차단 로직에 빠져나가지 못하는 상태가 없으며, 사망·텔레포트·재시작·스트리밍 해제·처치 시 정리 코드가 모두 붙어 있다. 다만 네 가지 실질적 허점이 있다. ① **드래그 경로에서 앵커가 매 포인터 이벤트마다 이동**하면서 `MoveMarker` 가 이벤트당 1개씩 생성되고 타깃·추격 시계가 매번 초기화된다(`click_move.dart:42-45` + `action_rpg_game.dart:903-906`). ② `_steerAutoHunt` 의 0.3타일 임계에도 불구하고 **자동 사냥 중에는 `Player._stuckTime` 기반 끼임 감지가 사실상 무력화**되며, 실제 안전망은 컨트롤러의 `pursuitTimeout` 뿐이다. ③ **일시정지 중에도 `super.update(dt)` 가 돌아** 몬스터는 움직이는데 자동 사냥만 멈추는 비대칭이 있다(기존 동작이지만 자동 사냥과 맞물려 재개 직후 어그로 상태가 바뀌어 있다). ④ 테스트 29개는 컨트롤러 단위로는 충실하나 **게임 루프 연결부·UI·드래그 경로는 전혀 커버되지 않는다.** 서버 트래픽 관점에서는 문제가 없다 — 전투·이동·킬은 전부 클라이언트 로컬이며 서버에 나가는 것은 레벨·xp 보고뿐이다(`spacetime_game_sync.dart:66,96`).

  

## 2. 근거

  - `lib/game/iso.dart:21` — `kMetersPerTile = 1.0` ("타일 = 미터"), `iso.dart:53` — `metersToTiles()` 정의.
  - `lib/game/systems/auto_hunt.dart:117` — `radiusTiles => metersToTiles(_radiusMeters)`; 거리 비교는 전부 그리드 단위(`:212`, `:250`, `:271`).
  - `lib/game/ui/auto_hunt_control.dart:236-253` — 타원 렌더 `rx = radiusTiles * kHalfTileWidth * sqrt2`, `ry = ... * kHalfTileHeight * sqrt2`. `gridToScreen`(`iso.dart:62-67`)에 원 `(r·cos t, r·sin t)` 를 대입하면 `x = r√2·kHalfW·cos(t+45°)`, `y = r√2·kHalfH·sin(t+45°)` 의 축 정렬 타원이 되므로 수식이 판정 반경과 정확히 일치한다(주석의 유도와 직접 검산 일치).
  - `lib/game/action_rpg_game.dart:470-491` — `update()` 가 `_applyInput()` → `_updateAutoHunt(dt)` → `super.update(dt)` 순으로 매 프레임 호출. 단 `:471-474` — `status != playing` 이면 `super.update(dt)` 만 호출하고 조기 반환.
  - `lib/game/action_rpg_game.dart:534-541` — `suspended = player.moveInput.length2 > 0.001` 로 수동 조작 우선.
  - `lib/game/entities/player.dart:334-337` — 수동 입력이 들어오면 `clearMoveTarget()` — 자동 사냥이 남긴 이동 목표를 사람 쪽에서 덮어쓴다.
  - `lib/game/action_rpg_game.dart:566-570` — `_steerAutoHunt` 는 목표가 0.3타일(`length2 < 0.09`) 이상 달라질 때만 `player.moveTo` 호출. `player.dart:401-405` — `moveTo` 는 `_stuckTime = 0` 으로 되돌린다. `player.dart:363-370` — 끼임 판정은 0.35초 누적.
  - `lib/game/input/click_move.dart:36-45` — `onDragStart`·`onDragUpdate` 모두 `movePlayerToWorldPoint` 호출 → 자동 사냥 중에는 `action_rpg_game.dart:903-906` 에서 매 호출마다 `moveAnchor` + `world.add(MoveMarker(...))`. `MoveMarker` 수명 0.55초(`click_move.dart:81`).
  - `lib/game/action_rpg_game.dart:1292-1293`(사망 시 `disable`), `:1142`(텔레포트 시 `moveAnchor`), `:1391`(restart 시 `disable`), `:502`(`_pruneRemoved` 에서 `forget`), `:762`(스트리밍 회수 시 `forget`), `:1320`(`onEnemyKilled` 에서 `forget`).
  - `lib/game/entities/enemy.dart:112-115` — 안전지대 안 플레이어는 몬스터가 노리지 않음; `:122-129` — 스폰 시 안전지대 겹치면 밖으로 밀어냄.
  - `lib/game/net/spacetime_game_sync.dart:66,96` — 서버로 나가는 것은 `reportLevel`/`reportProgress`(레벨·xp)뿐. 공격·이동·킬 reducer 호출 없음.
  - `lib/game/entities/player.dart:185-190` — `tryMelee` 는 `_meleeCooldown`(0.38초)로 자체 스로틀됨. 프레임마다 불러도 무해.
  - `GAME-DESIGN.md:346-353` — "재가동은 전투 상태를 남김없이 되돌린다… 클릭 이동 목표를 남기면 혼자 안전지대를 걸어 나가 다시 죽는다" — 자동 사냥의 사망 시 `disable` 이 이 설계 원칙과 정확히 일치.
  - `GAME-DESIGN.md:704-708, 710-720` — 몬스터는 미래에 서버 공유 개체 + 선점(태그) 방식 킬 판정 예정. 현재는 클라이언트 로컬.
  - `test/auto_hunt_test.dart` — 실제 `test(` 호출 29개(5그룹 5·3·7·4·7·3 합계 29), 모두 `AutoHuntController` 단위 테스트.

  

## 3. 상세 분석

  ### (1) 좌표계 일관성 — 문제 없음

  판정 경로 전체가 그리드 좌표로 닫혀 있다. 앵커는 ① 토글 시 `player.grid`(`action_rpg_game.dart:576`), ② 클릭 시 `screenToGrid(worldPoint)` → `nearestWalkable`(`:890-891`)로만 들어오고, 컨트롤러 내부의 모든 거리 비교(`auto_hunt.dart:201,212,250,271`)는 그리드 단위다. 화면 좌표가 비교에 섞인 곳은 없다. 미터는 사용자 입출력 경계(`radiusMeters` setter, 버튼 표시)에서만 쓰이고 `metersToTiles` 로 한 번 변환된다(`auto_hunt.dart:117`). `AutoHuntRangeField` 의 √2 배율 타원은 투영 수식과 정확히 일치한다(§2 검산). `kMetersPerTile` 가 1.0 이라 지금은 미터=타일이지만, 이 값이 바뀌어도 변환 지점이 한 곳이라 깨지지 않는 구조다.

  ### (2) 타깃 선택·해제 경계 조건 — 상태 기계는 건전

  - **선택**: `_pickTarget` 은 앵커 기준 최근접(`auto_hunt.dart:262-280`). 플레이어 기준이 아니라서 추격 중 반경 가장자리 몬스터에 끌려 무한 이탈하지 않는다 — 주석과 테스트(`auto_hunt_test.dart:147-162`)가 일치.
  - **해제**: 사망(`:243`), 반경+0.5 이탈(`:249-254`) 히스테리시스, 추격 4초 타임아웃 + 3초 차단(`:223-229`).
  - **차단 목록 누수 없음**: `_tickBlocklist` 가 매 프레임 감소·제거(`:282-286`), `forget` 이 명시 삭제(`:292-298`), `disable`/`enable` 이 `clear()`. `suspended` 중에도 `_tickBlocklist` 는 `suspended` 검사보다 먼저 호출되어(`:181` vs `:188`) 차단 시계는 계속 흐른다 — 올바른 선택이다.
  - **탈출 불가 상태 없음**: 닿지 않는 타깃 → 4초 후 차단 → 다른 후보 → 모두 차단되면 `idle`/`returnToAnchor` → 3초 후 재시도. 어떤 조합에서도 영구 정지가 없다.
  - **미세한 잔여 이슈 2개**: ① `moveAnchor` 는 `_blocked` 를 지우지 않는다(`:157-162`) — 앵커를 멀리 옮겨도 옛 사냥터의 차단 항목이 최대 3초 남는다. 실해는 거의 없지만 의도인지 주석이 없다. ② `pursuitTimeout` 은 "사거리에 못 넣은 시간"만 재는데, 몬스터가 플레이어보다 빠르게 도망치는 경우에도 같은 경로로 차단된다 — 결과적으로 올바르게 동작한다.

  ### (3) 게임 루프 연결과 상태 정리 — 한 군데 비대칭

  `_updateAutoHunt` 는 `playing` 상태에서 매 프레임, `_applyInput` 직후·`super.update` 직전에 호출된다(`action_rpg_game.dart:482-484`) — 순서상 수동 입력이 먼저 확정되고 자동 사냥이 그 결과를 보고 판단하므로 올바르다. 정리 경로는 사망·텔레포트·restart·스트리밍 회수·`isRemoved` 정리·처치 여섯 군데 모두 붙어 있다. 로그아웃은 게임 인스턴스가 통째로 폐기되는 경로라(`requestLogout`, `:1286-1311`) 별도 정리가 필요 없다.

  남은 비대칭: **`paused` 동안 `super.update(dt)` 가 계속 돈다**(`:471-474`). 즉 몬스터 AI·이동은 진행되는데 자동 사냥 판단만 쉰다. 재개 순간 타깃이 반경 밖으로 나가 있거나 플레이어에게 붙어 있을 수 있다 — 컨트롤러가 `_releaseTargetIfInvalid` 와 거리 재판정으로 스스로 회복하므로 기능 결함은 아니지만, "일시정지"의 의미가 월드 정지가 아니라는 기존 설계 위에서 자동 사냥이 무전제로 안전하다고 볼 수는 없다. 사망이 pause 중에 일어나면 `onPlayerDied` → `autoHunt.disable()` 이 pause 중에 실행된다 — 이 경로는 정리가 돼 있어 오히려 안전하다.

  ### (4) 기존 입력과의 충돌 — 구조는 맞고, 스택 감지 무력화와 드래그 스팸이 남는다

  - **우선순위 체인은 깨끗하다**: 수동 입력 → `Player._updateMovement` 가 `clearMoveTarget()`(`player.dart:337`) + 컨트롤러 `suspended`(상태 유지·판단 정지). 손을 떼면 타깃·앵커 그대로 사냥 재개. 자동 사냥 중 클릭은 앵커 이동으로 재해석되고 직접 이동 목표를 주지 않아 다음 프레임 덮어쓰기 경쟁이 없다(`action_rpg_game.dart:900-907`).
  - **`_stuckTime` 무력화는 실재한다.** `_steerAutoHunt` 의 0.3타일 임계는 "매 프레임 `moveTo` 호출"만 막을 뿐이다: ⓵ 움직이는 타깃을 쫓을 때는 목적지가 0.3타일 이상씩 계속 바뀌어 `moveTo` 가 빈번히 호출되고 매번 `_stuckTime = 0`(`player.dart:404`); ⓶ `Player` 가 스스로 끼임을 감지해 `clearMoveTarget()` 해도 다음 프레임 `_steerAutoHunt` 가 `moveTarget == null` 을 보고 같은 목적지로 즉시 재지시한다. 결과적으로 자동 사냥 중 벽 끼임 포기는 `Player` 가 아니라 컨트롤러의 `pursuitTimeout`(4초)이 전담한다. 주석(`action_rpg_game.dart:562-565`)이 약속하는 것보다 무력화 범위가 넓다. 기능적으로는 `pursuitTimeout` 이 받쳐 주므로 사냥이 멈추지는 않지만, 두 안전망 중 하나가 조용히 꺼져 있다는 점은 인지해야 한다.
  - **드래그 경로**: `ClickMoveLayer.onDragUpdate`(`click_move.dart:42-45`)가 포인터 이동마다 `movePlayerToWorldPoint` 를 부르므로, 자동 사냥 중 드래그하면 ⓵ 앵커가 손가락을 따라 매 이벤트 이동(타깃·추격 시계 매번 리셋 — `auto_hunt.dart:157-162`), ⓶ `MoveMarker` 가 이벤트당 1개씩 생성된다(수명 0.55초, 초당 수십 개가 겹쳐 렌더링되고 매번 컴포넌트 add/remove). "드래그로 사냥 구역을 끌고 다니는" UX 자체는 그럴듯하지만, 명세("클릭한 위치를 중심으로")에 드래그는 없었고 마커 스팸은 명백한 부산물이다.
  - **조이스틱 탭 차폐**: `TapShield`(`click_move.dart:58-70`)가 조이스틱·HUD 영역 탭을 삼키므로 조이스틱 조작이 앵커 이동으로 오인되지 않는다.

  ### (5) SpacetimeDB 상호작용 — 현재 무해, 미래에 충돌 지점 있음

  현재 전투·이동·킬은 전부 클라이언트 로컬이고 서버로 나가는 것은 레벨·xp 보고뿐이다(`spacetime_game_sync.dart:66,96`). `tryMelee` 매 프레임 호출은 0.38초 쿨다운으로 자체 스로틀되고(`player.dart:186-190`) 네트워크와 무관하다. 따라서 **현 시점에서 자동 사냥이 만드는 서버 부하·중복 보고는 0 이다.** 킬 크레딧 경쟁도 몬스터가 클라이언트 로컬 개체인 현 구조에서는 성립하지 않는다. 다만 `GAME-DESIGN.md:704-720` 이 정한 미래 — 몬스터 서버 공유 + 선점(태그) 킬 판정 — 에 오면, 자동 사냥은 "가장 가까운 몹을 자동으로 선타하는 기계"가 되어 태그 경쟁을 사람보다 유리하게 가져간다. 이것은 서버 권위 이전 시 밸런스 이슈가 될 지점이다(§4).

  ### (6) 테스트 실효성 — 컨트롤러는 충실, 연결부는 공백

  29개 테스트는 껍데기가 아니다. 앵커 복사본 격리(`:60-67`), 앵커 기준 선택의 핵심 회귀(`:147-162`), 히스테리시스 양쪽 경계(`:199-223`), 타임아웃·차단·차단 해제(`:319-349`), suspended 상태 유지(`:299-315`) 등 **이 로직에서 실제로 깨질 수 있는 조건**을 대부분 잡는다. 빠진 것: ⓵ `anchorReturnThreshold`(0.6) 경계, ⓶ `forget` 이 `_blocked` 에서도 지우는지, ⓷ `moveAnchor` 가 `_blocked` 를 유지하는 동작(의도 고정), ⓸ `_updateAutoHunt` 연결부 전체 — `suspended` 판정이 `player.moveInput` 과 연결되는지, `faceTowards` 가 attack 전에 호출되는지, `idle` 시 `clearMoveTarget` 이 되는지는 무보증이다. 이 연결부는 이번 변경 diff 의 절반이므로 위험의 절반이 테스트 밖에 있다. UI(버튼 토글, 반경 ±, 타원 렌더)는 Flame 위젯 테스트가 필요해 비용이 크지만, 최소한 타원 수식과 `_steerAutoHunt` 임계는 순수 로직으로 떼어낼 수 있다.

  ### (7) 게임 디자인 적합성 — 충돌 없음, 한 가지 미래 과제

  사망 시 자동 사냥 해제는 `GAME-DESIGN.md:350-353` 의 "재가동은 전투 상태를 남김없이 되돌린다" 원칙과 정확히 일치한다(배너 문구도 다르게 알림, `:1325-1327`). 자동 사냥의 후보 타입이 `Enemy` 로 고정돼 있어 **자동 PK 는 구조적으로 불가능**하다 — PK 는 의도적 행위여야 한다는 설계(`GAME-DESIGN.md:715-716`)와 어긋나지 않는다. 안전지대 상호작용도 정리돼 있다: 몬스터는 안전지대를 침범하지 않고(`enemy.dart:122-129`), 안전지대 안 플레이어는 어그로 대상이 아니므로(`:112-115`), 안전지대 안에서 자동 사냥을 켜면 반경 안 몬스터를 찾아 스스로 걸어 나가 사냥하는 정상 동작이 된다. 솔로 사냥 전제(파티 없음, `GAME-DESIGN.md:781`)와도 충돌하지 않는다.

  

## 4. 리스크 · 함정

  - **드래그 중 `MoveMarker` 폭증 + 타깃 리셋**: 드래그 이벤트마다 월드에 컴포넌트가 추가되고(`action_rpg_game.dart:905`) `moveAnchor` 가 타깃·추격 시계를 초기화한다(`auto_hunt.dart:160-161`). 손가락을 뗄 때까지 사냥이 사실상 재시작을 반복한다. 되돌리기 쉽지만 발견이 늦기 쉬운 종류의 문제다.
  - **`_stuckTime` 안전망의 조용한 무력화**: 주석이 "0.3타일 임계로 막았다"고 말하지만 실제로는 `Player` 의 자기 포기 로직이 자동 사냥 중 거의 작동하지 않는다. `pursuitTimeout` 하나에 의존하므로, 이 값을 나중에 늘리거나 없애는 변경이 들어오면 벽에 영구 정지하는 회귀로 이어진다.
  - **pause 의 비대칭**: `status != playing` 에서도 `super.update(dt)` 가 도는 기존 구조 위에서, pause 중 몬스터만 움직인다. 자동 사냥은 자기 회복 로직으로 버티지만 "일시정지"의 의미를 나중에 바꾸면(월드도 정지) 여기가 첫 검증 지점이다.
  - **자동 사냥 중 마우스 이동 불가**: 자동 사냥 중 클릭은 전부 앵커 이동으로 재해석되므로, 마우스만으로는 "저기로 도망"을 지시할 수 없다(키보드·조이스틱만 가능, 또는 토글 오프). 의도된 설계로 보이나 데스크톱 마우스 사용자에게는 함정이다.
  - **미래 서버 권위 이전 시 태그 경쟁**: `GAME-DESIGN.md:710-720` 의 선점(태그) 방식이 구현되면 자동 사냥은 반응 속도상 사람보다 선타에 유리하다. MMORPG 전제(수십~수천 명이 같은 몹을 노림)에서 "자동 사냥이 선점을 싹쓸이한다"는 불만이 생길 지점이며, 이는 클라이언트 판단 로직이 아니라 서버 reducer 정책(태그 부여 조건)에서 다뤄야 한다.
  - **연결부 무보증**: diff 의 실행 측(`_updateAutoHunt`·`toggleAutoHunt`·`movePlayerToWorldPoint` 분기)이 테스트 밖에 있어, 리팩터링 시 판단 코어는 지켜지면서 실행 측이 깨지는 회귀를 잡지 못한다.
  - **검증 주장의 미확인**: "29개 테스트 통과·전체 191개 통과·analyze 클린"은 읽기 전용 제약상 직접 실행해 확인하지 못했다(§6).

  

## 5. 권고안

  | 순위 | 권고 | 범위 | 근거 | 리스크 |
  |---|---|---|---|---|
  | 1 | 드래그 경로의 앵커 이동을 스로틀한다 — `ClickMoveLayer.onDragUpdate` 에서 마지막 앵커 이동으로부터 일정 거리(예: 1타일) 또는 시간(예: 0.2초) 미만이면 무시하고, 자동 사냥 분기에서는 `MoveMarker` 를 드래그 종료·탭 시에만 추가한다 | `lib/game/input/click_move.dart:42-45`, `lib/game/action_rpg_game.dart:903-906` | `click_move.dart:42-45` | 드래그로 구역을 끄는 손맛이 약간 둔해짐 |
  | 2 | `_steerAutoHunt` 무력화 사실을 주석에 정직하게 기록하고, `pursuitTimeout` 이 유일한 끼임 안전망임을 명시한다. 가능하면 `Player` 의 끼임 포기(`clearMoveTarget`)가 자동 사냥 목표였는지 구분해 자동 사냥에는 재지시하지 않게 한다 | `lib/game/action_rpg_game.dart:560-570`, `lib/game/entities/player.dart:363-370` | `player.dart:404`, `:367` | 끼임 시 4초 대기가 0.35초로 짧아져 벽 근처 몬스터를 과도하게 빨리 포기할 수 있음 |
  | 3 | 게임 루프 연결부에 대한 테스트를 보강한다 — Flame 없이 가능한 범위에서 `_updateAutoHunt` 와 동등한 배선(수동 입력 → suspended, attack 시 `faceTowards` 선행, idle 시 `clearMoveTarget`)을 검증하고, `moveAnchor` 가 `_blocked` 를 유지하는 현 동작을 테스트로 고정한다 | `test/auto_hunt_test.dart`, `lib/game/action_rpg_game.dart:525-559` | `action_rpg_game.dart:534-558`, `auto_hunt.dart:157-162` | 게임 클래스가 Flame 에 강결합돼 있어 테스트 하네스 비용이 든다 |
  | 4 | 서버 권위 전투 이전 과제에 "자동 사냥과 태그 정책"을 명시한다 — 선점 판정 시 자동 사냥 여부를 서버가 알 필요가 있는지(예: 공격 reducer 에 입력 출처 플래그), 태그 수명·갱신 규칙이 자동 선타에 의해 남용되지 않는지를 `GAME-DESIGN.md` 13장 과제 목록에 추가한다 | `GAME-DESIGN.md:702-729`, `spacetimedb/src/` (미래 reducer) | `GAME-DESIGN.md:710-720` | 정책 논의 선행이 필요한 항목이라 즉시 코드 작업은 아님 |
  | 5 | 자동 사냥 중 마우스 도주 불가를 UX 로 보완한다 — 앵커 이동 대신 "길게 누르면 이동" 같은 구분, 또는 HUD 에 "클릭은 사냥 중심 이동" 안내를 첫 활성화 시 표시한다 | `lib/game/ui/auto_hunt_control.dart`, `action_rpg_game.dart:900-907` | `action_rpg_game.dart:900-903` | 입력 제스처가 늘어나 오조작 가능성 |

  

## 6. 불확실 · 미확인

  - **테스트·분석 통과 주장 미검증**: "29개 테스트 통과, 전체 191개 통과, flutter analyze 클린"은 읽기 전용 규칙상 실행해 확인하지 못했다. 테스트 파일의 29개는 직접 세어 일치함을 확인했다.
  - **`status` 가 `paused` 가 되는 실제 트리거**: `pauseGame()` 호출부(ESC 키 등, `action_rpg_game.dart:1474-1483`)는 확인했으나, pause 중 몬스터가 실제로 플레이어를 죽일 수 있는지(사망 처리가 pause 중에도 완주하는지)는 `onPlayerDied` 의 호출 경로 전체를 추적하지 못해 미확인이다.
  - **`_keyboardInput` 설정 경로**: `_applyInput` 에서의 소비만 확인했고 키보드 이벤트가 `moveInput` 에 이르는 전체 경로(키 반복·포커스 상실 시 잔상)는 보지 못했다. 자동 사냥 suspended 판정이 키 릴리즈 누락으로 영구 suspended 가 되는 경우가 있는지는 미확인 `[추측]`.
  - **`enemies` 리스트의 완전성**: 후보로 넘기는 `enemies`(`action_rpg_game.dart:539`)에 월드 상주 몬스터와 웨이브 몬스터가 모두 들어가는지는 추가 지점(`:905`, `:976`)만 확인했다. 보스 등 별도 목록으로 관리되는 적이 있다면 자동 사냥이 그 적을 못 보는지 확인이 필요하다.
  - **`MovePathHint` 와의 상호작용**: 자동 사냥의 `moveTo` 가 설정하는 `moveTarget` 에도 이동 안내선이 그려진다(`click_move.dart:142-143`). 자동 이동에 안내선이 따라다니는 것이 의도된 연출인지는 문서에서 확인하지 못했다.
