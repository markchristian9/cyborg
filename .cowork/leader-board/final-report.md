# 종합 검토 — leader-board

> 요청: 순위 랭킹이 잘 되어져 있나요? 분석을 해서, 순위 랭킹이 올바로 동작하도록 수정/보완 해 주세요.
> 분석: claude · codex · grok(2-pass) · kimi — 4/4 성공
> 종합: 2026-08-04 20:45 · 읽기 전용 **정적 대조** — 작업공간 미수정, `cargo test`·`flutter analyze`·
> `flutter test` 는 실행하지 않았다(넷 다 미실행, 나도 미실행)
> 개정: 리뷰 4편 반영 — 권고 2 처방 교정, 유실 경로 정정, 인용 줄 재확인, 로딩 고착 복원

## 1. 결론

**순위를 매기는 규칙 자체는 서버에서 올바르게 구현되어 있다.** `rank_key` 가 레벨↓ → xp↓ →
생성시각↑ → id↑ 로 완전 순서를 만들고, `leaderboard` 의 `enumerate` 순위와 `my_rank` 의
"앞선 수 + 1" 은 같은 키를 쓰므로 같은 값을 낸다. 여기서 고칠 것은 없다.

**깨져 있는 것은 그 규칙에 들어가는 입력값이다.** 결정적 결함은 하나다 — 게임이 서버에 저장된
레벨을 복원하지 않는다. 재접속하면 인게임 레벨은 1로 돌아가는데 서버 값은 그대로 남고, 서버가
뒤로 가는 보고를 버리므로 **새 접속에서 아무리 사냥해도 이전 최고 레벨을 넘기 전까지 순위가
전혀 움직이지 않는다.** 캐릭터 선택 화면은 `Lv.12` 를 보여주는데 출격하면 HUD 는 `1` 이다.

그다음으로 심각한 것은 **만렙 구간의 순위가 캐릭터 생성 순으로 영구 고정**된다는 점이다.
다만 원인은 초판이 지목한 `xp = 0` 한 줄이 아니라 **두 줄**이다 — `gainXp` 가 만렙이면
**첫 줄에서 반환**(`player.dart:562`)하므로 만렙 이후에는 xp 자체가 쌓이지 않고, 그 위에
도달 시 잔여분마저 버려진다(`:582`). 리뷰 4편이 전원 지적한 지점이며 직접 확인했다.
**초판 권고 2(`:582` 한 줄 제거)는 그대로 적용해도 목표를 달성하지 못한다** — 정체 이유가
`created_at` 에서 "만렙 찍던 순간의 우연한 잔여값" 으로 바뀔 뿐이다. §7 에서 교정했다.

그 밖에 서버의 xp 무검증(조작 시 영구 1위 고착), 레벨업 즉시 보고가 잔여 xp 를 버리는 것,
**로그아웃 시** 최종 상태 유실, xp 막대의 거짓 표시, 구독 누수, **"순위를 불러오는 중" 영구
고착**이 실재한다.

## 2. 네 AI 의견 대조

| 쟁점 | claude | codex | grok | kimi | 검증 결과 |
|---|---|---|---|---|---|
| 순위 산정 규칙 | 맞다 | 맞다 | 맞다 | 맞다 | ✅ 합의 — `leaderboard.rs:69-76` 확인 |
| 서버 레벨 미복원 | 1순위 결함 | 2순위 | 3순위(미결정 프레임) | 미언급 | ⚖️ claude 판정 채택 — 실재하며 최우선 |
| 만렙 xp 정체 → 생성순 고정 | 10순위(기획 판단) | 미언급 | 미언급 | **1순위 결함** | ⚖️ kimi 가 맞다 — 단 원인은 `player.dart:562`+`:582` 두 줄 |
| 서버 xp 상한 없음 | 미언급 | 1순위 | 2순위 | 2순위 | ✅ 합의 — `leaderboard.rs:169-177` 확인 |
| 연속 레벨업 유실 | 종료 경로 한정 | 세션 유지 시 복구 인정 | **지연이지 유실 아님**(자기 교정) | 지연 | ⚖️ grok 이 맞다 — tick 이 따라잡는다 |
| 종료 시 진짜 유실 | 언급 | 언급 | **경로 특정** | 미언급 | ⚖️ grok 판정 — 단 **사망이 아니라 로그아웃** 경로 |
| `reportLevel` 이 xp=0 전송 | 미언급 | 미언급 | 언급 | **명시** | ✅ 확인 — `spacetime_game_sync.dart:63-64` |
| attach/detach 경쟁 | 지적 | 지적 | 지적 | 지적 | ✅ 합의 — `spacetime_leaderboard.dart:43-63` |
| **"불러오는 중" 영구 고착** | **명시** | 언급 | 언급 | 언급 | ✅ 확인 — `leaderboard_screen.dart:130`·`:132`·`:160` |
| xp 막대 peak=1 → 항상 꽉 참 | **명시** | 언급 | 언급 | "장식이라 문제없음" | ⚖️ claude 가 맞다 — kimi 는 과소평가 |
| 테스트 `xp=120` 이 곡선 위반 | 미언급 | **고유 지적** | 미언급 | 미언급 | ⚖️ codex 가 맞다 — `xpToNext(4)=109` |
| rank 일치 단언 플레이크 | 미언급 | 반증(SDK 동기 적용) | 미언급 | **고유 지적** | ⚖️ 양쪽 다 미확정 — 아래 §4 |
| 전수 스캔 성능 | 우려 | 우려 | 우려 | 우려 | ✅ 합의하되 넷 다 `[추측]` — 실측 없음 |

