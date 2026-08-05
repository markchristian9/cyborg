# 종합 검토 — auto-hunt-verify

> 요청: 방금 추가한 자동 사냥(auto hunt) 기능이 올바로 동작하는지 코드를 분석해서 검증해 주세요.
> 분석: codex · grok · kimi (**claude 는 제외** — 8초 만에 사고 과정만 출력하고 본문 없이 종료, `.logs/claude.log` 가 비어 원인 확인 불가)
> 종합: 2026-08-04 22:50 · 읽기 전용 분석 — 작업공간 미수정

## 1. 결론

**핵심 설계는 올바르다.** 좌표계는 그리드(타일)로 일관되고, 반경 1~10m 제한·앵커 기준 최근접 선택·히스테리시스·게임 루프 연결·주요 정리 경로(사망·텔레포트·restart·처치·스트리밍 회수)는 모두 의도대로 동작한다. 반경 표시 타원의 √2 배율도 투영 수식과 정확히 일치한다.

**그러나 "올바로 동작한다"고 단정할 수 없다.** 코드로 확인된 실제 결함이 넷 있다 — ① 닿지 않는 몬스터가 둘 이상일 때 더 먼 정상 몬스터가 **영원히 선택되지 않는 기아 상태**, ② 드래그 시 앵커가 매 포인터 이벤트마다 이동해 타깃이 계속 초기화되고 `MoveMarker` 가 폭증, ③ 자동 사냥 중 수동 대시의 방향이 타깃 쪽으로 꺾임, ④ 로그아웃 대기 3초 동안 자동 사냥이 계속 돌아 기록에 안 잡히는 경험치 발생.

가장 심각한 것은 ①이다. 내가 넣은 `blockDuration(3초) < pursuitTimeout(4초)` 라는 값 조합 자체가 원인이며, 이건 값 하나 바꾸는 것으로는 완전히 해결되지 않는 구조적 문제다.

## 2. 세 AI 의견 대조

| 쟁점 | codex | grok | kimi | 검증 결과 |
|---|---|---|---|---|
| 좌표계 일관성·타원 수식 | 통과 | 통과 | 통과 | ✅ 합의 — 직접 검산 일치 |
| 루프 연결(매 프레임 호출) | 통과 | 통과 | 통과 | ✅ 합의 — `:535` 확인 |
| 차단 목록 누수 | 없음 | 없음 | 없음 | ✅ 합의 |
| 서버 부하·중복 보고 | 현재 무해 | 현재 무해 | 현재 무해 | ✅ 합의 |
| **닿지 않는 타깃 기아** | **있음** | 언급 없음 | "탈출 불가 없음" | ⚖️ **codex 가 맞음** |
| **로그아웃 중 지속** | **결함** | "인스턴스 폐기 전제" | "정리 불필요" | ⚖️ **codex 가 맞음** |
| **일시정지 중 몬스터만 이동** | 언급 없음 | "엔진 정지로 동결" | **"비대칭 있음"** | ⚖️ **grok 이 맞음** |
| **`_stuckTime` 무력화** | 부분 무력화 | **"무력화 없음"** | **"실재한다"** | ⚖️ **kimi 가 맞음** |
| 드래그 앵커 스래싱 | 정상 동작 | 가능 | **상세 지적** | ⚖️ **kimi 가 맞음** |
| 수동 대시 방향 꺾임 | **지적** | 언급 없음 | 언급 없음 | ⚖️ **codex 고유·확인됨** |
| 반경 축소 시 즉시 재픽 | 언급 없음 | **"없음"** | 언급 없음 | ❌ grok 틀림 |

## 3. 합의 — 검증 통과

- **거리 판정이 전부 그리드 좌표계로 닫혀 있다.** 확인: `lib/game/systems/auto_hunt.dart:117` 이 `radiusTiles => metersToTiles(_radiusMeters)` 로 미터를 한 지점에서만 변환하고, 선택·해제·사거리 비교는 모두 `Vector2` 그리드 거리다. 화면 좌표는 `AutoHuntRangeField` 렌더에만 쓰인다. `kMetersPerTile` 이 바뀌어도 변환 지점이 하나라 깨지지 않는다.

