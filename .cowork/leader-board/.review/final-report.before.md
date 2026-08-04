# 종합 검토 — leader-board

> 요청: 순위 랭킹이 잘 되어져 있나요? 분석을 해서, 순위 랭킹이 올바로 동작하도록 수정/보완 해 주세요.
> 분석: claude · codex · grok(2-pass) · kimi — 4/4 성공
> 종합: 2026-08-04 20:45 · 읽기 전용 검증 — 작업공간 미수정

## 1. 결론

**순위를 매기는 규칙 자체는 서버에서 올바르게 구현되어 있다.** `rank_key` 가 레벨↓ → xp↓ →
생성시각↑ → id↑ 로 완전 순서를 만들고, `leaderboard` 의 `enumerate` 순위와 `my_rank` 의
"앞선 수 + 1" 은 같은 키를 쓰므로 같은 값을 낸다. 여기서 고칠 것은 없다.

**깨져 있는 것은 그 규칙에 들어가는 입력값이다.** 결정적 결함은 하나다 — 게임이 서버에 저장된
레벨을 복원하지 않는다. 재접속하면 인게임 레벨은 1로 돌아가는데 서버 값은 그대로 남고, 서버가
뒤로 가는 보고를 버리므로 **새 접속에서 아무리 사냥해도 이전 최고 레벨을 넘기 전까지 순위가
전혀 움직이지 않는다.** 캐릭터 선택 화면은 `Lv.12` 를 보여주는데 출격하면 HUD 는 `1` 이다.

그다음으로 심각한 것은 **만렙 구간의 순위가 캐릭터 생성 순으로 영구 고정**된다는 점이다
(만렙 도달 시 클라이언트가 xp 를 0 으로 버리므로 30레벨끼리는 전원 동점 → `created_at` 타이브레이크).
엔드게임 랭킹이 죽는다. 그 밖에 서버의 xp 무검증(조작 시 영구 1위 고착), 레벨업 즉시 보고가 잔여
xp 를 버리는 것, 전송 중 종료 시 유실, xp 막대의 거짓 표시, 구독 누수가 실재한다.

## 2. 네 AI 의견 대조

| 쟁점 | claude | codex | grok | kimi | 검증 결과 |
|---|---|---|---|---|---|
| 순위 산정 규칙 | 맞다 | 맞다 | 맞다 | 맞다 | ✅ 합의 — `leaderboard.rs:69-76` 확인 |
| 서버 레벨 미복원 | 1순위 결함 | 2순위 | 3순위(미결정 프레임) | 미언급 | ⚖️ claude 판정 채택 — 실재하며 최우선 |
| 만렙 xp=0 → 생성순 고정 | 10순위(기획 판단) | 미언급 | 미언급 | **1순위 결함** | ⚖️ kimi 가 맞다 — `player.dart:509` 확인 |
| 서버 xp 상한 없음 | 미언급 | 1순위 | 2순위 | 2순위 | ✅ 합의 — `leaderboard.rs:169-186` 확인 |
| 연속 레벨업 유실 | 유실 | 유실 | **지연이지 유실 아님**(자기 교정) | 지연 | ⚖️ grok 이 맞다 — tick 이 따라잡는다 |
| 종료 시 진짜 유실 | 언급 | 언급 | **경로 특정** | 미언급 | ⚖️ grok 판정 — `_inFlight` 중 종료 |
| `reportLevel` 이 xp=0 전송 | 미언급 | 미언급 | 언급 | **명시** | ✅ 확인 — `spacetime_game_sync.dart:63` |
| attach/detach 경쟁 | 지적 | 지적 | 지적 | 지적 | ✅ 합의 — `spacetime_leaderboard.dart:44-54` |
| xp 막대 peak=1 → 항상 꽉 참 | **명시** | 언급 | 언급 | "장식이라 문제없음" | ⚖️ claude 가 맞다 — kimi 는 과소평가 |
| 테스트 `xp=120` 이 곡선 위반 | 미언급 | **고유 지적** | 미언급 | 미언급 | ⚖️ codex 가 맞다 — `xpToNext(4)=109` |
| rank 일치 단언 플레이크 | 미언급 | 미언급 | 미언급 | **고유 지적** | ⚖️ 부분 인정 — 아래 §4 |
| 전수 스캔 성능 | 우려 | 우려 | 우려 | 우려 | ✅ 합의하되 넷 다 `[추측]` — 실측 없음 |

## 3. 합의 — 검증 통과

