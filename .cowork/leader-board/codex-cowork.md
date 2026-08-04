<!-- cowork:codex | 2026-08-04 20:29:49 | exit=0 | 319s -->
# codex 분석 — leader-board

> 요청: 순위 랭킹이 잘 되어져 있나요? 분석을 해서, 순위 랭킹이 올바로 동작하도록 수정/보완 해 주세요.
> 생성: 2026-08-04 20:29:49 · 소요 319s · 읽기 전용 분석(작업공간 미수정)

---



## 1. 결론 요약

현재 구현은 **정렬과 기본 전파는 맞지만, MMORPG 운영용 랭킹으로는 보완이 필수**다. 서버의 `level → xp → created_at → id` 정렬과 `my_rank` 계산은 서로 일치한다(`spacetimedb/src/leaderboard.rs:65-80`, `spacetimedb/src/leaderboard.rs:105-139`).  
그러나 서버가 레벨별 `xp` 상한과 성장 속도를 검사하지 않아 조작 클라이언트가 즉시 30레벨·비정상 `xp`로 상위권을 점유할 수 있다(`spacetimedb/src/leaderboard.rs:145-186`).  
또한 저장된 캐릭터의 `level`·`xp`를 게임 시작 시 복원하지 않아, 재접속 후 실제 플레이 상태와 서버 순위가 달라진다(`lib/main.dart:64-70`, `lib/game/action_rpg_game.dart:168-176`).  
전송 중 갱신 유실, 구독 해제 경쟁 조건, 전체 스캔 방식의 확장성도 수정하고 다중 클라이언트 테스트로 검증해야 한다(`lib/game/net/spacetime_game_sync.dart:78-95`, `lib/spacetime/spacetime_leaderboard.dart:44-63`).

## 2. 근거

- `spacetimedb/src/lib.rs:89-115` — `PlayerCharacter`에 `level` B-tree 인덱스와 `xp`, 생성·마지막 플레이 시각이 저장된다.
- `spacetimedb/src/leaderboard.rs:65-80` — 순서는 레벨 내림차순, `xp` 내림차순, 생성 시각, `id` 순이다.
- `spacetimedb/src/leaderboard.rs:105-139` — 상위 100명은 전체 정렬 후 산출하고, `my_rank`는 앞선 캐릭터 수에 1을 더한다.
- `spacetimedb/src/leaderboard.rs:43-62` — view 반환 타입용 비공개 `LeaderboardEntry`와 캐시 식별용 `character_id` 기본 키가 정의돼 있다.
- `spacetimedb/src/leaderboard.rs:143-186` — `report_progress`는 레벨 범위와 역행만 막고, `xp` 범위나 레벨 상승 속도는 검사하지 않는다.
- `lib/game/systems/level_system.dart:30-44` — 최대 레벨은 30이며 레벨별 다음 레벨 요구 경험치가 정의돼 있다.
- `lib/game/entities/player.dart:486-520` — `xp`는 레벨업 때 요구량을 차감하는 현재 레벨 내 진행도이고, 만렙에서는 0이 된다.
- `lib/main.dart:47-70` — 선택된 `PlayerCharacter`를 받지만 게임에는 이름만 전달하고 `level`·`xp`는 전달하지 않는다.
- `lib/game/action_rpg_game.dart:168-176` 및 `lib/game/action_rpg_game.dart:1001-1018` — 최초 진입과 재시작 모두 기본값의 `Player`를 새로 만든다.
- `lib/game/net/spacetime_game_sync.dart:17-95` — 5초 간격으로 보내지만 요청 중이면 새로운 상태를 저장하지 않고 즉시 버린다.
- `lib/spacetime/cyborg_connection.dart:28-42` — 기본 view와 리더보드의 `leaderboard`·`my_rank` view를 각각 명시적으로 구독한다.
- `lib/spacetime/spacetime_leaderboard.dart:44-87` — 화면 진입 시 두 view를 구독하고, 캐시 순서를 신뢰하지 않고 `rank`로 다시 정렬한다.
- `lib/game/ui/leaderboard_screen.dart:400-507` — 레벨과 상대적 `xp` 막대는 표시하지만 정확한 `xp`와 생성 시각 동점 규칙은 표시하지 않는다.
- `test/spacetime_integration_test.dart:180-264` — 진행도 반영·역행·레벨 범위·미선택·레벨 정렬만 검사하며 다중 클라이언트 경쟁 조건은 다루지 않는다.
- `spacetimedb/src/leaderboard.rs:213-237` — 서버 단위 테스트는 네 가지 정렬 규칙만 검증한다.

