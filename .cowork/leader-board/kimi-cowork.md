<!-- cowork:kimi | 2026-08-04 20:30:09 | exit=0 | 339s -->
# kimi 분석 — leader-board

> 요청: 순위 랭킹이 잘 되어져 있나요? 분석을 해서, 순위 랭킹이 올바로 동작하도록 수정/보완 해 주세요.
> 생성: 2026-08-04 20:30:09 · 소요 339s · 읽기 전용 분석(작업공간 미수정)

---

• 이어서 클라이언트 동기화·구독·레벨 시스템·통합 테스트를 읽는다.

• 통합 테스트와 캐릭터 모듈, 연결 클라이언트의 accessor 를 확인한다.

• 생성 코드와 플레이어 XP 처리 부분을 확인한다.

• 

## 1. 결론 요약

  순위 **산정 규칙 자체는 올바르다** — 서버 단일 계산(`leaderboard.rs:69-81`), 결정적 타이브레이크(레벨→xp→생성 순→id), 단조 증가 가드로 다중 기기 역전 방지, Rust 단위 테스트 4건과 실서버 통합 테스트 5건이 규칙을 잠그고 있다. 그러나 실제 MMORPG 조건에서 순위가 **틀리거나 죽어 버리는** 지점이 4곳 있다: ① 만렙(30) 도달 시 클라이언트가 xp 를 0 으로 리셋하고(`player.dart:509`) 동점 기준이 캐릭터 생성 시각이라, 만렙자끼리의 순위가 **생성 순으로 영구 고정** 된다. ② 서버가 xp 상한을 검사하지 않아 조작 클라이언트가 동 레벨 구간 1위를 영구 점유할 수 있다. ③ 구독 완료 전 화면을 닫으면 구독이 새는 경쟁 조건. ④ 레벨업 직후 실제 잔여 xp 대신 0 을 보고해 최대 5초간 동점 순위가 틀어진다.

  

## 2. 근거

  - `spacetimedb/src/leaderboard.rs:69-76` — 정렬 키: `Reverse(level) → Reverse(xp) → created_at(micros) → id`. 4단계 전부 결정적이며 테스트됨(`leaderboard.rs:213-237`).
  - `spacetimedb/src/leaderboard.rs:106-115` — `leaderboard` view: `level` 인덱스 전체 범위 스캔 후 정렬, 상위 100 에 1부터 매김.
  - `spacetimedb/src/leaderboard.rs:121-139` — `my_rank` view: "나보다 앞선 수 + 1". 같은 `rank_key` 를 쓰므로 두 view 의 순위 산정은 일치한다.
  - `spacetimedb/src/leaderboard.rs:169-184` — `report_progress`: 레벨 1~30 강제, `level < 기존 || (동레벨 && xp <= 기존)` 이면 무시. **xp 상한 검사 없음.**
  - `lib/game/entities/player.dart:504-509` — 레벨업 시 `xp -= xpToNextLevel`(잔여 이월), **만렙 도달 시 `xp = 0` 으로 버림**.
  - `lib/game/net/spacetime_game_sync.dart:59-65` — `reportLevel(level)` 은 **잔여 xp 를 버리고 무조건 `(level, 0)` 을 전송**.
  - `lib/spacetime/spacetime_leaderboard.dart:44-63` — `attach()` 가 `await` 중일 때 `close()` → `detach()` 는 `_querySetId == null` 이라 그냥 반환, 이후 await 완료로 구독이 걸린 채 남는다(누수).
  - `lib/spacetime/spacetime_leaderboard.dart:79-88` — 클라이언트는 순위를 재계산하지 않고 `rank` 로만 정렬. 서버 단일 진실 원칙 유지.
  - `lib/game/ui/leaderboard_screen.dart:488-491` — xp 막대는 같은 레벨 내 최댓값 대비 상대 표시. 순위와 무관한 장식이라 정합성 문제 없음.
  - `lib/game/systems/level_system.dart:30` — `maxLevel = 30`, 서버 `MAX_LEVEL`(`leaderboard.rs:30`)과 일치.
  - `test/spacetime_integration_test.dart:180-264` — 반영·역행 무시·상한 거절·미선택 거절·정렬 순서를 실서버에서 검증.
  - `lib/spacetime/generated/client.dart:97-129` — `leaderboard` / `my_rank` 캐시가 view 이름으로 분리돼 있어 같은 `LeaderboardEntry` 타입을 써도 충돌 없음.

  