- **순위 산정 규칙은 올바르다.** `spacetimedb/src/leaderboard.rs:69-76` 의 `rank_key` 는
  `(Reverse(level), Reverse(xp), created_at, id)` 4단계로 완전 순서를 만든다. `outranks`(`:79-81`)가
  같은 키를 쓰므로 `leaderboard`(`:106-115`)의 `enumerate` 순위와 `my_rank`(`:121-139`)의
  `ahead + 1` 은 같은 값을 낸다. 자기 자신은 `rank_key(me) < rank_key(me)` 가 false 라 세지 않는다.
  동점이어도 rank 는 겹치지 않는다.
- **순위를 저장하지 않고 계산하는 설계가 옳다.** `leaderboard.rs:3-6` 의 판단대로, 별도 순위 표가
  없으니 캐릭터 삭제(`character.rs:150`)·레벨 변동 시 두 표가 어긋날 경로가 구조적으로 없다.
- **서버 권위 원칙을 지킨다.** `report_progress` 는 `crate::require_session`(`lib.rs:150-156`)으로
  호출자를 도출하고 `account_id` 를 인자로 받지 않는다. `LeaderboardEntry` 를 별도 값으로 만들어
  `account_id` 가 순위표를 타고 나가지 않는다.
- **클라이언트가 순위를 재계산하지 않는다.** `spacetime_leaderboard.dart:79-88` 은 서버 `rank` 로
  정렬만 한다. 단일 진실 공급원이 유지된다.
- **서버 xp 상한 검증이 없다.** `leaderboard.rs:169-186` 은 `level == 0 || level > MAX_LEVEL` 과
  단조성만 본다. xp 는 어떤 `u64` 든 통과한다.
- **attach/detach 경쟁 조건이 있다.** `spacetime_leaderboard.dart:44-54` — `await subscribe` 중
  `detach()` 가 오면 `_querySetId` 가 아직 null 이라 no-op 이고, 이후 구독이 설정되어 남는다.
  `leaderboard_screen.dart` 의 `onRemove` 는 `if (_open)` 조건이라 이 누수를 풀지 못한다.

## 4. 이견 — 자료로 판정

### 쟁점 1: "연속 레벨업 시 보고가 유실되는가"

- claude·codex: 유실된다. grok(2-pass): **지연이지 유실이 아니다.** kimi: 지연.
- **판정: grok 이 맞다.** `spacetime_game_sync.dart:48-49` 의 `tick` 이 매 프레임
  `_level = game.player.level; _xp = game.player.xp;` 로 최신값을 읽고, `_inFlight` 로 건너뛴
  보고는 다음 주기(≤5초)에 `game.player` 기준으로 다시 전송된다. 세션이 유지되는 한 따라잡는다.
- **다만 진짜 유실 경로는 따로 있다** — grok 이 pass2 에서 특정했다:
  `reportRunFinished`(`:70-77`)가 `_send(_level, _xp)` 로 **내부 캐시**를 쓰는데,
  `reportLevel`(`:59-65`)이 직전에 `_xp = 0` 으로 덮었고 그 뒤 tick 이 한 번도 돌지 않았다면
  잔여 xp 가 0 으로 보고된다. 그리고 그 시점에 `_inFlight` 이면 `_send` 가 그냥 반환해
  **최종 상태가 서버에 남지 않는다.** 게임 오버 시 `update()` 가 멈춰 따라잡을 tick 이 없다.

### 쟁점 2: "xp 막대는 장식인가 결함인가"

- kimi: "순위와 무관한 장식이라 정합성 문제 없음". claude: 하위권일수록 막대가 꽉 차는 **표시 오류**.
- **판정: claude 가 맞다.** `leaderboard_screen.dart:488-491` 의 `peak` 은 `_rows`(상위 100) 안에서
  같은 레벨의 최대 xp 를 찾고 **초기값이 1** 이다. 100위 밖 플레이어의 레벨 그룹이 `_rows` 에
  없으면 `peak = 1` → `ratio = (xp / 1).clamp(0,1) = 1.0`. `_renderMyRank` 가 같은 함수를 부르므로
  (`:560-569`) **하위권일수록 자기 막대가 꽉 찬 것을 본다.** 순위는 바닥인데 진행 막대는 최대치 —
  사용자가 순위 근거를 오해하는 방향으로 정확히 틀렸다. 장식이 아니라 거짓 정보다.
- 게다가 정확한 분모가 이미 앱 안에 있다: `LevelSystem.xpToNext(level)`(`level_system.dart:41-44`).
  코드 주석("다음 레벨까지 필요한 양은 클라이언트만 알고" — `:486`)이 스스로를 반박하고 있다.