## 3. 합의 — 정적 대조 통과

- **순위 산정 규칙은 올바르다.** `spacetimedb/src/leaderboard.rs:69-76` 의 `rank_key` 는
  `(Reverse(level), Reverse(xp), created_at, id)` 4단계로 완전 순서를 만든다. `outranks`(`:79-81`)가
  같은 키를 쓰므로 `leaderboard`(`:105-115`)의 `enumerate` 순위와 `my_rank`(`:121-139`)의
  `ahead + 1` 은 같은 값을 낸다. 자기 자신은 `rank_key(me) < rank_key(me)` 가 false 라 세지 않는다.
  동점이어도 rank 는 겹치지 않는다.
- **순위를 저장하지 않고 계산하는 설계가 옳다.** `leaderboard.rs:3-6` 의 판단대로, 별도 순위 표가
  없으니 캐릭터 삭제(`character.rs:136`)·레벨 변동 시 두 표가 어긋날 경로가 구조적으로 없다.
- **서버 권위 원칙을 지킨다.** `report_progress` 는 `crate::require_session`(`lib.rs:156-162`)으로
  호출자를 도출하고 `account_id` 를 인자로 받지 않는다. `LeaderboardEntry` 를 별도 값으로 만들어
  `account_id` 가 순위표를 타고 나가지 않는다.
- **클라이언트가 순위를 재계산하지 않는다.** `spacetime_leaderboard.dart:78-88` 은 서버 `rank` 로
  정렬만 한다. 단일 진실 공급원이 유지된다.
- **서버 xp 상한 검증이 없다.** `leaderboard.rs:169-177` 은 `level == 0 || level > MAX_LEVEL` 과
  단조성만 본다. xp 는 어떤 `u64` 든 통과한다. 같은 이유로 **레벨 1 → 30 즉시 점프도 통과**한다
  (모듈 주석 `:151-153` 이 "그럴듯한 속도로 올려 보내는 것은 막지 못한다"고 이미 인정한 한계의
  더 강한 형태다).
- **attach/detach 경쟁 조건이 있다.** `spacetime_leaderboard.dart:43-63` — `await subscribe` 중
  `detach()` 가 오면 `_querySetId` 가 아직 null 이라 no-op 이고(`:59-60`), 이후 구독이 설정되어
  남는다. `_subscribing` 플래그는 중복 구독만 막을 뿐 이 경로를 막지 못한다.
  `leaderboard_screen.dart:155` 의 `onRemove` 는 `if (_open)` 조건이라 이 누수를 풀지 못한다.
- **"순위를 불러오는 중" 이 영원히 풀리지 않을 수 있다.** `leaderboard_screen.dart:130` 이
  `_loading` 을 켜고 `:132` 는 `source.attach()` 의 `Future` 를 버린다. `_loading = false` 는
  `_onChanged`(`:160`)와 `close`(`:140`)에만 있으므로, 구독이 실패하거나 결과가 비어 알림이
  오지 않으면 화면이 갇힌다. 사용자가 리더보드를 열었을 때 가장 먼저 마주치는 실패 모드다
  (claude 가 발견, 네 리뷰 전원 복원 요구, 직접 확인).

## 4. 이견 — 자료로 판정

### 쟁점 1: "연속 레벨업 시 보고가 유실되는가"

- claude·codex: 종료 경로에서 유실. grok(2-pass): **지연이지 유실이 아니다.** kimi: 지연.
- **판정: grok 이 맞다.** `spacetime_game_sync.dart:49-50` 의 `tick` 이 매 프레임
  `_level = game.player.level; _xp = game.player.xp;` 로 최신값을 읽고, `_inFlight` 로 건너뛴
  보고는 다음 주기(≤5초)에 `game.player` 기준으로 다시 전송된다. 세션이 유지되는 한 따라잡는다.
- **진짜 유실 경로는 로그아웃이다** — 초판이 이 경로를 "게임 오버" 로 잘못 적었다. 정정한다:
  이 게임에는 **게임 오버가 없다.** `onPlayerDied`(`action_rpg_game.dart:902-919`)는 주석대로
  ("모두가 하나의 월드를 공유하므로 이 게임에는 게임 오버가 없다", `:904`) 안전지대 리스폰만
  하고 `status` 를 바꾸지 않으므로 `update()`(`:313`)와 `sync?.tick` 은 계속 돈다.
  `reportRunFinished()`(`:944-955`)의 **유일한 호출처는 `requestLogout()`(`:817`)** 이고, 그
  바로 다음 줄 `onLogout?.call()`(`:818`)은 전송 완료를 기다리지 않는다. 이 fire-and-forget
  구간에서 ⑴ `reportRunFinished` 가 `_send(_level, _xp)` 로 **내부 캐시**를 쓰는데
  `reportLevel`(`:58-65`)이 직전에 `_xp = 0` 으로 덮었고 tick 이 아직 안 돌았다면 잔여 xp 가
  0 으로 보고되고, ⑵ 그 시점에 `_inFlight` 이면 `_send`(`:79`)가 그냥 반환해 **최종 상태가
  서버에 남지 않는다.** 로그아웃 확인 다이얼로그(`main.dart:74-` )가 사실상 시간을 벌어 주지만
  계약상 보장은 아니다(grok 의 단서). 프로세스 강제 종료는 durable local queue 없이는 어떤
  수정으로도 보장되지 않는다.
