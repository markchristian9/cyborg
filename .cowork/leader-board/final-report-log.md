## 리뷰 라운드 — 2026-08-04 20:54

> 4 AI 리뷰(claude·codex·grok·kimi) → claude 종합 → final-report.md **갱신**

- **권고 2 를 교정했다(리뷰 4/4 합의, 직접 확인).** `player.dart:562` 의 `if (level >= LevelSystem.maxLevel) return;` 때문에 `:582` 의 `xp = 0` 만 제거해도 만렙 이후 `gainXp` 가 조기 반환해 xp 가 쌓이지 않는다. 범위를 조기 반환 해제까지 확장하고, 검증 기준을 "서로 다르게 유지" → "실제로 증가하는지" 로 바꿨다. §1·§4 쟁점 4·§6 에도 반영.
- **§4 쟁점 1 의 "게임 오버 시 update() 가 멈춘다" 를 철회했다(claude·codex·grok 3/4, 직접 확인).** `action_rpg_game.dart:904` 가 "게임 오버가 없다"고 명시하고 `onPlayerDied`(`:907-919`)는 리스폰만 하며 `GameStatus.gameOver` 로 전이하는 코드가 없다. `reportRunFinished()` 의 유일한 호출처는 `requestLogout()`(`:817`)이고 `onLogout?.call()`(`:818`)이 await 하지 않는다 — 실패 경로를 로그아웃으로 정정하고 권고 4⑶ 을 그에 맞게 고쳤다.
- **"불러오는 중" 영구 고착을 복원했다(4/4 지적, 직접 확인).** `leaderboard_screen.dart:130`·`:132`(attach Future 무시)·`:160`(해제 지점). §2 표에 행 추가, §3 합의에 항목 추가, 권고 6 에 ⑶ 으로 편입 — 세대 가드만 넣으면 오히려 악화된다는 kimi 의 상호작용 지적도 리스크 칸에 넣었다.
- **권고 3 을 거절 → clamp 로 바꿨다(claude 지적 2·7, codex 지적 8).** 거절이면 ⑴ 권고 2 적용 후 정직한 만렙 플레이어가 CAP 에 닿는 순간 `_rejected = true`(`spacetime_game_sync.dart:90`)로 보고가 끊기고 ⑵ 기존 비정상 행이 단조 가드와 새 검증 사이에서 영구 갱신 불가가 된다. 배포 전 감사·정규화를 선행 조건으로 명시하고, 곡선 검증을 "Rust·Dart 공유 고정 표" 로 구체화했다(claude 지적 8).
- **xp 정의 확장을 명시했다(codex 지적 3, grok 지적 3).** `.cowork/cowork-prompt.md:72-73` 과 `leaderboard.rs:57-61` 이 xp 를 "현재 레벨 안 진행도"로 못박았으므로 권고 2 를 "규격 확장"으로 라벨하고, 대안(별도 열·만렙 도달 시각)과 그 비용(`last_played_at` 이 `character.rs:121-124` 에서도 갱신 → 스키마 이주 필요)을 §8 에 남겼다.
- **인용 줄 번호를 전부 재확인해 정정했다.** `player.dart` `gainXp` `:560-583`·조기반환 `:562`·`xp=0` `:582`·`level=1` `:42-43`(리뷰들이 제시한 `:489`/`:509` 조차 이미 낡았다), 테스트 `:190`·`:207`, `lib.rs:156-162`, `spacetime_game_sync.dart` tick `:49-50`·`reportRunFinished` `:67-76`, `action_rpg_game.dart:1020`, `character.rs:136`. 검토 중 `player.dart` 가 편집되어 함수가 62줄 이동하는 것을 목격해 §8 에 기록했다.
- **권고 1 에 `_sentLevel`/`_sentXp` 초기화(3/4 지적, `:34-35` 확인)와 `restart()` 후퇴 리스크(codex 지적 4, `:1020` 확인)를 추가**했고, **권고 4⑶ 의 `_rejected` 백오프는 내렸다**(kimi 반증 — `:37-43` 주석의 정당화와 `:87`/`:91` 예외 분리를 확인, clamp 를 택하면 거절 자체가 사라진다).
- **반영하지 않은 것**: ⑴ codex 지적 1 의 "종합본 폐기" — `.cowork/cowork-prompt.md:25-41` 이 HP 과제를 담은 것은 사실이나 `monster_codex.dart:241`·`enemy.dart:833` 이 이미 몬스터 레벨을 구현해 그 문구가 stale 임을 확인했고 사용자 요청은 명시적으로 리더보드다 → §8 에 기록만. ⑵ rank 단언 완화 — kimi 의 플레이크 주장도 codex 의 SDK 반증도 내가 `spacetimedb_sdk` 내부를 열지 못해 양쪽 미확정으로 두고 `:207` 은 손대지 않기로 했다. ⑶ kimi 지적 2·3 의 귀속 오류 — 원본 분석 파일을 열 수 없어 "kimi 뿐" 단정만 완화. ⑷ §5 제목은 grok 지적대로 "소수가 짚었으나 검증됨" 으로 수정. ⑸ codex 지적 9 의 부하 시험 게이트 — 임계값 근거가 없어 §6 유보를 유지하고 §8 에만 남겼다.

- 원본 백업: `.review/final-report.before.md`

---

