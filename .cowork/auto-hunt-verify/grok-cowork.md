<!-- cowork:grok | 2026-08-04 22:43:00 | exit=0 | 397s -->
# grok 분석 — auto-hunt-verify

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
> 생성: 2026-08-04 22:43:00 · 소요 397s · 읽기 전용 분석(작업공간 미수정)

---



## 1. 결론 요약

자동 사냥은 **컨트롤러 판단 / 게임 실행 / UI** 분리가 명확하고, 요구 동작(앵커 중심 1~10 m, 반경 안 탐색·근접 사냥, 클릭으로 앵커 이동)을 코드 수준에서 **올바르게 구현**했다.  
좌표계는 전부 그리드 기준이며 `AutoHuntRangeField` 타원은 판정 반경과 일치하고, 사망·텔레포트·restart·킬·스트리밍 해제·prune 경로에서 상태 정리가 빠지지 않는다.  
치명 버그(영구 멈춤·좌표 붕괴·차단 맵 무한 성장)는 주 경로에서 확인되지 않는다. 남는 리스크는 **근접 전용(원거리 계통 접근 중 피격)**, **추격 중 반경 리쉬 없음**, **게임 루프·UI 통합 테스트 부재**, **서버 전투 연결 시 의도 전송 설계**다. 단위 테스트 29개는 상태 기계에 대해 **실효적**이다.

---

## 2. 근거

- `lib/game/systems/auto_hunt.dart:47-50, 116-117, 249-252, 271-272` — 거리는 전부 그리드; `radiusTiles = metersToTiles(...)`; 선택·해제는 `length`/`length2` 원형 반경.
- `lib/game/iso.dart:17-21, 52-53` — `kMetersPerTile = 1.0`, `metersToTiles` 는 실질 identity.
- `lib/game/ui/auto_hunt_control.dart:233-253` — 화면 타원 `rx/ry = radiusTiles * halfTile * √2`; 렌더 전용, 판정에 화면 좌표 미사용.
- `lib/game/action_rpg_game.dart:539-553` — `update` 에서 `_applyInput()` 직후 `_updateAutoHunt(dt)`, `super.update` 전 호출.
- `lib/game/action_rpg_game.dart:642-675` — `suspended = moveInput ≠ 0`; attack 시 `faceTowards` + `tryMelee`; 사거리 상수 `Player.meleeRange`(1.5).
- `lib/game/action_rpg_game.dart:683-687` — `moveTo` 재호출 억제 `length2 < 0.09`(0.3 타일); stuck 리셋 방지 주석과 일치.
- `lib/game/entities/player.dart:167, 173, 185-190, 361-367, 401-404, 419-424, 470-476` — 쿨 `_meleeDuration(0.32)+0.06≈0.38s`; stuck 0.35s; `moveTo`가 `_stuckTime=0`; `faceTowards`; 타격 `meleeRange + bodyRadius`, 부채꼴 0.35.
- `lib/game/action_rpg_game.dart:1018-1024` · `lib/game/input/click_move.dart:28-45` — 자동 사냥 ON 시 탭/드래그 = `moveAnchor` (직접 `player.moveTo` 안 함).
- `lib/game/action_rpg_game.dart:605, 879, 1320, 1413-1414, 1259, 1515` — prune·스트리밍 회수·킬 `forget`; 사망 `disable`; 텔레포트 `moveAnchor`; restart `disable`.
- `lib/game/systems/auto_hunt.dart:73-93, 157-162, 181-188, 223-228, 282-298` — 히스테리시스 0.5, pursuit 4s, block 3s, `moveAnchor`는 타깃만 비움(`_blocked` 유지), suspended 시 판단 중단, `forget`.
- `lib/game/net/spacetime_game_sync.dart:7-11, 56-70` — 서버로 **레벨·누적 XP만**; `reportKill` override 없음.
- `lib/game/net/game_sync.dart:23-24` · `action_rpg_game.dart:1352` — `reportKill` 호출은 있으나 기본 no-op.
- `lib/spacetime/spacetime_world_presence.dart:20-30, 102-114` — 위치 보고 200ms·0.15타일 스로틀(자동 사냥 전용 경로 아님).
- `lib/game/systems/monster_codex.dart:456-481` — siege 사거리 7.5 / aggro 3.5~6; sovereign 9.0 / aggro 8~9; drone aggro 7~9.
- `test/auto_hunt_test.dart` 전 구간 — 켜기/반경/앵커 최근접/히스테리시스/포기·차단/suspended 등 **29 시나리오**, Flame 없이 컨트롤러만.
- `GAME-DESIGN.md:605-617, 699-700, 710-716` · `CLAUDE.md:32-36` — 조작표에 자동 사냥 없음; 서버 킬 배포·클라 미연결; 솔로 킬 선점·PK 허용.

