## 리뷰 라운드 — 2026-08-05 14:56

> 4 AI 리뷰(claude·codex·grok·kimi) → claude 종합 → final-report.md **갱신**

- **§4 yaw 판정의 근거를 교체**(codex 리뷰 8). `enemy.dart:1130` 의 조준선은 연속 `facing` 에서 계산되고 호출 지점 `:634` 가 `canvas.restore()`(`:630`) **밖**이라 플립과 무관함을 직접 확인 — "연속 yaw 화하면 조준선이 깨진다"는 근거는 반증됐다. 결론(1차 2면 유지)은 유지하되 근거를 미러-비대칭 충돌로 바꾸고 "확정 기각"→"별도 결정"으로 완화, §6 에 반증 항목 추가.
- **§7 검증 칸 전면 정정 + 권고 0 신설**(claude 1 · codex 9 · kimi 5). `cyborg_render_snapshot_test.dart:33` 이 `expect(sheet.width, greaterThan(0))` 뿐이고 `matchesGoldenFile` 이 없음을 전문 확인 — "스냅샷"을 자동 회귀 검증처럼 쓴 표기를 analyze→test→PNG 육안 절차로 바꾸고 권고 6의 "골든 전체 변경" 리스크도 정정.
- **0.275 배율에 조건 복원**(claude 2). `_zoomScale` 기본값 1(`:315`)·`_minZoomScale = 0.5`(`:321`) 확인 → "기본 하한 0.55(59px), 최대 축소 시 0.275(30px)"로 §1·§5·§7·§8 을 통일.
- **순위 재배치**(claude 7·8 · grok 2). 배율 결정을 게이트(권고 1)로 끌어올리고, 요청의 핵심 축인 남녀 골격 분리를 6→4위로 상향. Phase A/B/C 로 나눠 파츠·서버가 조형과 동시에 착수되지 않게 했다(grok 8).
- **blur 표현 완화 + 정의 분리**(codex 7 · grok 1·3·4 · kimi 2). §3 의 "성능 주범" 단정을 "위험 후보"로 낮춰 §8 의 `[추측]` 과의 내부 모순을 해소하고, `iso_entity.dart:67` 그림자 blur·`player.dart` 이펙트 4개소를 확인해 예산에 반영. 부하 기준을 실제 상한 50/50(`action_rpg_game.dart:216,223`)으로 명시.
- **근거·귀속 정정**: Instructions 인용 제거 후 요청문+ULPC 라이선스로 교체(claude 3), 프롬프트 드리프트를 §8 최상위로 신설(claude 4 · codex 2), `female_cyborg` 분기 2곳 확인(claude 5), 헬멧 항목 제목과 `:643` 의도 주석 리스크(claude 9), claude 실패 서술 "빈 응답"→"조기 종료·본문 없음"(claude 10), 팔레트 발견자를 codex·반론을 kimi 로 정정(kimi 1), `quantizeYaw` 인과에 `[추측]` 부여(kimi 3), §1 "세 AI 모두 반대"→"codex·grok 명시·kimi 전제 배제"(kimi 4).
- **누락 근거 복원**: codex 의 최소 치수(4px/3.6px/2~2.5px)·LOD 예산표(claude 6 · kimi 9, `[판단]`/`[추측]` 표기 유지), `Set<CyborgImplant>` 한계(kimi 6), grok 의 미러 금지 제약(kimi 7), `schemaVersion`·마이그레이션(codex 11), 관절 2-Path 분절(grok 7), bake 조기 채택 기각 명시(grok 6).
- **반영하지 않음**: codex 1·3(프롬프트가 HP 과제이므로 이 보고서를 폐기하고 재수행하라) — 사람의 실제 요청은 머리말에 인용된 캐릭터 아트이고 프롬프트는 분석 **이후** 다른 세션이 교체한 공용 파일이다. 리뷰 시점 프롬프트로 분석 시점 과제를 부정할 수 없으며, `maxLevel = 200` 은 코드에 실재하므로 코드 사실을 우선했다. 드리프트 자체는 §8 최상위 항목으로 기록했다. codex 10(서버 설계 전체 확장)은 확인 가능한 범위(모든 테이블 비공개·view 구독)만 권고 10 리스크에 반영하고 나머지는 확장하지 않았다.

- 원본 백업: `.review/final-report.before.md`

---