### 쟁점 3: "`my_rank` 와 `leaderboard` 의 rank 가 항상 일치하는가"

- claude: 같은 키를 쓰므로 일치한다. kimi: 별도 계산이라 순간 어긋날 수 있다(테스트 플레이크).
- **판정: 둘 다 부분적으로 맞다.** **서버 계산은 일치한다**(claude 가 맞다) — 같은 `rank_key` 를
  쓰고 같은 트랜잭션 스냅샷에서 평가되기 때문이다. 그러나 **테스트가 검증하는 것은 클라이언트가
  본 두 캐시의 값**이고, 그 사이에 제3자가 레벨업하면 서로 다른 스냅샷을 볼 수 있다.
  두 view 를 같은 query set 으로 묶어 구독하므로(`cyborg_connection.dart` 의
  `kLeaderboardSubscriptions`) 위험은 낮지만, **공용 월드에서 0 은 아니다.**
  `test/spacetime_integration_test.dart:199` 의 `expect(row.rank, mine.rank)` 는 그대로 두면
  드물게 깨진다.

### 쟁점 4: "만렙 순위 정체가 얼마나 급한가"

- kimi: 1순위. claude: 10순위(기획 판단으로 미룸). codex·grok: 미언급.
- **판정: kimi 가 맞다.** `player.dart:504-509` 를 열어 확인: `while` 루프 뒤
  `if (level >= LevelSystem.maxLevel) xp = 0;`. 30레벨 캐릭터는 전원 `xp = 0` 이 되고, 순위는
  `created_at` 으로만 갈린다. **먼저 만렙을 찍어도 나보다 일찍 만들어진 캐릭터가 만렙이 되는 순간
  영원히 아래로 밀린다.** MMORPG 에서 가장 오래 경쟁이 유지돼야 할 구간이 "계정 개설 순"으로
  고정된다. 그리고 kimi 의 지적대로 **만렙 인구가 쌓인 뒤에 고치면 순위가 하루아침에 뒤집힌다** —
  지금이 가장 싸게 고칠 시점이다.

## 5. 고유 통찰 — 하나만 발견했으나 검증됨

- **codex**: 통합 테스트가 도달 불가능한 값을 정상으로 단언한다 — 확인:
  `test/spacetime_integration_test.dart:186` 이 `reportProgress(level: 4, xp: Int64(120))` 을 쓰는데,
  클라이언트 곡선상 `xpToNext(4) = round(60 × 1.22³) = 109` 다. **xp 120 은 4레벨에서 존재할 수
  없는 값**이며, 그 상태면 이미 5레벨이어야 한다. 서버에 xp 검증을 넣는 순간 이 테스트가 깨진다.
  내가 쓴 테스트의 결함이다.
- **kimi**: 단조 가드가 치트를 **영구 보존**한다 — 확인: `leaderboard.rs:175-177` 의
  `xp <= character.xp` 무시 규칙 때문에, 조작 클라이언트가 `xp = u64::MAX` 를 한 번 보내면
  **정직한 후속 보고로는 절대 덮이지 않는다.** 상한 검증 없는 단조 가드는 방어가 아니라
  치트 고착 장치다. 이 인과를 짚은 것은 kimi 뿐이다.
- **grok**: 순위 단위가 계정이 아니라 **캐릭터**다 — 확인: `character.rs:12` 의
  `MAX_CHARACTERS = 4`. 한 계정의 캐릭터 4개가 순위표에 나란히 오를 수 있다. 의도된 설계일 수
  있으나 UI 어디에도 그 사실이 없어 "내 계정이 네 줄"로 읽힐 수 있다.
- **grok**: 이 문제의 성격이 버그가 아니라 **미결정**이다 — 선택 화면은 서버 레벨
  (`character_select_screen.dart:258` 의 `'Lv.${character.level}'`)을, 월드는 로컬 레벨을 보여준다.
  "순위 = 지금 몸체" 인지 "순위 = 역대 최고 도달" 인지가 코드에도 문서에도 고정돼 있지 않다.
  이 프레이밍이 정확하며, 아래 권고 1의 선택 근거가 된다.

## 6. 반증 — 근거가 틀린 주장

- **kimi**: "xp 막대는 순위와 무관한 장식이라 정합성 문제 없다"(`kimi-cowork.md:33`) — ❌
  `leaderboard_screen.dart:488-491` 을 열어보니 `peak` 초기값이 1 이라 참조 집합 밖에서는
  ratio 가 항상 1.0 이 된다. 장식이 아니라 **틀린 정보를 자신 있게 표시**하는 코드다. §4 쟁점 2 참조.
