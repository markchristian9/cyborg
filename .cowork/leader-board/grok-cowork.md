<!-- cowork:grok | 2026-08-04 20:32:13 | exit=0 | 463s -->
# grok 분석 — leader-board

> 요청: 순위 랭킹이 잘 되어져 있나요? 분석을 해서, 순위 랭킹이 올바로 동작하도록 수정/보완 해 주세요.
> 생성: 2026-08-04 20:32:13 · 소요 463s · 읽기 전용 분석(작업공간 미수정)

---

Pass 2 적대적 검증을 위해 1차 인용의 줄 번호와 구현을 원문 기준으로 다시 확인합니다.1차 인용의 줄 번호와 로그아웃·전송 경로를 재검증했고, 과대 표현과 놓친 경로를 반영해 최종 보고서를 작성합니다.

## 1. 결론 요약

**순위 산정·표시 파이프라인의 뼈대는 올바르다.** 서버가 `level ↓ → xp(레벨 내 진행도) ↓ → created_at ↑ → id` 로 안정 정렬하고, 상위 100과 `my_rank` 를 분리하며, 클라이언트는 서버 `rank` 를 재계산하지 않고 표시만 한다. 단위·통합 테스트가 happy path 를 뒷받침한다.

**다만 “MMORPG 레벨 랭킹이 올바로 완성됐다”고 보기는 이르다.** (1) `_inFlight` 중 최신값을 큐에 남기지 않아 **연속 레벨업은 최대 약 5초 지연**, **전송 중 세션 종료 시 영구 유실** 가능, (2) `report_progress` 는 클라이언트가 신고한 level/xp 를 상한·단조만 검사해 **치팅·xp 폭주에 약함**, (3) 월드 입장 시 로컬 `Player` 는 항상 1레벨이라 **순위표(서버 high-water)와 인게임 HUD 의미가 어긋남**, (4) view 전수 스캔은 인구 증가 시 구조적 비용이다.

**이 단계는 읽기 전용 분석만 수행한다.** 보완 방향은 §5 우선순위로 적는다(실제 수정은 오케스트레이터 몫).

## 2. 근거

- `spacetimedb/src/leaderboard.rs:69–76` — `rank_key`: `Reverse(level)`, `Reverse(xp)`, `created_at`, `id`.
- `spacetimedb/src/leaderboard.rs:105–115` — `leaderboard` view: `level` 인덱스 `filter(0..)` 전수 수집 → 정렬 → 상위 100, `rank = i+1`.
- `spacetimedb/src/leaderboard.rs:121–138` — `my_rank`: `outranks` 인원 수 + 1 (100위 밖 포함).
- `spacetimedb/src/leaderboard.rs:57–61, 28–30` — `xp` = 현재 레벨 안 진행도; `MAX_LEVEL = 30`.
- `spacetimedb/src/leaderboard.rs:145–186` — `report_progress`: 세션·선택 캐릭터, level 1–30, **후퇴 무시**, `account_id` 인자 없음. **xp 상한·곡선 검증 없음.**
- `spacetimedb/src/leaderboard.rs:213–237` — 단위 테스트: 레벨·xp·생성시각·id 타이브레이크.
- `spacetimedb/src/lib.rs:9–16, 105–114` — 클라이언트 비신뢰·비공개 테이블·`level` btree 는 리더보드 조회용.
- `lib/game/net/spacetime_game_sync.dart:47–65, 78–96` — 5초 `tick` + 레벨업 즉시 보고; `_inFlight`/`_rejected` 시 **즉시 return, pending 없음**; `reportLevel` 은 **항상 xp=0**.
- `lib/game/entities/player.dart:504–537` + `action_rpg_game.dart:892–896` — `gainXp` while 다중 `_levelUp` → 매번 `reportLevel(level)`.
- `lib/game/action_rpg_game.dart:812–817, 945–951` — 로그아웃 시 `reportRunFinished()` 후 `onLogout`(확인 다이얼로그); **await 없음**. sync 쪽은 내부 `_level`/`_xp` 만 전송.
- `lib/spacetime/spacetime_leaderboard.dart:14–15, 44–63, 79–87` — 서버 rank 신뢰; attach/detach; 캐시는 rank 재정렬만.
- `lib/spacetime/cyborg_connection.dart:16–21, 34–42` — view 구독 필수; 리더보드는 화면 열 때만 구독(갱신 빈도 이유).
- `lib/main.dart:64–70` — 출격 시 `characterName` 만 반영, **서버 level/xp 미복원**. `player.dart:32–34` 기본 `level=1, xp=0`.
- `lib/auth/character_select_screen.dart:258` — 선택 UI 는 `Lv.${character.level}`(서버 값) 표시.
- `lib/game/ui/leaderboard_screen.dart:19–20, 125–168, 485–506, 527–569` — Flame `PositionComponent`; 로딩/빈 목록; xp 는 **같은 level 동료 대비 상대 막대**; 하단 고정 내 순위.
- `test/spacetime_integration_test.dart:180–264` — 반영·후퇴 무시·상한 거절·**level 비증가** 정렬. 동점 xp 순서·삭제 후 재배치·전송 큐는 없음.
- `lib/game/systems/level_system.dart:30–44` — 클라이언트 곡선 `base=60`, `curve=1.22`, max 30. 서버 reducer 에 동일 불변식 없음.

