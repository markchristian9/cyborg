<!-- cowork:claude | 2026-08-04 20:35:24 | exit=0 | 654s -->
# claude 분석 — leader-board

> 요청: 순위 랭킹이 잘 되어져 있나요? 분석을 해서, 순위 랭킹이 올바로 동작하도록 수정/보완 해 주세요.
> 생성: 2026-08-04 20:35:24 · 소요 654s · 읽기 전용 분석(작업공간 미수정)

---



## 1. 결론 요약

순위 **산정 규칙 자체는 서버에서 올바르게 구현되어 있다** — `rank_key` 가 레벨↓ → xp↓ → 생성시각↑ → id↑ 로 동점을 완전히 가르고, `leaderboard` view 의 `enumerate` 순위와 `my_rank` 의 "앞선 수 + 1" 은 같은 키를 쓰므로 같은 값을 낸다. 깨져 있는 것은 **그 규칙에 들어가는 입력값**이다. 게임이 서버에 저장된 레벨을 복원하지 않아 재접속하면 화면 레벨은 1로 돌아가는데 서버 값은 그대로 남고, 서버가 뒤로 가는 보고를 버리므로 **새 접속에서 아무리 사냥해도 이전 최고 레벨을 넘기 전까지 순위가 전혀 움직이지 않는다.** 이것이 "순위가 제대로 안 된다"의 실체다. 그 외에 xp 막대가 내 줄에서 항상 꽉 차는 표시 오류, 구독 누수 경합, 한 번 거절되면 영영 멈추는 보고, MMORPG 규모에서의 view 재평가 비용이 실재한다.

## 2. 근거

