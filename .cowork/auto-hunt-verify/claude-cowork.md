<!-- cowork:claude | 2026-08-04 22:36:31 | exit=0 | 8s -->
# claude 분석 — auto-hunt-verify

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
> 생성: 2026-08-04 22:36:31 · 소요 8s · 읽기 전용 분석(작업공간 미수정)

---

생각:
사용자는 자동 사냥(auto hunt) 기능이 올바로 동작하는지 코드를 분석해서 검증해 달라고 요청했다. 나는 읽기 전용 분석가 역할이며, 산출물은 stdout 마크다운 보고서 한 편이다. 플랜 모드도 활성화되어 있지만, 이 요청은 분석 보고서 출력이 목적이다. 지정된 6개 섹션 형식으로 출력해야 한다.

먼저 관련 파일들을 읽어야 한다. 병렬로 여러 파일을 읽자.