- **코드 주석이 스스로 틀렸다**: `spacetime_game_sync.dart:60-61` 은 "경험치는 레벨업 직후 0 부터
  다시 쌓이므로 0 으로 보낸다" 고 하지만, `gainXp` 의 while 은 `xp -= xpToNextLevel`(`:578`)로
  잔여를 남긴다. `:28-29` 의 "사망 시점에는 게임 루프가 멈춰" 라는 주석도 현재 코드와 어긋난다.

### 쟁점 2: "xp 막대는 장식인가 결함인가"

- kimi: "순위와 무관한 장식이라 정합성 문제 없음". claude: 하위권일수록 막대가 꽉 차는 **표시 오류**.
- **판정: claude 가 맞다.** `leaderboard_screen.dart:488-490` 의 `peak` 은 `_rows`(상위 100) 안에서
  같은 레벨의 최대 xp 를 `fold<int>(1, ...)` 로 찾고 **초기값이 1** 이다. 100위 밖 플레이어의 레벨
  그룹이 `_rows` 에 없으면 `peak = 1` → `ratio = (xp / 1).clamp(0,1) = 1.0`(`:491`).
  `_renderMyRank`(`:531-570`)가 같은 렌더 경로를 타므로 **하위권일수록 자기 막대가 꽉 찬 것을
  본다.** 순위는 바닥인데 진행 막대는 최대치 — 사용자가 순위 근거를 오해하는 방향으로 정확히
  틀렸다. 장식이 아니라 거짓 정보다.
- 게다가 정확한 분모가 이미 앱 안에 있다: `LevelSystem.xpToNext(level)`(`level_system.dart:41-44`).
  코드 주석("다음 레벨까지 필요한 양은 클라이언트만 알고" — `:486`)이 스스로를 반박하고 있다.

### 쟁점 3: "`my_rank` 와 `leaderboard` 의 rank 가 항상 일치하는가"

- claude: 같은 키를 쓰므로 일치한다. kimi: 별도 계산이라 순간 어긋날 수 있다(테스트 플레이크).
  codex(리뷰): SDK 가 한 `TransactionUpdateMessage` 의 query-set 테이블을 동기 적용하므로
  플레이크하지 않는다.
- **판정: 서버 계산은 일치한다**(claude 가 맞다) — 같은 `rank_key` 를 쓰고 같은 트랜잭션 스냅샷에서
  평가된다. 그러나 **테스트가 검증하는 것은 클라이언트가 본 두 캐시의 값**이다. 두 view 는 같은
  query set(`cyborg_connection.dart` 의 `kLeaderboardSubscriptions`)으로 묶여 있고, 테스트의 두
  읽기(`spacetime_integration_test.dart:195`·`:202`) 사이에 `await` 가 없다.
  **양쪽 다 미확정으로 남긴다** — kimi 의 플레이크 주장도, codex 의 SDK 동기 적용 반증도 나는
  `spacetimedb_sdk` 내부를 열어 확인하지 못했다. `[추측]`. 재현 자료가 나오기 전에는
  `test/spacetime_integration_test.dart:207` 의 `expect(row.rank, mine.rank)` 를 **약화하지 않는다**
  (근거 없이 단언을 무르면 진짜 회귀를 놓친다).

### 쟁점 4: "만렙 순위 정체가 얼마나 급한가"

- kimi: 1순위. claude: 10순위(기획 판단으로 미룸). codex·grok: 미언급.
- **판정: kimi 가 맞다.** 단 원인 지목을 교정한다. `player.dart:560-583` 을 열어 확인:
  `gainXp` 의 **두 번째 줄이 `if (level >= LevelSystem.maxLevel) return;`(`:562`)** 이고, while
  루프(`:577-580`) 뒤에 `if (level >= LevelSystem.maxLevel) xp = 0;`(`:582`) 이 있다.
  즉 30레벨 캐릭터는 ⑴ 도달 순간 잔여를 버리고 ⑵ 그 뒤로는 xp 획득 함수 자체가 조기 반환하므로
  전원 `xp = 0` 에 고정되고, 순위는 `created_at` 으로만 갈린다. **먼저 만렙을 찍어도 나보다 일찍
  만들어진 캐릭터가 만렙이 되는 순간 영원히 아래로 밀린다.** MMORPG 에서 가장 오래 경쟁이
  유지돼야 할 구간이 "계정 개설 순"으로 고정된다. 그리고 kimi 의 지적대로 **만렙 인구가 쌓인 뒤에
  고치면 순위가 하루아침에 뒤집힌다** — 지금이 가장 싸게 고칠 시점이다(단, 현재 만렙 인구는
  `[미확인]` — maincloud 를 조회하지 않았다).

## 5. 고유 통찰 — 소수가 짚었으나 검증됨

- **codex**: 통합 테스트가 도달 불가능한 값을 정상으로 단언한다 — 확인:
  `test/spacetime_integration_test.dart:190` 이 `reportProgress(level: 4, xp: Int64(120))` 을 쓰는데,
  클라이언트 곡선상 `xpToNext(4) = round(60 × 1.22³) = 109` 다. **xp 120 은 4레벨에서 존재할 수
  없는 값**이며, 그 상태면 이미 5레벨이어야 한다. 서버에 xp 검증을 넣는 순간 이 테스트가 깨진다.
  내가 쓴 테스트의 결함이다.
- **kimi**: 단조 가드가 치트를 **영구 보존**한다 — 확인: `leaderboard.rs:175-177` 의
  `xp <= character.xp` 무시 규칙 때문에, 조작 클라이언트가 `xp = u64::MAX` 를 한 번 보내면
  **정직한 후속 보고로는 절대 덮이지 않는다.** 상한 검증 없는 단조 가드는 방어가 아니라
  치트 고착 장치다. kimi 가 이 인과를 가장 명확히 짚었다(codex 도 같은 방향을 언급했다는
  리뷰 지적이 있으나 원본 분석 파일을 열지 못해 귀속은 단정하지 않는다).