- **반경 표시 타원이 판정 반경과 일치한다.** 확인: `lib/game/iso.dart:62-67` 의 `x=(gx-gy)·64, y=(gx+gy)·32` 에 그리드 원 `(r·cos t, r·sin t)` 을 넣으면 `x=r√2·64·cos(t+45°)`, `y=r√2·32·sin(t+45°)` 인 축 정렬 타원이 된다. `lib/game/ui/auto_hunt_control.dart` 의 `_ellipseScale = sqrt2` 와 정확히 같다.

- **매 프레임 호출된다.** 확인: `lib/game/action_rpg_game.dart:535` 에서 `_applyInput()` 다음, `super.update(dt)` 앞에 `_updateAutoHunt(dt)` 가 있다. 수동 입력이 먼저 확정된 뒤 자동 사냥이 양보 여부를 판단하는 순서가 맞다.

- **차단 목록은 누수되지 않는다.** 확인: `auto_hunt.dart:282` `_tickBlocklist` 가 매 프레임 감소·제거하고, `forget`/`disable`/`enable` 이 정리한다. 게임 쪽 제거 경로 셋(`:587` prune, `:861` 스트리밍 회수, `:1229` 처치)이 모두 `forget` 을 부른다.

- **현재 서버 부하는 0 이다.** 확인: `lib/game/net/spacetime_game_sync.dart` 는 레벨·누적 XP 만 보내고 `reportKill` 은 `game_sync.dart:24` 의 빈 기본 구현이다. `tryMelee` 를 매 프레임 불러도 `player.dart` 의 근접 쿨다운(약 0.38초)이 자체 스로틀한다.

## 4. 이견 — 자료로 판정

### 쟁점 1: 닿지 않는 타깃이 둘 이상일 때 기아가 발생하는가

- codex: `blockDuration(3s) < pursuitTimeout(4s)` 라 A·B 가 번갈아 풀리며 더 먼 C 가 영원히 평가받지 못한다.
- kimi: "어떤 조합에서도 영구 정지가 없다."
- **판정: codex 가 맞다.** kimi 는 "영구 정지(idle 고착)"를 검사했고 codex 는 "특정 후보의 영구 미선택"을 지적했다. 둘은 다른 문제이며 codex 쪽이 실재한다.
- **근거**: `auto_hunt.dart:88`(`pursuitTimeout = 4.0`), `:93`(`blockDuration = 3.0`), `:224-227`(타임아웃 시 `_blocked[target] = blockDuration`). 벽 뒤 A(앵커거리 2)·B(3)와 접근 가능한 C(5)를 놓고 추적하면:

  | 시각 | 선택 | 차단 만료 |
  |---|---|---|
  | 0–4s | A | A → 7s |
  | 4–8s | B (A 차단 중) | B → 11s |
  | 8–12s | **A** (7s에 이미 해제, C보다 가까움) | A → 15s |
  | 12–16s | **B** (11s에 해제) | B → 19s |

  A와 B의 차단 구간이 절대 겹치지 않아 **C 는 한 번도 선택되지 않는다.** `blockDuration` 을 늘리면 후보 2개까지는 풀리지만, 닿지 않는 후보가 N개면 `blockDuration > pursuitTimeout × (N-1)` 이 필요해 고정값으로는 일반해가 없다.

### 쟁점 2: 로그아웃 대기 중 자동 사냥이 계속 도는가

- codex: 결함이다. kimi: "인스턴스가 통째로 폐기되므로 정리 불필요." grok: "명시적 disable 없음, 폐기 전제."
- **판정: codex 가 맞다.** 폐기는 `onLogout?.call()` **이후**이고, 그 전에 최대 3초의 창이 열려 있다.
- **근거**: `action_rpg_game.dart:1195-1221`. `reportRunFinished()`(:1199) 로 기록을 확정하고 `presence.leave()`(:1209) 로 월드에서 빠진 뒤 `await sync.flushProgress().timeout(3초)`(:1214) 를 기다리는데, 이 구간에서 `status` 는 여전히 `playing` 이고 엔진도 멈추지 않는다. 즉 자동 사냥이 계속 몬스터를 죽이고 경험치를 얻지만 그 결과는 이미 보낸 최종 기록에 반영되지 않는다. 수동 플레이에도 있던 틈이지만, 사람이 손을 놓아도 계속 싸우는 자동 사냥이 노출을 키운다.

### 쟁점 3: 일시정지 중 몬스터만 움직이는가