- `spacetimedb/src/leaderboard.rs:69-81` — `rank_key` = `(Reverse(level), Reverse(xp), created_at, id)`. 네 단계로 갈라 동점에서도 순서가 흔들리지 않는다. `outranks` 가 같은 키를 쓴다.
- `spacetimedb/src/leaderboard.rs:106-115` vs `:122-139` — `leaderboard` 는 정렬 후 `enumerate` 로 1..100, `my_rank` 는 `outranks` 로 센 `ahead + 1`. **같은 키를 쓰므로 두 값은 일치한다.** 자기 자신은 `rank_key(me) < rank_key(me)` 가 false 라 세지 않는다.
- `spacetimedb/src/leaderboard.rs:175-177` — `level < character.level || (level == character.level && xp <= character.xp)` 이면 조용히 무시. 레벨은 **절대 내려가지 않는다**.
- `lib/game/entities/player.dart:32-33` — `int level = 1; int xp = 0;` 하드코딩. 서버 값을 받는 경로가 없다.
- `lib/game/action_rpg_game.dart:175`, `:1017` — `onLoad()` 와 `restart()` 모두 `player = Player(grid: map.respawnPoint())` 로 항상 레벨 1 신규 생성.
- `lib/main.dart:70` — `..characterName = widget.character?.name.toUpperCase()`. `PlayerCharacter` 를 받아 놓고 **이름만** 쓴다. `lib/spacetime/generated/player_character.dart:38-40` 에 `level`·`xp` 가 있고, `lib/auth/cyborg_gate.dart:45-50` 이 그 객체를 통째로 넘긴다 — 배선 한 줄이 빠진 상태다.
- `lib/game/ui/leaderboard_screen.dart:488-491` — `peak` 을 `_rows` 안 같은 레벨의 최대 xp 로 잡는다. 초기값 1. 내가 100위 밖이면 내 레벨 그룹이 `_rows` 에 없어 `peak = 1` → `ratio = clamp(xp/1) = 1.0` → **YOU 줄 막대가 항상 꽉 찬다.**
- `lib/game/systems/level_system.dart:41-44` — `LevelSystem.xpToNext(level)` 이 존재한다. 위 주석(`leaderboard_screen.dart:486-487`)이 "클라이언트만 안다"고 한 그 값을 이 코드가 이미 갖고 있다.
- `lib/spacetime/spacetime_leaderboard.dart:44-63` — `attach()` 의 `await` 중 `detach()` 가 오면 `_querySetId` 가 아직 null 이라 no-op 이고, 이후 구독이 설정되어 **남는다**. `lib/spacetime/cyborg_connection.dart:34-38` 이 명시한 "보고 있지 않으면 받지 않는다" 설계가 깨진다.
- `lib/game/net/spacetime_game_sync.dart:43`, `:87-90` — `_rejected` 는 영구 플래그. 재연결 중 세션이 비면 `require_session`(`spacetimedb/src/lib.rs:156-162`)이 실패해 거절되고, 그 게임 화면 내내 보고가 멈춘다.
- `lib/game/net/spacetime_game_sync.dart:79` — `_inFlight` 이면 그냥 반환. 레벨업 즉시 보고(`:59-65`)와 로그아웃 직전 마지막 보고(`:68-76`)가 주기 전송과 겹치면 유실되고, 로그아웃 뒤엔 따라잡을 tick 이 없다.
- `lib/game/ui/leaderboard_screen.dart:130`, `:159-162` — `_loading` 은 캐시 알림으로만 풀린다. 구독 실패나 빈 결과로 알림이 오지 않으면 "순위를 불러오는 중"이 영구히 남는다. `LeaderboardSource.attach()`(`lib/game/net/leaderboard_source.dart:46`)는 이미 `Future` 를 반환하는데 쓰이지 않는다.
- `lib/spacetime/generated/client.dart:97-101`, `:120-129`, `:187-202` — `leaderboard` 와 `my_rank` 는 이름이 다른 별도 캐시로 등록된다. 같은 `LeaderboardEntry` 타입이지만 **섞이지 않는다** (`.pub-cache/.../client_cache.dart:62-78` 이 이름 기준 단일 인스턴스를 보장).
- `.pub-cache/hosted/pub.dev/spacetimedb_sdk-2.4.0/lib/src/cache/table_cache.dart:701-706` — `rows.value` 에 매번 새 `List` 를 할당하므로 값이 같아도 알림이 간다. 반대로 `_refreshRowsNotifier()` 가 아예 호출되지 않는 경로(빈 결과)에서는 알림이 없다.
- `spacetimedb/src/leaderboard.rs:213-237` / `test/spacetime_integration_test.dart:249-260` — 서버 테스트는 `rank_key` 정렬만, 통합 테스트는 레벨 내림차순만 본다. **`leaderboard` 의 rank 와 `my_rank` 의 rank 가 같은 값을 낸다는 것은 어디서도 검증하지 않는다.**
- `lib/game/entities/player.dart:509` — 만렙 도달 시 `xp = 0`. 30레벨끼리는 전원 xp=0 이라 순위가 `created_at` 순 = **사실상 가입 순서**가 된다.

## 3. 상세 분석

### 서버 계층 — 규칙은 맞다

`leaderboard.rs` 의 설계 판단(순위를 저장하지 않고 매번 계산)은 타당하고, 표 이원화로 인한 정합성 붕괴를 구조적으로 없앤다. `LeaderboardEntry` 를 별도 값으로 만들어 `account_id` 가 새어 나갈 수 없게 한 것도 `lib.rs:15-16` 의 원칙 3을 지킨다. `report_progress` 는 `ctx.sender()` 로 세션을 도출하고 `account_id` 를 인자로 받지 않는다(원칙 1). 상한(30)과 단조 증가로 명백히 불가능한 값을 막는다. **순위 계산 로직에서 고칠 것은 없다.**

### 클라이언트 계층 — 입력값이 끊겨 있다

문제는 계층 경계에 있다. 서버는 "캐릭터의 레벨"을 영속 상태로 들고 있는데, 클라이언트 게임 루프는 그것을 **읽지 않는다**. `Player` 는 매번 레벨 1로 태어나고(`player.dart:32-33`), `SpacetimeGameSync` 는 그 값을 서버로 밀어 올리려 하지만 서버의 단조 증가 규칙에 막힌다.

구체적 진행:

1. 캐릭터가 서버에 레벨 12로 저장돼 있다.
2. 재접속 → `Player` 레벨 1 → HUD·캐릭터 화면은 "1".
3. 리더보드를 연다 → `my_rank` 는 서버 값 "12". **두 화면이 다른 숫자를 보여준다.**
4. 사냥해서 레벨 2, 3, … 11 → 매번 `report_progress` 가 가지만 `level < character.level` 로 전부 무시. **순위표가 미동도 하지 않는다.**
5. 레벨 13이 되어서야 처음으로 순위가 움직인다.

`restart()`("새 월드로 재접속")도 같은 경로라 성장이 통째로 리셋된다. 단일 공유 월드 MMORPG 전제에서 이건 리더보드 문제 이전에 캐릭터 지속성 문제다.

### 표시 계층 — xp 막대가 거짓말을 한다

`_renderXpTick` 은 "같은 레벨끼리 누가 앞섰는가"를 상대적으로 보여주려 하지만, 참조 집합(`_rows`)이 상위 100위로 잘려 있다는 사실을 계산에 넣지 않았다. `_renderMyRank` 가 같은 함수를 부르므로(`leaderboard_screen.dart:560-569`), 하위권 플레이어일수록 자기 막대가 꽉 찬 것을 본다. 순위는 아래인데 진행 막대는 최대치 — 사용자가 순위 근거를 오해하는 방향으로 정확히 틀렸다. 게다가 정확한 분모(`LevelSystem.xpToNext`)가 같은 앱 안에 이미 있다.

### 부하 — MMORPG 규모에서 무너지는 지점

`leaderboard` view 는 평가마다 전체를 `collect()` 후 `sort` = O(N log N) + O(N) 메모리. `my_rank` 는 **구독자마다** O(N) 전체 스캔. 보고 주기는 플레이어당 5초(`spacetime_game_sync.dart:22`)라 트랜잭션 수가 접속자 수에 비례하고, 각 트랜잭션이 `player_character` 를 건드려 두 view 를 모두 재평가시킨다. N=1000·리더보드 구독자 100명이면 초당 200 트랜잭션 × (1000 log 1000 + 100×1000) 규모다. "혼자서는 괜찮다"가 통하지 않는 전형적 지점이다.

다만 근본 대책(상위 100 materialized 표)은 `leaderboard.rs:3-6` 이 명시적으로 거부한 방향이라 사람 판단 없이 뒤집을 사안이 아니다. 보고 빈도를 줄이는 쪽이 같은 원칙 안에서 가능한 완화다.

### 범위 경계

- **서버만 고쳐서 되는 것**: 없다. 순위 규칙은 이미 맞다.
- **클라이언트만 고쳐서 되는 것**: P0-A(레벨 복원), P0-B/C(보고 안정화), P1-A(xp 막대), P1-B(구독 누수), P1-C(로딩 상태), P1-D(정원 표시), P2-B(보고 빈도) — **거의 전부.**
- **양쪽을 함께 고쳐야 하는 것**: P2-A(검증 테스트). 서버에 순수 함수를 뽑고 통합 테스트를 보강한다.
- **사람이 결정해야 하는 것**: 만렙 동점 규칙, 계정당 다중 캐릭터의 순위 취급.

## 4. 리스크 · 함정