## 3. 상세 분석

### 3.1 권위와 데이터 흐름

```
[로컬 전투] Player.gainXp → level / xp
  → SpacetimeGameSync.reportLevel | tick(5s) | reportRunFinished
  → reducer report_progress(level, xp)
  → PlayerCharacter 갱신
  → view leaderboard / my_rank
  → (패널 open 시 구독) SpacetimeLeaderboard → LeaderboardScreen
```

| 데이터 | 권위 | 비고 |
|---|---|---|
| `rank` | **서버 view** | 클라이언트 재계산 없음 (`spacetime_leaderboard.dart:14–15`) |
| `level`/`xp` 저장값 | **클라이언트 신고** + 서버 필터 | 전투 시뮬 없음 전제 (`leaderboard.rs:145–153`) |
| 인게임 HUD 레벨 | **로컬 `Player`** | 세션마다 1부터 (`player.dart:32`) |

범위: “순위 숫자 자체”는 서버가 맞추고, “그 숫자의 원천 성장”은 아직 클라이언트다. 후자를 서버 시뮬로 옮기라는 권고는 현 단계 범위 밖(문서 명시).

### 3.2 순위 규칙 (게임 디자인)

| 순위 키 | 의미 | 공정성 |
|---|---|---|
| 1 | level 높을수록 | 명확 |
| 2 | 같은 level 에서 xp(레벨 내 진행도) 높을수록 | 용어 정의와 코드 일치 |
| 3 | `created_at` 이른 캐릭터 | UI 에 사유 미표시 |
| 4 | 작은 `id` | auto_inc 비연속이어도 **안정 타이브레이크** 용도로 타당 |

`rank` 는 1부터 **겹치지 않음**(완전 순서 + dense 번호). 웨이브·킬·점수는 전송·저장 대상 아님 (`spacetime_game_sync.dart:9–11`).

순위 단위는 **계정 단위가 아니라 `PlayerCharacter` 단위**다. 한 계정의 캐릭터 최대 4개(`character.rs:12`)가 표에 나란히 오를 수 있다 — MMORPG 에서 흔한 선택이지만 카피에 없으면 “내 계정이 네 줄”로 오해할 수 있다.

### 3.3 서버 정합성 — 살아남은 판단

- **별도 순위 테이블 없음** (`leaderboard.rs:3–6`): 삭제·갱신 시 표 불일치 위험이 구조적으로 없다. 좋은 선택.
- **단조 증가** (`175–177`): 다기기·지연 패킷으로 옛 값이 최신을 덮는 경로를 막는다.
- **가드 공백 (유지)**: `xp` 상한 없음 → 같은 level 에서 `u64::MAX` 로 동점 구간 선점 가능. level 1→30 한 방 점프도 단조만 만족하면 허용. 정상 클라이언트의 `xp < xpToNext(level)` 은 서버에 없음.

### 3.4 클라이언트 전송 경로 — 1차보다 정밀한 판정

```dart
// spacetime_game_sync.dart:78–80
if (_rejected || _inFlight) return;  // 최신 (level,xp) 를 남기지 않음
```