## 3. 상세 분석

  ### 올바르게 돼 있는 부분 (서버·순위 산정)

  - **순위는 저장하지 않고 계산** 한다(`leaderboard.rs:3-6`). 캐릭터 삭제(`character.rs:150`)·레벨 변동 시 별도 순위 표와 어긋날 경로가 구조적으로 없다.
  - `leaderboard`(익명 view)와 `my_rank`(발신자 view)가 **같은 `rank_key` 함수**를 쓰므로 두 경로의 순위 정의가 갈라지지 않는다. `my_rank` 는 정렬 대신 카운트라 대용량에서도 한 번만 훑는다(`leaderboard.rs:119-120`).
  - 타이브레이크가 `created_at → id` 까지 내려가 완전 결정적이다. "아무 일도 없는데 목록이 요동치는" 문제는 없다.
  - 역행 보고 무시(`leaderboard.rs:173-177`)로 같은 계정 다중 기기의 늦은 패킷 역전을 막았고, 통합 테스트(`spacetime_integration_test.dart:205-220`)가 이를 실서버에서 확인한다.

  ### 문제 1 — 만렙 구간 순위가 영구 정체된다 (정합성·디자인 결함)

  `player.dart:509` 에서 만렙 도달 순간 xp 를 0 으로 버린다. 그러면 레벨 30 인 캐릭터는 전원 `level=30, xp=0` 이 되고, 순위는 타이브레이크인 **`created_at`(캐릭터 생성 시각)** 으로만 갈린다(`leaderboard.rs:73`). 즉:

  - 먼저 만렙을 찍어도, 나보다 일찍 **만들어진** 캐릭터가 만렙이 되는 순간 나는 영원히 아래로 밀린다.
  - 만렙 인구가 늘수록 상위권이 "계정 개설 순" 으로 고정된다. MMORPG 의 엔드게임 랭킹(가장 오래 경쟁이 유지돼야 할 구간)이 사실상 죽는다.
  - `my_rank` 와 `leaderboard` 양쪽에 동일하게 적용되므로 표시 불일치는 아니고, **규칙 자체가 플레이어에게 납득 불가** 한 문제다.

  경계: 서버 규칙(`rank_key`)과 클라이언트 규칙(`player.dart:509`)이 합작해 만든 문제라, 한쪽만 고쳐서는 안 된다. 서버가 xp 를 받아주어도 클라이언트가 0 을 보내면 그대로다.

  ### 문제 2 — xp 무제한 신고로 동 레벨 구간 1위 영구 점유 (보안)

  `report_progress` 는 레벨만 1~30 으로 강제하고 xp 는 어떤 `u64` 든 받는다(`leaderboard.rs:155-187`). 동점 타이브레이크가 xp 내림차순이므로, 조작 클라이언트가 `xp = u64::MAX` 를 한 번 보내면:

  - 그 레벨 구간(특히 만렙 30 구간)에서 **누구도 추월 불가능한 1위**가 된다.
  - 단조 가드(`xp <= 기존이면 무시`)가 오히려 이 값을 영구화한다 — 정직한 클라이언트의 후속 보고로는 절대 덮이지 않는다.

  프롬프트 지침 5 의 전제(레벨 자체는 클라이언트 신고를 수용) 위에서도, **xp 의 상한은 서버가 아는 정보로 막을 수 있는** 구간이다. `xpToNext` 곡선은 클라이언트에만 있지만(`level_system.dart:41-44`) 서버에 같은 곡선을 복제하거나, 최소한 "현재 레벨에서 도달 가능한 xp 상한" 상수로 클램프할 수 있다.

  ### 문제 3 — 구독 attach/detach 경쟁 조건 (클라이언트)

  `attach()` 가 `_subscribing = true` 로 두 번 걸리는 것은 막지만, **구독 await 중에 `detach()` 가 오면 아무것도 취소되지 않는다**(`spacetime_leaderboard.dart:44-63`). 화면을 빠르게 여닫으면 패널이 닫힌 뒤에도 리더보드 구독이 살아 있어, 누가 레벨업할 때마다 전체 순위표가 이 클라이언트에 계속 밀려온다. 다음에 열고 닫을 때까지 해제되지 않는다. `cyborg_connection.dart:34-38` 이 "보고 있을 때만 받는다" 는 설계 의도를 깨는 지점이다.

  ### 문제 4 — 레벨업 직후 잘못된 xp 보고 (클라이언트)

  `reportLevel` 은 실제 잔여 xp(`gainXp` 의 이월분, `player.dart:505`)를 무시하고 `(level, 0)` 을 보낸다(`spacetime_game_sync.dart:63-64`). 서버는 레벨이 올랐으니 받아들이고, 다음 `tick`(최대 5초)까지 순위표의 내 xp 는 0 이다. 동 레벨 동점 상황에서는 이 창에 순위가 실제보다 아래로 나온다. 자기 회복은 되지만, 레벨업 직후가 순위가 가장 많이 바뀌고 가장 많이 보는 순간이다.

  ### 문제 5 — 규모 확장 시 재계산 비용 (성능, [추측] 포함)

  - 모든 `report_progress`(접속자 전원, 5초 주기)가 `player_character` 갱신을 일으키고, 그때마다 `leaderboard` view 전체 스캔+정렬과 **구독자 각자의** `my_rank` 전체 스캔이 재계산된다(`leaderboard.rs:106-139`).
  - 익명 view 인 `leaderboard` 는 결과 공유가 가능하지만, `my_rank` 는 발신자별 계산이라 패널을 연 인원 × 전체 캐릭터 수 에 비례한다. 수천 명 규모에서 주된 비용 지점이 된다. 실제 SpacetimeDB 의 view 재계산 최적화 정도는 확인하지 못했다 → §6.

  ### 부차적 관찰

  - 통합 테스트 `spacetime_integration_test.dart:196-202` 는 `my_rank` 와 `leaderboard` 의 rank 가 같음을 단언하는데, 두 view 는 별도 계산이라 공용 월드에서 제3자의 레벨업이 끼면 순간 어긋날 수 있다 — 플레이크 가능성.
  - `LeaderboardEntry` 의 "빈 표" 트릭(`leaderboard.rs:38-43`)은 생성기 제약 회피용으로 의도된 것이며 정상.

  