- **레벨 복원 시 연출 폭발.** `Player._levelUp()`(`player.dart:512-537`)은 `spawnEffect`·`GameAudio.play`·`game.onLevelUp` 을 부른다. 복원용으로 이걸 N번 돌리면 접속하자마자 레벨업 배너가 N번 뜨고 `sync.reportLevel` 이 되돌아 호출된다. **스탯 적용만 하는 별도 경로가 반드시 필요하다.**
- **레벨 복원은 되돌리기 어려운 밸런스 변경이다.** 레벨 25 캐릭터가 웨이브 1부터 시작하게 된다(`action_rpg_game.dart:963`). 리더보드 정합성은 회복되지만 초반 난이도가 무의미해진다. 웨이브 시작점을 레벨에 맞출지는 별도 기획 판단이다.
- **`restart()` 에서 성장을 유지하기로 하면** "새 월드로 재접속"의 의미가 바뀐다. MMORPG 전제상 유지가 맞다고 보지만, 현재 UI 문구(`main.dart:268`)와 어긋날 수 있다.
- **`_sentLevel` 초기화를 잊으면** 접속자 전원이 접속 직후 이미 서버가 아는 값을 한 번씩 다시 보낸다. 부하 완화와 정반대로 간다.
- **만렙 xp=0 문제는 복원을 넣어도 남는다.** 오히려 만렙 인구가 쌓일수록 드러난다.
- **통합 테스트는 실서버(maincloud)를 건드린다.** `test/spacetime_integration_test.dart:24-26` 이 매번 새 계정을 만드므로, 순위 테스트를 늘리면 실서버 리더보드에 테스트 캐릭터가 섞인다. `cleanup` 이 지우지만 실패 시 잔재가 남는다.
- **`leaderboard` view 는 익명 구독 가능**(`leaderboard.rs:105`)이라 로그인 없이도 이름·레벨·`character_id` 가 보인다. 리더보드로서는 의도된 공개이고 `select_character`·`delete_character` 가 소유자를 검사하므로(`character.rs:117`, `:146`) 악용 경로는 없다. 다만 공개 범위라는 사실은 인지하고 있어야 한다.

## 5. 권고안

| 순위 | 권고 | 범위 | 근거 | 리스크 |
|---|---|---|---|---|
| 1 | **서버 레벨·xp 를 게임 시작 시 복원한다.** `Player` 에 연출 없이 스탯만 맞추는 `restoreProgress(level, xp)` 를 추가(`_levelUp` 의 스탯 부분을 `_applyGains` 로 추출해 공유), `ActionRpgGame` 에 `startLevel`/`startXp` 필드를 두고 `onLoad()`·`restart()` 의 `Player` 생성 직후 호출, `main.dart` 에서 `widget.character` 의 값을 넘긴다 | 클라이언트 전용 | `player.dart:32-33`, `action_rpg_game.dart:175`·`:1017`, `main.dart:70`, `leaderboard.rs:175-177` | 초반 난이도 무의미화, 연출 오발동(별도 경로로 회피) |
| 2 | **`SpacetimeGameSync` 생성자에 시작 레벨·xp 를 받아 `_sentLevel`/`_sentXp` 를 초기화한다.** 접속 직후 중복 보고를 없앤다 | 클라이언트 전용 | `spacetime_game_sync.dart:35-36`, `:80` | 없음 (1번과 함께 해야 의미) |
| 3 | **보고 유실·영구 중단을 없앤다.** `_rejected` 영구 플래그를 백오프(30초, 연속 5회 후 포기)로 바꾸고, `_inFlight` 중 들어온 최신 값을 `_pending` 에 잡아 `finally` 에서 이어 보낸다 | 클라이언트 전용 | `spacetime_game_sync.dart:43`·`:79`·`:87-90`, `lib.rs:156-162` | 재시도 루프가 서버 로그를 늘릴 수 있어 상한 필요 |
| 4 | **xp 막대를 `LevelSystem.xpToNext(row.level)` 기준 실제 진행도로 바꾼다.** 만렙은 막대 대신 `MAX` 표시로 분기 | 클라이언트 전용 | `leaderboard_screen.dart:485-507`, `level_system.dart:41-44` | 만렙 분기를 빠뜨리면 항상 0으로 보인다 |
| 5 | **`attach()`/`detach()` 경합을 막는다.** `_detachRequested` 플래그를 두고 `attach()` 의 `finally` 에서 요청이 있었으면 즉시 `unsubscribe` | 클라이언트 전용 | `spacetime_leaderboard.dart:44-63`, `cyborg_connection.dart:34-38` | 없음 |
| 6 | **로딩 상태를 `attach()` 완료로 확정한다.** `open()` 에서 `attach()` 의 Future 완료 시 `_loading = false`, 세대 카운터로 늦게 온 완료를 무시 | 클라이언트 전용 | `leaderboard_screen.dart:130`·`:159-162`, `leaderboard_source.dart:46` | 닫은 뒤 도착한 완료가 상태를 뒤집지 않도록 가드 필수 |
| 7 | **순위 규칙 검증 테스트를 넣는다.** 서버에 `rank_among(me, others)` 순수 함수를 뽑아 view 와 테스트가 공유, "정렬 인덱스 == `rank_among`"·"101명일 때 101위"·"동점 무리에서 rank 미중복"을 검증. 통합 테스트에 rank 연속성·같은 레벨 xp 내림차순·`my_rank`↔`leaderboard` rank 일치를 추가 | 서버 + 테스트 | `leaderboard.rs:213-237`, `spacetime_integration_test.dart:249-260` | 실서버에 테스트 캐릭터 잔재 |
| 8 | **보고 빈도를 낮춘다.** 주기 5초 → 15초, 값이 실제로 바뀐 경우에만, 같은 레벨 안에서는 진행도가 10% 이상 움직였을 때만. 레벨업은 지금처럼 즉시 | 클라이언트 전용 | `spacetime_game_sync.dart:22`, `leaderboard.rs:106-115`·`:122-139` | 리더보드 xp 반영이 최대 15초 늦어진다 |
| 9 | **"상위 100위"를 화면에 적는다.** `LeaderboardSource` 에 `capacity` 를 두고 헤더 힌트에 표시. 서버 `LEADERBOARD_SIZE` 와 함께 바뀌는 값이라는 주석을 `MAX_LEVEL` 관례대로 단다 | 클라이언트 전용 | `leaderboard_screen.dart:313-318`, `leaderboard.rs:24`·`:26-30` | 서버 상수와 어긋나면 거짓 표시 |
| 10 | **만렙 동점 규칙과 계정당 캐릭터 수 취급을 결정받는다.** 코드는 건드리지 않고 선택지만 제시 | 기획 판단 | `player.dart:509`, `character.rs:12` | 결정 없이 진행하면 되돌리기 어렵다 |

