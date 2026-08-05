<!-- cowork:grok | 2026-08-05 22:14:35 | exit=0 | 492s -->
# grok 분석 — swing-animation-sync

> 요청: 서버/여러플레이어 화면 동기화 작업이 잘 되는지, 수정보완할 내용이 있으면 수정보완해주세요. 특히, pc 가 몬스터를 공격할 때 스윙/슬래시/칼휘두름 애니메이션이 내 화면에만 보이고, 다른 pc 화면에 보이지 않습니다. 이런 빠져있는 부분들을 수정/보완해주세요.
> 생성: 2026-08-05 22:14:35 · 소요 492s · 읽기 전용 분석(작업공간 미수정)

---



## 1. 결론 요약

**공격 사건 동기화 자체는 이미 서버·구독·통합 테스트 경로까지 존재한다.** 남 화면에서 칼이 “안 보이는” 체감은 (1) 원격 근접 연출이 로컬 블레이드 궤적 대비 극히 빈약하고, (2) 서버에 남는 것은 **명중·reducer 성공**뿐이며 로컬 스윙 시작과 시점·범위가 다르고, (3) `RemotePlayerEntity`/`Enemy`의 `_playedAttackAt == 0` 가드가 **첫 유효 공격(및 시야 재진입 직후 한 타)** 재생을 삼키는 버그가 겹친 결과다.  
“파이프라인이 없다”는 진단은 코드·테스트와 맞지 않는다. 우선 고칠 곳은 **클라이언트 재생 가드 + 원격 슬래시 연출 동급화**, 그다음 **성공 타격 vs 스윙 의도 분리(선택)**, 잔여 연출(대시·원격 사망) 순이다. 이 분석은 파일을 수정하지 않는다.

## 2. 근거

- `spacetimedb/src/world.rs:1553-1562` — `attack_monster` 성공 시 `last_attack_at`·`attack_dir_*`·`attack_skill` 기록. 주석: 없으면 남의 화면에서 가만히 선 채 몹만 죽는다.
- `spacetimedb/src/world.rs:399-409` · `#[default(Timestamp::UNIX_EPOCH)]` — 미공격 상태는 epoch(클라이언트 `toInt()`≈0). 사건을 “값 변화”로 전달.
- `spacetimedb/src/world.rs:1701-1711` · `1764-1770` — `cast_skill`·`attack_player`도 동일 필드 갱신.
- `lib/spacetime/spacetime_world_presence.dart:340-345` · `409-427` — `attack`은 `.ignore()`(결과 미대기); `others`에 `lastAttackAtMicros`·방향·스킬 매핑.
- `lib/game/entities/remote_player.dart:26-34` · `123` · `178-206` — 생성자가 `lastAttackAt`을 **읽지 않음**; `_playedAttackAt` 초기 0; `if (_playedAttackAt != 0 && attackAt != 0)` 일 때만 스윙.
- `lib/game/entities/remote_player.dart:135-138` · `316-350` · `397-415` — 스윙 0.26s, 짧은 `drawArc`; `showBlade: isSwinging`만; 근접 스윙 SFX 없음(플라즈마 탄 소리만 `302`).
- `lib/game/entities/cyborg_renderer.dart:90-115` — `showBlade`는 **등에 멘 칼**(`_drawHolsteredBlade`), 휘두르는 칼날이 아님.
- `lib/game/entities/player.dart:198-211` · `536-606` · `1067-1227` — 로컬 `tryMelee`는 즉시 상태·스윙음; 히트는 progress≥0.35에서; 서버 `presence.attack`/`attackPlayer`는 히트 경로; 렌더는 긴 `_renderBladeSwing`.
- `lib/game/entities/enemy.dart:173-177` · `600-603` — 몹 타격 연출도 동일 0-가드; 서버 몹 피격 시 체력 미삭감·`presence.attack`+로컬 히트음만(거절 대기 없음).
- `lib/game/action_rpg_game.dart:628-633` · `754-787` · `241` — 매 프레임 `report`+`_syncRemotePlayers`→`applySnapshot`; 원격 표시 50명 상한.
- `lib/spacetime/cyborg_connection.dart:82-110` — 청크 AOI 구독. 청크 밖이면 행·몸·스윙 전부 없음.
- `test/attack_and_loot_sync_test.dart:109-182` — **표**에 `lastAttackAt`·방향이 상대 캐시에 남는지 검증. `RemotePlayerEntity` 스윙 재생은 검증 없음.
- `test/server_interpolation_test.dart:259-318` — 원격 보간·facing 테스트만. 공격 시각 재생 없음.
- `spacetimedb/src/world.rs:2314-2337` — 사망 시 같은 갱신에서 `alive: true`·안전지대 재가동. `RemotePlayer`에 `deaths` 없음(`world_presence.dart:9-66`).
- `lib/game/ui/hud.dart:372-374` — `AGENTS n` / `OFFLINE`으로 멀티 연결·가시 인원 교차 확인 가능.