- **grok**: 순위 단위가 계정이 아니라 **캐릭터**다 — 확인: `character.rs:12` 의
  `MAX_CHARACTERS = 4`. 한 계정의 캐릭터 4개가 순위표에 나란히 오를 수 있다. 의도된 설계일 수
  있으나 UI 어디에도 그 사실이 없어 "내 계정이 네 줄"로 읽힐 수 있다.
- **grok**: 이 문제의 성격이 버그가 아니라 **미결정**이다 — 선택 화면은 서버 레벨
  (`character_select_screen.dart:258` 의 `'Lv.${character.level} · ${kind.codename}'`)을, 월드는
  로컬 레벨(`player.dart:42` 의 `int level = 1`)을 보여준다. "순위 = 지금 몸체" 인지
  "순위 = 역대 최고 도달" 인지가 코드에도 문서에도 고정돼 있지 않다. 이 프레이밍이 정확하며,
  아래 권고 1의 선택 근거가 된다.

## 6. 반증 — 근거가 틀린 주장

- **kimi**: "xp 막대는 순위와 무관한 장식이라 정합성 문제 없다" — ❌
  `leaderboard_screen.dart:488-490` 을 열어보니 `peak` 초기값이 1 이라 참조 집합 밖에서는
  ratio 가 항상 1.0 이 된다. 장식이 아니라 **틀린 정보를 자신 있게 표시**하는 코드다. §4 쟁점 2 참조.
- **claude**: "만렙 동점 규칙은 기획 판단이라 코드를 건드리지 말고 선택지만 제시"(권고 10) — ⚠️
  판단 자체는 합리적이나 **우선순위가 틀렸다.** 만렙 인구가 생긴 뒤에는 되돌리기 비용이 급증하므로
  (kimi 의 지적, 검증됨) "나중에 결정" 이 가장 비싼 선택지다. 지금 결정해야 한다.
- **초판 종합(§4 쟁점 1)**: "게임 오버 시 `update()` 가 멈춰 따라잡을 tick 이 없다" — ❌ **철회.**
  `action_rpg_game.dart:904` 가 "이 게임에는 게임 오버가 없다"고 명시하고, `onPlayerDied` 는
  `respawnAt`(`:919`)만 한다. `GameStatus.gameOver`(`:41`)로 전이시키는 코드는 없다. 실제 경로는
  로그아웃이다. 세 리뷰(claude·codex·grok)가 독립적으로 같은 반증을 냈고 직접 확인했다.
- **초판 권고 2**: "`xp = 0` 제거만으로 만렙 이후 누적 진행도가 동점을 가른다" — ❌ **철회.**
  `player.dart:562` 의 조기 반환 때문에 만렙 이후 `gainXp` 가 아무 일도 하지 않는다.
  네 리뷰 전원이 지적했고 직접 확인했다. §7 권고 2 에서 처방을 교정했다.
- **네 AI 공통**: 전수 스캔 성능 문제 — ⚠️ **근거는 맞으나 결론은 미확정.**
  `leaderboard.rs:105-115` 가 `filter(0u32..)` 로 전체를 모아 정렬하고 `my_rank`(`:130-136`)가
  사용자마다 전체를 훑는 것은 사실이다. 그러나 **SpacetimeDB 2.7 이 view 를 언제·얼마나
  재평가하는지는 넷 다 실측하지 못했고**(각자 `[추측]` 로 명시), 나도 확인하지 못했다.
  현재 인구 규모에서 구조를 바꾸는 것은 근거 없는 최적화다. **이번 수정 범위에서 제외한다.**

## 7. 최종 권고