## 3. 상세 분석

**순위 산정**

`rank_key`와 `outranks`가 같은 비교 기준을 사용하므로, 상위 100 목록과 `my_rank`의 순위 계산은 논리적으로 일치한다. 상위 목록은 정렬된 결과에 `1..N`을 부여하므로 동점이어도 `rank`가 겹치지 않는다(`spacetimedb/src/leaderboard.rs:65-91`, `spacetimedb/src/leaderboard.rs:105-139`).

`created_at`까지 같을 때 `id`를 쓰는 것은 순서를 안정시키는 용도로는 적절하다. 다만 auto-inc 값은 연속성을 보장하지 않으므로 `id`는 생성 순서의 증명이라기보다 최종 결정적 타이브레이커로만 해석해야 한다(`.cowork/cowork-prompt.md:57-62`, `spacetimedb/src/leaderboard.rs:69-75`).

**서버 권위와 조작 가능성**

`report_progress`는 호출자의 세션에서 선택 캐릭터를 찾기 때문에 다른 계정의 `account_id`를 직접 지정할 수 없다. 또한 낮은 `(level, xp)` 보고를 무시하므로 여러 기기에서 오래된 보고가 최신 기록을 덮는 문제는 방지한다(`spacetimedb/src/leaderboard.rs:155-184`, `spacetimedb/src/lib.rs:152-162`).

반면 유효한 `xp` 범위가 없다. 클라이언트 규칙상 4레벨 요구량은 `round(60 × 1.22³) = 109`인데, 통합 테스트는 `level=4, xp=120`을 정상 상태로 보고하고 서버가 이를 수용하기를 기대한다(`lib/game/systems/level_system.dart:30-44`, `test/spacetime_integration_test.dart:180-192`). 조작 클라이언트는 30레벨과 매우 큰 `xp`를 한 번에 신고할 수 있고, `xp` 내림차순 정렬 때문에 만렙 동점자 중 영구적으로 앞설 수 있다. 이후 정상값으로 되돌리는 보고도 역행 검사에 의해 무시된다(`spacetimedb/src/leaderboard.rs:65-75`, `spacetimedb/src/leaderboard.rs:169-184`).

서버가 전투를 시뮬레이션하지 않는 현재 단계에서는 조작을 완전히 제거할 수 없다. 그래도 레벨별 `xp` 범위, 만렙 `xp=0`, 서버 시각 대비 비현실적인 누적 성장량 같은 구조적·시간적 이상은 서버에서 막거나 기록할 수 있다(`spacetimedb/src/leaderboard.rs:143-153`, `spacetimedb/src/lib.rs:17-18`).

**게임 상태와 서버 순위 불일치**

선택 화면에서 전달되는 `PlayerCharacter`에는 `level`과 `xp`가 있지만, `GameScreen`은 이름만 `ActionRpgGame`에 전달한다(`lib/main.dart:47-70`, `lib/spacetime/generated/player_character.dart:38-44`). 게임의 `Player`는 항상 1레벨·0 `xp`로 시작하고 재시작 때도 다시 기본값으로 생성된다(`lib/game/entities/player.dart:24-34`, `lib/game/action_rpg_game.dart:1001-1018`).

따라서 서버에 6레벨·50 `xp`가 저장된 캐릭터도 재접속하면 로컬에서는 1레벨로 보인다. 로컬의 낮은 보고는 서버가 무시하므로 랭킹에는 과거 6레벨이 계속 표시되고, 플레이 화면과 순위표가 서로 다른 캐릭터 상태를 보여 준다(`spacetimedb/src/leaderboard.rs:173-184`). 이는 단순 표시 문제가 아니라 성장 스탯·전투력·순위가 서로 분리되는 계층 간 정합성 결함이다.

**갱신 전송과 구독 경쟁 조건**

`SpacetimeGameSync._send`는 `_inFlight`인 동안 들어온 레벨업이나 최신 `xp`를 대기열에 남기지 않는다. 다음 5초 주기까지 플레이가 계속되면 복구되지만, 그 전에 일시정지·종료·연결 해제가 발생하면 최신 상태가 전송되지 않는다(`lib/game/net/spacetime_game_sync.dart:17-22`, `lib/game/net/spacetime_game_sync.dart:78-95`, `lib/game/action_rpg_game.dart:311-334`).