## 4. 리스크 · 함정

  - **만렙 순위 정체(문제 1)는 되돌리기 어렵다.** 규칙을 나중에 바꾸면 이미 쌓인 "생성 순 고정" 구간의 순위가 하루아침에 뒤집혀 커뮤니티 반발을 부른다. 만렙 인구가 생기기 전에 고쳐야 한다.
  - xp 상한 클램프를 넣을 때, 서버 곡선이 클라이언트 `LevelSystem`(`level_system.dart:30-43`)과 어긋나면 정직한 플레이어의 정상 xp 가 잘린다. 두 곳이 함께 바뀌어야 하며 상수 이중 관리가 생긴다.
  - 단조 가드는 양날의 겁니다: 조작된 큰 xp 를 막는 장치가 없는 한 가드가 그 값을 영구 보존한다. 상한 클램프 없이는 가드가 오히려 치트를 돕는다.
  - `report_progress` 에 상승 속도 제한을 추가하는 안은 `last_played_at` 이 `select_character` 에서도 갱신되므로(`character.rs:121-124`) 그대로는 "마지막 레벨업 시각" 으로 쓸 수 없다 — 별도 열이 필요해 스키마 이주가 따른다.
  - attach/detach 수정 시 세대(generation) 카운터 방식이 아닌 임의 플래그로 어설프게 고치면, 정상적인 빠른 재열기에서 구독이 두 번 걸리거나 영구 해제되는 역방향 버그가 생기기 쉽다.
  - `flutter analyze` 0·`cargo test` 통과가 이 프로젝트의 검증 기준이므로, 어떤 수정도 그 게이트를 깨면 안 된다.

  