---

## 3. 상세 분석

### 3.1 아키텍처

| 층 | 역할 | 게임 객체 의존 |
|---|---|---|
| `AutoHuntController<T>` | 앵커·반경·타깃·차단·행동 판단 | 없음 (콜백만) |
| `ActionRpgGame._updateAutoHunt` | `enemies` 후보 공급, 이동/공격 실행 | Flame `Player`/`Enemy` |
| `auto_hunt_control.dart` | 토글·±1 m·바닥 타원 | `HasGameReference` |

판단/실행 분리는 테스트 가능성과 유지보수에 유리하다 (`auto_hunt.dart:23-27, 41-45`).

### 3.2 (1) 좌표계 일관성 — **통과**

- 사람 입력: 미터 → `metersToTiles` → 타일 (`radiusTiles`).
- 선택·해제·공격 거리: 모두 `(gridA - gridB).length` / `length2`.
- 화면 좌표는 **렌더 전용** (`gridVecToScreen` in RangeField). 판정에 픽셀 `position`을 쓰지 않음.
- `kMetersPerTile = 1.0` 이라 “5 m = 5 타일”이 성립.

**타원**  
그리드 원 `(r cos t, r sin t)` 를 2:1 투영하면 축정렬 타원  
`x ∝ r√2 · kHalfTileWidth`, `y ∝ r√2 · kHalfTileHeight`.  
코드 `_ellipseScale = √2` 와 일치. **표시 반경 = 판정 반경.**

### 3.3 (2) 타깃 선택·해제 — **대체로 통과, 의도적 설계 포인트**

흐름:

```
enable(origin) → 매 프레임 update
  → blocklist tick
  → (suspended면 판단 중단, 상태 유지)
  → 무효 타깃 해제(사망 / 반경+0.5 이탈)
  → 없으면 앵커 최근접 픽
  → 있으면 사거리 비교 → attack | approach(+pursuit) | timeout→block
  → 없으면 drift>0.6 → returnToAnchor else idle
```

- **앵커 기준 최근접** (`auto_hunt.dart:257-261`) — 가장자리로 끌려 나감 방지. 테스트로 고정.
- **히스테리시스** — 잡기 `r`, 놓기 `r+0.5`.
- **pursuit 4 s / block 3 s** — 경로 탐색 부재(벽 뒤) 대응. 공격 중 `_pursuitTime = 0`.
- **`forget`** — 차단 키 제거 + 타깃 해제. 스트리밍/킬/prune에서 호출 → 주 경로에서 차단 누수 막힘.
- `moveAnchor`는 타깃만 비우고 `_blocked` 유지 (`157-162`). 앵커 이동 직후 최대 3초간 옛 몹 재선택 지연 가능 — 버그보다 잔존 정책. 테스트 없음.
- 반경 축소 시 **즉시 재픽 없음**. 다음 `_releaseTargetIfInvalid`에서 `새 r+0.5` 밖이면 해제.

**리쉬 부재 (설계 공백)**  
타깃이 살아 있고 앵커 반경(+히스테리시스) 안이면, 플레이어가 수동으로 멀리 간 뒤 손을 떼면 **반경 밖에서 타깃까지 장거리 접근**한다. `returnToAnchor`는 **타깃이 없을 때만** 동작한다.