- **claude**: "만렙 동점 규칙은 기획 판단이라 코드를 건드리지 말고 선택지만 제시"(권고 10) — ⚠️
  판단 자체는 합리적이나 **우선순위가 틀렸다.** 만렙 인구가 생긴 뒤에는 되돌리기 비용이 급증하므로
  (kimi 의 지적, 검증됨) "나중에 결정" 이 가장 비싼 선택지다. 지금 결정해야 한다.
- **네 AI 공통**: 전수 스캔 성능 문제 — ⚠️ **근거는 맞으나 결론은 미확정.**
  `leaderboard.rs:106-115` 가 `filter(0u32..)` 로 전체를 모아 정렬하는 것은 사실이다. 그러나
  **SpacetimeDB 2.7 이 view 를 언제·얼마나 재평가하는지는 넷 다 실측하지 못했고**(각자 §6 에
  `[추측]` 로 명시), 나도 확인하지 못했다. 현재 캐릭터 수가 두 자리인 단계에서 구조를 바꾸는 것은
  근거 없는 최적화다. **이번 수정 범위에서 제외한다.**

## 7. 최종 권고

| 순위 | 권고 | 범위 | 근거 | 리스크 | 검증 방법 |
|---|---|---|---|---|---|
| 1 | **서버 레벨·xp 를 게임 시작 시 복원한다.** `Player` 에 연출 없이 스탯만 맞추는 `restoreProgress(level, xp)` 추가(`_levelUp` 의 스탯 상승분을 공유 헬퍼로 추출), `ActionRpgGame` 에 시작 레벨·xp 필드, `main.dart` 에서 `widget.character` 의 값 전달 | 클라이언트 | `main.dart:70`, `player.dart:32-33`, `action_rpg_game.dart:176`·`1017`, `leaderboard.rs:175-177` | 레벨 25 캐릭터가 웨이브 1부터 시작 — 초반 난이도 무의미. 연출(`_levelUp`)을 재사용하면 배너·효과음 N번 폭발 | `flutter analyze` 0, `flutter test` 통과. 재접속 시 HUD 레벨이 선택 화면 `Lv.N` 과 일치하는지 |
| 2 | **만렙에서 xp 를 버리지 않는다.** `player.dart:509` 의 `xp = 0` 제거 → 만렙 이후 누적 진행도가 동점을 가른다 | 클라이언트 | `player.dart:504-509`, `leaderboard.rs:73` | 기존 만렙 캐릭터의 상대 순위가 바뀐다(현재 만렙 인구 0 이므로 지금이 최적 시점). HUD 는 만렙 시 게이지를 1.0 으로 고정하므로(`hud.dart:170`) 표시 영향 없음 | `flutter test`. 만렙 두 캐릭터의 xp 가 서로 다르게 유지되는지 |
| 3 | **서버에 xp 상한을 강제한다.** `leaderboard.rs` 에 클라이언트와 같은 곡선(`base=60`, `curve=1.22`)의 `xp_to_next(level)` 을 두고, `level < 30` 이면 `xp < xp_to_next(level)`, `level == 30` 이면 `xp <= ENDGAME_XP_CAP` 을 강제 | **서버 (재배포 필요)** | `leaderboard.rs:169-186`, `level_system.dart:30-44` | ⚠️ **maincloud 재배포**. 곡선이 클라이언트와 어긋나면 정직한 보고가 거절된다 — 두 곳의 상수를 서로 참조하도록 주석으로 묶어야 한다. 기존 저장 행은 자동 교정되지 않는다 | `cargo test`(곡선 일치 단위 테스트 추가), 통합 테스트로 과대 xp 거절 확인 |
| 4 | **전송 신뢰성을 고친다.** ⑴ `GameSync.reportLevel(int level)` → `reportLevel(int level, int xp)` 로 확장해 실제 잔여 xp 를 보낸다 ⑵ `_inFlight` 중 들어온 최신값을 `_pending` 에 잡아 `finally` 에서 이어 보낸다 ⑶ `_rejected` 영구 플래그를 백오프(연속 실패 상한)로 바꾼다 | 클라이언트 | `spacetime_game_sync.dart:59-65`·`70-77`·`79-95`, `game_sync.dart:27` | 인터페이스 변경이라 `OfflineGameSync` 와 호출부(`action_rpg_game.dart`)를 함께 고쳐야 한다. 재시도 상한이 없으면 서버 로그가 늘어난다 | `flutter analyze` 0, `flutter test` |
| 5 | **xp 막대를 실제 진행도로 바꾼다.** `LevelSystem.xpToNext(row.level)` 를 분모로 쓰고, 만렙은 막대 대신 `MAX` 표시로 분기 | 클라이언트 | `leaderboard_screen.dart:485-507`, `level_system.dart:41-44` | 만렙 분기를 빠뜨리면 만렙 행이 늘 0 으로 보인다 | `flutter test`, 화면 확인 |
| 6 | **구독 누수를 막는다.** `attach()` 에 세대 카운터를 두고, `await` 완료 시점에 세대가 바뀌었으면 즉시 `unsubscribe`. `onRemove` 의 `if (_open)` 조건도 함께 정리 | 클라이언트 | `spacetime_leaderboard.dart:44-63`, `leaderboard_screen.dart` `onRemove`, `cyborg_connection.dart:34-38` | 어설픈 플래그로 고치면 빠른 재열기에서 구독이 두 번 걸리거나 영구 해제된다 — 세대 방식이어야 한다 | `flutter analyze` 0, 빠른 여닫기 수동 확인 |
| 7 | **테스트를 바로잡고 보강한다.** ⑴ `xp: 120` → 곡선상 유효한 값으로 교체 ⑵ `expect(row.rank, mine.rank)` 를 플레이크에 강하게 완화 ⑶ 같은 레벨 다른 xp 의 순위 역전 검증 추가 ⑷ 서버에 만렙 동점·xp 상한 단위 테스트 추가 | 테스트 (서버 + 클라이언트) | `spacetime_integration_test.dart:186`·`199`, `leaderboard.rs:213-237` | 통합 테스트는 실서버(maincloud)를 건드린다 — 생성한 캐릭터를 반드시 정리해야 한다 | `cargo test`, `flutter test` |
| — | **전수 스캔 최적화는 하지 않는다.** 근거는 맞으나 재평가 비용을 아무도 실측하지 못했고, 현재 인구 규모에서는 근거 없는 최적화다 | — | §6 반증 항목 | 인구가 늘면 재검토 | 실측 후 판단 |