구독도 빠른 열기·닫기 경쟁 조건이 있다. `attach`는 `await subscribe`가 끝난 뒤에야 `_querySetId`를 기록하지만, 그 전에 `detach`하면 `id == null`이라 아무 작업도 하지 않는다. 이후 구독이 완료되면 닫힌 화면에 활성 구독이 남는다(`lib/spacetime/spacetime_leaderboard.dart:44-63`). 화면 제거 시에도 `_open`이 false면 다시 해제하지 않아 누수가 유지될 수 있다(`lib/game/ui/leaderboard_screen.dart:125-156`).

**MMORPG 확장성**

`leaderboard`는 실행할 때마다 모든 캐릭터를 수집해 `O(N log N)` 정렬하고, `my_rank`도 모든 캐릭터를 훑는 `O(N)` 계산이다(`spacetimedb/src/leaderboard.rs:101-114`, `spacetimedb/src/leaderboard.rs:119-138`). 동시에 성장하는 플레이어가 많으면 각 플레이어가 최대 5초마다 갱신하므로 view 재평가와 전파 부담이 빠르게 커진다(`lib/game/net/spacetime_game_sync.dart:17-22`, `lib/spacetime/cyborg_connection.dart:34-42`).

`level` 인덱스와 최대 30레벨이라는 제한을 활용하면 상위 레벨 버킷부터 조회하고 100명을 채운 시점에 중단할 수 있다. `my_rank`도 자신보다 높은 레벨 범위와 동일 레벨 동점자만 검사할 수 있어, 현재의 전체 하한 없는 스캔보다 범위를 줄일 수 있다(`spacetimedb/src/lib.rs:105-111`, `spacetimedb/src/leaderboard.rs:26-30`).

## 4. 리스크 · 함정

- 서버 검증을 추가하면 현재 통합 테스트의 `level=4, xp=120`이 즉시 실패한다. 테스트 데이터와 배포 서버의 기존 비정상 진행도를 함께 정리해야 한다(`test/spacetime_integration_test.dart:180-192`, `lib/game/systems/level_system.dart:40-44`).
- `[추측]` maincloud에 이미 범위를 벗어난 `xp`가 저장돼 있다면 reducer 검증만 추가해도 기존 행은 자동 교정되지 않는다. 배포 전 감사·정규화 정책이 필요하다.
- 저장 레벨을 `Player.level`에 숫자로만 대입하면 HP·에너지·공격력·이동속도 상승분이 누락된다. 2레벨부터 저장 레벨까지 `LevelSystem.gainsFor`를 재적용해야 한다(`lib/game/entities/player.dart:512-525`).
- 생성 시각 우선 동점 규칙은 오래된 캐릭터에 영구 우선권을 준다. 유지 여부는 게임 디자인 결정이며, 유지한다면 화면에서 명시해야 한다(`spacetimedb/src/leaderboard.rs:65-75`, `lib/game/ui/leaderboard_screen.dart:443-507`).
- 상대적 `xp` 막대는 상위 100 목록 안의 같은 레벨 최고값만 기준으로 한다. 100위 밖의 내 순위에는 비교 대상이 없어서 낮은 `xp`도 가득 찬 막대로 보일 수 있다(`lib/game/ui/leaderboard_screen.dart:484-507`, `lib/game/ui/leaderboard_screen.dart:527-569`).
- 계정당 최대 네 캐릭터가 모두 독립적으로 랭킹을 차지할 수 있다. 현재 구현 의도와 일치하지만 계정 단위 경쟁을 원한다면 정책이 달라져야 한다(`spacetimedb/src/character.rs:11-12`, `spacetimedb/src/leaderboard.rs:1-6`).
- `spacetimedb/src/lib.rs` 머리말은 현재 범위를 계정·캐릭터 선택까지라고 적지만 실제로는 리더보드 모듈을 포함한다. 운영 문서가 구현보다 뒤처져 있다(`spacetimedb/src/lib.rs:5-22`).

## 5. 권고안