**suspended 중 blocklist**  
`_tickBlocklist`는 suspended 전에 돌아가므로, 수동 조작 중에도 차단 타이머가 소모된다 (`181-188`). 의도에 가깝고 누수는 아님.

### 3.4 (3) 게임 루프·상태 정리 — **통과 (주요 경로)**

| 이벤트 | 동작 | 근거 |
|---|---|---|
| 매 프레임 | `_updateAutoHunt` 호출 | `action_rpg_game.dart:551-552` |
| 적 처치 | `forget` | `:1320` |
| 컴포넌트 제거 | `_pruneRemoved` → `forget` | `:605` |
| 스트리밍 회수 | `forget` | `:879` |
| 사망 | `disable` + 배너 | `:1413-1448` |
| 텔레포트 | `moveAnchor(player.grid)` | `:1259` |
| restart | `disable` + RangeField 재추가 | `:1515, 1544` |
| pause/resume | `pauseEngine` → update 정지 → 상태 동결 | `:1483-1497` |
| 로그아웃 | 명시적 `disable` 없음; 인스턴스 폐기 전제 | `:1286-1311` |

사망 시 자동 사냥을 끄는 것은 안전지대 재진입 직후 옛 앵커로 재돌입하는 것을 막는 **올바른 선택**이다.

### 3.5 (4) 입력 충돌 — **통과**

- 키보드/조이스틱: `_applyInput` → `moveInput` → `suspended` → 자동 판단 `none`. 동시에 `Player`는 `moveInput`이 있으면 `clearMoveTarget` (`player.dart:334-337`) → **수동 우선**.
- 자동 사냥 ON + 땅 클릭/드래그: 앵커만 이동. 드래그 중 앵커가 매 이벤트로 바뀌어 **타깃 리셋 스래싱** 가능(사냥터 끌기에 가깝다).
- `_steerAutoHunt` 0.3 타일 임계: 정지 몹 추격 시 `moveTo` 1회 → stuck 누적 가능 → 0.35 s 후 목표 클리어 → 다음 프레임 재설정. **stuck 무력화 없음.** 벽에 막히면 4 s pursuit 타임아웃으로 차단.
- UI 버튼은 자체 `TapCallbacks` + `event.handled = true`. `ActionButton` 연속 발동을 쓰지 않음 (`auto_hunt_control.dart:14-16`).

### 3.6 (5) SpacetimeDB / 멀티플레이 — **현재 무해, 미래 주의**

현재:

- 전투·몹 생사는 클라이언트 로컬. `SpacetimeGameSync`는 **progress(레벨/XP)만** (5초 주기·레벨업 즉시).
- `onEnemyKilled` → `sync?.reportKill(...)` 는 인터페이스 기본 빈 구현. **킬 스팸 없음.**
- `tryMelee` 매 프레임 호출이어도 클라이언트 쿨로 실제 스윙 ≈ 1/0.38 ≈ **2.6회/s**.
- 위치: `presence.report` 매 프레임 호출이나 `SpacetimeWorldPresence`가 **200 ms · 0.15 타일**로 스로틀. 자동 사냥 전용 과다 경로 없음.

서버 `attack_monster` / 이동 권위 연결 후:

- 자동 사냥이 “의도 전송”에 그대로 붙으면 **다수 AFK 클라가 동일 몹을 노리는** 부하·태그 경쟁이 생긴다.
- 설계상 킬은 선점 태그·솔로 귀속 (`GAME-DESIGN.md:710-716`)이라 파티 문제는 없고, **사냥터 점유·리스폰 경쟁**은 커진다.
- 권고: 스윙 성공·히트 확정 시에만 `attack_monster`; `move_to`는 기존 스로틀 재사용; 자동 사냥 전용 reducer 금지.