## 3. 상세 분석

### 3.1 질문 범위와 권위 경계

요청은 **다인 화면 동기화 전반 + 특히 PC 근접 스윙이 관찰자 화면에 안 보이는 문제**다. (주입 프롬프트의 HP 1만 재설계는 별 축. 참고: 클라이언트 `baseMaxHp = 10000`은 이미 반영됨 — `player.dart:47`.)

| 축 | 권위 | 관찰자 화면 |
|---|---|---|
| 위치·facing | 서버 `move_to` / report | `RemotePlayerEntity` 보간 |
| 몹 HP·생사·선점 | 서버 | `Enemy.applyServerState` |
| 내 HP/MP/사망 누계 | 서버 | `_adoptServerState` (`deaths`·`lastDamagedAt`) |
| **타격 성공 사건** | 서버 reducer 후 `last_attack_at` | 값이 바뀌면 원격 스윙 시도 |
| **로컬 칼 애니메이션** | 클라 `tryMelee` 즉시 | **내 화면만** `Player` |
| 대시 | 클라만(서버 필드 없음) | 원격 없음 |

### 3.2 의도된 파이프라인 (서버·표 구간은 성립)

```text
A: tryMelee → (로컬 스윙·스윙음 즉시)
   → progress≥0.35 히트 → Enemy.applyDamage(server)
   → presence.attack(id)  [Future ignore]
   → attack_monster 성공 시에만 last_attack_at 갱신
B: 구독 → presence.others → applySnapshot
   → lastAttackAt 변화 & 가드 통과 → _swingTimer / 짧은 호 / (plasma면 0뎀 탄)
```

`attack_and_loot_sync_test`가 **B의 표 입력**까지는 보증한다. 사용자 증상은 **B 끝단(재생·연출)** 과 **A↔서버 사건 정의 불일치** 쪽이다.

### 3.3 결함 A — 재생 가드가 “시야 진입 스킵”과 “미공격 요원 첫 타”를 묶음

`remote_player.dart:184-205`:

```dart
if (attackAt != _playedAttackAt) {
  if (_playedAttackAt != 0 && attackAt != 0) { /* 재생 */ }
  _playedAttackAt = attackAt;
}
```

| 상황 | 동작 |
|---|---|
| 미공격 요원, `last_attack_at`=epoch(0) | 0→0 변화 없음. `_playedAttackAt` 계속 0 |
| 그 상태의 **첫 성공 타** `0→T1` | `_playedAttackAt==0` 이라 **재생 스킵**, T1만 기록 |
| 두 번째 타 `T1→T2` | 재생됨 |
| 이미 T를 가진 채 시야 진입 | 의도대로 과거 타 비재생 후, **이후 타**부터 재생 |
| 시야 밖 제거 후 재생성 | `_playedAttackAt` 리셋 → 또 한 번 “첫 전이” 스킵 가능 |

의도(주석 180-182, 서버 주석 405-407: 재구독 시 옛 공격 재연 방지)는 타당하다. 구현이 **“아직 prime 안 됨”을 `==0`에 실어** epoch 상태 요원의 첫 실공격을 함께 버린다. `Enemy` 동일(`enemy.dart:173-177`).

**한계:** 연타·이미 사냥 중인 요원만 보면 2타부터는 코드상 재생된다. “완전히 안 보인다” 체감의 **전부**를 A만으로 설명하면 과하다. 다만 단타·시야 경계 전투·첫 조우에서는 A만으로도 “남의 스윙이 없다”로 충분하다.

**비대칭:** 새 몹은 생성 직후 `applyServerState`로 prime(`action_rpg_game.dart:1492-1499`). `RemotePlayerEntity`는 생성자가 공격 시각을 안 읽고(`26-34`), 다음 프레임 `applySnapshot`이 사실상 prime다.

### 3.4 결함 B — 로컬 vs 원격 연출 격차 (지속 관찰에서도 “안 보임” 가능)

| | 로컬 `Player` | 원격 `RemotePlayerEntity` |
|---|---|---|
| 칼 | 긴 호+칼날 라인, 콤보 방향 | 짧은 arc 1회 |
| 무기 표시 | 기본 `showBlade`(등 칼)+스윙 궤적 | 스윙 중만 등 칼 |
| 팔 | melee 시 궤적 주역 | armSwing 윈드업/스트라이크 |
| 길이 | 0.32s | 0.26s |
| 음 | 스윙·히트 | 근접 스윙음 없음 |