**되돌리기 어렵거나 외부에 영향을 주는 변경**: 권고 3 만 **maincloud 재배포**가 필요하다
(`spacetime publish withcenter-cyborg --server maincloud -p ./spacetimedb --yes`).
나머지 1·2·4·5·6·7 은 클라이언트 전용이라 재배포 없이 적용된다.

## 8. 미해결 · 사람 판단 필요

- **순위의 의미**(grok 의 프레이밍): "지금 몸체의 레벨" 인가 "역대 최고 도달" 인가. 권고 1 은
  전자를 택한 것이다 — 캐릭터 선택 화면이 이미 서버 레벨을 `Lv.N` 으로 보여주고
  (`character_select_screen.dart:258`), CLAUDE.md 가 단일 공유 월드 MMORPG 를 명시하므로 캐릭터
  성장이 지속되는 쪽이 장르 관례에 맞다고 판단했다. **다른 의도였다면 되돌려야 한다.**
- **레벨 복원 후의 웨이브 난이도**: 복원해도 `startGame()` 은 항상 웨이브 1부터다
  (`action_rpg_game.dart`). 레벨 25 캐릭터에게 웨이브 1은 무의미하다. **이번 수정 범위 밖**이며
  별도 기획 결정이 필요하다.
- **계정당 캐릭터 4개가 모두 독립 순위에 오르는 것**(`character.rs:12`)이 의도인지. 코드는 전자로
  구현돼 있고 이번에 바꾸지 않는다.
- **`ENDGAME_XP_CAP` 의 값**: 어떤 상한을 두든 치터는 그 상한까지 올릴 수 있다. 상한의 가치는
  `u64::MAX` 고착을 막고 정직한 플레이어가 언젠가 따라잡을 수 있게 하는 것이다. 값은 판단이며,
  권고 3 에서는 정상 플레이로 도달 가능하되 무의미하게 크지 않은 수준으로 잡는다.
- **view 재평가 비용**: 넷 다 실측 못 했고 나도 못 했다. 인구가 세 자리를 넘으면 계측이 필요하다.
- **maincloud 에 이미 저장된 비정상 xp 유무**: 조회하지 않았다. 권고 3 을 배포해도 기존 행은
  교정되지 않는다.