### 3.7 (6) 테스트 실효성 — **컨트롤러: 높음 / 통합: 없음**

검증하는 것: enable/disable/toggle, 반경 clamp, 타일 환산, 반경 안밖·경계, 사망 해제, 히스테리시스, 앵커 최근접, moveAnchor, approach/attack/idle/return, suspended, pursuit timeout, block 만료, 공격 중 timeout 비적용.

검증하지 않는 것:

- `_updateAutoHunt`가 `update`에 묶였는지
- `tryMelee`/`moveTo`/`faceTowards` 배선
- 사망·스트리밍·prune·텔레포트 정리
- UI 버튼·RangeField
- `moveAnchor` 후 `_blocked` 잔존, 드래그 앵커 스래싱

단위 테스트가 초록이어도 **루프 배선이 빠지면 인게임에서 정지**할 수 있다. 회귀 위험은 중.

### 3.8 (7) 게임 디자인 / MMORPG

- **솔로 사냥·공유 월드·킬 단독 귀속**과 충돌 없음. 자동 사냥이 파티/공유 데미지를 만들지 않음 → PK 자동화 아님.
- **근접 전용**: siege(7.5)·sovereign(9.0) 구역 AFK 시 접근 중 피격 → 사망 후 자동 해제라 연속 재돌입은 막힘. “안전한 방치 파밍”이 아님.
- 문서 어그로 표(1~5 m, siege 2.5~4) vs 코드(drone 7~9, siege 3.5~6, sovereign 8~9) **불일치** — 자동 사냥 체감 난이도에 영향. 자동 사냥 버그라기보다 몬스터 수치 드리프트.
- `GAME-DESIGN.md` §11.4 조작표에 자동 사냥 **미기재**.

---

## 4. 리스크 · 함정

| 심각도 | 내용 |
|---|---|
| 중 | **근접만 수행** — 원거리 몹 구역 AFK 시 사망 후 자동 해제. 안전 방치 아님. |
| 중 | **추격 중 반경 리쉬 없음** — 수동 이탈 후 재개 시 원 밖 장거리 러시. |
| 중 | **통합/루프 테스트 없음** — 배선 회귀 시 단위 테스트는 초록인데 인게임 정지 가능. |
| 낮~중 | 드래그로 앵커 연속 이동 시 타깃 리셋 스래싱. |
| 낮 | `moveAnchor`가 blocklist 유지 → 새 자리에서 최대 3초간 옛 몹 재선택 지연. |
| 낮 | 반경 축소 시 즉시 재픽 없음(히스테리시스 구간). |
| 미래 | 서버 `attack_monster` 연결 시 프레임 단위 의도 전송 설계 실수 → 부하·쿨 불일치. |
| 문서 | `GAME-DESIGN` 조작 미반영; 어그로 문서 vs 코드 불일치 — 자동 사냥 체감에 간접 영향. |

**치명 버그(영구 멈춤·좌표계 붕괴·차단 맵 무한 성장)는 주 경로에서 확인되지 않음.**

---

## 5. 권고안

| 순위 | 권고 | 범위 | 근거 | 리스크 |
|---|---|---|---|---|
| 1 | **통합 스모크 테스트**: enable → approach/attack 분기, 사망 시 `enabled==false`, streaming `forget` 후 target null | `test/` + 필요 시 테스트 훅 | 루프·정리 미커버 | 테스트 더블 비용 |
| 2 | **추격 리쉬 정책 명시·구현 여부 결정**: 예) 플레이어가 `radiusTiles + margin` 밖이면 타깃 포기 후 `returnToAnchor` | `auto_hunt.dart` update | 반경 의미 일관성 | 히스테리시스와 충돌 시 체감 변화 |
| 3 | **원거리 위협 UX**: 자동 사냥 중 원거리 몹만 있을 때 배너/경고 중 하나 | `_updateAutoHunt` 또는 UI | siege 7.5 / sovereign 9.0 | 스코프 확대 |
| 4 | **서버 전투 연결 체크리스트**: 스윙 성공·히트 확정 시에만 `attack_monster`; move는 기존 스로틀 재사용; 자동 사냥 전용 경로 금지 | `net/` · world reducer 연동 시 | 현재 미연결 + 선점 킬 설계 | 미연동 시 불필요 |
| 5 | **문서 반영**: `GAME-DESIGN` 조작·시스템에 자동 사냥(앵커·1~10 m·근접·사망 시 해제) | `GAME-DESIGN.md` | 설계 SSOT 공백 | 없음 |
| 6 | (선택) `moveAnchor` 시 `_blocked.clear()` 또는 반경 변경 시 즉시 `_releaseTargetIfInvalid` | `auto_hunt.dart` | 직관성 | 벽 뒤 몹 재시도 빈도 증가 |