멀리서 보면 원격 “스윙”이 걷기 팔 흔들림과 구분 안 될 수 있다. **데이터가 와도 UI상 비가시**와 양립한다. 사용자 문장이 “애니메이션이 내 화면에만”이라면 B가 체감 주원인일 개연성이 크다.

### 3.5 결함 C — 사건 정의 = 성공 타격뿐

- 로컬: 빈 휘두름·빗나감도 애니메이션·스윙음(`tryMelee`).
- 서버: 사거리·쿨·alive 통과 후에만 `last_attack_at`(`world.rs:1487-1562`).
- 로컬 히트 판정 후 `presence.attack`은 비동기 ignore; 거절이어도 로컬 히트음·스파크는 나갈 수 있음(`enemy.dart:600-603`). 남 화면: 스윙도 몹 HP도 없음.
- 좌표 리콘실리(`player.dart:852-876`)로 서버 좌표와 어긋날수록 C 빈도↑.

로컬 콤보 3단은 클라 연출·피해 배율; 서버 쿨 ~350ms(`ATTACK_COOLDOWN_MICROS`)로 **성공 타격 횟수 ≤ 로컬 스윙 횟수**. 관찰자는 “덜 휘두르는” 사람을 본다.

### 3.6 멀티 전반 — 되는 것 / 약한 것

**되는 편:** 청크 구독·20Hz 위치·facing, 서버 몹·루트, 플라즈마 원격 탄(0뎀, 단 A 가드 안), 내 피격/사망(`deaths`/`lastDamagedAt`), 표 단위 공격 사건(통합 테스트).

**약함/없음:** 원격 근접 스윙(A·B·C), 대시(서버 필드 없음), 원격 사망 연출(`alive`가 false로 남는 구간 거의 없음·`deaths` 미전달), 버프 오라·콤보 단계 공유, 오프라인 `OfflineWorldPresence`는 `others` 비어 멀티 자체 없음.

### 3.7 문서 vs 코드

- `lib.rs` “모든 테이블 비공개” vs `WorldPlayer`/`Monster` `public` — 월드 표는 공개가 실측 설계.
- cowork Overview “실시간 멀티 없음”은 **구식**; 전투·존재 동기화는 서버 권위 단계.

## 4. 리스크 · 함정

- **가드만 제거:** 시야 진입 시 과거 `last_attack_at`으로 **등장 직후 헛스윙** 회귀. `_attackPrimed`(bool)와 “값 변화 재생”을 분리해야 한다.
- **연출만 키우고 A·C 방치:** 첫 타·거절·빗나감은 여전히 어긋난다.
- **모든 스윙을 서버 사건화:** 대역·쿨 의미 붕괴·허공 연타 스팸. “성공 타 연출 강화 + 선택적 의도 이벤트”가 안전.
- **연출용 탄 `damage: 0` 유지**(`remote_player.dart:296-297`). 관찰자 화면에서 피해 금지.
- **표 동기화 테스트 ≠ 스윙 보임.** `RemotePlayerEntity` 단위 테스트 없으면 A 회귀 재발.
- **AOI·OFFLINE·AGENTS=1** 이면 동기화 버그가 아니라 시야/연결 문제(`hud.dart:372-374`).
- 스키마 열 추가 시 **맨 끝+default** (`world.rs:390-395` 주석). 열 재배치 금지.

## 5. 권고안