| 순위 | 권고 | 범위 | 근거 | 리스크 | 검증 방법 |
|---|---|---|---|---|---|
| 1 | **서버 레벨·xp 를 게임 시작 시 복원한다.** `Player` 에 연출 없이 스탯만 맞추는 `restoreProgress(level, xp)` 추가(`_levelUp` 의 스탯 상승분을 공유 헬퍼로 추출), `ActionRpgGame` 에 시작 레벨·xp 필드, `main.dart` 에서 `widget.character` 의 값 전달. **함께**: `SpacetimeGameSync` 생성/attach 시 `_sentLevel`/`_sentXp` 를 복원값으로 초기화 | 클라이언트 | `main.dart:64-70`, `player.dart:42-44`·`585-593`, `action_rpg_game.dart:1020`, `spacetime_game_sync.dart:34-35`, `leaderboard.rs:175-177` | 레벨 25 캐릭터가 웨이브 1부터 시작 — 초반 난이도 무의미. 연출(`_levelUp`)을 재사용하면 배너·효과음 N번 폭발. `_sent*` 를 초기화하지 않으면 접속 직후 전원이 서버가 이미 아는 값을 재전송(단조 가드로 no-op 이나 불필요 트랜잭션). **`restart()`(`:988-1030`)가 `Player` 를 새로 만드므로**(`:1020`) 시작값을 고정 필드로만 두면 재시작 때 출격 시점으로 후퇴한다 — 최초 hydrate 와 재시작 경로를 분리해야 한다 | `flutter analyze` 0, `flutter test` 통과. 재접속 시 HUD 레벨이 선택 화면 `Lv.N` 과 일치하는지 |
| 2 | **만렙 구간에서 xp 가 계속 쌓이게 한다.** ⑴ `player.dart:562` 의 만렙 조기 반환을 해제해 만렙에서도 `xp += amount` 가 돌게 하고 ⑵ `:582` 의 `xp = 0` 을 제거한다. while 루프(`:577`)는 만렙에서 `xpToNext(30) = 1 << 30`(`level_system.dart:42`)이라 자연히 돌지 않는다 ⑶ HUD·캐릭터 화면의 만렙 분기(`hud.dart:138`·`:170`, `character_screen.dart:280`·`:287`)가 이미 `MAX`/1.0 고정이라 표시는 그대로다 | 클라이언트 | `player.dart:560-583`, `level_system.dart:42`, `leaderboard.rs:72` | ⚠️ **용어 규격 확장이다.** `.cowork/cowork-prompt.md:72-73` 과 `leaderboard.rs:57-61` 은 `xp` 를 "현재 레벨 안의 진행도"로 못박았다. 만렙 구간만 "엔드게임 누적 점수"로 의미가 바뀌므로 **양쪽 주석을 함께 고쳐 예외를 문서화해야 한다**. 대안(별도 필드·만렙 도달 시각)은 §8 참조. 기존 만렙 캐릭터의 상대 순위가 바뀐다 | `flutter test`. **만렙 캐릭터가 계속 사냥할 때 xp 가 실제로 증가하는지**(초판의 "서로 다르게 유지되는지" 는 이 실패를 통과시킨다) |
| 3 | **서버에 xp 상한을 두되 거절이 아니라 clamp 한다.** `leaderboard.rs` 에 클라이언트와 같은 곡선(`base=60`, `curve=1.22`)의 `xp_to_next(level)` 을 두고, `level < 30` 이면 `xp` 를 `xp_to_next(level) - 1` 로, `level == 30` 이면 `ENDGAME_XP_CAP` 으로 **잘라서 저장**한다. **배포 전 `player_character` 의 비정상 xp 를 조회·정규화한다** | **서버 (재배포 필요)** | `leaderboard.rs:169-184`, `level_system.dart:30-44`, `spacetime_game_sync.dart:87-90` | ⚠️ **maincloud 재배포**. **거절(`Err`)로 구현하면 두 가지가 깨진다** — ⑴ 권고 2 로 만렙 xp 가 자라면 정직한 플레이어가 CAP 에 닿는 순간 `_rejected = true`(`:90`)로 그 세션 보고가 전면 중단되고, ⑵ 이미 비정상 xp 가 저장된 행은 정직한 보고가 단조 가드에 막히고 큰 보고는 새 검증에 막혀 **영구 갱신 불가(데드락)** 가 된다. clamp 는 둘 다 없앤다. 대신 clamp 된 값과 클라이언트 `_sentXp` 가 어긋나 이후 보고가 가드에 걸릴 수 있으므로 클라이언트가 `my_characters` 로 서버 값을 다시 읽어야 한다. 곡선이 클라이언트와 어긋나면 정상 진행이 잘린다. **기존 저장 행은 clamp 로도 자동 교정되지 않는다 — 배포 전 정규화가 선행 조건** | `cargo test`. **곡선 대조는 자기 곡선끼리 비교로는 부족하다** — 1~30 레벨 `xpToNext` 기대값을 고정 표로 박아 Rust·Dart 테스트가 **같은 표**를 검증하게 한다(부동소수 `round()` 경계도 이 표로 고정). 통합 테스트로 과대 xp 가 잘리는지 확인 |
| 4 | **전송 신뢰성을 고친다.** ⑴ `GameSync.reportLevel(int level)` → `reportLevel(int level, int xp)` 로 확장해 실제 잔여 xp 를 보낸다(현 주석 `:60-61` 의 "레벨업 직후 0" 전제가 틀렸다 — `:578` 이 잔여를 남긴다) ⑵ `_inFlight` 중 들어온 최신값을 `_pending` 에 잡아 `finally` 에서 이어 보낸다 ⑶ `reportRunFinished`/`flushProgress` 를 `Future` 로 만들고 `requestLogout()`(`:813-819`)이 제한 시간과 함께 **완료를 기다린 뒤** `onLogout` 을 부른다 | 클라이언트 | `spacetime_game_sync.dart:58-65`·`67-76`·`78-96`, `action_rpg_game.dart:813-819`·`944-955`, `game_sync.dart:27` | 인터페이스 변경이라 `OfflineGameSync` 와 호출부를 함께 고쳐야 한다. **프로세스 강제 종료·연결 선(先)차단은 durable local queue 없이는 어떤 수정으로도 보장되지 않는다** — 이 권고의 한계로 명시한다. `_rejected` 를 백오프로 바꾸는 초판 항목은 **내렸다**: 코드 주석(`:37-43`)이 "게임 화면은 캐릭터를 고른 뒤에만 뜨고 로그아웃하면 통째로 사라진다"고 영구 플래그를 정당화하고, 연결 끊김은 `SpacetimeDbException`(`:91`)으로 이미 재시도 경로에 있다. 권고 3 을 clamp 로 하면 거절 자체가 사라진다 | `flutter analyze` 0, `flutter test` |
| 5 | **xp 막대를 실제 진행도로 바꾼다.** `LevelSystem.xpToNext(row.level)` 를 분모로 쓰고, 만렙은 막대 대신 `MAX` 표시로 분기 | 클라이언트 | `leaderboard_screen.dart:485-507`, `level_system.dart:41-44` | 만렙 분기를 빠뜨리면 만렙 행이 늘 0(또는 권고 2 적용 후 임의값)으로 보인다. 권고 2 를 적용하면 만렙 xp 는 진행도가 아니므로 이 분기는 **필수**다 | `flutter test`, 화면 확인 |
| 6 | **구독 누수와 로딩 고착을 함께 막는다.** ⑴ `attach()` 에 세대 카운터를 두고, `await` 완료 시점에 세대가 바뀌었으면 즉시 `unsubscribe` ⑵ `onRemove` 의 `if (_open)` 조건 정리 ⑶ **`open()` 이 `source.attach()` 의 `Future` 를 받아 완료·실패·타임아웃으로 `_loading` 을 확정**하고 실패 시 재시도 UI 를 보여준다(같은 세대 가드로, 닫은 뒤 도착한 완료가 상태를 뒤집지 않게) | 클라이언트 | `spacetime_leaderboard.dart:43-63`, `leaderboard_screen.dart:126-134`·`:155`·`:159-162`, `cyborg_connection.dart` | 어설픈 플래그로 고치면 빠른 재열기에서 구독이 두 번 걸리거나 영구 해제된다 — 세대 방식이어야 한다. **⑴ 만 하고 ⑶ 을 빠뜨리면 "늦게 걸린 구독을 즉시 해제" 하는 경로가 늘어 알림이 영영 안 오는 경우가 오히려 많아진다**(kimi 지적) — 반드시 한 묶음으로 고친다 | `flutter analyze` 0, 빠른 여닫기 수동 확인, 구독 실패를 강제해 로딩이 풀리는지 |
| 7 | **테스트를 바로잡고 보강한다.** ⑴ `xp: Int64(120)`(`:190`) → 곡선상 유효한 값으로 교체(예: `level: 4, xp: 60`) ⑵ 같은 레벨 다른 xp 의 순위 역전 검증 추가 ⑶ 서버에 만렙 동점·xp clamp 단위 테스트 추가 ⑷ 곡선 고정 표 테스트(권고 3) | 테스트 (서버 + 클라이언트) | `spacetime_integration_test.dart:190`·`:197`·`:207`, `leaderboard.rs:213-237` | 통합 테스트는 실서버(maincloud)를 건드린다 — 생성한 캐릭터를 반드시 정리해야 한다(`cleanup`, `:182-184`). **`expect(row.rank, mine.rank)`(`:207`) 는 손대지 않는다** — 플레이크 주장·반증 양쪽 다 미확정이므로(§4 쟁점 3) 재현 자료 없이 단언을 무르지 않는다 | `cargo test`, `flutter test` |
| — | **전수 스캔 최적화는 하지 않는다.** 근거는 맞으나 재평가 비용을 아무도 실측하지 못했고, 현재 인구 규모에서는 근거 없는 최적화다 | — | §6 반증 항목 | 인구가 늘면 재검토 | 실측 후 판단 |