| 시나리오 | 실제 결과 | 1차 표현 보정 |
|---|---|---|
| 연속 레벨업 (세션 유지) | 중간 `reportLevel` 스킵 → 메모리 `_level` 은 최신; **다음 `tick`(≤5s) 이 `game.player` 로 따라잡음** | “유실”이 아니라 **지연**이 기본 |
| `reportLevel` 직후 잔여 xp | 즉시 보고는 항상 xp=0 (`59–64`). tick 전 순위표 동점 구간이 잠시 불리 | 치명적이지 않으나 즉시성 약화 |
| `_inFlight` 중 로그아웃/`reportRunFinished` | `_send` 가 또 return → **서버에 최종 레벨이 안 남을 수 있음** | **진짜 유실 경로** |
| `reportRunFinished` 값 소스 | `game.player` 가 아니라 내부 `_level`/`_xp`. 직전 `reportLevel` 이 `_xp=0` 으로 덮으면 **잔여 xp 유실** | 1차에서 약하게만 언급 → 승격 |
| 로그아웃 UX | `requestLogout` → `reportRunFinished()`(await 없음) → 확인 다이얼로그 → `session.logout` (`action_rpg_game.dart:812–817`, `main.dart:74–97`) | 다이얼로그가 시간 여유를 줘 평소엔 대부분 성공 **가능**하나 계약상 보장은 없음 |

`_rejected`: `SpacetimeDbReducerException` 한 번이면 해당 `SpacetimeGameSync` 생명주기 동안 재시도 없음 (`87–90`). 캐릭터 선택 후 게임 전제에서는 드물지만, 예외 분류가 넓으면 세션 전체 기록 중단.

### 3.5 로컬 레벨 vs 서버 레벨 (제품 의미)

- 선택 화면: 서버 `Lv.N` (`character_select_screen.dart:258`).
- 월드: `Player.level = 1` 고정 시작 (`player.dart:32`, `main.dart` 미복원).
- 서버에 이미 더 높은 값이 있으면 `report_progress` 는 조용히 no-op (`175–177`) → **서버 기록 = 사실상 캐릭터 역대 최고 도달(high-water)**.
- 인게임 HUD/성장 체감은 “이번 출격 런”.

코드는 후자(high-water)에 가깝고, UI 카피(“레벨 순위”)만으로는 전자(지금 몸체)로 읽히기 쉽다. **제품 정의가 코드/문서에 고정되어 있지 않다** — 버그가 아니라 **미결정**에 가깝다. `[판단]`

### 3.6 구독·표시

- view 구독 전제 준수 (`cyborg_connection.dart:16–21, 39–41`).
- **attach race** (`spacetime_leaderboard.dart:44–63`): `subscribe` await 중 `detach` 하면 `_querySetId == null` 이라 unsubscribe 불가 → 완료 후 구독 잔존. 다음 `open` 은 기존 id 재사용으로 목록은 보일 수 있으나 “볼 때만 구독” 계약 위반(백그라운드 트래픽).
- xp 막대: 같은 level 버킷 내 상대 비율 (`leaderboard_screen.dart:485–491`). 동점이면 모두 가득 참; `created_at` 타이브레이크는 보이지 않음 → “왜 내가 아래?” 납득 약함.

### 3.7 MMORPG 스케일

- 주석: 누가 레벨업해도 구독자 전원에 결과 푸시 (`cyborg_connection.dart:36–38`).
- 매 계산: 전 캐릭터 collect + `O(N log N)` 정렬 / `my_rank` 는 전 행 `outranks` 스캔 `O(N)`.
- SpacetimeDB 2.7: view 핸들 `iter()` 없음 → 인덱스 범위가 유일한 다행 경로. `filter((me.level+1)..)` 등으로 상위 버킷만 세는 최적화는 **미구현·가능 여부는 API 범위 안에서 설계 필요**.
- 임계 인구 수치는 이 환경에서 실측하지 않음 `[추측: 수백~수천 캐릭터·빈번한 progress 에서 먼저 체감]`.

### 3.8 테스트

| 있음 | 없음 |
|---|---|
| 서버 정렬 단위(레벨·xp·시각·id) | 연속 report + `_inFlight` / pending |
| 반영·후퇴·상한·미선택 | 같은 level 다른 xp 의 **통합** 순위 |
| 기존 표 level 비증가 스모크 | 100위 경계, 삭제 후 제외, attach race, 로그아웃 플러시 |

통합 “정렬시험”은 **전역 목록의 level 단조**만 본다 — 우리 캐릭터가 순위를 바꿨다는 인과 검증은 약하다.

## 4. 리스크 · 함정