| 순위 | 권고 | 범위 | 근거 | 리스크 |
|---|---|---|---|---|
| 1 | **`_attackPrimed`(또는 동등)로 “첫 스냅샷 스킵”과 “첫 실공격 재생” 분리.** epoch→T1도 재생. 시야 진입 시 과거 T만 스킵. 생성 시 `lastAttackAt`으로 즉시 prime. `Enemy` 동일. | 클라 연출 | `remote_player.dart:26-34,178-206`, `enemy.dart:173-177` | prime 없이 가드만 지우면 헛스윙 회귀 |
| 2 | **원격 근접을 로컬 `_renderBladeSwing` 수준으로** (긴 호·칼날; 가능하면 스윙 SFX 거리 감쇠). `showBlade`/짧은 arc만으로 “때림” 표현 금지. | 클라 렌더 | `player.dart:1174-1227` vs `remote_player.dart:316-415`, `cyborg_renderer.dart:90-115` | 다인 시 그리기 비용 |
| 3 | **단위 테스트:** (a) 0→T1 재생 (b) 시야 진입 과거 T 비재생 (c) T1→T2 재재생. 통합은 표만이 아니라 가능하면 엔티티 `_swingTimer`/`isSwinging`. | test | `attack_and_loot_sync_test` 공백, `server_interpolation_test` 범위 | 없음 |
| 4 | **거절·히트 피드백 정합:** 가능하면 attack 성공 후에만 히트음/스파크; 또는 거절률 낮추는 좌표 리콘실리 강화. | 클라±좌표 | `enemy.dart:600-603`, `spacetime_world_presence.dart:340-345`, `player.dart:852-876` | 입력 지연 체감 |
| 5 | (선택) **빗나간 스윙 공유:** 성공과 무관한 의도/연출 플래그 또는 스윙 전용 경로. 현재 스키마는 성공 타 전제. | 서버+클라 | `world.rs:1553-1562`, `player.dart:198-211` | 대역·어뷰즈 |
| 6 | 잔여: **원격 `deaths`/텔레포트 스냅**, 대시 짧은 이벤트 필드. | 서버 스키마+클라 | `world.rs:2314-2337`, `RemotePlayer` 필드 부재 | 마이그레이션(열 끝+default) |

**구현 시 손댈 위치(방향만)**

1. `lib/game/entities/remote_player.dart` — prime + 슬래시 렌더(+선택 SFX)  
2. `lib/game/entities/enemy.dart` — 동일 prime  
3. `test/` — 스윙 재생 회귀  
4. (선택) `spacetimedb/src/world.rs` — 의도 이벤트·사망 사건 표출  
5. 배포 시 `spacetime publish` + 생성 코드 재생성 규칙 준수  

## 6. 불확실 · 미확인

- 실기기 2인에서 **A vs B 기여 비율**은 런타임 재현 없이 단정 불가. 코드상 **둘 다 실재**.
- maincloud 배포 스키마가 로컬 `world.rs`와 동일한지 — 이 샌드박스에서 publish/실접속 미검증. 통합 테스트 통과 환경이면 필드는 있을 가능성 큼.
- `Timestamp`→`Int64.toInt()` 웹 타깃 정밀도 — 네이티브는 통상 OK, 웹은 `[추측]` 추가 확인.
- 사용자 장면이 AOI 밖·OFFLINE·단독 접속이었는지 — HUD `AGENTS`/`OFFLINE` 교차 필요.
- 파티 팔로우 중 공격 가시성·전 스킬 목록 전수 추적은 이번 깊이 밖. 스윙 이슈와 분리 가능.

## 7. 자기 비판으로 바로잡은 것

- 🔁 수정: 1차 «핵심 결함 A(첫 타 스킵)가 1순위 원인» → **체감 전면 비가시는 A+B+C 복합이며, 연타 관찰 시 A만으로는 부족; 지속 “안 보임”은 B(연출)가 더 유력, 단타·시야 경계는 A가 결정적.** 이유: 가드 통과 후 2타부터는 재생 코드가 있음(`remote_player.dart:185-186`).
- 🔁 수정: 권고 표에서 A 단독 1순위 고정 → **1=prime 분리, 2=연출 동급, 3=테스트**를 유지하되 §3에서 원인 가중을 재서술. 구현 순서는 여전히 A가 값싸고 확정 버그.
- ➕ 추가: **생성자가 `lastAttackAt` 미적용**(`remote_player.dart:26-34`) — 몹은 생성 직후 `applyServerState`로 prime하는 비대칭(`action_rpg_game.dart:1492-1499`).
- ➕ 추가: 시야 밖 제거 후 재생성 시 `_playedAttackAt` 리셋 → **경계 전투에서 스킵 반복**.
- ➕ 추가: 원격 **근접 스윙 SFX 전무**(플라즈마만 `302`) — “안 들리면 안 친 것처럼” 체감 강화.
- ➕ 추가: 서버 주석이 재구독 시 옛 공격 비재생을 **의도**로 명시(`world.rs:405-407`) — 가드 자체는 설계, `==0` 혼동이 버그.
- ➕ 추가: HUD `AGENTS`/`OFFLINE`으로 오진 배제(`hud.dart:372-374`).
- ➕ 추가: 로컬 콤보·빈 스윙 빈도 > 서버 성공 타 기록 빈도 → 관찰자 “덜 휘두름”.
- ❌ 철회: 1차가 가설 1(필드 부재)을 반증한 것은 **재검증 생존**. 줄 번호·내용 재열람 일치. 철회 없음.
- ❌ 철회 후보였으나 유지: «cowork Overview 멀티 없음은 구식» — `WorldPlayer` public·reducer·테스트로 재확인, 주제 부가 사실로만 유지.