- kimi: "`status != playing` 에서도 `super.update(dt)` 가 돌아 몬스터 AI 는 진행된다." grok: "`pauseEngine` 으로 update 정지, 상태 동결."
- **판정: grok 이 맞다. kimi 의 주장은 반증됐다.**
- **근거**: `action_rpg_game.dart:1393-1399` 의 `pauseGame()` 이 `pauseEngine()` 을 호출한다. Flame 이 게임 루프 자체를 멈추므로 `update` 가 아예 불리지 않는다. kimi 는 `:524-527` 의 조기 반환만 보고 그 위의 `pauseEngine()` 을 놓쳤다.

### 쟁점 4: `_stuckTime` 벽 끼임 감지가 무력화되는가

- kimi: "실재한다. 실제 안전망은 `pursuitTimeout` 뿐이다." grok: "무력화 없음." codex: "완전히 무력화하지는 않는다."
- **판정: kimi 가 맞다.**
- **근거**: `action_rpg_game.dart:665-669` 의 `_steerAutoHunt` 는 `moveTarget` 이 `null` 이면 무조건 `moveTo` 를 다시 부른다. `player.dart` 에서 벽에 막힌 플레이어가 0.35초 뒤 `clearMoveTarget()` 으로 목표를 버려도, **다음 프레임에 자동 사냥이 같은 목적지를 즉시 재지시**하고 `moveTo` 가 `_stuckTime = 0` 으로 되돌린다. 0.3타일 임계는 "매 프레임 호출"만 막을 뿐 이 재지시 루프를 막지 못한다. 내가 그 함수에 단 주석("벽에 붙어 한 발도 못 나가는데도 영영 목표를 포기하지 않는다"를 막았다는 취지)은 실제 동작보다 과한 약속이다. 기능이 멈추지는 않는다 — `pursuitTimeout` 4초가 대신 받쳐 준다. 다만 안전망 둘 중 하나가 조용히 꺼져 있다.

### 쟁점 5: 드래그 시 앵커 스래싱

- kimi: 드래그 이벤트마다 앵커 이동 + `MoveMarker` 생성. codex: "정상적으로 앵커 이동 분기를 탄다."
- **판정: kimi 가 맞다.**
- **근거**: `lib/game/input/click_move.dart:42-45` 의 `onDragUpdate` 가 포인터가 움직일 때마다 `movePlayerToWorldPoint` 를 부르고, `action_rpg_game.dart:930-931` 이 그때마다 `autoHunt.moveAnchor(target)` 과 `world.add(MoveMarker(...))` 를 실행한다. `moveAnchor`(`auto_hunt.dart:157-162`)는 `_target = null; _pursuitTime = 0` 이므로 **드래그하는 내내 사냥이 재시작을 반복**하고, 수명 0.55초짜리 마커가 초당 수십 개 쌓인다.

## 5. 고유 통찰 — 하나만 발견했으나 검증됨

- **codex — 자동 사냥이 수동 대시 방향을 꺾는다.** 확인: `action_rpg_game.dart:624-663` 의 `suspended` 판정은 `player.moveInput` 만 본다. 이동 입력 없이 제자리 대시를 하면 `moveInput` 이 0 이라 자동 사냥이 계속 판단하고, 타깃이 사거리 안이면 `faceTowards()` 로 `facing` 을 돌린다. `player.dart` 의 `_updateMovement` 는 `isDashing` 일 때 매 프레임 `facing` 을 속도로 쓰므로 **대시가 타깃 쪽으로 휘어진다.** `tryMelee()` 는 대시 중 스스로 걸러지지만 `faceTowards()` 는 그 앞에서 이미 실행된다.

- **codex — 세로가 짧은 창에서 반경 증가 버튼이 잘린다.** 확인: `action_rpg_game.dart:477` 의 `autoHuntY = math.max(52.0, size.y - 298)` 이 하한 52 에 걸리면 그 52 위에 놓이는 `+` 버튼의 중심 y 가 0 이 된다. 반경 15, 앵커 center 이므로 위쪽 절반이 화면 밖으로 나간다.

- **kimi — 자동 사냥 중에는 마우스만으로 도망칠 수 없다.** 확인: `action_rpg_game.dart:924-933` 이 자동 사냥 중 모든 땅 클릭을 앵커 이동으로 재해석한다. 키보드·조이스틱이나 토글 해제 없이는 "저기로 피해라"를 지시할 방법이 없다. 의도된 설계지만 데스크톱 마우스 사용자에게는 함정이다.

## 6. 반증 — 근거가 틀린 주장