규격(앵커 중심 1~10 m 근접 자동 사냥) 자체를 바꿀 필요는 없다. **구현 품질은 출시 가능 수준**이고, 보완은 정책·테스트·미래 서버 연동 쪽이다.

---

## 6. 불확실 · 미확인

- `flutter test` / `flutter analyze` 를 이 세션에서 **실행하지 않음** (읽기 전용·상태 변경 금지). 사용자 진술(29/191 통과)은 코드·테스트 내용으로만 간접 신뢰.
- 실기기에서 버튼 히트 영역과 액션 버튼 겹침·짧은 세로 해상도 레이아웃은 시각 확인 없음(좌표 계산상 대시와 간격 여유는 있음 `[부분 확인]`).
- 서버 권위 몬스터 240기와 로컬 `MonsterPopulation` 공존 전환기에서 자동 사냥이 어느 쪽 `enemies`를 보게 될지는 **연동 설계 이후** 재검증 필요.
- “AFK 자동 사냥 허용 / 안전지대 근처만 허용”은 **기획 결정**이며 코드만으로 단정하지 않음.
- `GameSync.reportKill` 을 채우는 다른 구현체 — 워크스페이스에서 `SpacetimeGameSync`만 확인, 서브클래스 추가 없음(`[부분 확인]`).

---

## 7. 자기 비판으로 바로잡은 것

- ❌ 철회: 1차 근거 줄번호 다수(`action_rpg_game.dart:456-470` update, `:525-558` _updateAutoHunt, `:900-907` moveAnchor 분기, `:762` 스트리밍, `:1199` 킬, `:488` prune, `:1142` 텔레포트, `:1290-1327` 사망, `:1391` restart) — 재확인 결과 **현재 파일과 불일치**. 내용은 대체로 맞았으나 줄 번호는 환각에 가깝다. 본 보고서는 재측정 줄로 교체.
- 🔁 수정: “서버 이동/공격 과다 전송 없음” → **공격·킬 보고는 현재 no-op으로 무해** + **위치는 `presence.report`가 200 ms·0.15 타일 스로틀**되어 자동 사냥 전용 폭주는 없음 (`spacetime_world_presence.dart:20-30, 102-114`). 1차는 presence 스로틀을 근거로 대지 않음.
- 🔁 수정: “`reportKill` 미구현” → 더 정확히는 **호출은 있으나** (`action_rpg_game.dart:1352`) **`SpacetimeGameSync`가 override하지 않아 기본 no-op** (`game_sync.dart:24`).
- ➕ 추가: suspended 중이어도 `_tickBlocklist`는 진행 (`auto_hunt.dart:181-188`) — 차단 누수가 아니라 타이머 소모 정책.
- ➕ 추가: 문서 어그로(1~5 m) vs 코드(drone 7~9, siege 3.5~6, sovereign 8~9) 불일치를 `monster_codex.dart` 줄로 재확인 — 1차 “최대 9 m” 주장은 유지·근거 강화.
- 🔁 수정: 1차 “출시 가능 수준” 결론은 **유지**. 줄 번호 오류가 결론 자체를 뒤집지는 않음 — 재검증한 동작 경로는 동일하게 통과.