- **전송 신뢰**: pending 없음 + fire-and-forget 종료 보고 → 연속 성장 직후 종료 시 서버 순위가 로컬 도달보다 낮을 수 있음.
- **치팅**: 조작 클라이언트의 level 30 / 거대 xp. 완전 제거는 현 전제 밖이나, 순위를 홍보·보상과 묶기 전에는 수용 범위를 명시해야 함.
- **xp 폭주**: 서버 상한 없음 → 동점 타이브레이크 무력화.
- **의미 혼동**: 선택 화면 Lv vs 인게임 Lv → “랭킹 버그” 오인 리포트.
- **스케일**: 전수 정렬 view × 실시간 구독.
- **구독 레이스**: 빠른 여닫기 시 리더보드 구독 잔존.
- **`_rejected` 영구 차단**: 오탐 시 세션 전체 미기록.
- **설계 원칙**: `account_id` 인자 없음·비공개 테이블·더미 `LeaderboardEntry` 표(코드젠용)는 원칙과 맞음. `server/` 옛 스캐폴드·생성 코드 손수정·위젯 재작성 권고는 부적절.

## 5. 권고안

| 순위 | 권고 | 범위 | 근거 | 리스크 |
|---|---|---|---|---|
| 1 | **`SpacetimeGameSync` 에 최신-wins pending**: `_inFlight` 중 새 `(level,xp)` 는 `_pending` 에 덮어쓰고, `finally` 에서 pending 이 있으면 재전송. `reportLevel`/`tick`/`reportRunFinished` 모두 동일 경로. 종료 전에는 가능하면 `player` 의 현재 level/xp 로 한 번 동기화한 뒤 플러시(필요 시 `GameSync` API 확장). | 클라이언트 동기화 | `spacetime_game_sync.dart:59–96`, `action_rpg_game.dart:812–817, 945–951` | 네트워크 연속 실패 시 pending 재시도 정책만 정하면 됨 |
| 2 | **`report_progress` xp 가드**: 최소 비정상 크기 거절/clamp. 이상적으로 서버에 `xp_to_next` 동일 곡선(`base=60`, `curve=1.22`, max 30)을 두고 `xp < xp_to_next`(만렙 0) 강제. level 단조·상한은 유지. | 서버 reducer | `leaderboard.rs:169–177`, `level_system.dart:30–44` | 곡선 드리프트 시 정상 클라이언트 거절 → 상수·테스트를 한곳에 문서화 |
| 3 | **제품 의미 고정 + 카피**: (A) 순위 = 캐릭터 **최고 도달**이면 리더보드/선택 UI 에 명시, 또는 (B) 입장 시 서버 level/xp·스탯을 `Player` 에 복원. 미결정 상태가 “버그 제보”를 반복 유발함. | 기획 + 클라이언트 | `main.dart:64–70`, `character_select_screen.dart:258`, `leaderboard.rs:175–177` | (B) 는 밸런스·만렙 스탯 재적용 필요 |
| 4 | **view 조회 축소**(여유 시): 예) `level` 인덱스에서 상위 버킷만 모아 상위 100 채우기; `my_rank` 는 `(me.level+1)..` 인원 + 동 level 버킷 비교. 의미 동일 유지. | 서버 view | `leaderboard.rs:106–136` | SpacetimeDB 범위 API·테스트 복잡도 |
| 5 | **`SpacetimeLeaderboard` 세대/토큰**: `attach` 시 세대 증가; subscribe 완료 시 세대 불일치면 즉시 unsubscribe. | 클라이언트 구독 | `spacetime_leaderboard.dart:44–63` | 낮음 |
| 6 | **표시 보완**: 행에 xp 숫자 또는 “동점 시 선등록 우선” 힌트; 상대 막대만으로는 납득 부족. | Flame UI | `leaderboard_screen.dart:443–444, 485–506` | 연출만, 순위 로직 불변 |
| 7 | **테스트 보강**: (a) 같은 level 다른 xp rank, (b) mock 으로 pending 최종값 커밋, (c) 삭제 후 목록 제외. | test | `spacetime_integration_test.dart:249–264` 공백 | maincloud 오염·정리 비용 |

**하지 말 것**  
- 현 단계에서 전투 전체 서버 시뮬로 `report_progress` 제거.  
- `server/` 옛 스캐폴드 기준 수정.  
- `lib/spacetime/generated/` 손수정.  
- 리더보드를 Flutter 위젯으로 재작성.

## 6. 불확실 · 미확인