## 5. 권고안

  | 순위 | 권고 | 범위 | 근거 | 리스크 |
  |---|---|---|---|---|
  | 1 | 만렙에서도 xp 를 계속 쌓게 한다: `player.dart:509` 의 `xp = 0` 리셋 제거(또는 만렙 전용 누적 xp 유지), 서버는 만렙 구간 xp 상한을 별도 상수(예: 클라이언트 `xpToNext(29)` 수준 이상)로 클램프 | 서버 `leaderboard.rs` + 클라이언트 `player.dart` (양쪽 필수) | `player.dart:509`, `leaderboard.rs:73` | 기존 만렙 캐릭터의 순위가 바뀐다; 상수 이중 관리 |
  | 2 | `report_progress` 에 xp 상한 검사 추가: `LevelSystem.xpToNext` 곡선(`_baseXp 60`, `_curve 1.22`)을 서버에 복제해 `xp >= xp_to_next(level)` 이면 클램프하거나 거절 | 서버 `leaderboard.rs:155-187` | `leaderboard.rs:169-177`, `level_system.dart:41-44` | 곡선 변경 시 양쪽 동시 배포 필요 |
  | 3 | attach/detach 경쟁 해소: `attach()` 에 세대 카운터를 두고, await 완료 시점에 현재 세대와 다르면 즉시 `unsubscribe` | 클라이언트 `spacetime_leaderboard.dart:44-63` | `spacetime_leaderboard.dart:44-63` | 잘못 구현하면 재열기 시 구독 유실 |
  | 4 | `reportLevel` 이 잔여 xp 를 함께 보내도록: `onLevelUp` 호출 시점의 `player.xp` 를 전달하거나 `reportLevel(int level, int xp)` 로 시그니처 확장(`GameSync` 인터페이스 포함) | 클라이언트 `spacetime_game_sync.dart:59-65`, `game_sync.dart:27`, `action_rpg_game.dart:896` | `spacetime_game_sync.dart:63-64`, `player.dart:505` | 인터페이스 변경으로 `OfflineGameSync` 등 구현체 동시 수정 필요 |
  | 5 | 통합 테스트의 rank 일치 단언(`spacetime_integration_test.dart:199-202`)을 "같다" 대신 "수렴한다" 로 완화하거나 단독 네임스페이스에서만 검증 | 테스트 | `spacetime_integration_test.dart:196-202` | 검증 강도가 약간 낮아짐 |
  | 6 | 규모 확장 전 `my_rank` 재계산 비용을 실측(구독자 수 × 캐릭터 수). 필요하면 주기 스냅숏 등 서버 측 완충 검토 — 단, 현재 "순위는 저장하지 않는다" 원칙(`leaderboard.rs:3-6`)과 충돌하므로 실측 후 판단 | 서버 | `leaderboard.rs:121-139` | 성급한 캐시 도입은 정합성 원칙을 깬다 |

  

## 6. 불확실 · 미확인

  - SpacetimeDB 2.7 의 view 재계산 전략(증분 평가 여부, 익명 view 결과 공유 범위)을 실제로 확인하지 못했다 — 문제 5 의 비용 추정은 코드 구조 기반 [추측]이다. 대규모 부하 실측이 필요하다.
  - 수정 작업 자체는 이번 세션의 읽기 전용 규칙상 수행하지 않았다. `cargo test` · `flutter analyze` · 통합 테스트 통과 여부는 현재 코드 기준으로만 테스트 파일을 읽어 확인했고 직접 실행하지 않았다.
  - 만렙 도달 시각을 순위에 쓰려면 `PlayerCharacter` 에 열 추가가 필요한데, maincloud 배포본의 스키마 이주 정책(기존 행 기본값 처리)은 확인하지 못했다.
  - 클라이언트가 만렙에서 xp 를 버리는 것이 의도된 디자인("만렙 = 끝")인지 확인이 필요하다. 의도라면 권고 1 대신 "만렙 도달 시각(`last_played_at` 계열)으로 타이브레이크" 가 대안이 된다 — 기획 판단 영역이다.