**적용 순서**: 권고 3 은 **기존 행 감사·정규화 → 서버 배포 → 클라이언트 변경** 순이어야 한다.
권고 2 는 권고 3 의 `ENDGAME_XP_CAP` 이 clamp 로 서 있어야 안전하게 의미를 갖는다.
권고 6 은 ⑴⑵⑶ 을 한 커밋으로 묶는다.

**되돌리기 어렵거나 외부에 영향을 주는 변경**: 권고 3 만 **maincloud 재배포**가 필요하다
(`spacetime publish withcenter-cyborg --server maincloud -p ./spacetimedb --yes`).
나머지 1·2·4·5·6·7 은 클라이언트 전용이라 재배포 없이 적용된다.

## 8. 미해결 · 사람 판단 필요

- **순위의 의미**(grok 의 프레이밍): "지금 몸체의 레벨" 인가 "역대 최고 도달" 인가. 권고 1 은
  전자를 택한 것이다 — 캐릭터 선택 화면이 이미 서버 레벨을 `Lv.N` 으로 보여주고
  (`character_select_screen.dart:258`), CLAUDE.md 가 단일 공유 월드 MMORPG 를 명시하므로 캐릭터
  성장이 지속되는 쪽이 장르 관례에 맞다고 판단했다. **다른 의도였다면 되돌려야 한다.**
- **만렙 타이브레이크 방식**: 권고 2 는 `xp` 의미를 만렙 구간에서 확장한다. **대안은 "만렙 도달
  시각" 타이브레이크**인데, `last_played_at` 은 `select_character`(`character.rs:121-124`)에서도
  갱신되므로 그 용도로 쓸 수 없다 — **열 추가 = 스키마 이주**가 따른다. 또 다른 대안은 별도
  `endgame_xp` 열이며 역시 이주가 필요하다. 세 선택지의 비용 차이가 결정의 핵심이다.
- **`ENDGAME_XP_CAP` 의 값**: 어떤 상한을 두든 치터는 그 상한까지 올릴 수 있다. 상한의 가치는
  `u64::MAX` 고착을 막고 정직한 플레이어가 언젠가 따라잡을 수 있게 하는 것이다. clamp 로
  구현하면 "정상 플레이로 도달 가능한 값"으로 잡아도 랭킹이 CAP 에서 정체될 뿐 보고가 끊기지는
  않는다 — 정체를 피하려면 정상 플레이로 닿기 어려운 크기로 잡아야 한다. 값은 판단이다.
- **레벨 복원 후의 웨이브 난이도**: 복원해도 `startGame()`(`action_rpg_game.dart:960-967`)은 항상
  웨이브 1부터다. 레벨 25 캐릭터에게 웨이브 1은 무의미하다. **이번 수정 범위 밖**이며 별도 기획
  결정이 필요하다.