| 순위 | 권고 | 범위 | 근거 | 리스크 |
|---|---|---|---|---|
| 1 | 서버에 레벨별 정수 XP 요구량 표를 두고 `level < 30`이면 `xp < xpToNext(level)`, 30레벨이면 `xp == 0`을 강제한다. `(level, xp)`를 내부 누적 성장량으로 환산해 서버 시각 대비 비현실적 점프는 차단 또는 감사 대상으로 기록한다. | `spacetimedb/src/leaderboard.rs`, `lib/game/systems/level_system.dart` | `spacetimedb/src/leaderboard.rs:145-186`, `lib/game/systems/level_system.dart:30-44` | 서버·클라이언트 곡선 불일치와 기존 데이터 이관 필요 |
| 2 | 선택한 캐릭터의 저장 `level`·`xp`를 게임 생성자에 전달하고, 해당 레벨까지 모든 성장 스탯을 재구성한다. 재시작도 저장 성장 상태를 유지하게 한다. | 앱 셸·게임·Player | `lib/main.dart:47-70`, `lib/game/action_rpg_game.dart:168-176`, `lib/game/entities/player.dart:512-525` | 초기화 순서가 틀리면 스탯이 중복 적용될 수 있음 |
| 3 | `_inFlight` 중 최신 진행도를 `pending`으로 병합하고 완료 직후 다시 전송한다. 여러 레벨 상승 처리가 끝난 최종 `(level, xp)`만 즉시 플러시하며, 모든 reducer 오류를 영구 `_rejected`로 취급하지 않는다. | 클라이언트 동기화 | `lib/game/net/spacetime_game_sync.dart:45-95`, `lib/game/entities/player.dart:504-509` | 재시도 폭주를 막는 백오프·중복 제거 필요 |
| 4 | 구독에 `desiredAttached` 또는 세대 토큰을 두어 닫힌 뒤 완료된 구독을 즉시 해제한다. 연결 실패·시간 초과·재연결 상태를 `LeaderboardSource`와 화면에 명시한다. | 어댑터·Flame 화면 | `lib/spacetime/spacetime_leaderboard.dart:30-63`, `lib/game/ui/leaderboard_screen.dart:125-169` | 빠른 재열기 시 새 구독을 잘못 해제하지 않도록 세대 구분 필요 |
| 5 | 상위 100은 30레벨부터 레벨 버킷별로 조회·정렬하고 100명에서 중단한다. `my_rank`는 더 높은 레벨과 동일 레벨 동점자만 조회한다. | 서버 view 성능 | `spacetimedb/src/lib.rs:105-111`, `spacetimedb/src/leaderboard.rs:105-138` | 만렙에 인원이 집중되면 동일 레벨 버킷은 여전히 클 수 있음 |
| 6 | 로컬 DB에서 100명 경계, `xp` 동점, 생성 시각 동점, 비정상 `xp`, 삭제, 두 클라이언트 동시 보고, 다른 클라이언트로의 view 전파를 자동 검증한다. 현재 `level=4, xp=120` 픽스처도 유효값으로 교체한다. | Rust·Dart·통합 테스트 | `spacetimedb/src/leaderboard.rs:213-237`, `test/spacetime_integration_test.dart:180-264` | maincloud 직접 대량 테스트는 운영 데이터와 비용을 오염시킴 |
| 7 | 정확한 `xp/요구량`과 “동점은 먼저 생성된 캐릭터 우선” 문구를 표시한다. 100위 밖 내 행의 상대 막대는 제거하거나 자기 레벨 요구량 기준으로 계산한다. | Flame `PositionComponent` UI | `lib/game/ui/leaderboard_screen.dart:443-507`, `lib/game/ui/leaderboard_screen.dart:527-569` | 작은 화면에서 열 너비 재조정 필요 |

## 6. 불확실 · 미확인

- 읽기 전용 지침에 따라 `cargo test`, `cargo build`, `flutter analyze`, `flutter test`는 실행하지 않았다. 현재 빌드·테스트 통과 여부는 미확인이다.
- 실제 maincloud 배포 바이너리와 작업공간 소스의 일치 여부, 기존 `PlayerCharacter` 행의 `level`·`xp` 유효성은 확인하지 못했다.
- `[미확인]` SpacetimeDB 2.7이 각 캐릭터 갱신에서 익명 view와 사용자별 `my_rank`를 실제로 몇 번 재평가·공유하는지는 프로파일링 자료가 없다. 성능 판정은 현재 함수의 알고리즘 비용 기준이다.
- 모든 보유 캐릭터를 독립 랭킹에 올릴지, 계정별 최고 캐릭터 하나만 올릴지는 코드상 전자로 구현돼 있으나 최종 게임 디자인 결정은 별도로 확인해야 한다.