- **kimi**: "`paused` 동안 `super.update(dt)` 가 계속 돌아 몬스터만 움직인다" — ❌ `action_rpg_game.dart:1397` 에 `pauseEngine()` 이 있어 게임 루프 자체가 멈춘다. 조기 반환 코드만 보고 내린 결론이다.

- **kimi**: "로그아웃은 게임 인스턴스가 통째로 폐기되는 경로라 별도 정리가 필요 없다" — ❌ `:1214` 의 3초 대기 동안 인스턴스는 살아 있고 `status` 도 `playing` 이다.

- **grok**: "`_steerAutoHunt` 0.3타일 임계로 stuck 무력화 없음" — ❌ `:665-669` 는 `moveTarget == null` 일 때 무조건 재지시하므로, Player 가 포기해도 다음 프레임에 되살아난다.

- **grok**: "반경 축소 시 즉시 재픽 없음" — ❌ `auto_hunt.dart` 의 `_releaseTargetIfInvalid` 가 매 프레임 현재 `radiusTiles` 로 판정하므로 반경을 줄이면 다음 프레임에 해제된다. 과장된 지적이다.

- **grok**: 1차 분석의 줄 번호 다수가 실제 파일과 불일치했고 grok 스스로 §7 에서 철회했다. 이번 종합은 내가 직접 연 줄 번호만 쓴다.

## 7. 최종 권고

| 순위 | 권고 | 범위 | 근거 | 리스크 | 검증 방법 |
|---|---|---|---|---|---|
| 1 | 닿지 않는 타깃을 **실패 횟수 기반 지수 backoff** 로 바꾼다(4→8→16초, 상한 60초). 값만 키우는 것으로는 후보 N개 일반해가 없다 | `auto_hunt.dart` | `:88`, `:93`, `:224-227` | 일시적으로 막힌 몬스터를 오래 무시할 수 있어 상한 필요 | 기아 시나리오(A·B 닿지 않음 + C 정상) 단위 테스트 추가 |
| 2 | 드래그 중 앵커 이동을 스로틀한다(마지막 앵커에서 1타일 또는 0.2초 미만이면 무시). `MoveMarker` 는 실제로 앵커가 옮겨졌을 때만 생성 | `click_move.dart:42-45`, `action_rpg_game.dart:930` | `auto_hunt.dart:157-162` | 사냥터를 끄는 손맛이 둔해짐 | 드래그 중 `moveAnchor` 호출 횟수 검증 |
| 3 | `suspended` 판정에 `player.isDashing` 을 포함해 대시 중에는 `faceTowards()` 를 부르지 않는다 | `action_rpg_game.dart:624-663` | `player.dart` `_updateMovement` 의 `isDashing` 분기 | 대시 직후 자동 사냥 재개가 한 박자 늦어짐 | 대시 중 타깃 사거리 진입 시 facing 불변 테스트 |
| 4 | `requestLogout` 첫 줄에서 `autoHunt.disable()` + 이동 목표 정리 + 엔진 정지를 먼저 하고, 그 뒤에 기록 확정·퇴장·flush 순서로 진행 | `action_rpg_game.dart:1195-1221` | `:1199` 와 `:1214` 사이의 3초 창 | 정지 시점을 잘못 잡으면 마지막 타격분 경험치 누락 | 로그아웃 중 `kills` 증가 없음 확인 |
| 5 | `_steerAutoHunt` 주석을 실제 동작에 맞게 고치고, `pursuitTimeout` 이 유일한 끼임 안전망임을 명시 | `action_rpg_game.dart:660-669` | 쟁점 4 판정 | 없음(주석) | 코드 리뷰 |
| 6 | 게임 루프 연결부 테스트를 보강한다 — `suspended` 배선, attack 전 `faceTowards` 선행, idle 시 `clearMoveTarget` | `test/auto_hunt_test.dart` | 연결부가 diff 절반인데 커버리지 0 | Flame 테스트 하네스 비용 | `flutter test` |
| 7 | 짧은 세로 창에서 `+` 버튼이 잘리지 않도록 하한을 `radius + 여백` 으로 올린다 | `action_rpg_game.dart:477` | 하한 52 → `+` 중심 y=0 | 없음 | 작은 창 실행 확인 |
| 8 | `GAME-DESIGN.md` 조작표·시스템에 자동 사냥을 반영한다 | `GAME-DESIGN.md` | 문서에 미기재 | 없음 | 문서 검토 |