- **계정당 캐릭터 4개가 모두 독립 순위에 오르는 것**(`character.rs:12`)이 의도인지. 코드는 전자로
  구현돼 있고 이번에 바꾸지 않는다. 동점 타이브레이크 규칙(생성 순)이 UI 어디에도 표시되지
  않는 것도 함께 판단 대상이다.
- **레벨 점프 차단**: xp 상한을 넣어도 조작 클라이언트가 레벨 1 → 30 을 한 번에 보내는 것은
  막지 못한다(`leaderboard.rs:175-177` 은 증가만 본다). 서버가 전투를 시뮬레이션하지 않는 한
  완전 차단은 불가능하며, 진행 속도 감사·비현실적 점프 격리 같은 완화책은 **실측 근거 없이는
  임계값을 정할 수 없어** 이번 범위에서 제외했다. 랭킹에 보상을 붙이려면 먼저 결정해야 한다.
- **상위 100 밖으로 밀려난 행의 delete 델타**: 서버가 델타를 보내지 않으면 클라이언트 캐시에
  유령 행이 남고, `spacetime_leaderboard.dart:82-83` 의 rank 정렬은 이를 감추지 못해 **순위가
  중복 표시**될 수 있다. claude·grok 이 독립적으로 짚었으나 둘 다, 나도 실측하지 못했다
  `[추측]`. **검증하려면 101명 이상 상황을 만들어야 한다** — 현재 인구로는 재현되지 않는다.
- **`my_rank` 와 `leaderboard` 의 클라이언트 캐시 일치**(§4 쟁점 3): 플레이크 주장과 SDK 동기
  적용 반증 양쪽 다 미확정 `[추측]`. `spacetimedb_sdk` 의 query-set 적용 경로를 열어 확인해야
  결론이 난다.
- **view 재평가 비용**: 넷 다 실측 못 했고 나도 못 했다. 인구가 세 자리를 넘으면 계측이 필요하다.
- **maincloud 의 현재 상태**: 만렙 인구도, 비정상 xp 유무도 **조회하지 않았다** `[미확인]`.
  권고 2 의 "지금이 가장 싼 시점" 논거와 권고 3 의 정규화 범위가 모두 이 조회에 달려 있다.
- **인용 줄 번호의 유효 기간**: 이 검토 중에도 `lib/game/entities/player.dart` 가 편집되어
  `gainXp` 의 위치가 이동하는 것을 직접 목격했다(같은 함수가 `:497` → `:560`). 표의 줄 번호는
  마지막 확인 시점 기준이며, **적용 시에는 함수명으로 다시 찾을 것.**
- **`.cowork/cowork-prompt.md` 가 낡았다**: `:25-41` 이 "이번 분석에서 시키려는 것" 으로 HP
  10,000·방어력·몬스터 레벨 재설계를 적고 `:34` 에서 "몬스터 레벨이라는 개념 자체가 없다"고
  단언하지만, `lib/game/systems/monster_codex.dart:241`·`:272` 와 `enemy.dart:833`
  (`'Lv.${species.level}'`)이 이미 몬스터 레벨을 구현하고 있다. **이전 과제 문구가 그대로 남은
  stale 상태**이며 이번 리더보드 분석의 전제를 오염시켰다(codex 가 이 충돌을 감지해 종합본
  폐기를 권했다 — 채택하지 않았다. 사용자 요청은 명시적으로 리더보드다). 다음 cowork 실행 전에
  `:25-41` 을 갱신해야 한다.

## 9. 적용 결과

> 적용: 2026-08-04 21:20 · 서버 배포 완료 · **커밋하지 않음**(사유는 아래 "커밋" 절)

### 선행 감사 (권고 3 의 차단 조건)

`spacetime sql withcenter-cyborg "SELECT level, xp FROM player_character"` 로 배포본을 조회했다.
**캐릭터 49 개가 전부 `level = 1, xp = 0`.** §8 이 `[미확인]` 으로 남긴 두 항목이 여기서 풀린다.

- **비정상 xp 없음** → 권고 3 의 "배포 전 정규화" 선행 조건이 **불필요**해졌다. clamp 만 넣으면 된다.
- **만렙 인구 0** → 권고 2 의 "지금이 가장 싼 시점" 논거가 **사실로 확인**됐다. 순위가 뒤집힐
  기존 만렙 캐릭터가 없다.