- SpacetimeDB maincloud 의 Anonymous view 캐시·재계산 비용 모델(구독자 수 × 갱신 빈도) — 문서/실측 없음.
- 상위 100 구성원 교체 시 클라이언트 SDK 삭제 델타 정확성 — 코드만으로 확정 불가.
- 프로덕션 `withcenter-cyborg` 캐릭터 수·순위 분포 — 조회하지 않음.
- `_inFlight`/미플러시가 실유저에서 얼마나 잦은지 — 텔레메트리 없음.
- 제품이 원하는 순위 의미: **라이브 성장** vs **역대 최고** — **사람 판단 필요.**
- cargo/flutter 테스트는 읽기 전용 분석에서 **실행하지 않음**.
- SpacetimeDB 인덱스 `filter` 로 “높은 level 버킷만 partial” 이 기대한 성능으로 되는지 — 구현 전 확인 필요.

---

**한 줄 판정:** 순위 **규칙·서버 정렬·표시 권위 분리는 맞고**, happy path 는 동작한다. **전송 큐 부재(특히 종료 경로)·느슨한 xp 검증·로컬/서버 레벨 의미 불일치·전수 스캔** 때문에 “완성된 MMORPG 랭킹”은 아니다. 보완 1순위는 **pending + 종료 시 player 기준 플러시**, 2순위는 **서버 xp 가드**다.

## 7. 자기 비판으로 바로잡은 것

- 🔁 수정: 1차 “연속 레벨업·로그아웃 시 진행 **유실**” → **세션 유지 시에는 주로 ≤5초 지연(`tick`)** 이고, **영구 유실은 `_inFlight` 중 종료·강제 종료·또는 `reportRunFinished` 가 내부 `_xp=0` 캐시를 보낼 때**. 이유: `spacetime_game_sync.dart:47–56, 78–95` 를 다시 보면 inFlight 스킵 후에도 tick 이 `game.player` 를 읽어 재시도함. 완전 유실을 상시 버그처럼 동급한 것은 과장.
- ➕ 추가: `reportRunFinished` 가 `game.player.level/xp` 를 인자로 받지 않고 내부 `_level`/`_xp` 만 씀 (`spacetime_game_sync.dart:68–76`, `action_rpg_game.dart:945–951`). `reportLevel` 이 `_xp=0` 으로 덮은 직후 종료하면 **잔여 레벨 내 xp 가 서버에 안 감**. 1차는 레벨 유실 위주였고 이 경로는 약했다.
- ➕ 추가: `requestLogout` 은 `reportRunFinished()` 를 **await 없이** 호출한 뒤 확인 다이얼로그로 넘어감 (`action_rpg_game.dart:812–817`, `main.dart:74–97`). 다이얼로그가 사실상 완충이 될 수 **있으나** 계약상 완료 보장은 아님 — 1차의 “로그아웃 레이스”를 이 구조로 구체화.
- 🔁 수정: “다중 레벨업 시 이후 report 전부 스킵되어 **메모리는 갱신되지만 전송은 tick 의존**” — 1차와 방향은 같으나, `reportLevel` 이 스킵 전에도 `_level`/`_xp=0` 을 먼저 쓰는 점(`59–64`)을 명시해 종료 경로와의 결합을 강화.
- ➕ 추가: 순위 단위가 **캐릭터(최대 4/계정)** 임 (`character.rs:12`, `PlayerCharacter` 단위 view). 1차 미언급.
- 🔁 수정: 통합 “정렬시험”의 지지 강도를 낮춤 — level 비증가 스모크일 뿐 동점 xp·인과 반영은 검증 안 함 (`spacetime_integration_test.dart:249–264`). 서버 **단위 테스트**가 정렬 규칙의 주 근거.
- ❌ 철회에 가깝게 완화: 1차 결론 톤의 “연속 레벨업이면 순위가 깨진다”는 인상 → **평시 플레이에서 순위 규칙은 서버에서 맞고, 전송 계층 신뢰도·제품 의미·스케일이 미완성** 으로 재진술. 인용 줄(`leaderboard.rs` 정렬·`spacetime_leaderboard` rank 신뢰)은 재확인 결과 유효.
- ✅ 유지: 정렬 키·단조 가드·클라이언트 rank 비재계산·xp 서버 미검증·로컬 1레벨 시작·전수 스캔·attach race — 해당 `파일:줄` 재오픈으로 내용 일치 확인.