권고 1~6, 8~9 는 **서버 재배포 없이** 적용 가능하다. 7만 서버 변경(순수 함수 추출)이 필요하며, 순위 규칙 자체는 바뀌지 않는다.

## 6. 불확실 · 미확인

- **SpacetimeDB 2.7 이 view 를 언제 재평가하는지 실측하지 못했다.** `player_character` 를 건드리는 모든 트랜잭션이 두 view 를 재평가한다고 가정했으나(`filter(0u32..)` 가 전체 범위이므로), 엔진이 의존성을 더 좁게 추적할 가능성이 있다. §3 의 부하 추정은 이 가정 위에 있다 — 권고 8 을 적용하기 전에 실제 계측이 낫다. `[추측]`
- **100위 밖으로 밀려난 행에 서버가 delete 를 보내는지** 확인하지 못했다. 보내지 않으면 클라이언트 캐시에 유령 행이 남아 순위가 중복되어 보인다. `spacetime_leaderboard.dart:82-83` 의 rank 정렬은 이를 감추지 못한다. 101명 이상 상황을 실제로 만들어 확인해야 한다. `[추측]`
- **캐릭터가 0개인 DB 에서 리더보드를 열었을 때** `_refreshRowsNotifier()` 가 호출되지 않아 "불러오는 중"에 갇히는지 실측하지 못했다. `SubscriptionManager._tablesToApply` 의 빈 테이블 처리를 읽지 않았다. 권고 6 은 이 경로와 무관하게 안전하다.
- **레벨을 복원했을 때 웨이브 난이도를 어떻게 맞출지**는 기획 결정이다. 현재 `startGame()`(`action_rpg_game.dart:963`)은 항상 웨이브 1부터다.
- **`test/spacetime_integration_test.dart` 의 `prepare`/`cleanup`/`pumpUntil` 구현**(1~100줄 밖)을 읽지 않았다. 권고 7 의 테스트 추가 시 기존 헬퍼 재사용 가능 여부를 먼저 확인해야 한다.
- **성능 수치는 계측이 아니라 코드 구조에서 추정한 것**이다. 실제 maincloud 에서 동시 접속 100명 규모의 측정치가 없다.