| 권고 | 적용 | 파일 | 검증 |
|---|---|---|---|
| 1 서버 레벨·xp 복원 | ✅ 적용 | `player.dart` `restoreProgress`·`_applyGains`, `action_rpg_game.dart` `_carriedLevel/_carriedXp`·`_spawnPlayer()`·`restart()`, `main.dart` `_createGame()` | `flutter analyze` error/warning 0. `test/player_progress_test.dart` 가 복원 레벨·누적 스탯·연출 미발동·범위 클램프를 검증 |
| 2 만렙 xp 누적 | ✅ 적용 | `player.dart` `gainXp` — 만렙 조기 반환과 `xp = 0` **둘 다** 제거(리뷰 교정 반영) | `test/player_progress_test.dart` 의 "만렙에 도달한 뒤에도 경험치가 계속 쌓인다" |
| 3 서버 xp clamp | ✅ 적용·**배포 완료** | `leaderboard.rs` `XP_TO_NEXT`(29 개 고정 표)·`ENDGAME_XP_CAP`·`clamp_xp`, `report_progress` 가 비교 **전에** clamp | `cargo test` 17/17. 실서버 통합 테스트: `level 4, xp 999999` → **108 저장**, `level 30, xp 9.2e18` → **10,000,000 저장** |
| 4 전송 신뢰성 | ✅ 적용 | `game_sync.dart` `reportLevel(level, xp)`·`flushProgress()`, `spacetime_game_sync.dart` `_pending` 이어보내기·시작값 초기화, `action_rpg_game.dart` `requestLogout()` 이 3 초 제한으로 flush 를 **await** | `flutter analyze` 0. `_rejected` 백오프는 리뷰 판단대로 **적용하지 않음** |
| 5 xp 막대 실제 진행도 | ✅ 적용 | `leaderboard_screen.dart` `_renderXpTick` — 분모를 `LevelSystem.xpToNext(row.level)` 로, 만렙은 `MAX` 표시로 분기 | `flutter analyze` 0 |
| 6 구독 누수 + 로딩 고착 | ✅ 적용(한 묶음) | `spacetime_leaderboard.dart` 세대 카운터, `leaderboard_screen.dart` `open()` 이 `attach()` Future 로 `_loading` 확정 + 8 초 타임아웃 + `_failed` 안내, `onRemove` 무조건 detach | `flutter analyze` 0 |
| 7 테스트 교정·보강 | ✅ 적용 | `spacetime_integration_test.dart` `xp 120 → 60`, clamp 2 건·동점 순위 1 건 추가. 신규 `test/level_system_curve_test.dart`(서버 표와 대조), `test/player_progress_test.dart` | 리더보드 통합 8/8 실서버 통과, 곡선 테스트 3/3 |
| — 전수 스캔 최적화 | ⏸️ 보류 | — | 재평가 비용 실측 근거가 없어 §6 판단대로 제외 |

### 검증 결과

- `cargo test` — **17/17 통과**(신규 4 건: 곡선 표 대조, 레벨 내 clamp, 만렙 clamp, 조작값 무력화)
- `flutter test test/spacetime_integration_test.dart --plain-name 리더보드` — **8/8 통과**(실제 maincloud)
- `flutter test test/level_system_curve_test.dart` — **3/3 통과**. 서버 `XP_TO_NEXT` 와 클라이언트
  `LevelSystem.xpToNext` 가 1~29 레벨 전부 일치함을 실측으로 확인했다(리뷰가 요구한 "자기 곡선끼리
  비교로는 부족하다" 를 고정 표 양쪽 검증으로 충족).
- `flutter analyze` — 내가 건드린 파일에 error/warning **0**.

### 사람 확인·후속 조치

- **maincloud 재배포 완료**(`spacetime publish`). 스키마 변경은 없고 reducer 로직만 바뀌었다.
  기존 49 개 행은 전부 유효 범위 안이라 clamp 의 영향을 받지 않는다.
- **§8 의 미해결 항목은 그대로 남는다** — 순위의 의미(지금 몸체 vs 역대 최고), 레벨 복원 후의
  웨이브 난이도, 계정당 캐릭터 4 개의 순위 취급, 레벨 점프 차단, 100 위 밖 delete 델타,
  view 재평가 비용. 이번 수정은 이 중 어느 것도 결정하지 않았다.
- **동시 편집 주의**: 적용 중에도 `enemy.dart`·`monster_codex.dart`·`action_rpg_game.dart` 가 다른
  작업(HP·몬스터 레벨 재설계)으로 계속 바뀌었다. `test/player_progress_test.dart` 는 `Player` →
  `ActionRpgGame` → `Enemy` 를 간접 의존하므로 그쪽이 컴파일되지 않는 순간에는 함께 실패한다.
  리더보드 코드 자체의 문제가 아니다.

### 권고에 없었지만 필요해진 변경

- `.claude/skills/cowork` **심볼릭 링크 생성** — `cowork.sh` 는 프로젝트 루트를 스킬 위치에서
  역산하는데, 플러그인 캐시에서 실행되어 `/Users/thruthesky/.claude/plugins/cache` 를 루트로 잡고
  거기에 `.cowork/` 를 만들고 있었다. 링크로 루트가 이 프로젝트로 잡히게 했다.
- `.cowork/cowork-prompt.md` 작성 — 초안 상태여서 4 AI 가 프로젝트 맥락 없이 분석할 뻔했다.
  (이 파일은 이후 다른 작업이 자기 주제로 덮어썼다. 이번 분석에는 리더보드 맥락이 주입된
  상태로 실행됐다 — `.prompt.md` 로 확인.)

### 커밋

**커밋하지 않았다.** 작업 트리에 다른 작업(HP·방어력·몬스터 레벨 재설계, 텔레포트, 자동 포션)의
**진행 중** 변경이 섞여 있고, 그 변경이 `action_rpg_game.dart`·`player.dart`·`world_menu.dart` 처럼
리더보드가 손댄 것과 **같은 파일**에 들어 있다. 파일 단위로는 분리되지 않으므로 지금 커밋하면
남의 미완성 작업이 함께 들어간다.

적용된 변경은 전부 작업 트리에 있고 검증도 끝났다. 커밋 시점과 범위는 두 작업의 상태를 아는
사람이 정하는 편이 맞다.

### 최종 검증 (2026-08-04 21:35)

| 검증 | 결과 |
|---|---|
| `cd spacetimedb && cargo test` | **26/26 통과** (리더보드 신규 4 건 포함) |
| `flutter analyze` | error·warning **0** |
| `flutter test` (전체) | **132/132 통과** — 실서버 리더보드 통합 8 건 포함 |