## 8. 미해결 · 사람 판단 필요

- **반경의 의미 확정** — 지금은 "탐색(타깃 선택)만 반경 제한"이고, 근접 스윙 자체는 기존 판정(전방 부채꼴)이라 경계 근처에서 반경 밖 몬스터도 함께 맞는다. "자동 사냥으로 피해를 주는 대상도 반경 안으로 제한"할지는 기획 결정이다. 현재 구현은 요청 문구("반경 내에서만 몬스터를 **탐색**")에는 부합한다.

- **AFK 방치 사냥 허용 여부** — 지금은 근접 전용이라 원거리 몬스터(siege 사거리 7.5, sovereign 9.0) 구역에서는 접근 중 맞다가 죽고, 죽으면 자동 해제되므로 무한 방치는 안 된다. 이를 유지할지, 더 조일지는 기획 결정이다.

- **서버 권위 전투 이전 시의 태그 경쟁** — 몬스터가 서버 공유 개체가 되면 자동 사냥이 사람보다 선타에 유리해진다. 세 AI 모두 이를 지적했다. 클라이언트가 아니라 서버 reducer 정책에서 다룰 문제다.

- **claude 분석 부재** — 네 번째 관점이 빠졌다. 위 판정은 모두 내가 직접 파일을 열어 확인했으나, claude 만 발견했을 수 있는 논점은 확인할 방법이 없다.

- **실행 검증 없음** — 세 AI 모두 읽기 전용이라 실행하지 못했고, 나 역시 `flutter analyze`·`flutter test`(191개 통과)까지만 확인했다. **실제 게임을 띄워 버튼이 눌리고 캐릭터가 사냥하는 것은 아무도 보지 못했다.**

## 9. 적용 결과

> 적용: 2026-08-04 23:05 · 커밋 **없음**(사유는 아래)

| 권고 | 적용 | 파일 | 검증 |
|---|---|---|---|
| 1 기아 → 지수 backoff | ✅ 적용 | `auto_hunt.dart` `blockDurationBase=8`·`blockDurationMax=60`·`blockDurationFor()`·`_failures` | 회귀 테스트 추가. **옛 동작(고정 3초)으로 되돌려 실제로 실패함을 확인**한 뒤 복원 |
| 2 드래그 앵커 스로틀 | ✅ 적용 | `action_rpg_game.dart` `_autoHuntAnchorStep = 1.0` | 1타일 미만 이동은 `moveAnchor`·`MoveMarker` 모두 건너뜀 |
| 3 대시 충돌 | ✅ 적용 | `action_rpg_game.dart` `manual` 판정에 `player.isDashing` 추가 | 정적 분석 |
| 5 과장된 주석 | ✅ 적용 | `action_rpg_game.dart` `_steerAutoHunt` 문서 주석 | `pursuitTimeout` 이 유일한 끼임 안전망임을 명시 |
| 7 짧은 창 버튼 잘림 | ✅ 적용 | `action_rpg_game.dart` `autoHuntY` 하한 52 → 72 | 계산상 `+` 버튼 상단이 화면 안에 들어옴 |
| 4 로그아웃 3초 창 | ⏸️ 보류 | — | 사용자가 범위에서 제외. 자동 사냥 밖 기존 동작에도 영향을 주는 변경이라 별도 판단 필요 |
| 6 루프 연결부 테스트 | ⏸️ 보류 | — | Flame 테스트 하네스가 필요해 범위가 커짐 |
| 8 `GAME-DESIGN.md` 반영 | ⏸️ 보류 | — | 문서 작업으로 분리 |

- 검증: `flutter test` **210개 전부 통과**(자동 사냥 32개 포함), `flutter analyze` 에 이번 변경 관련 신규 이슈 없음.
- **커밋하지 않았다.** 워킹 트리의 `action_rpg_game.dart` 에 다른 세션이 진행 중인 멀티플레이 작업(`WorldPresence`·`RemotePlayerEntity`·`_remotePlayers`)이 미커밋 상태로 섞여 있다. 지금 커밋하면 남의 미완성 작업이 함께 들어간다. 부분 스테이징은 이 환경에서 대화형 플래그를 쓸 수 없어 불가하므로 사람 판단이 필요하다.
- 권고에 없었지만 한 일: 회귀 테스트 3개 추가(기아 시나리오, backoff 계산, 실패 기록 초기화).
