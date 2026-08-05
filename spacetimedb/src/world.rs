//! 서버가 주관하는 월드 — 몬스터와 킬 판정.
//!
//! ## 왜 몬스터가 서버에 있는가
//!
//! 하나의 오픈 월드를 여럿이 공유하므로 몬스터는 각자의 화면에 따로 존재하는
//! 연출이 아니라 **모두가 같은 것을 보는 하나의 개체**여야 한다. 클라이언트가
//! 자기 몫을 따로 굴리면 A 가 쓰러뜨린 몹이 B 화면에는 살아 있고, 그 순간
//! "하나의 월드" 라는 전제가 깨진다.
//!
//! ## 킬 판정은 선점(태그) 방식이다
//!
//! 몹을 **처음 때린 사람**이 그 몹의 주인이 되고, 누가 막타를 넣든 경험치는
//! 주인에게 간다. 막타 방식은 남이 깎아 둔 몹을 가로채는 짓에 보상을 주므로
//! 쓰지 않는다.
//!
//! 이 규칙은 PK 와 맞물려 돌아간다 — 남이 선점한 몹을 뺏고 싶으면 몹이 아니라
//! **그 사람**을 쓰러뜨려야 한다. 사냥터 다툼이 그대로 PK 의 동기가 된다.
//!
//! 주인이 자리를 떠도 몹이 영영 묶여 있으면 안 되므로 태그에는 수명이 있다
//! ([`TAG_TTL_MICROS`]). 수명이 지나면 다음에 때린 사람이 주인이 된다.
//!
//! ## 같은 몹에 막타가 동시에 들어오면
//!
//! reducer 는 원자적 트랜잭션이고 격리 수준이 strongly serializable 이다. 같은
//! 몹을 향한 두 호출은 직렬화되어, 먼저 커밋된 쪽이 `alive = false` 로 만들고
//! 나중 호출은 이미 죽은 몹을 보고 그대로 실패한다. 둘 다 킬을 먹거나 둘 다
//! 놓치는 상태는 생기지 않는다. 몹마다 락을 걸거나 큐를 두지 않는 이유가 이것이다.
//!
//! 다만 SpacetimeDB 는 직렬화 이상을 감지하면 **같은 인자로 reducer 를 다시
//! 실행할 수 있다.** 그래서 판정에 쓰는 상태는 전부 표 안에만 둔다. 모듈 전역
//! 변수에 무언가를 세어 두면 재실행될 때 두 번 세어진다.
//!
//! ## 이 표들만 공개인 이유
//!
//! [`crate`] 의 설계 원칙 3 번은 "모든 표가 비공개" 다. 여기 세 표는 예외다.
//! 원칙이 지키려는 것은 **남에게 갈 이유가 없는 것**(비밀번호 해시, `account_id`)
//! 이지, 월드에 드러난 사실이 아니다. 다른 요원이 어디 서 있고 어떤 몹이 살아
//! 있는지는 게임이 성립하려면 서로 보여야 하는 정보다. 대신 이 표들에는
//! `account_id` 처럼 계정을 가리키는 값을 한 열도 두지 않는다.

use spacetimedb::{Identity, ReducerContext, ScheduleAt, Table, TimeDuration, Timestamp};

use crate::{PlayerCharacter, player_character};

// ── 상수 ────────────────────────────────────────────────────────────────

/// 플레이어가 실제로 걸을 수 있는 한 변의 길이(타일 = m).
///
/// 규격은 "걸을 수 있는 거리 가로 1 km × 세로 1 km" 다. 격자 크기가 아니라
/// 이 값이 1000 이어야 한다. 클라이언트 `kWorldPlayableTiles` 와 같아야 한다.
pub const WORLD_PLAYABLE_TILES: f32 = 1000.0;

/// 걸을 수 있는 영역 바깥을 두르는 통행 불가 테두리의 두께(타일).
///
/// 클라이언트 `kWorldEdgeMarginTiles` 와 같아야 한다.
pub const WORLD_EDGE_MARGIN: f32 = 3.0;

/// 월드 격자 한 변의 타일 수. 클라이언트 `kWorldTiles` 와 같아야 한다.
///
/// 걸을 수 있는 영역에 양쪽 테두리를 더한 값이며, 유효 좌표의 **배타 상한**이다
/// (타일 인덱스는 `0 ..= WORLD_TILES - 1`).
pub const WORLD_TILES: f32 = WORLD_PLAYABLE_TILES + WORLD_EDGE_MARGIN * 2.0;

/// 플레이어가 설 수 있는 좌표의 최댓값.
///
/// 통행 가능 구간의 상한은 배타적이라, 포함 상한을 요구하는 `clamp` 에는
/// 한 틱 안쪽 값을 넘겨야 마지막 통행 가능 칸에 머문다.
pub const PLAYABLE_MAX: f32 = WORLD_TILES - WORLD_EDGE_MARGIN - 0.001;

/// 안전지대 한 변의 길이(타일). 클라이언트 `kSafeZoneSizeMeters` 와 같아야 한다.
///
/// 타일 하나가 1 m 이므로 미터 값을 그대로 쓴다.
pub const SAFE_ZONE_TILES: f32 = 50.0;

/// 몬스터 레벨의 상한. 레벨 1 부터 이 값까지 한 단계도 빠짐없이 배치한다.
///
/// 플레이어 만렙(999)과는 별개다. 몬스터 난이도는 플레이어가 어디까지 크는지가
/// 아니라 **월드가 무엇을 품고 있는지**로 정한다.
pub const MONSTER_MAX_LEVEL: u32 = 200;

/// 한 레벨의 군집에 들어가는 최소·최대 마릿수.
///
/// 레벨마다 이 범위에서 마릿수를 뽑아 **한자리에 모아** 배치한다. 흩뿌리지 않는
/// 이유는 사냥터가 되게 하기 위해서다 — 같은 레벨이 뭉쳐 있어야 "여기는 30 레벨
/// 구역" 이라는 것이 걸어 보면 알게 되고, 자기 수준에 맞는 자리를 찾아다니는
/// 행동이 생긴다. 한 마리씩 흩어 두면 어디를 가도 난이도가 뒤죽박죽이다.
///
/// **세 배(15~60)로 올려 봤다가 절반(3~10)으로 내렸다.** 올렸을 때 몹이
/// 22,500 기가 되자 AI 틱이 훑을 수도 함께 세 배가 되어 서버가 밀렸다 —
/// `move_to` 가 10 초 타임아웃을 내고 `spacetime logs` 조차 응답하지 않았다.
/// 되돌린 뒤에도 AI 틱 로그 간격이 41.7 ms 설정값의 30 배에 달해(실측 1.2 초),
/// 지금 규모도 이 서버에는 버겁다는 뜻이었다. 그래서 요청대로 절반으로 낮춘다.
///
/// 화면이 성기게 느껴지면 이 값보다 **AI 틱 주기**([`MONSTER_AI_MICROS`])를
/// 먼저 살펴야 한다. 몹 수와 틱 빈도가 곱해져 부하가 되기 때문이다.
pub const CLUSTER_MIN: u32 = 3;
pub const CLUSTER_MAX: u32 = 10;

/// 군집 한 덩어리가 퍼져 있는 반경(타일).
///
/// 화면에 여러 마리가 함께 들어와 "무리" 로 보일 만큼 좁게, 그러나 서로 겹쳐
/// 한 마리처럼 보이지는 않을 만큼 넓게 잡는다.
const CLUSTER_RADIUS: f32 = 9.0;

/// 같은 레벨의 군집이 나타나는 **지역의 수**.
///
/// 월드는 중심에서의 거리(레벨 대역)와 방위로 나뉜 격자다. 같은 레벨이 한
/// 곳에만 있으면 그 레벨을 사냥하려는 사람이 월드에서 그 한 지점을 찾아가야
/// 하고, 반대 방향으로 나선 사람에게는 자기 레벨대가 아예 없는 셈이 된다.
/// 같은 대역을 여러 방위에 두면 어느 쪽으로 나서든 제 수준의 사냥터를 만난다.
pub const CLUSTERS_PER_LEVEL: u32 = 3;

/// 월드에 배치할 수 있는 몬스터 수의 상한.
///
/// 레벨 200 × 지역 3 × 최대 10 마리 = 6,000. 실제 마릿수는 군집마다 뽑은
/// 값의 합이라 이보다 적다. 이 상수는 스폰 자리 번호를 나눠 줄 때의 한계로만 쓴다.
pub const MONSTER_CAPACITY: u32 = MONSTER_MAX_LEVEL * CLUSTERS_PER_LEVEL * CLUSTER_MAX;

/// 근접 공격이 닿는 거리(타일).
///
/// 클라이언트의 연출 사거리보다 넉넉하게 잡는다. 서버와 클라이언트의 좌표는
/// 지연 때문에 항상 조금 어긋나 있고, 여기를 빡빡하게 잡으면 화면에서는 분명히
/// 닿았는데 서버가 거절하는 일이 잦아진다.
const ATTACK_RANGE_TILES: f32 = 2.2;

/// 공격 사이의 최소 간격(마이크로초). 0.35 초.
const ATTACK_COOLDOWN_MICROS: i64 = 350_000;

/// 선점 태그의 수명(마이크로초). 30 초.
///
/// 주인이 몹을 때리다 자리를 뜨면 그 몹은 아무도 못 잡는 상태가 된다. 마지막
/// 타격에서 이 시간이 지나면 태그를 놓아 준다.
const TAG_TTL_MICROS: i64 = 30_000_000;

/// 쓰러진 몹이 되살아나기까지의 시간(마이크로초). 20 초.
const RESPAWN_MICROS: i64 = 20_000_000;

/// 몬스터 정비(리스폰) 주기(초).
const MONSTER_TICK_SECS: u64 = 5;

/// 몬스터 AI 주기(마이크로초). **10 Hz** — 이 게임의 월드 틱이다.
///
/// 한때 24 Hz(41,667 μs)로 두었으나 **서버가 그 빈도를 지키지 못했다.** 로그의
/// 실제 틱 간격은 1.22 초로 설정값의 서른 배였고, 그 밀림이 다른 reducer 까지
/// 굶겨 `enter_world` 뒤 내 행이 구독으로 오지 않고 `move_to` 가 10 초
/// 타임아웃을 냈다 — 게임이 실질적으로 돌아가지 않는 상태였다.
///
/// 10 Hz 는 MMO 가 흔히 쓰는 범위의 아래쪽이고, 클라이언트가 스냅샷 사이를
/// 등속으로 보간하므로 눈에는 이어져 보인다. 올리려면 먼저 **한 틱이 실제로
/// 얼마나 걸리는지** 재고, 설정값이 지켜지는 것을 로그로 확인해야 한다.
///
/// 밀리초가 아니라 마이크로초로 두는 이유가 있다. 1/24 초는 41.666… ms 로
/// **밀리초로 떨어지지 않는다.** 41ms 로 반올림하면 24.39Hz, 42ms 면 23.81Hz 라
/// 어느 쪽도 24 틱이 아니다. 마이크로초로 두면 41,667μs = 23.9998Hz 로,
/// 하루를 돌려도 어긋남이 1 틱 미만이다.
///
/// 짧을수록 추격이 매끄럽지만 그만큼 트랜잭션이 늘어난다. 1/24 초면 몹이
/// 한 번에 0.1 타일씩 움직이고, 클라이언트가 그 사이를 보간해 걸어오는 것처럼
/// 보인다.
///
/// **0.3 → 0.15 → 0.05 → 1/24 초로 줄여 왔다.** 보간은 두 스냅샷 사이를 메우는
/// 일이라 갱신 간격만큼의 지연을 반드시 안고 간다 — 간격이 길면 몹이 방향을 튼
/// 것이 화면에 닿기까지 그만큼 걸려, 아무리 매끄럽게 그려도 "따라오다 갑자기
/// 꺾는" 모습이 남는다. MMORPG 가 보통 쓰는 10~30 Hz 안이고, 클라이언트의 좌표
/// 보고 주기([`spacetime_world_presence.dart`] 의 `_interval`)와 같은 24 Hz 라
/// PC 와 몹이 같은 리듬으로 갱신된다.
///
/// 훑는 범위는 플레이어 주변 청크뿐이라 한 틱의 비용은 접속자 수에 비례할 뿐
/// 몹 수와는 무관하다. 그리고 실제 쓰기는 [`moved_enough`] 가 거르므로,
/// 목표에 도착해 서 있는 몹은 24 Hz 로 판정해도 **한 번도 브로드캐스트되지
/// 않는다** — 늘어나는 것은 판정 비용이지 델타 폭이 아니다.
const MONSTER_AI_MICROS: u64 = 100_000;

/// 아무도 쫓지 않는 몹을 몇 틱에 한 번 볼 것인가. 24 Hz ÷ 3 = **8 Hz**.
///
/// 갱신 빈도를 거리로 차등하는 손잡이다. 어그로 안의 몹은 매 틱 그대로 두고
/// ([`needs_tick`]), 혼자 집으로 돌아가는 몹만 솎는다 — 아무도 그 몹을 쫓고 있지
/// 않으므로 24 Hz 로 그려 줄 이유가 없고, 클라이언트가 그 사이를 보간해 메운다.
///
/// **이것이 이 구조에서 가능한 거리 차등의 전부다.** 구독은 행 단위라 "A 에게는
/// 24 Hz, B 에게는 8 Hz" 를 쓸 수 없다 — 한 번 쓰면 그 행을 구독한 전원에게 같은
/// 델타가 간다. 그래서 차등의 기준은 **받는 사람과의 거리**가 아니라 **그 몹이
/// 지금 교전 중인가**가 된다. 다행히 둘은 대체로 같은 것을 가리킨다.
const FAR_MONSTER_TICK_DIVISOR: u64 = 3;

/// 몬스터가 플레이어를 알아채는 거리(타일).
///
/// 클라이언트 `kAggroMaxMeters` 와 같은 자릿수다. 서버가 판정의 주인이므로
/// 실제로 쫓아올지는 이 값이 정한다.
const MONSTER_AGGRO_TILES: f32 = 9.0;

/// 이 거리를 벗어나면 추격을 포기하고 제자리로 돌아간다.
///
/// 어그로 범위와 같게 두면 경계에서 쫓아왔다 돌아섰다를 반복한다.
const MONSTER_LEASH_TILES: f32 = 16.0;

/// 집에서 이만큼 멀어지면 무조건 돌아간다. 몹이 월드를 가로질러 끌려다니는
/// 것을 막는다.
const MONSTER_MAX_ROAM_TILES: f32 = 26.0;

/// 몬스터 이동 속도(타일/초). 플레이어(3.6)보다 느려 도망칠 여지를 남긴다.
const MONSTER_SPEED: f32 = 2.4;

/// 몬스터가 플레이어를 때리는 간격(마이크로초). 1.2 초.
const MONSTER_ATTACK_COOLDOWN_MICROS: i64 = 1_200_000;

/// 이동 보고가 허용하는 최대 속도(타일/초).
///
/// 클라이언트가 좌표를 보내고 서버는 **속도 상한만** 본다. 완전한 서버 이동
/// 시뮬레이션은 조작에 더 강하지만 예측·롤백을 함께 만들어야 하고, 그 비용은
/// 지금 단계에서 얻는 것보다 크다. 대시와 지연을 감안해 상한은 넉넉히 둔다 —
/// 여기서 잡으려는 것은 "월드 반대편으로 순간이동해 기습하고 사라지는" 짓이지
/// 미세한 속도 조작이 아니다.
const MAX_MOVE_SPEED: f32 = 14.0;

// ── 전투 수치 (클라이언트와 같은 정본) ──────────────────────────────────
//
// 🛑 **여기가 전투 수치의 단일 진실 공급원이다.** 서버가 판정의 주인이므로 이 값이
// 정본이고, 클라이언트의 같은 상수는 표시·예측용 사본이다. 한쪽만 바꾸면 화면과
// 판정이 갈라져 "분명히 맞았는데 안 죽는" 상태가 된다.
//
// 대응하는 클라이언트 위치:
//   BASE_MAX_HP / HP_PER_LEVEL  → `Player.baseMaxHp` · `LevelGains.maxHp`
//   BASE_MAX_MP / MP_PER_LEVEL  → `Player.mp` 초기값 · `LevelGains.maxMp`
//   MELEE_* / RANGED_*          → `Player.meleeDamage` · `rangedDamage` · `LevelGains`
//   DEFENSE_CONSTANT            → `Player.defenseConstant`
//   MONSTER_BASE_HP / _PER_LEVEL→ `MonsterCodex._statsFor` 의 `baseHp`
//   MONSTER_BASE_XP / _PER_LEVEL→ `MonsterCodex._statsFor` 의 `baseXp`

/// 1 레벨 사이보그의 몸체 내구도.
///
/// 몬스터가 주는 피해가 곧 그 몬스터의 레벨이므로(1~200), 이 값은 "레벨 N 몬스터에게
/// 몇 대까지 버티는가" 를 그대로 뜻한다.
const BASE_MAX_HP: i32 = 10_000;

/// 레벨업 한 번에 늘어나는 최대 체력.
const HP_PER_LEVEL: i32 = 1_000;

/// 1 레벨 사이보그의 마력 회로 용량.
const BASE_MAX_MP: i32 = 5_000;

/// 레벨업 한 번에 늘어나는 최대 마력.
const MP_PER_LEVEL: i32 = 600;

/// 1 레벨의 근접 피해. 레벨마다 [`MELEE_PER_LEVEL`] 씩 오른다.
const MELEE_BASE_DAMAGE: f32 = 26.0;
const MELEE_PER_LEVEL: f32 = 4.5;
/// 5 레벨 강화 구간에서 [`MELEE_PER_LEVEL`] 대신 붙는 몫의 **차액**.
const MELEE_MILESTONE_BONUS: f32 = 3.5;

/// 1 레벨의 원거리 피해.
const RANGED_BASE_DAMAGE: f32 = 18.0;
const RANGED_PER_LEVEL: f32 = 3.0;
const RANGED_MILESTONE_BONUS: f32 = 2.5;

/// 방어력이 이 값과 같아지면 받는 피해가 절반이 된다([`damage_after_defense`]).
const DEFENSE_CONSTANT: i32 = 100;

/// 회복 판정 주기(밀리초). 1 초.
///
/// 회복은 몹 AI 처럼 촘촘할 필요가 없다. 클라이언트가 그 사이를 이어 그리므로
/// 화면에서는 부드럽게 차오르고, 서버 트랜잭션은 초당 한 번으로 끝난다.
const REGEN_TICK_MILLIS: u64 = 1_000;

/// 안전지대에서 1 초에 채워지는 최대 체력의 비율(1000 분율).
///
/// 클라이언트 `RestRecovery.hpPerSecond`(0.12)와 같아야 한다. 정수로 두는 이유는
/// reducer 가 같은 인자로 재실행될 수 있어 부동소수 누적을 상태로 들고 있으면
/// 안 되기 때문이다 — 매 틱 최대치에서 다시 계산하면 재실행돼도 결과가 같다.
const REST_HP_PER_MILLE: i32 = 120;

/// 안전지대에서 1 초에 채워지는 최대 마력의 비율(1000 분율).
/// 클라이언트 `RestRecovery.mpPerSecond`(0.15)와 같아야 한다.
const REST_MP_PER_MILLE: i32 = 150;

/// 거점 밖에서 1 초에 저절로 차는 마력의 비율(1000 분율). 거의 차지 않는다.
/// 클라이언트 `RestRecovery.fieldMpPerSecond`(0.005)와 같아야 한다.
const FIELD_MP_PER_MILLE: i32 = 5;

/// 1 레벨 몬스터의 기본 체력. 계열 배율([`hp_scale`])이 곱해진다.
const MONSTER_BASE_HP: f32 = 26.0;
const MONSTER_HP_PER_LEVEL: f32 = 23.0;

/// 1 레벨 몬스터의 기본 경험치. 계열 배율([`xp_scale`])이 곱해진다.
const MONSTER_BASE_XP: f64 = 10.0;
const MONSTER_XP_PER_LEVEL: f64 = 9.0;

/// 텔레포트 목적지가 월드 가장자리에서 안쪽으로 들어온 거리(타일).
///
/// 클라이언트 `TeleportDestination.edgeInset` 과 같은 값이어야 한다.
const TELEPORT_EDGE_INSET: f32 = 30.0;

/// 착지점이 목적지 기준점에서 벗어날 수 있는 최대 거리(타일).
///
/// 클라이언트는 가장자리가 막혀 있으면 중앙 쪽으로 물러나며 착지점을 다시
/// 찾는다(`_retryCount 12 × _retryStride 12` = 144 타일, 여기에
/// `nearestWalkable` 의 탐색 반경 24). 서버는 지형을 모르므로 그 보정을 재현할
/// 수 없고, 대신 **얼마나 벗어날 수 있는지** 만 검증한다.
const TELEPORT_LANDING_SLACK: f32 = 180.0;

/// 텔레포트 사이의 최소 간격(마이크로초). 8 초.
///
/// 클라이언트에는 쿨다운이 없다. 서버가 두지 않으면 사냥터 사이를 무한히
/// 넘나들며 남이 선점한 몹만 골라 가로채거나, PK 가 붙었을 때 맞자마자 사라지는
/// 짓이 공짜가 된다.
const TELEPORT_COOLDOWN_MICROS: i64 = 8_000_000;

// ── 표 ──────────────────────────────────────────────────────────────────

/// 월드에 들어와 있는 캐릭터.
///
/// 로그인했다고 여기 행이 생기는 것이 아니라 [`enter_world`] 를 불러야 생긴다.
/// 캐릭터 선택 화면에 머무는 동안에는 월드에 없는 것이 맞다.
#[spacetimedb::table(
    accessor = world_player,
    public,
    // 관심 영역 구독의 뼈대다. 클라이언트가 자기 청크와 이웃 여덟 칸을 등식으로
    // 나열해 구독하므로([`PLAYER_SUB_CHUNK_TILES`]), 이 인덱스가 없으면 그 구독이
    // 전수 검사가 된다. **인덱스를 지우면 구독이 런타임 오류로 깨진다.**
    index(accessor = by_sub_chunk, btree(columns = [sub_chunk]))
)]
pub struct WorldPlayer {
    /// 접속 주체. 한 연결은 한 캐릭터만 조종한다.
    #[primary_key]
    pub identity: Identity,

    /// 조종 중인 캐릭터. `unique` 라 같은 캐릭터를 두 기기에서 동시에 월드에
    /// 올릴 수 없다. 이 검사가 없으면 한 캐릭터가 두 곳에서 사냥하며 경험치를
    /// 두 배로 벌어들인다.
    #[unique]
    pub character_id: u64,

    pub name: String,
    pub kind: String,
    pub level: u32,

    pub grid_x: f32,
    pub grid_y: f32,

    pub hp: i32,
    pub max_hp: i32,
    pub alive: bool,

    /// 이 시각 전에는 다시 공격할 수 없다. 쿨다운을 서버가 쥐고 있어야
    /// 연타 조작이 통하지 않는다.
    pub next_attack_at: Timestamp,

    /// 마지막으로 좌표를 보고한 시각. 속도 상한 계산의 기준이다.
    pub last_move_at: Timestamp,

    pub entered_at: Timestamp,

    /// 이 시각 전에는 다시 텔레포트할 수 없다([`TELEPORT_COOLDOWN_MICROS`]).
    ///
    /// **맨 끝에 있어야 하고 기본값이 필요하다.** 이미 배포된 표에 열을 더하는
    /// 자동 마이그레이션은 두 조건을 모두 요구한다 — 열 순서가 바뀌면 기존 행을
    /// 읽을 수 없고, 기본값이 없으면 기존 행의 새 열을 채울 수 없기 때문이다.
    /// 기본값을 epoch 로 두면 옛 행은 "쿨다운이 이미 지난 상태" 가 되어
    /// 첫 텔레포트가 막히지 않는다.
    #[default(Timestamp::UNIX_EPOCH)]
    pub next_teleport_at: Timestamp,

    /// 이 시각 전에는 몬스터에게 다시 맞지 않는다.
    ///
    /// 여러 몹이 동시에 달려들 때 한 틱에 몰아서 맞고 즉사하는 것을 막는다.
    /// 쿨다운을 몹이 아니라 **맞는 쪽**에 두는 이유다.
    ///
    /// 맨 끝에 있고 기본값이 있어야 한다([`next_teleport_at`] 과 같은 이유).
    #[default(Timestamp::UNIX_EPOCH)]
    pub next_hurt_at: Timestamp,

    /// 지금 마력. 스킬을 쓸 때 서버가 여기서 깎는다.
    ///
    /// 클라이언트가 "마력을 얼마 썼다" 고 보고하는 길은 없다 — 보고를 받으면 그
    /// 순간 마력은 조작 가능한 값이 되고, 마력으로 제한하려던 모든 것이 무의미해진다.
    #[default(0)]
    pub mp: i32,

    #[default(0)]
    pub max_mp: i32,

    /// 방어력. 받는 피해를 [`DEFENSE_CONSTANT`] 기준의 승수로 깎는다.
    ///
    /// 기본값은 0 이며, 이때 받는 피해는 때린 몬스터의 레벨과 정확히 같다.
    /// 지금은 올릴 방법이 없다 — 성장·장비·버프 중 어디에 붙일지 정해지지 않았다.
    /// 축만 먼저 세워 둔다.
    #[default(0)]
    pub defense: i32,

    /// 지금까지 쓰러진 횟수.
    ///
    /// 사망은 **이 게임에서 상태가 아니라 사건**이다 — 쓰러지면 곧바로 안전지대에서
    /// 다시 일어서므로 `alive` 를 내려 두는 순간이 거의 없고, 클라이언트가 구독으로
    /// 그 찰나를 보리라 기대할 수 없다. 대신 이 누적 수가 **오르는 것**을 보고
    /// 사망 연출·카메라 이동을 시작한다. 상태 변화로 사건을 전달하는 방식이며,
    /// 별도의 이벤트 표보다 재접속·재구독에 강하다(과거 이벤트가 되살아나지 않는다).
    #[default(0)]
    pub deaths: u32,

    /// 이 시각 전에는 어떤 피해도 통하지 않는다.
    ///
    /// 재가동 직후의 무방비 상태를 지켜 준다. 안전지대 안은 어차피 면역이지만,
    /// 밖으로 걸어 나가는 순간 대기하던 몹에게 즉사하지 않도록 짧은 유예를 준다.
    #[default(Timestamp::UNIX_EPOCH)]
    pub invulnerable_until: Timestamp,

    /// 마지막으로 피해를 입은 시각. 안전지대 회복의 대기 시간 기준이다.
    ///
    /// 얻어맞자마자 거점으로 뛰어들어 즉시 회복하는 것을 막는다
    /// (클라이언트 `RestRecovery.warmupAfterDamage` 와 같은 규칙).
    #[default(Timestamp::UNIX_EPOCH)]
    pub last_damaged_at: Timestamp,

    /// 관심 영역 구독용 공간 청크. `player_sub_chunk_of(grid_x, grid_y)` 로 만든다.
    ///
    /// **지금 좌표로 정한다.** 몹의 [`chunk`](Monster::chunk) 가 집 좌표인 것과
    /// 반대다 — 구독은 "지금 화면에 보여야 할 것" 을 고르는 일이므로 현재 위치가
    /// 기준이어야 한다.
    ///
    /// **좌표를 쓰는 모든 곳에서 함께 갱신해야 한다.** 하나라도 빠뜨리면 그 사람은
    /// 옛 청크에 남아, 본인 화면에서는 주변이 비고 남들 화면에는 유령이 남는다.
    /// 특히 사망 재가동([`apply_damage_to_player`])은 좌표를 월드 중심으로 되돌리
    /// 므로 놓치기 쉽다.
    ///
    /// **이 자리를 옮기면 안 된다.** 이미 배포된 표에서 이 열은
    /// `last_damaged_at` 과 `last_attack_at` 사이에 있다. 열 순서가 바뀌면
    /// SpacetimeDB 는 자동 마이그레이션을 거부한다("Reordering table ...
    /// requires a manual migration") — 새 열은 반드시 **맨 끝**에 붙이고,
    /// 이미 있는 열은 제자리에 두어야 한다.
    #[default(0u32)]
    pub sub_chunk: u32,

    /// 마지막으로 공격을 **휘두른** 시각.
    ///
    /// 다른 사람 화면에서 이 몸이 공격 동작을 하려면, 공격이 일어났다는 사실
    /// 자체가 표에 남아야 한다. [`next_attack_at`](WorldPlayer::next_attack_at) 으로
    /// 역산할 수도 있을 것 같지만 그것은 쿨다운의 끝이고 스킬마다 길이가 달라,
    /// 언제 휘둘렀는지를 되짚을 수 없다.
    ///
    /// 사건을 상태로 전달하는 방식이다([`deaths`](WorldPlayer::deaths) 와 같은
    /// 이유) — 이 값이 **바뀌는 것**을 보고 동작을 한 번 재생한다. 별도 이벤트
    /// 표와 달리 재구독해도 옛 공격이 되살아나지 않는다.
    #[default(Timestamp::UNIX_EPOCH)]
    pub last_attack_at: Timestamp,

    /// 그 공격이 향한 방향(정규화된 그리드 벡터).
    ///
    /// **서버가 계산한다.** 클라이언트가 보내면 조작할 수 있는 값이 되고, 어차피
    /// 서버는 사거리를 재느라 양쪽 좌표를 이미 쥐고 있다.
    #[default(0.0f32)]
    pub attack_dir_x: f32,

    #[default(0.0f32)]
    pub attack_dir_y: f32,

    /// 무엇으로 쳤는지. [`ATTACK_SKILL_NONE`] 이면 기본 공격이다.
    ///
    /// 스킬마다 동작과 이펙트가 다르므로, 이것이 없으면 남의 화면에서는 모든
    /// 공격이 같은 주먹질로 보인다.
    ///
    /// 문자열이 아니라 번호인 것은 스키마 기본값 때문이다 — `String` 은 상수
    /// 문맥에서 만들 수 없어 `#[default(...)]` 를 붙일 수 없고, 기본값 없는 열은
    /// 이미 배포된 표에 더할 수 없다.
    #[default(0u32)]
    pub attack_skill: u32,

    /// 바라보는 방향(정규화된 그리드 벡터).
    ///
    /// 좌표만으로는 **멈춰 선 사람의 방향**을 알 수 없다. 가만히 서서 몸만 돌려
    /// 사방을 살피는 동작이 남의 화면에서는 통째로 사라지고, 마지막으로 걸었던
    /// 쪽을 계속 바라보는 모습이 된다. PK 가 허용되는 월드에서 상대가 어디를
    /// 보고 있는지는 덤빌지 물러설지를 가르는 정보다.
    ///
    /// 맨 끝에 있고 기본값이 있어야 한다([`sub_chunk`](WorldPlayer::sub_chunk) 와
    /// 같은 이유).
    #[default(0.0f32)]
    pub facing_x: f32,

    #[default(1.0f32)]
    pub facing_y: f32,
}

/// 월드에 상주하는 몬스터 한 마리.
///
/// 자리는 [`spawn_slot`](Monster::spawn_slot) 마다 고정이다. 쓰러져도 행을
/// 지우지 않고 `alive` 만 내리는데, 그래야 되살아날 자리를 잃지 않고 클라이언트도
/// 행이 사라졌다 나타나는 대신 상태 변화로 받아 볼 수 있다.
#[spacetimedb::table(
    accessor = monster,
    public,
    index(accessor = by_alive_died, btree(columns = [alive, died_at])),
    // 몬스터 AI 는 매 틱 **플레이어 근처만** 훑어야 한다. 7,000 기를 전부
    // 순회하면 한 틱이 감당할 수 없다.
    //
    // 좌표(`f32`)에는 범위 인덱스를 걸 수 없어 정수 청크 번호를 따로 둔다.
    // 플레이어가 선 청크와 그 이웃만 조회하면 훑는 수가 수십 기로 줄어든다.
    index(accessor = by_chunk, btree(columns = [chunk])),
    // 구독은 집이 아니라 **지금 있는 자리**로 골라야 한다. 집 청크로 3×3 을
    // 조회하면 확실히 잡히는 것은 반경 32 − MONSTER_MAX_ROAM_TILES(26) = 6 타일
    // 안의 몹뿐이라, 화면 구석의 몹이 아예 오지 않는다.
    index(accessor = by_pos_chunk, btree(columns = [pos_chunk]))
)]
pub struct Monster {
    #[primary_key]
    #[auto_inc]
    pub id: u64,

    /// 고정 스폰 자리 번호. 리스폰하면 같은 자리로 돌아온다.
    #[unique]
    pub spawn_slot: u32,


    /// 계열. 클라이언트 `MonsterBuild` 와 같은 이름을 쓴다
    /// ([`normalize_build`] 가 판정한다).
    pub kind: String,

    pub level: u32,

    /// 배치된 원래 자리. 순찰과 리스폰의 기준점이다.
    pub home_x: f32,
    pub home_y: f32,

    pub grid_x: f32,
    pub grid_y: f32,

    pub hp: i32,
    pub max_hp: i32,
    pub alive: bool,

    /// 이 몹을 선점한 캐릭터. 킬 크레딧의 주인이며, 비어 있으면 아직 아무도
    /// 손대지 않은 몹이다.
    pub tagged_by: Option<u64>,

    /// 태그가 마지막으로 갱신된 시각. [`TAG_TTL_MICROS`] 의 기준이다.
    pub tagged_at: Timestamp,

    /// 쓰러진 시각. 리스폰 판정에만 쓰며 살아 있는 동안의 값은 의미가 없다.
    pub died_at: Timestamp,

    /// 이 몹이 속한 공간 청크. `chunk_of(home_x, home_y)` 로 만든다.
    ///
    /// **집 좌표로 정한다.** 추격하며 움직인 위치로 정하면 청크가 계속 바뀌어
    /// 인덱스를 다시 써야 하고, 어차피 몹은 집에서 멀리 벗어나지 않는다
    /// ([`MONSTER_MAX_ROAM_TILES`]).
    ///
    /// 맨 끝에 있고 기본값이 있어야 한다 — 이미 배포된 표에 열을 더하는
    /// 자동 마이그레이션의 조건이다. 기본값 행은 다음 재배치에서 제 값을 얻는다.
    #[default(0u32)]
    pub chunk: u32,

    /// 구독용 공간 청크. `chunk_of(grid_x, grid_y)` — **지금 있는 자리** 기준이다.
    ///
    /// [`chunk`](Monster::chunk) 와 격자는 같지만([`CHUNK_TILES`]) 기준점이 다르다.
    /// 집 청크는 AI 가 후보를 모을 때 쓰고(집에서 벗어나는 거리가 제한적이라 그쪽은
    /// 그것으로 충분하다), 이쪽은 클라이언트가 화면에 그릴 것을 고를 때 쓴다.
    ///
    /// 격자를 새로 만들지 않고 32 를 그대로 쓰는 이유는 두 가지다. 첫째,
    /// **몬스터는 면적으로 마릿수를 자를 수 없다** — 레벨이 반지름에 선형으로
    /// 배치되어([`cluster_center`]) 밀도가 중심 쪽에서 열 배 넘게 높아지므로,
    /// 어떤 청크 크기를 골라도 평균만 맞고 실제 마릿수는 크게 흔들린다. 마릿수
    /// 상한은 클라이언트가 거리순으로 잘라 만든다. 둘째, 남는 기준은 **화면을
    /// 덮는가** 인데 3×3 의 보장 반경이 곧 한 변이라 32 면 최대 축소 화면도 덮는다.
    /// [`Loot`] 도 같은 격자를 쓰므로 클라이언트가 청크 번호를 한 번만 계산해
    /// 두 구독에 함께 쓸 수 있다.
    ///
    /// 맨 끝에 있고 기본값이 있어야 한다([`chunk`](Monster::chunk) 와 같은 이유).
    #[default(0u32)]
    pub pos_chunk: u32,

    /// 바라보는 방향(정규화된 그리드 벡터).
    ///
    /// **멈춰 있을 때가 이 값이 필요한 이유다.** 움직이는 동안은 좌표 변화로
    /// 방향을 유추할 수 있지만, 사거리 안에 붙어 때리는 몹은 제자리에 선다 —
    /// 그때 화면마다 다른 쪽을 보고 있으면 누구를 노리는지가 사람마다 달라진다.
    ///
    /// 맨 끝에 있고 기본값이 있어야 한다([`chunk`](Monster::chunk) 와 같은 이유).
    #[default(0.0f32)]
    pub face_x: f32,

    #[default(1.0f32)]
    pub face_y: f32,

    /// 마지막으로 **후려친** 시각.
    ///
    /// 서버가 피해를 판정해 체력을 깎기만 하면, 어느 화면에서도 몹이 때리는
    /// 장면이 나오지 않는다 — 몹은 조용히 다가와 서 있고 사람의 체력만 줄어든다.
    /// 무엇에 맞았는지 알 수 없으니 피할 수도, 도우러 갈 수도 없다.
    ///
    /// 값이 **바뀌는 것**을 보고 클라이언트가 타격 동작을 한 번 재생한다
    /// ([`WorldPlayer::last_attack_at`] 과 같은 방식이다). 실제로 때린 틱에만
    /// 쓰므로, 쫓아만 다니는 몹은 이 열을 건드리지 않는다.
    ///
    /// 맨 끝에 있고 기본값이 있어야 한다([`chunk`](Monster::chunk) 와 같은 이유).
    #[default(Timestamp::UNIX_EPOCH)]
    pub last_attack_at: Timestamp,
}

/// 바닥에 떨어진 전리품 하나.
///
/// **드롭도 서버가 정한다.** 클라이언트가 각자 굴리면 같은 몹을 잡고도 사람마다
/// 다른 것을 줍게 되고, 무엇이 떨어졌는지 서로 보이지 않아 "네가 먹어라" 도
/// 성립하지 않는다.
#[spacetimedb::table(
    accessor = loot,
    public,
    index(accessor = by_chunk, btree(columns = [chunk]))
)]
pub struct Loot {
    #[primary_key]
    #[auto_inc]
    pub id: u64,

    /// 클라이언트 `PickupKind` 의 이름. 아는 값만 들어간다([`LOOT_KINDS`]).
    pub kind: String,

    /// 회복량·점수 등 종류에 따른 크기.
    pub amount: u32,

    pub grid_x: f32,
    pub grid_y: f32,

    /// 공간 청크. 주변 전리품만 훑기 위한 것으로 몬스터와 같은 방식이다.
    pub chunk: u32,

    /// 이 시각까지는 **선점자만** 주울 수 있다.
    ///
    /// 잡은 사람이 다가가는 동안 옆에 있던 사람이 낚아채면 선점 규칙이
    /// 무의미해진다. 잠깐의 우선권을 준 뒤 모두에게 연다.
    pub reserved_until: Timestamp,

    /// 우선권을 가진 캐릭터. 몹을 선점했던 사람이다.
    pub reserved_for: Option<u64>,

    pub dropped_at: Timestamp,
}

/// 서버가 인정하는 전리품 종류. 클라이언트 `PickupKind` 와 이름이 같아야 한다.
pub const LOOT_KINDS: [&str; 10] = [
    "nanoVial",
    "nanoCanister",
    "repairCell",
    "regenAmpoule",
    "overhaulKit",
    "energyCell",
    "overchargeCell",
    "combatStim",
    "dataChip",
    "scrapCore",
];

/// 전리품이 바닥에 남아 있는 시간(마이크로초). 3 분.
const LOOT_TTL_MICROS: i64 = 180_000_000;

/// 잡은 사람이 우선권을 갖는 시간(마이크로초). 12 초.
const LOOT_RESERVE_MICROS: i64 = 12_000_000;

/// 주울 수 있는 거리(타일).
const LOOT_PICKUP_TILES: f32 = 2.5;

/// 서버가 확정한 킬 기록.
///
/// "누가 잡았는가" 의 **정답**이다. 클라이언트가 무엇을 그렸든 이 표에 남은
/// 것이 사실이며, 경험치도 이 판정에 따라 지급된다.
#[spacetimedb::table(accessor = monster_kill, public)]
pub struct MonsterKill {
    #[primary_key]
    #[auto_inc]
    pub id: u64,

    /// 크레딧을 가져간 캐릭터. 곧 선점자다.
    #[index(btree)]
    pub character_id: u64,
    pub character_name: String,

    pub monster_kind: String,
    pub monster_level: u32,
    pub xp_awarded: u32,

    /// 막타를 넣은 캐릭터가 선점자와 다를 때만 채워진다.
    ///
    /// 즉 **가로채기 시도의 흔적**이다. 크레딧에는 영향을 주지 않지만, 사냥터
    /// 분쟁이 어디서 일어나는지 나중에 들여다볼 수 있도록 남긴다.
    pub last_hit_by: Option<u64>,

    pub killed_at: Timestamp,
}

/// 쓰러진 몹을 되살리는 정비 타이머.
/// 몬스터 AI 를 주기적으로 깨우는 타이머.
///
/// **서버가 몬스터를 움직인다.** 클라이언트가 각자 굴리면 A 화면에서는 몹이
/// 쫓아오는데 B 화면에서는 제자리인 상태가 되고, "도망치는 동료를 도와준다"
/// 같은 일이 성립하지 않는다. 판정의 주인이 하나여야 협업이 가능하다.
#[spacetimedb::table(accessor = monster_ai_timer, scheduled(monster_ai))]
pub struct MonsterAiTimer {
    #[primary_key]
    #[auto_inc]
    scheduled_id: u64,
    scheduled_at: ScheduleAt,
}

/// 체력·마력 자연 회복을 주기적으로 깨우는 타이머.
///
/// **회복도 서버가 판정한다.** 클라이언트가 스스로 채우면 "안전지대에 있다" 는
/// 주장 하나로 무한히 회복할 수 있고, 그러면 사냥의 압박이 사라진다. 안전지대
/// 안인지도 서버가 자기 좌표로 본다.
#[spacetimedb::table(accessor = regen_timer, scheduled(regen_tick))]
pub struct RegenTimer {
    #[primary_key]
    #[auto_inc]
    scheduled_id: u64,
    scheduled_at: ScheduleAt,
}

#[spacetimedb::table(accessor = monster_tick_timer, scheduled(monster_tick))]
pub struct MonsterTickTimer {
    #[primary_key]
    #[auto_inc]
    pub scheduled_id: u64,
    pub scheduled_at: ScheduleAt,
}

// ── 계열별 수치 ─────────────────────────────────────────────────────────

/// 서버가 인정하는 몬스터 계열.
///
/// 클라이언트 `MonsterBuild` 와 이름이 같아야 한다. 클라이언트가 어떤 계열을
/// 그리든 판정은 서버 값으로 하므로, 목록이 어긋나면 서버 쪽이 정본이다.
pub const MONSTER_BUILDS: [&str; 4] = ["drone", "walker", "siege", "sovereign"];

/// 레벨에서 골격을 정한다. **클라이언트 도감(`MonsterFamily.all`)과 같은 표다.**
///
/// 도감은 `레벨 = 등급 × 20 + 계열 + 1` 로 200 종을 채우므로, 레벨만 알면 계열이
/// 나오고 계열에서 골격이 나온다. 서버가 골격을 무작위로 뽑으면 같은 레벨의
/// 몹이 서버에서는 보행형인데 클라이언트 도감에서는 비행형이 되어, 화면에
/// 그려지는 몸과 서버가 계산한 체력·경험치가 서로 다른 것을 가리키게 된다.
///
/// 이 배열이 클라이언트와 어긋나면 그 순간 두 세계가 갈라진다.
const FAMILY_BUILDS: [&str; 20] = [
    "drone", "drone", "drone", "drone", "drone", // 정찰기 ~ 섬광기
    "walker", "walker", "walker", "walker", // 순찰병 ~ 창병
    "sovereign", // 군주 — 10, 30, 50 … 레벨의 구역 보스
    "siege", "siege", "siege", "siege", "siege", // 방벽 ~ 공성기
    "walker", "walker", // 사냥개 · 결전병
    "siege", "siege", // 수확자 · 처형자
    "sovereign", // 종말 — 20, 40, 60 … 레벨의 구역 대군주
];

/// [`level`] 의 몬스터가 어떤 골격인지.
pub fn build_for_level(level: u32) -> &'static str {
    FAMILY_BUILDS[((level.max(1) - 1) % 20) as usize]
}

/// 계열 이름을 서버가 아는 값으로 정규화한다.
pub fn normalize_build(raw: &str) -> Result<String, String> {
    let build = raw.trim().to_lowercase();
    if MONSTER_BUILDS.contains(&build.as_str()) {
        Ok(build)
    } else {
        Err(format!("알 수 없는 몬스터 계열이다: {raw:?}"))
    }
}

/// 계열별 체력 배율. 클라이언트 `MonsterCodex._statsFor` 의 `baseHp * N` 과 같아야 한다.
///
/// 서버가 판정의 주인이므로 이 값이 정본이고 클라이언트는 표시용 사본이다. 한쪽만
/// 바뀌면 "화면에서는 죽었는데 서버는 살아 있는" 상태가 생긴다.
fn hp_scale(build: &str) -> f32 {
    match build {
        "drone" => 0.72,
        "walker" => 1.15,
        "siege" => 1.6,
        "sovereign" => 2.8,
        _ => 1.0,
    }
}

/// 계열별 경험치 배율. 클라이언트 `MonsterCodex._statsFor` 의 `baseXp * N` 과 같아야 한다.
fn xp_scale(build: &str) -> f64 {
    match build {
        "drone" => 0.8,
        "walker" => 1.0,
        "siege" => 1.45,
        "sovereign" => 4.0,
        _ => 1.0,
    }
}

/// 계열이 나타나는 비율. 앞쪽일수록 흔하다.
fn build_for_roll(roll: u32) -> &'static str {
    match roll % 100 {
        0..=54 => "drone",
        55..=84 => "walker",
        85..=97 => "siege",
        _ => "sovereign",
    }
}

/// 몹 레벨에 따른 체력.
///
/// 클라이언트 `MonsterCodex._statsFor` 의 `baseHp = 26 + (level-1) * 23` 과 같은 식이다.
/// 곡선이 지수가 아니라 선형인 이유는 레벨이 200 까지 뻗기 때문이다 — 지수면 후반
/// 체력이 손댈 수 없게 불어난다.
fn monster_max_hp(build: &str, level: u32) -> i32 {
    let base = MONSTER_BASE_HP + (level.saturating_sub(1) as f32) * MONSTER_HP_PER_LEVEL;
    (base * hp_scale(build)).round() as i32
}

/// 몹을 잡았을 때 주는 경험치. **나누기 전의 총량**이다.
///
/// 잡은 사람의 레벨은 보지 않는다. 혼자 잡았다면 고레벨이 저레벨 사냥터를 쓸어
/// 담아도 얻는 것이 적어 자연히 갈라지기 때문이다.
///
/// 파티가 나눌 때는 이야기가 다르다 — 손 하나 대지 않고 곁에 서 있기만 해도
/// 몫이 오므로 레벨 격차를 따로 본다([`crate::party::split_xp`]).
///
/// 클라이언트 `MonsterCodex._statsFor` 의 `baseXp = 10 + (level-1) * 9` 와 같은 식이다.
fn monster_xp(build: &str, level: u32) -> u32 {
    let base = MONSTER_BASE_XP + (level.saturating_sub(1) as f64) * MONSTER_XP_PER_LEVEL;
    (base * xp_scale(build)).round() as u32
}

/// 캐릭터 레벨에 따른 최대 체력.
///
/// 클라이언트 `Player.baseMaxHp` + `LevelGains.maxHp` 누적과 같아야 한다.
fn max_hp_for_level(level: u32) -> i32 {
    BASE_MAX_HP + (level.saturating_sub(1) as i32) * HP_PER_LEVEL
}

/// 캐릭터 레벨에 따른 최대 마력.
///
/// 클라이언트 `Player.mp` 초기값 5,000 + `LevelGains.maxMp` 누적과 같아야 한다.
fn max_mp_for_level(level: u32) -> i32 {
    BASE_MAX_MP + (level.saturating_sub(1) as i32) * MP_PER_LEVEL
}

/// 레벨 [`level`] 까지 오는 동안 5 레벨 구간(강화 구간)을 몇 번 지났는가.
///
/// 클라이언트 `LevelSystem.gainsFor` 는 `level % 5 == 0` 인 레벨에서 더 큰 성장치를
/// 준다. 레벨업 루프를 돌리지 않고 같은 총합을 얻으려면 그 횟수만 세면 된다.
fn milestones_upto(level: u32) -> i32 {
    (level.max(1) / 5) as i32
}

/// 캐릭터가 근접 한 대에 넣는 피해.
///
/// 장비가 아직 없으므로 레벨만 본다. 클라이언트가 보낸 값은 쓰지 않는다.
/// 클라이언트 `Player.meleeDamage`(26 에서 시작, 레벨당 +4.5, 5 레벨마다 +8.0)와
/// 같은 값이어야 한다.
fn player_damage(level: u32) -> i32 {
    let steps = level.saturating_sub(1) as f32;
    (MELEE_BASE_DAMAGE + steps * MELEE_PER_LEVEL
        + milestones_upto(level) as f32 * MELEE_MILESTONE_BONUS)
        .round() as i32
}

/// 캐릭터가 원거리 한 발에 넣는 피해.
///
/// 클라이언트 `Player.rangedDamage`(18 에서 시작, 레벨당 +3.0, 5 레벨마다 +5.5)와
/// 같은 값이어야 한다.
fn player_ranged_damage(level: u32) -> i32 {
    let steps = level.saturating_sub(1) as f32;
    (RANGED_BASE_DAMAGE + steps * RANGED_PER_LEVEL
        + milestones_upto(level) as f32 * RANGED_MILESTONE_BONUS)
        .round() as i32
}

/// 방어력을 적용한 뒤 실제로 깎이는 피해.
///
/// 감산형(`피해 - 방어력`)이 아니라 승수형인 이유는 몬스터 레벨이 1~200 으로 넓고
/// 구역마다 레벨대가 묶여 배치되기 때문이다. 감산형이면 방어력이 조금만 올라도
/// 저레벨 구역 하나가 통째로 무해해진다. 클라이언트 `Player.damageAfterDefense`
/// 와 같은 식이다.
///
/// 방어력이 0 이면 받는 피해는 때린 몬스터의 레벨과 정확히 같다 — 이것이 기획 규격이다.
fn damage_after_defense(amount: i32, defense: i32) -> i32 {
    if defense <= 0 {
        return amount.max(0);
    }
    let reduced =
        (amount as f32) * DEFENSE_CONSTANT as f32 / (DEFENSE_CONSTANT + defense) as f32;
    reduced.round().max(0.0) as i32
}

// ── 좌표 헬퍼 ───────────────────────────────────────────────────────────

/// 월드 한가운데. 안전지대의 중심이자 입장 지점이다.
fn world_center() -> (f32, f32) {
    (WORLD_TILES / 2.0, WORLD_TILES / 2.0)
}

/// 공간 청크 한 변의 길이(타일).
///
/// 어그로·추격 거리(9~16 타일)보다 넉넉히 커야 이웃 청크 하나만 함께 봐도
/// 놓치는 몹이 없다.
const CHUNK_TILES: f32 = 32.0;

/// 한 줄에 들어가는 청크 수.
const CHUNKS_PER_ROW: u32 = (WORLD_TILES / CHUNK_TILES) as u32 + 1;

/// 좌표가 속한 청크 번호.
pub fn chunk_of(x: f32, y: f32) -> u32 {
    let cx = (x / CHUNK_TILES).max(0.0) as u32;
    let cy = (y / CHUNK_TILES).max(0.0) as u32;
    cy * CHUNKS_PER_ROW + cx
}

/// 플레이어 구독용 청크 한 변(타일). 3×3 을 구독하므로 **AOI 는 96×96 m** 다
/// (타일 = 미터, `kMetersPerTile`).
///
/// 구독 SQL 에는 `LIMIT` 도 거리 정렬도 없어 "가까운 50 명" 을 쿼리로 표현할 수
/// 없으므로, 인원은 면적으로 근사할 수밖에 없다.
///
/// **74 에서 32 로 줄였다.** 74 는 "동접 1,000 명이 고르게 퍼졌을 때 3×3 에
/// 50 명" 에서 역산한 값이었지만(222×222 m), 인원 상한은 이미 클라이언트가
/// 거리순으로 만들고 있다(`ActionRpgGame._maxRemotePlayers`). 그러니 면적은
/// 인원이 아니라 **화면**에 맞추는 것이 옳다 — 화면 밖 사람의 좌표는 받아도
/// 그릴 곳이 없다. 면적이 5.3 분의 1 이 되므로 퍼져 있을 때 받는 델타도 그만큼
/// 줄어든다.
///
/// 🛑 **이 값의 하한을 정하는 것은 부하가 아니라 보장 반경이다.** 3×3 구독에서
/// 어디에 서 있든 반드시 들어오는 반경은 청크 한 변과 같다. 화면이 그보다 넓게
/// 보이면(최대 축소) 청크 경계에 선 사람은 **화면 안쪽의 요원을 놓친다** — 그가
/// 월드에서 나간 것과 구별할 수 없어 조용히 사라진다.
///
/// ```text
/// 최대 축소에서 화면이 덮는 반경 (타일 128×64px, 줌 = clamp(h/760, .55, 1.6) × .5)
///   1080p  0.71 → 21~34 타일
///   4K     0.80 → 37~42 타일
/// ```
///
/// 32 는 [`CHUNK_TILES`] 와 같은 값이며, 그쪽 문서가 "3×3 의 보장 반경이 곧
/// 한 변이라 32 면 최대 축소 화면도 덮는다" 고 적어 둔 그 근거를 공유한다.
/// **더 줄이려면** 이 값을 낮추는 대신 ring 을 넓히고 청크를 잘게 나눠야 한다 —
/// 같은 면적에서 격자가 촘촘할수록 경계 손실이 줄기 때문이다(ring=2·C=19 면
/// 95 m 에 보장 반경 38 m).
///
/// ⚠️ **뭉쳐 있을 때는 면적이 아무것도 해 주지 않는다.** 구독은 서로를 향하므로
/// 한자리에 모인 N 명은 N² 쌍의 델타를 만드는데, 그 N 은 면적이 아니라 **모인
/// 사람 수**가 정한다. 좁혀도 50 명이 모이면 여전히 초당 6 만 행이다. 그쪽은
/// **갱신 빈도를 거리로 차등**해야 풀린다.
///
/// 면적으로 자른 인원은 **평균이지 상한이 아니다.** 안전지대처럼 사람이 몰리는
/// 곳에서는 그대로 인원수만큼 온다.
pub const PLAYER_SUB_CHUNK_TILES: f32 = 32.0;

/// 한 줄에 들어가는 플레이어 구독 청크 수.
pub const PLAYER_SUB_CHUNKS_PER_ROW: u32 = (WORLD_TILES / PLAYER_SUB_CHUNK_TILES) as u32 + 1;

/// 좌표가 속한 플레이어 구독 청크 번호.
///
/// 클라이언트 `kPlayerSubChunkTiles` 와 같은 식이어야 한다 — 어긋나면 서로를
/// 영영 보지 못한다.
pub fn player_sub_chunk_of(x: f32, y: f32) -> u32 {
    let cx = (x / PLAYER_SUB_CHUNK_TILES).max(0.0) as u32;
    let cy = (y / PLAYER_SUB_CHUNK_TILES).max(0.0) as u32;
    cy * PLAYER_SUB_CHUNKS_PER_ROW + cx
}

/// 안전지대 안인가.
///
/// 클라이언트 [`SafeZone`] 과 같은 축 정렬 사각형 판정이다. 몹은 여기에 발을
/// 들이지 못한다.
pub fn in_safe_zone(x: f32, y: f32) -> bool {
    let (cx, cy) = world_center();
    let half = SAFE_ZONE_TILES / 2.0;
    (x - cx).abs() <= half && (y - cy).abs() <= half
}

/// 두 점 사이 거리의 제곱. 제곱근을 피해 비교만 한다.
fn dist_sq(ax: f32, ay: f32, bx: f32, by: f32) -> f32 {
    let dx = ax - bx;
    let dy = ay - by;
    dx * dx + dy * dy
}

/// 두 시각의 차이(마이크로초). `later` 가 앞서면 음수다.
fn micros_between(later: Timestamp, earlier: Timestamp) -> i64 {
    later.to_micros_since_unix_epoch() - earlier.to_micros_since_unix_epoch()
}

// ── 초기 배치 ───────────────────────────────────────────────────────────

/// 월드를 처음 세운다. [`crate::init`] 이 부른다.
///
/// 이미 몹이 있으면 아무것도 하지 않으므로, 모듈을 다시 배포해도 사냥터가
/// 통째로 리셋되지 않는다.
pub fn bootstrap(ctx: &ReducerContext) {
    // 타이머부터 확인한다. 몹이 이미 있어 아래에서 돌아 나가더라도 주기 작업은
    // 돌고 있어야 한다 — 이 순서를 뒤집으면 재배포 뒤 AI 와 리스폰이 조용히
    // 멈춘 채로 남고, 몹이 그냥 안 움직이는 것처럼 보인다.
    ensure_timers(ctx);

    if ctx.db.monster().count() > 0 {
        log::info!("월드가 이미 서 있다. 몬스터 배치를 건너뛴다.");
        return;
    }

    let mut slot: u32 = 0;
    let mut placed: u32 = 0;

    // 레벨 1 부터 200 까지 한 단계도 빠뜨리지 않고, 각 레벨을 서로 다른
    // 지역 [`CLUSTERS_PER_LEVEL`] 곳에 군집으로 심는다.
    for level in 1..=MONSTER_MAX_LEVEL {
        for sector in 0..CLUSTERS_PER_LEVEL {
            let (cx, cy) = cluster_center(ctx, level, sector);
            let count = CLUSTER_MIN + (ctx.random::<u32>() % (CLUSTER_MAX - CLUSTER_MIN + 1));

            for _ in 0..count {
                if slot >= MONSTER_CAPACITY {
                    break;
                }
                // 군집 중심 둘레에 흩어 놓는다. 정확히 겹치면 한 마리처럼 보인다.
                let (x, y) = scatter_around(ctx, cx, cy, CLUSTER_RADIUS);
                let build = build_for_roll(ctx.random::<u32>());
                let max_hp = monster_max_hp(build, level);

                ctx.db.monster().insert(Monster {
                    id: 0,
                    spawn_slot: slot,
                    kind: build.to_string(),
                    level,
                    home_x: x,
                    home_y: y,
                    // 처음에는 화면 아래쪽(플레이어 기준 정면)을 본다. 첫
                    // 추격에서 제 방향을 얻는다.
                    face_x: 0.0,
                    face_y: 1.0,
                    last_attack_at: Timestamp::UNIX_EPOCH,
                    grid_x: x,
                    grid_y: y,
                    chunk: chunk_of(x, y),
                    // 갓 배치된 몹은 집에 서 있으므로 두 청크가 같은 값에서 출발한다.
                    pos_chunk: chunk_of(x, y),
                    hp: max_hp,
                    max_hp,
                    alive: true,
                    tagged_by: None,
                    tagged_at: ctx.timestamp,
                    died_at: ctx.timestamp,
                });
                slot += 1;
                placed += 1;
            }
        }
    }

    log::info!(
        "몬스터 {placed} 마리를 레벨 1~{MONSTER_MAX_LEVEL} × 지역 {CLUSTERS_PER_LEVEL} 곳의 군집으로 배치했다."
    );
}

/// 월드가 비어 있으면 몬스터를 채운다.
///
/// [`crate::init`] 은 데이터베이스가 **처음 만들어질 때 한 번만** 돈다. 그래서
/// 이미 서 있는 데이터베이스에 이 모듈을 새로 올리면 몹이 하나도 없는 월드가
/// 된다. 데이터를 지우고 다시 만들면 될 일이지만 그러면 계정과 캐릭터가 함께
/// 사라지므로, 배치만 따로 부를 수 있게 열어 둔다.
///
/// **여러 번 불러도 안전하다.** 몹이 이미 있으면 아무것도 하지 않는다. 그래서
/// 호출자를 가리지 않는다 — 누가 부르든 할 수 있는 일은 "아직 비어 있는 월드를
/// 채우는 것" 하나뿐이고, 그것은 어차피 일어나야 하는 일이다.
/// 주기 작업 타이머가 돌고 있는지 확인하고, 없으면 건다.
///
/// 표를 선언하는 것만으로는 아무것도 돌지 않는다 — **행을 하나 넣어야** 그때부터
/// 주기 실행이 시작된다. 이걸 빠뜨리면 리스폰도 AI 도 조용히 멈춰 있고, 몹이
/// 그냥 안 움직이는 것처럼 보여 원인을 찾기 어렵다.
///
/// 여러 번 불러도 안전하다. 이미 있으면 더 넣지 않는다.
fn ensure_timers(ctx: &ReducerContext) {
    if ctx.db.monster_tick_timer().count() == 0 {
        ctx.db.monster_tick_timer().insert(MonsterTickTimer {
            scheduled_id: 0,
            scheduled_at: ScheduleAt::Interval(
                std::time::Duration::from_secs(MONSTER_TICK_SECS).into(),
            ),
        });
        log::info!("몬스터 정비 타이머를 걸었다({MONSTER_TICK_SECS}초 주기).");
    }

    // **주기를 바꿨으면 다시 걸어야 한다.** 스케줄 행은 한 번 넣으면 그 값으로
    // 계속 도므로, 상수만 고쳐 배포하면 코드와 실제 주기가 조용히 어긋난다.
    // 실측으로 확인한 함정이다 — 300ms 를 150ms 로 바꿔 배포했는데 로그의
    // 간격은 그대로 300ms 였다.
    let ai_interval: TimeDuration =
        std::time::Duration::from_micros(MONSTER_AI_MICROS).into();
    let ai_stale = ctx
        .db
        .monster_ai_timer()
        .iter()
        .any(|t| t.scheduled_at != ScheduleAt::Interval(ai_interval));
    if ai_stale {
        for timer in ctx.db.monster_ai_timer().iter().collect::<Vec<_>>() {
            ctx.db
                .monster_ai_timer()
                .scheduled_id()
                .delete(timer.scheduled_id);
        }
        log::info!("몬스터 AI 타이머 주기가 달라 다시 건다.");
    }
    if ctx.db.monster_ai_timer().count() == 0 {
        ctx.db.monster_ai_timer().insert(MonsterAiTimer {
            scheduled_id: 0,
            scheduled_at: ScheduleAt::Interval(ai_interval),
        });
        log::info!("몬스터 AI 타이머를 걸었다({MONSTER_AI_MICROS}μs 주기).");
    }

    if ctx.db.regen_timer().count() == 0 {
        ctx.db.regen_timer().insert(RegenTimer {
            scheduled_id: 0,
            scheduled_at: ScheduleAt::Interval(
                std::time::Duration::from_millis(REGEN_TICK_MILLIS).into(),
            ),
        });
        log::info!("회복 타이머를 걸었다({REGEN_TICK_MILLIS}ms 주기).");
    }
}

/// 주기 작업 타이머를 지금 상수로 다시 건다.
///
/// [`ensure_timers`] 는 배포 훅에서도 돌지만, 그 훅이 실제로 도는지는 서버
/// 구현에 달려 있다. 주기를 바꿨는데 로그의 간격이 그대로일 때 **확실하게**
/// 손볼 수 있는 길이 하나 필요하다.
///
/// ⚠️ 운영용이다. 부르는 순간 옛 주기의 스케줄 행이 지워지고 새로 걸린다.
#[spacetimedb::reducer]
pub fn reset_timers(ctx: &ReducerContext) {
    for timer in ctx.db.monster_ai_timer().iter().collect::<Vec<_>>() {
        ctx.db
            .monster_ai_timer()
            .scheduled_id()
            .delete(timer.scheduled_id);
    }
    for timer in ctx.db.monster_tick_timer().iter().collect::<Vec<_>>() {
        ctx.db
            .monster_tick_timer()
            .scheduled_id()
            .delete(timer.scheduled_id);
    }
    for timer in ctx.db.regen_timer().iter().collect::<Vec<_>>() {
        ctx.db.regen_timer().scheduled_id().delete(timer.scheduled_id);
    }
    ensure_timers(ctx);
    log::info!("타이머를 모두 다시 걸었다.");
}

/// 몬스터를 전부 걷어내고 지금 규칙으로 다시 심는다.
///
/// 배치 규칙(레벨 대역·지역 수·군집 크기)을 바꿔도 [`bootstrap`] 은 이미 몹이
/// 있으면 아무것도 하지 않으므로 옛 배치가 그대로 남는다. 그렇다고 데이터를
/// 통째로 지우면 계정과 캐릭터까지 사라진다. **몬스터만** 다시 세우는 길이 필요하다.
///
/// ⚠️ 운영용이다. 부르는 순간 살아 있던 몹이 전부 사라지므로, 사냥 중이던
/// 사람은 눈앞의 대상을 잃는다. 선점 태그와 함께 없어질 뿐 경험치 기록
/// ([`MonsterKill`])과 캐릭터 성장은 그대로다.
#[spacetimedb::reducer]
pub fn rebuild_monsters(ctx: &ReducerContext) -> Result<(), String> {
    let ids: Vec<u64> = ctx.db.monster().iter().map(|m| m.id).collect();
    let removed = ids.len();
    for id in ids {
        ctx.db.monster().id().delete(id);
    }
    log::info!("몬스터 {removed} 마리를 걷어냈다. 다시 심는다.");

    bootstrap(ctx);
    Ok(())
}

#[spacetimedb::reducer]
pub fn ensure_world_populated(ctx: &ReducerContext) -> Result<(), String> {
    bootstrap(ctx);
    Ok(())
}

/// 안전지대를 피해 몹 자리를 하나 고른다.
///
/// 지금은 쓰이지 않는다 — 최초 배치가 레벨별 군집([`cluster_center`])으로
/// 바뀌었기 때문이다. 무작위 한 자리가 필요해질 때를 위해 남겨 둔다.
#[allow(dead_code)]
fn pick_spawn_point(ctx: &ReducerContext) -> (f32, f32) {
    // 가장자리는 지형이 끊겨 있으므로 안쪽으로만 놓는다.
    const MARGIN: f32 = 24.0;
    let span = WORLD_TILES - MARGIN * 2.0;

    for _ in 0..32 {
        let x = MARGIN + (ctx.random::<u32>() % span as u32) as f32;
        let y = MARGIN + (ctx.random::<u32>() % span as u32) as f32;
        // 안전지대에 조금이라도 걸치면 다시 뽑는다.
        if !in_safe_zone(x, y) {
            return (x, y);
        }
    }

    // 32 번을 내리 실패할 확률은 사실상 없지만, 그때는 안전지대 바로 바깥에 둔다.
    let (cx, cy) = world_center();
    (cx + SAFE_ZONE_TILES, cy + SAFE_ZONE_TILES)
}

/// [`level`] 군집을 [`sector`] 번째 지역에 놓을 자리.
///
/// 월드는 **중심에서의 거리 × 방위**로 나뉜 격자다.
///
/// - **거리가 레벨 대역을 정한다.** 안전지대를 갓 나선 사람이 1 레벨 무리를
///   만나고, 깊이 들어갈수록 험해진다. 난이도를 지도 위의 거리로 읽을 수 있게
///   하려는 것이고, 그래야 "더 멀리 나가 볼까" 가 성장의 동기가 된다.
/// - **방위가 지역을 가른다.** 같은 레벨의 군집이 둘레를 [`CLUSTERS_PER_LEVEL`]
///   등분한 자리에 하나씩 놓이므로, 어느 쪽으로 나서든 제 수준의 사냥터를
///   만난다. 한 곳뿐이면 반대편으로 나선 사람에게는 그 레벨대가 없는 셈이다.
fn cluster_center(ctx: &ReducerContext, level: u32, sector: u32) -> (f32, f32) {
    let (cx, cy) = world_center();

    // 안전지대 밖에서 시작해 월드 가장자리 안쪽까지. 레벨을 그 구간에 편다.
    let inner = SAFE_ZONE_TILES / 2.0 + 12.0;
    let outer = WORLD_TILES / 2.0 - 24.0;
    let t = (level.saturating_sub(1)) as f32 / (MONSTER_MAX_LEVEL - 1).max(1) as f32;

    // 같은 레벨의 세 군집이 정확히 같은 원 위에 서면 경계가 자로 그은 듯
    // 보인다. 대역 안에서 조금씩 흔들어 지역의 윤곽을 흐린다.
    let band = (outer - inner) / MONSTER_MAX_LEVEL as f32;
    let wobble = ((ctx.random::<u32>() % 2048) as f32 / 2048.0 - 0.5) * band * 6.0;
    let radius = (inner + (outer - inner) * t + wobble).clamp(inner, outer);

    // 둘레를 지역 수만큼 등분하고, 자기 몫 안에서만 흔든다. 그래야 세 군집이
    // 한쪽에 뭉치지 않고 고르게 퍼진다.
    let slice = 1.0 / CLUSTERS_PER_LEVEL as f32;
    let jitter = (ctx.random::<u32>() % 1024) as f32 / 1024.0 * slice;
    let turn = sector as f32 * slice + jitter;
    let (dx, dy) = ring_direction(turn);

    let x = (cx + dx * radius).clamp(24.0, WORLD_TILES - 24.0);
    let y = (cy + dy * radius).clamp(24.0, WORLD_TILES - 24.0);

    // 안전지대와 겹치면 바깥으로 밀어낸다. 몹이 쉬는 곳까지 따라오면 안 된다.
    if in_safe_zone(x, y) {
        return (cx + radius.max(inner), cy);
    }
    (x, y)
}

/// 0~1 의 [`turn`] 을 정사각형 둘레 위의 단위 방향으로 바꾼다.
///
/// 원이 아니라 사각형이라 대각선 쪽이 약간 멀지만, 몬스터 배치에서는 그 차이가
/// 보이지 않는다. 부동소수 삼각함수를 쓰지 않으므로 결과가 플랫폼에 좌우되지도
/// 않는다.
fn ring_direction(turn: f32) -> (f32, f32) {
    let t = turn.clamp(0.0, 1.0) * 4.0;
    match t as u32 {
        0 => (1.0, t - 1.0),
        1 => (1.0 - (t - 1.0) * 2.0, 1.0),
        2 => (-1.0, 1.0 - (t - 2.0) * 2.0),
        _ => ((t - 3.0) * 2.0 - 1.0, -1.0),
    }
}

/// 군집 중심 둘레에 한 마리를 흩어 놓는다.
fn scatter_around(ctx: &ReducerContext, cx: f32, cy: f32, radius: f32) -> (f32, f32) {
    for _ in 0..16 {
        let span = (radius * 2.0) as u32 + 1;
        let ox = (ctx.random::<u32>() % span) as f32 - radius;
        let oy = (ctx.random::<u32>() % span) as f32 - radius;
        let x = (cx + ox).clamp(24.0, WORLD_TILES - 24.0);
        let y = (cy + oy).clamp(24.0, WORLD_TILES - 24.0);
        if !in_safe_zone(x, y) {
            return (x, y);
        }
    }
    (cx, cy)
}

// ── reducer ─────────────────────────────────────────────────────────────

/// 고른 캐릭터로 월드에 들어간다.
///
/// 들어가는 자리는 항상 안전지대 한가운데다. 마지막 위치에서 이어 시작하면
/// 사냥터 한복판에서 로그아웃해 위험을 회피하는 짓이 통하기 때문이다.
#[spacetimedb::reducer]
pub fn enter_world(ctx: &ReducerContext, grid_x: f32, grid_y: f32) -> Result<(), String> {
    let session = crate::require_session(ctx)?;
    let character_id = session
        .selected_character_id
        .ok_or_else(|| "플레이할 캐릭터를 먼저 골라라.".to_string())?;

    let character = ctx
        .db
        .player_character()
        .id()
        .find(character_id)
        .ok_or_else(|| "캐릭터를 찾을 수 없다.".to_string())?;

    // 세션에서 도출한 캐릭터이므로 소유자 확인이 한 번 더 필요하지는 않지만,
    // 세션과 캐릭터가 어긋난 상태로 들어오는 길을 아예 막아 둔다.
    if character.account_id != session.account_id {
        return Err("캐릭터를 찾을 수 없다.".to_string());
    }

    // 같은 캐릭터가 다른 기기에서 이미 월드에 있으면 그쪽을 내보낸다.
    // `character_id` 가 unique 라 두 행이 공존할 수 없고, 남겨 두면 새 접속이
    // 영영 들어오지 못한다.
    if let Some(existing) = ctx.db.world_player().character_id().find(character_id) {
        if existing.identity != ctx.sender() {
            ctx.db.world_player().identity().delete(existing.identity);
        }
    }

    // 입장 좌표는 **클라이언트가 정한다.** 지형을 아는 것은 그쪽뿐이고, 서버가
    // 중심에 고정하면 실제 몸이 선 자리와 어긋난다. 그 어긋남은 눈에 잘 띄지
    // 않으면서 치명적이다 — `move_to` 는 속도 상한(14타일/초)에 걸려 그 간격을
    // 몇 초에 걸쳐 좁히고, 그동안 다른 요원의 화면에는 엉뚱한 곳에 서 있거나
    // 아예 화면 밖에 있다. "움직여야 비로소 보인다" 는 증상이 여기서 나온다.
    //
    // 대신 **안전지대 안인지**만 검증한다. 아무 데나 나타날 수 있으면 입장이
    // 곧 무제한 텔레포트가 된다. 안전지대는 어차피 모두가 시작하는 자리다.
    let (cx, cy) = world_center();
    let (spawn_x, spawn_y) = if grid_x.is_finite()
        && grid_y.is_finite()
        && in_safe_zone(grid_x, grid_y)
    {
        (grid_x, grid_y)
    } else {
        (cx, cy)
    };

    let max_hp = max_hp_for_level(character.level);
    let max_mp = max_mp_for_level(character.level);

    // 이미 월드에 있던 행이면 사망 누계를 이어받는다. 0 으로 되돌리면 재접속이
    // 사망 기록을 지우는 수단이 되고, 클라이언트는 줄어든 수를 사망으로 읽지 않는다.
    let deaths = ctx
        .db
        .world_player()
        .identity()
        .find(ctx.sender())
        .map(|existing| existing.deaths)
        .unwrap_or(0);

    let player = WorldPlayer {
        identity: ctx.sender(),
        character_id,
        name: character.name,
        kind: character.kind,
        level: character.level,
        grid_x: spawn_x,
        grid_y: spawn_y,
        hp: max_hp,
        max_hp,
        alive: true,
        next_attack_at: ctx.timestamp,
        last_move_at: ctx.timestamp,
        entered_at: ctx.timestamp,
        next_teleport_at: ctx.timestamp,
        next_hurt_at: ctx.timestamp,
        mp: max_mp,
        max_mp,
        // 방어력을 얻는 경로가 아직 없다. 축만 세워 두고 값은 0 이다.
        defense: 0,
        deaths,
        // 입장 지점은 안전지대라 어차피 면역이지만, 밖으로 걸어 나가는 순간까지
        // 이어지도록 짧은 유예를 준다.
        invulnerable_until: ctx.timestamp
            + TimeDuration::from_micros(RESPAWN_INVULNERABLE_MICROS),
        last_damaged_at: Timestamp::UNIX_EPOCH,
        sub_chunk: player_sub_chunk_of(spawn_x, spawn_y),
        // 아직 아무것도 휘두르지 않았다. epoch 로 두면 클라이언트가 "값이
        // 바뀌었다" 로 오인해 입장하자마자 헛손질을 그리는 일이 없다.
        last_attack_at: Timestamp::UNIX_EPOCH,
        attack_dir_x: 0.0,
        attack_dir_y: 0.0,
        attack_skill: ATTACK_SKILL_NONE,
        // 입장할 때는 화면 아래쪽을 본다. 첫 보고에서 제 방향을 얻는다.
        facing_x: 0.0,
        facing_y: 1.0,
    };

    match ctx.db.world_player().identity().find(ctx.sender()) {
        Some(_) => ctx.db.world_player().identity().update(player),
        None => ctx.db.world_player().insert(player),
    };

    Ok(())
}

/// 월드에서 나간다.
#[spacetimedb::reducer]
pub fn leave_world(ctx: &ReducerContext) -> Result<(), String> {
    // 파티는 접속과 함께 끝난다. 캐릭터를 알아내려면 행을 지우기 전에 읽어야 한다.
    if let Some(me) = ctx.db.world_player().identity().find(ctx.sender()) {
        crate::party::on_character_left(ctx, me.character_id);
    }
    ctx.db.world_player().identity().delete(ctx.sender());
    Ok(())
}

/// 지금 위치를 보고한다.
///
/// 클라이언트가 좌표를 보내고 서버는 **속도 상한만** 본다([`MAX_MOVE_SPEED`]).
/// 상한을 넘으면 거절하는 대신 갈 수 있는 데까지만 당겨서 받아들인다. 거절하면
/// 지연이 한 번 튈 때마다 화면이 뒤로 끌려가 조작감이 무너지기 때문이다.
#[spacetimedb::reducer]
pub fn move_to(
    ctx: &ReducerContext,
    grid_x: f32,
    grid_y: f32,
    facing_x: f32,
    facing_y: f32,
) -> Result<(), String> {
    let me = require_world_player(ctx)?;

    // 쓰러진 몸은 걷지 않는다. 이 검사가 없으면 사망 판정과 재가동 사이에 들어온
    // 좌표 보고가 시체를 사냥터로 되돌려 놓는다.
    if !me.alive {
        return Err("쓰러진 상태다.".to_string());
    }

    if !grid_x.is_finite() || !grid_y.is_finite() {
        return Err("좌표가 올바르지 않다.".to_string());
    }
    // 걸을 수 있는 격자는 `[WORLD_EDGE_MARGIN, WORLD_TILES - WORLD_EDGE_MARGIN)`
    // 이고 상한은 배타적이다. `clamp` 는 상한을 포함하므로 한 틱 안쪽으로 당겨,
    // 클라이언트에서 설 수 없는 테두리 좌표를 서버가 받아들이지 않게 한다.
    let x = grid_x.clamp(WORLD_EDGE_MARGIN, PLAYABLE_MAX);
    let y = grid_y.clamp(WORLD_EDGE_MARGIN, PLAYABLE_MAX);

    let elapsed = micros_between(ctx.timestamp, me.last_move_at).max(0) as f32 / 1_000_000.0;
    let budget = MAX_MOVE_SPEED * elapsed.max(0.05);

    let moved_sq = dist_sq(x, y, me.grid_x, me.grid_y);
    let (next_x, next_y) = if moved_sq <= budget * budget {
        (x, y)
    } else {
        // 상한을 넘은 만큼 잘라 낸다. 방향은 보고한 그대로 둔다.
        let moved = moved_sq.sqrt();
        let ratio = budget / moved;
        (
            me.grid_x + (x - me.grid_x) * ratio,
            me.grid_y + (y - me.grid_y) * ratio,
        )
    };

    // 방향은 자르지 않고 그대로 받는다. 속도 상한과 달리 방향은 아무리 빨리
    // 돌려도 부정이 되지 않는다 — 제자리에서 몸을 도는 것은 원래 즉시 되는 일이다.
    // 다만 쓰레기 값이 들어오면 남의 화면에서 몸이 엉뚱하게 서므로 검사는 한다.
    let (fx, fy) = if facing_x.is_finite()
        && facing_y.is_finite()
        && (facing_x * facing_x + facing_y * facing_y) > 0.0001
    {
        let len = (facing_x * facing_x + facing_y * facing_y).sqrt();
        (facing_x / len, facing_y / len)
    } else {
        (me.facing_x, me.facing_y)
    };

    ctx.db.world_player().identity().update(WorldPlayer {
        grid_x: next_x,
        grid_y: next_y,
        sub_chunk: player_sub_chunk_of(next_x, next_y),
        last_move_at: ctx.timestamp,
        facing_x: fx,
        facing_y: fy,
        ..me
    });

    Ok(())
}

/// 텔레포트 목적지. 클라이언트 `TeleportDestination` 과 같은 곳을 가리켜야 한다.
///
/// 이름을 서버가 갖는 이유는 [`teleport_to`] 가 좌표가 아니라 **목적지**를 받기
/// 때문이다. 목적지가 늘면 여기와 클라이언트를 함께 고친다.
pub const TELEPORT_DESTINATIONS: [&str; 5] = ["safe_zone", "north", "east", "south", "west"];

/// 목적지의 기준점. 착지 검증의 중심이 된다.
fn teleport_anchor(destination: &str) -> Option<(f32, f32)> {
    let (cx, cy) = world_center();
    let inset = TELEPORT_EDGE_INSET;
    match destination {
        "safe_zone" => Some((cx, cy)),
        "north" => Some((cx, inset)),
        "east" => Some((WORLD_TILES - inset, cy)),
        "south" => Some((cx, WORLD_TILES - inset)),
        "west" => Some((inset, cy)),
        _ => None,
    }
}

/// 정해진 목적지로 순간이동한다.
///
/// ## 왜 좌표가 아니라 목적지를 받는가
///
/// [`move_to`] 는 속도 상한으로 순간이동을 막는다. 텔레포트는 그 상한을 정당하게
/// 넘는 유일한 이동이므로 **검사를 건너뛸 구멍**이 되기 쉽다. 클라이언트가 도착
/// 좌표를 정하게 두면 "아무 데나 순간이동" 과 구별할 방법이 없어진다. 그래서
/// 목적지 이름만 받고, 그 이름이 가리키는 곳은 서버가 안다.
///
/// ## 착지점은 왜 그래도 받는가
///
/// 목적지 기준점이 통행 불가일 수 있어 클라이언트가 근처로 보정한다(지형은
/// 클라이언트만 안다). 서버는 그 보정을 재현할 수 없으므로 **기준점에서 얼마나
/// 벗어났는지**만 본다([`TELEPORT_LANDING_SLACK`]). 목적지 다섯 곳 주변으로
/// 범위가 좁혀지므로, 임의 좌표를 받는 것과는 위험이 다르다.
#[spacetimedb::reducer]
pub fn teleport_to(
    ctx: &ReducerContext,
    destination: String,
    grid_x: f32,
    grid_y: f32,
) -> Result<(), String> {
    let me = require_world_player(ctx)?;
    if !me.alive {
        return Err("쓰러진 상태다.".to_string());
    }
    if ctx.timestamp < me.next_teleport_at {
        return Err("아직 텔레포트할 수 없다.".to_string());
    }

    let name = destination.trim().to_lowercase();
    let (ax, ay) =
        teleport_anchor(&name).ok_or_else(|| format!("알 수 없는 목적지다: {destination:?}"))?;

    if !grid_x.is_finite() || !grid_y.is_finite() {
        return Err("좌표가 올바르지 않다.".to_string());
    }
    if dist_sq(grid_x, grid_y, ax, ay) > TELEPORT_LANDING_SLACK * TELEPORT_LANDING_SLACK {
        return Err("착지점이 목적지에서 너무 멀다.".to_string());
    }

    ctx.db.world_player().identity().update(WorldPlayer {
        grid_x,
        grid_y,
        sub_chunk: player_sub_chunk_of(grid_x, grid_y),
        // 도착 직후의 이동 보고가 "방금 470 타일을 뛰었다" 로 읽히지 않도록
        // 기준 시각을 함께 민다. 이걸 빼먹으면 텔레포트 다음 한 번의 `move_to`
        // 가 상한에 걸려 잘린다.
        last_move_at: ctx.timestamp,
        next_teleport_at: ctx.timestamp + TimeDuration::from_micros(TELEPORT_COOLDOWN_MICROS),
        ..me
    });

    Ok(())
}

/// 몬스터를 한 대 친다. **이 모듈의 핵심이다.**
///
/// 클라이언트는 "몇 번 몹을 친다" 는 의도만 보낸다. 피해량도, 사거리도, 쿨다운도
/// 서버가 자기가 가진 값으로 정한다. 클라이언트가 피해량을 보내는 구조였다면
/// 여기서 하는 판정이 전부 무의미해진다.
#[spacetimedb::reducer]
pub fn attack_monster(ctx: &ReducerContext, monster_id: u64) -> Result<(), String> {
    let me = require_world_player(ctx)?;
    if !me.alive {
        return Err("쓰러진 상태다.".to_string());
    }
    if ctx.timestamp < me.next_attack_at {
        return Err("아직 공격할 수 없다.".to_string());
    }

    let mut monster = ctx
        .db
        .monster()
        .id()
        .find(monster_id)
        .ok_or_else(|| "몬스터를 찾을 수 없다.".to_string())?;

    // 같은 몹에 막타가 동시에 들어왔을 때, 진 쪽이 걸리는 자리가 여기다.
    // 트랜잭션이 직렬화되므로 나중 호출은 반드시 `alive == false` 를 본다.
    if !monster.alive {
        return Err("이미 쓰러진 몬스터다.".to_string());
    }

    // 사거리는 서버가 가진 좌표로만 본다.
    if dist_sq(me.grid_x, me.grid_y, monster.grid_x, monster.grid_y)
        > ATTACK_RANGE_TILES * ATTACK_RANGE_TILES
    {
        return Err("사거리 밖이다.".to_string());
    }

    // ── 선점 판정 ───────────────────────────────────────────────────────
    // 주인이 없거나 태그 수명이 다했으면 지금 때린 사람이 주인이 된다.
    let tag_expired = micros_between(ctx.timestamp, monster.tagged_at) > TAG_TTL_MICROS;
    if monster.tagged_by.is_none() || tag_expired {
        monster.tagged_by = Some(me.character_id);
    }
    // 주인이 계속 때리는 동안에는 태그가 만료되지 않도록 시각을 민다.
    // 남이 때릴 때 갱신하면 가로채려는 쪽이 태그를 붙잡아 둘 수 있으므로,
    // 주인이 때렸을 때만 민다.
    if monster.tagged_by == Some(me.character_id) {
        monster.tagged_at = ctx.timestamp;
    }

    monster.hp -= player_damage(me.level);

    let mut killed = None;
    if monster.hp <= 0 {
        monster.hp = 0;
        monster.alive = false;
        monster.died_at = ctx.timestamp;

        // 크레딧은 선점자에게 간다. 막타를 넣은 사람이 아니다.
        let owner = monster.tagged_by.unwrap_or(me.character_id);
        let stealer = if owner == me.character_id {
            None
        } else {
            Some(me.character_id)
        };
        killed = Some((owner, stealer));
    }

    let kind = monster.kind.clone();
    let level = monster.level;
    // 쓰러진 자리. 전리품을 여기 떨궈야 하는데 아래 update 가 행을 가져가므로
    // 미리 빼 둔다.
    let (mx, my) = (monster.grid_x, monster.grid_y);
    ctx.db.monster().id().update(monster);

    // 휘두른 사실과 방향을 남긴다. 이것이 없으면 다른 사람 화면에서 나는
    // 가만히 서 있는 채로 몹만 죽어 나간다.
    let (adx, ady) = unit_toward(me.grid_x, me.grid_y, mx, my);
    ctx.db.world_player().identity().update(WorldPlayer {
        next_attack_at: ctx.timestamp + TimeDuration::from_micros(ATTACK_COOLDOWN_MICROS),
        last_attack_at: ctx.timestamp,
        attack_dir_x: adx,
        attack_dir_y: ady,
        attack_skill: ATTACK_SKILL_NONE,
        ..me
    });

    if let Some((owner, stealer)) = killed {
        award_kill(ctx, owner, stealer, &kind, level, mx, my);
    }

    Ok(())
}

// ── 스킬 ────────────────────────────────────────────────────────────────

/// 서버가 아는 스킬 하나의 정의.
///
/// **정의가 서버에 있어야 스킬이 성립한다.** 마력 비용·쿨다운·사거리를 클라이언트가
/// 보내면 "비용 0, 쿨다운 0, 사거리 무한" 이라고 보내지 못할 이유가 없다.
struct SkillSpec {
    /// 한 번 쓰는 데 드는 마력.
    mp_cost: i32,
    /// 재사용까지의 간격(마이크로초).
    cooldown_micros: i64,
    /// 닿는 거리(타일).
    range_tiles: f32,
}

/// 플라즈마 볼트 — 원거리 단일 대상.
///
/// 클라이언트 `Player.tryShoot` 과 같은 값이어야 한다(마력 60, 쿨다운 0.24 초).
/// 사거리는 클라이언트가 발사체 비행으로 표현하던 것을 서버 판정용 거리로 옮긴
/// 값이다 — 발사체를 서버가 시뮬레이션하려면 고주파 틱이 필요하고, 그 비용은
/// 지금 얻는 것보다 크다. 대신 몹의 어그로 거리(9 타일)보다 조금 길게 잡아
/// "화면에 보이는 적은 쏠 수 있다" 를 지킨다.
const SKILL_PLASMA: SkillSpec = SkillSpec {
    mp_cost: 60,
    cooldown_micros: 240_000,
    range_tiles: 10.0,
};

/// 이름으로 스킬 정의를 찾는다. 서버가 모르는 이름은 스킬이 아니다.
fn skill_spec(skill_id: &str) -> Option<SkillSpec> {
    match skill_id.trim().to_lowercase().as_str() {
        "plasma" => Some(SKILL_PLASMA),
        _ => None,
    }
}

/// 기본 공격. 스킬을 쓰지 않았다는 뜻이다.
pub const ATTACK_SKILL_NONE: u32 = 0;

/// 플라즈마 스킬([`SKILL_PLASMA`]).
pub const ATTACK_SKILL_PLASMA: u32 = 1;

/// 스킬 id 를 [`WorldPlayer::attack_skill`] 에 담을 번호로 바꾼다.
///
/// 클라이언트도 같은 대응을 알고 있어야 한다(`lib/game/net/world_presence.dart`).
fn attack_skill_code(skill_id: &str) -> u32 {
    match skill_id.trim().to_lowercase().as_str() {
        "plasma" => ATTACK_SKILL_PLASMA,
        _ => ATTACK_SKILL_NONE,
    }
}

/// 스킬을 쓴다. **마력·쿨다운·사거리·피해를 전부 서버가 정한다.**
///
/// 클라이언트는 "무슨 스킬을 누구에게" 라는 의도만 보낸다. 실패하면 마력도 쿨다운도
/// 소비되지 않으며, 실패 사유가 에러로 돌아간다.
///
/// 지금은 즉시 판정형 하나뿐이다. 지속 장판이나 지연 강타처럼 시간에 걸쳐 효과가
/// 이어지는 스킬은 고주파 틱을 전제로 하므로, 회복·AI 틱의 비용이 실측된 뒤에 붙인다.
#[spacetimedb::reducer]
pub fn cast_skill(
    ctx: &ReducerContext,
    skill_id: String,
    monster_id: u64,
) -> Result<(), String> {
    let me = require_world_player(ctx)?;
    if !me.alive {
        return Err("쓰러진 상태다.".to_string());
    }

    let spec = skill_spec(&skill_id).ok_or_else(|| format!("모르는 스킬이다: {skill_id:?}"))?;

    // 쿨다운은 기본 공격과 같은 시계를 쓴다. 따로 두면 평타와 스킬을 번갈아
    // 눌러 두 배로 때리는 길이 열린다.
    if ctx.timestamp < me.next_attack_at {
        return Err("아직 쓸 수 없다.".to_string());
    }
    if me.mp < spec.mp_cost {
        return Err("마력이 모자란다.".to_string());
    }

    let mut monster = ctx
        .db
        .monster()
        .id()
        .find(monster_id)
        .ok_or_else(|| "몬스터를 찾을 수 없다.".to_string())?;
    if !monster.alive {
        return Err("이미 쓰러진 몬스터다.".to_string());
    }
    if dist_sq(me.grid_x, me.grid_y, monster.grid_x, monster.grid_y)
        > spec.range_tiles * spec.range_tiles
    {
        return Err("사거리 밖이다.".to_string());
    }

    // 선점 규칙은 평타와 같다 — 스킬로 때렸다고 크레딧 규칙이 달라지면
    // "스킬로만 가로채기" 라는 구멍이 생긴다.
    let tag_expired = micros_between(ctx.timestamp, monster.tagged_at) > TAG_TTL_MICROS;
    if monster.tagged_by.is_none() || tag_expired {
        monster.tagged_by = Some(me.character_id);
    }
    if monster.tagged_by == Some(me.character_id) {
        monster.tagged_at = ctx.timestamp;
    }

    monster.hp -= player_ranged_damage(me.level);

    let mut killed = None;
    if monster.hp <= 0 {
        monster.hp = 0;
        monster.alive = false;
        monster.died_at = ctx.timestamp;
        let owner = monster.tagged_by.unwrap_or(me.character_id);
        let stealer = if owner == me.character_id {
            None
        } else {
            Some(me.character_id)
        };
        killed = Some((owner, stealer));
    }

    let kind = monster.kind.clone();
    let level = monster.level;
    // 쓰러진 자리. 전리품을 여기 떨궈야 하는데 아래 update 가 행을 가져가므로
    // 미리 빼 둔다.
    let (mx, my) = (monster.grid_x, monster.grid_y);
    ctx.db.monster().id().update(monster);

    let (adx, ady) = unit_toward(me.grid_x, me.grid_y, mx, my);
    ctx.db.world_player().identity().update(WorldPlayer {
        mp: me.mp - spec.mp_cost,
        next_attack_at: ctx.timestamp + TimeDuration::from_micros(spec.cooldown_micros),
        last_attack_at: ctx.timestamp,
        attack_dir_x: adx,
        attack_dir_y: ady,
        // 무엇으로 쳤는지 남긴다. 스킬마다 동작이 달라, 이것이 없으면 남의
        // 화면에서는 모든 공격이 같은 주먹질로 보인다.
        attack_skill: attack_skill_code(&skill_id),
        ..me
    });

    if let Some((owner, stealer)) = killed {
        award_kill(ctx, owner, stealer, &kind, level, mx, my);
    }

    Ok(())
}

// ── PK ──────────────────────────────────────────────────────────────────

/// 다른 요원을 친다. **PK 는 허용된다.**
///
/// 사냥터 다툼이 그대로 PK 의 동기가 된다 — 남이 선점한 몹을 뺏고 싶으면 몹이
/// 아니라 그 사람을 쓰러뜨려야 한다([`attack_monster`] 의 선점 규칙 참고).
///
/// 안전지대 안에서는 통하지 않는다. 그 판정은 [`apply_damage_to_player`] 가 한다 —
/// 몹의 공격과 같은 규칙을 쓰지 않으면 "PK 로는 안전지대에서도 맞는다" 는 구멍이 된다.
#[spacetimedb::reducer]
pub fn attack_player(ctx: &ReducerContext, target_character_id: u64) -> Result<(), String> {
    let me = require_world_player(ctx)?;
    if !me.alive {
        return Err("쓰러진 상태다.".to_string());
    }
    if me.character_id == target_character_id {
        return Err("자기 자신은 칠 수 없다.".to_string());
    }
    if ctx.timestamp < me.next_attack_at {
        return Err("아직 공격할 수 없다.".to_string());
    }

    let target = ctx
        .db
        .world_player()
        .character_id()
        .find(target_character_id)
        .ok_or_else(|| "상대를 찾을 수 없다.".to_string())?;

    // 때리는 쪽이 안전지대 안이면 일방적으로 때리고 도망칠 수 있다. 양쪽 모두 막는다.
    if in_safe_zone(me.grid_x, me.grid_y) {
        return Err("안전지대에서는 공격할 수 없다.".to_string());
    }
    if dist_sq(me.grid_x, me.grid_y, target.grid_x, target.grid_y)
        > ATTACK_RANGE_TILES * ATTACK_RANGE_TILES
    {
        return Err("사거리 밖이다.".to_string());
    }

    let (adx, ady) = unit_toward(me.grid_x, me.grid_y, target.grid_x, target.grid_y);
    let updated = apply_damage_to_player(ctx, target, player_damage(me.level), false, false);
    ctx.db.world_player().identity().update(updated);

    ctx.db.world_player().identity().update(WorldPlayer {
        next_attack_at: ctx.timestamp + TimeDuration::from_micros(ATTACK_COOLDOWN_MICROS),
        last_attack_at: ctx.timestamp,
        attack_dir_x: adx,
        attack_dir_y: ady,
        attack_skill: ATTACK_SKILL_NONE,
        ..me
    });

    Ok(())
}

/// 몬스터를 움직이고, 닿으면 때린다. **서버가 몬스터의 주인이다.**
///
/// 클라이언트가 각자 AI 를 굴리면 A 화면에서는 몹이 쫓아오는데 B 화면에서는
/// 제자리인 상태가 된다. 그러면 "쫓기는 동료를 도와준다" 같은 일이 성립하지
/// 않는다 — 판정의 주인이 하나여야 협업이 가능하다.
///
/// 매 틱 7,000 기를 전부 훑지는 않는다. 플레이어가 없으면 아무것도 하지 않고,
/// 있으면 그 주변만 [`by_grid_x`](Monster) 인덱스로 좁혀 본다. 몹은 대부분
/// 아무도 없는 곳에 서 있으므로 실제로 계산되는 것은 소수다.
#[spacetimedb::reducer]
pub fn monster_ai(ctx: &ReducerContext, _timer: MonsterAiTimer) {
    let players: Vec<WorldPlayer> = ctx
        .db
        .world_player()
        .iter()
        .filter(|p| p.alive)
        .collect();
    if players.is_empty() {
        return;
    }

    let dt = MONSTER_AI_MICROS as f32 / 1_000_000.0;
    let step = MONSTER_SPEED * dt;
    let mut moved = 0u32;
    let mut hits = 0u32;

    // 플레이어 주변 몹 중 **이번 틱에 할 일이 있는 것만** 모은다. 한 몹이 여러
    // 사람 범위에 걸릴 수 있으므로 번호로 중복을 없앤 뒤 한 번씩만 판단한다.
    //
    // 🛑 **거르는 자리가 여기여야 한다.** 예전에는 청크 안의 몹을 전부 담고 아래
    // 루프에서 `continue` 로 흘려보냈다. 그 `continue` 는 공짜가 아니다 —
    // [`Monster`] 는 `kind: String` 을 들고 있어서 담는 순간 힙 할당이 한 번씩
    // 일어난다. 실측에서 요원 셋 주변 469 기를 매 틱 담았는데 실제로 움직인 것은
    // 0 기였고, 그 낭비가 50ms 예산을 넘겨 스케줄이 1.2 초까지 밀렸다.
    let mut nearby: std::collections::HashMap<u64, Monster> =
        std::collections::HashMap::new();

    // 🛑 **훑을 청크를 먼저 모아 중복을 없앤다.** 요원마다 곧바로 훑으면 같은
    // 청크를 사람 수만큼 다시 읽는다 — 파티가 뭉쳐 사냥하는 상황이 정확히
    // 그렇고, 그때가 하필 서버가 가장 바쁠 때다. 요원 50 명이 한자리에 모이면
    // 9 칸을 50 번, 32,000 행을 훑게 된다. 청크를 먼저 접으면 9 칸 640 행이다.
    //
    // 겹친 몹을 [`HashMap`] 이 걸러 주므로 결과는 전과 같다. 달라지는 것은
    // **읽는 횟수**뿐이다.
    let mut chunks: std::collections::HashSet<u32> = std::collections::HashSet::new();
    for player in &players {
        // 선 청크와 이웃 여덟 칸. 청크 한 변(32타일)이 추격 거리보다 넉넉해
        // 이 범위면 관계있는 몹을 놓치지 않는다.
        let cx = (player.grid_x / CHUNK_TILES) as i64;
        let cy = (player.grid_y / CHUNK_TILES) as i64;
        for dy in -1..=1i64 {
            for dx in -1..=1i64 {
                let nx = cx + dx;
                let ny = cy + dy;
                if nx < 0 || ny < 0 {
                    continue;
                }
                chunks.insert((ny as u32) * CHUNKS_PER_ROW + (nx as u32));
            }
        }
    }

    // 지금이 몇 번째 틱인가. [`needs_tick`] 이 먼 몹을 솎을 때 위상으로 쓴다.
    //
    // reducer 는 상태를 들고 있을 수 없으므로(같은 인자로 재실행될 수 있다) 틱
    // 번호를 어딘가 세어 둘 곳이 없다. 시각을 주기로 나누면 표를 늘리지 않고도
    // 같은 것을 얻는다 — 재실행돼도 같은 값이 나오므로 결정성도 지킨다.
    let tick_no =
        (ctx.timestamp.to_micros_since_unix_epoch().max(0) as u64) / MONSTER_AI_MICROS;

    let mut scanned = 0u32;
    for key in chunks {
        for monster in ctx.db.monster().by_chunk().filter(key) {
            scanned += 1;
            if !monster.alive || !needs_tick(&monster, &players, tick_no) {
                continue;
            }
            nearby.insert(monster.id, monster);
        }
    }

    let nearby_count = nearby.len();

    // 이번 틱에 맞은 사람 → 받은 피해의 **합**(방어 적용 전).
    //
    // 여기서 체력을 깎지 않고 합만 모으는 이유는, 방어·무적·사망·재가동 판정이
    // [`apply_damage_to_player`] 한 곳에만 있어야 하기 때문이다. 여러 몹이 같은
    // 사람을 때렸을 때 몹마다 따로 판정하면 무적 창이 몹 수만큼 갈라진다.
    let mut hurt: std::collections::HashMap<Identity, i32> = std::collections::HashMap::new();

    for (_, monster) in nearby {
        // 가장 가까운 플레이어를 고른다. 사람 수는 적으므로 전부 재도 싸다.
        let mut target: Option<(&WorldPlayer, f32)> = None;
        for player in &players {
            let d2 = dist_sq(monster.grid_x, monster.grid_y, player.grid_x, player.grid_y);
            if target.is_none() || d2 < target.unwrap().1 {
                target = Some((player, d2));
            }
        }
        let Some((player, dist_sq_to_player)) = target else {
            continue;
        };
        let distance = dist_sq_to_player.sqrt();
        let from_home = dist_sq(monster.grid_x, monster.grid_y, monster.home_x, monster.home_y)
            .sqrt();

        // 너무 멀리 끌려왔거나 대상이 어그로를 벗어나면 제자리로 돌아간다.
        // 이 줄이 없으면 몹이 월드를 가로질러 끌려다니고, 사냥터가 무너진다.
        let go_home = distance > MONSTER_LEASH_TILES || from_home > MONSTER_MAX_ROAM_TILES;

        if go_home {
            if from_home > 0.2 {
                let (nx, ny) = step_toward(
                    monster.grid_x,
                    monster.grid_y,
                    monster.home_x,
                    monster.home_y,
                    step,
                );
                if moved_enough(nx, ny, &monster) {
                    let (fx, fy) =
                        unit_toward(monster.grid_x, monster.grid_y, monster.home_x, monster.home_y);
                    ctx.db.monster().id().update(Monster {
                        grid_x: nx,
                        grid_y: ny,
                        pos_chunk: chunk_of(nx, ny),
                        face_x: fx,
                        face_y: fy,
                        ..monster
                    });
                    moved += 1;
                }
            }
            continue;
        }

        if distance > MONSTER_AGGRO_TILES {
            continue; // 아직 못 봤다. 제자리에 선다.
        }

        // 안전지대 안의 사람은 쫓지 않는다. 쉬는 곳까지 따라오면 회복할 자리가
        // 월드에서 사라진다.
        if in_safe_zone(player.grid_x, player.grid_y) {
            continue;
        }

        if distance > ATTACK_RANGE_TILES {
            // 아직 멀다. 다가간다.
            let (nx, ny) = step_toward(
                monster.grid_x,
                monster.grid_y,
                player.grid_x,
                player.grid_y,
                step,
            );
            if moved_enough(nx, ny, &monster) {
                let (fx, fy) =
                    unit_toward(monster.grid_x, monster.grid_y, player.grid_x, player.grid_y);
                ctx.db.monster().id().update(Monster {
                    grid_x: nx,
                    grid_y: ny,
                    pos_chunk: chunk_of(nx, ny),
                    face_x: fx,
                    face_y: fy,
                    ..monster
                });
                moved += 1;
            }
            continue;
        }

        // 닿았다. 제자리에 서지만 **대상 쪽은 본다.**
        //
        // 좌표가 멈추므로 클라이언트는 방향을 유추할 길이 없다. 이 갱신이 없으면
        // 때리는 몹이 마지막으로 걸어온 쪽을 계속 바라보고, 옆으로 돌아 들어간
        // 사람은 자기 등 뒤를 향해 휘두르는 몹을 보게 된다.
        //
        // 실제로 각도가 달라졌을 때만 쓴다. 매 틱 갱신하면 붙어 선 몹 수만큼
        // 트랜잭션이 늘어나는데, 얻는 것은 눈에 보이지도 않는 미세한 각도다.
        let level = monster.level;
        let (fx, fy) = unit_toward(monster.grid_x, monster.grid_y, player.grid_x, player.grid_y);
        if (fx - monster.face_x).abs() > 0.08 || (fy - monster.face_y).abs() > 0.08 {
            ctx.db.monster().id().update(Monster {
                face_x: fx,
                face_y: fy,
                ..monster
            });
        }

        // 맞는 쪽의 쿨다운을 본다 — 여러 몹이 한 틱에 몰아치면 손쓸 새 없이
        // 즉사한다.
        if ctx.timestamp < player.next_hurt_at {
            continue;
        }

        // **후려친 사실을 남긴다.** 이것이 없으면 모든 화면에서 몹은 조용히
        // 서 있고 사람의 체력만 줄어든다 — 무엇에 맞았는지 알 수 없다.
        //
        // 실제로 때린 틱에만 쓴다. 쫓아만 다니는 몹까지 매 틱 갱신하면 어그로
        // 걸린 몹 수만큼 쓰기가 늘어나는데, 얻는 것은 아무것도 없다.
        if let Some(fresh) = ctx.db.monster().id().find(monster.id) {
            ctx.db.monster().id().update(Monster {
                last_attack_at: ctx.timestamp,
                ..fresh
            });
        }

        // 때린 사실만 모아 둔다. 실제 판정은 아래에서 한 번에 한다 — 여러 몹이
        // 같은 사람을 때렸을 때 방어·무적·사망을 각자 따로 계산하면 어긋난다.
        *hurt.entry(player.identity).or_insert(0) += level as i32;
        hits += 1;
    }

    // 실제로 무언가 일어났을 때만 남긴다. 매 틱 찍으면 초당 스물네 줄씩 쌓인다.
    //
    // **훑은 수와 판단한 수를 함께 남긴다.** 둘의 차이가 곧 사전 거르기
    // ([`needs_tick`])가 걷어낸 몫이고, 틱이 밀릴 때 어디가 무거운지 이 두 숫자
    // 없이는 알 수 없다 — 예전 로그는 "469 기 중 0 기 이동" 만 말해 주어서,
    // 469 를 담는 비용 자체가 원인이라는 것이 드러나기까지 오래 걸렸다.
    if moved > 0 || hits > 0 {
        log::info!(
            "AI: 요원 {} 명 · 훑은 {} 기 → 판단 {} 기 · {} 기 이동, {} 회 타격",
            players.len(),
            scanned,
            nearby_count,
            moved,
            hits
        );
    }

    // 피해 적용은 표에서 다시 읽은 최신 행으로 한다. 위 루프가 도는 사이
    // 같은 사람이 다른 reducer 로 갱신됐을 수 있다.
    for (identity, raw_damage) in hurt {
        let Some(victim) = ctx.db.world_player().identity().find(identity) else {
            continue;
        };
        // 무적·안전지대·방어·사망·재가동은 전부 이 한 곳이 판정한다.
        let hurt_at = ctx.timestamp + TimeDuration::from_micros(MONSTER_ATTACK_COOLDOWN_MICROS);
        let updated = apply_damage_to_player(ctx, victim, raw_damage, false, false);
        ctx.db.world_player().identity().update(WorldPlayer {
            next_hurt_at: hurt_at,
            ..updated
        });
    }
}

/// 쓰러진 자리에 전리품을 떨군다.
///
/// 종류와 양은 **서버가 굴린다.** 클라이언트가 각자 굴리면 같은 몹을 잡고도
/// 사람마다 다른 것을 보게 되어, 무엇이 떨어졌는지를 두고 이야기할 수조차 없다.
///
/// 잡은 사람에게 잠깐 우선권을 준다([`LOOT_RESERVE_MICROS`]). 다가가는 사이
/// 옆 사람이 낚아채면 선점 규칙이 무의미해지고, 그렇다고 영원히 묶어 두면
/// 자리를 뜬 뒤 아무도 못 줍는 쓰레기가 쌓인다.
fn spawn_loot(
    ctx: &ReducerContext,
    monster_kind: &str,
    monster_level: u32,
    owner: u64,
    x: f32,
    y: f32,
) {
    // 강한 계열일수록 더 많이, 더 좋은 것을 떨군다.
    let rolls = match monster_kind {
        "sovereign" => 4,
        "siege" => 2,
        _ => 1,
    };

    for i in 0..rolls {
        // 절반 확률로 거른다. 매번 떨구면 바닥이 전리품으로 덮인다.
        if i > 0 && ctx.random::<u32>() % 100 < 40 {
            continue;
        }

        let roll = ctx.random::<u32>() % 100;
        let (kind, base) = if roll < 34 {
            ("nanoVial", 100)
        } else if roll < 54 {
            ("energyCell", 60)
        } else if roll < 70 {
            ("dataChip", 20)
        } else if roll < 82 {
            ("nanoCanister", 200)
        } else if roll < 90 {
            ("scrapCore", 40)
        } else if roll < 95 {
            ("repairCell", 400)
        } else if roll < 98 {
            ("combatStim", 1)
        } else {
            ("overhaulKit", 1200)
        };

        // 레벨이 높은 사냥터일수록 벌이가 낫다. 더 위험한 곳으로 나갈 이유다.
        let amount = base + base * monster_level / 40;

        // 한자리에 겹쳐 두면 한 덩어리로 보인다. 조금씩 흩어 놓는다.
        let ox = (ctx.random::<u32>() % 5) as f32 - 2.0;
        let oy = (ctx.random::<u32>() % 5) as f32 - 2.0;
        let lx = (x + ox).clamp(WORLD_EDGE_MARGIN, PLAYABLE_MAX);
        let ly = (y + oy).clamp(WORLD_EDGE_MARGIN, PLAYABLE_MAX);

        ctx.db.loot().insert(Loot {
            id: 0,
            kind: kind.to_string(),
            amount,
            grid_x: lx,
            grid_y: ly,
            chunk: chunk_of(lx, ly),
            reserved_until: ctx.timestamp
                + TimeDuration::from_micros(LOOT_RESERVE_MICROS),
            reserved_for: Some(owner),
            dropped_at: ctx.timestamp,
        });
    }
}

/// 바닥의 전리품을 줍는다.
///
/// 거리와 우선권을 **서버가 본다.** 같은 것을 두 사람이 동시에 주우면 트랜잭션이
/// 직렬화되어, 먼저 커밋된 쪽이 행을 지우고 나중 호출은 없는 것을 보고 실패한다.
/// 둘 다 얻거나 둘 다 놓치는 상태는 생기지 않는다.
#[spacetimedb::reducer]
pub fn pick_loot(ctx: &ReducerContext, loot_id: u64) -> Result<(), String> {
    let me = require_world_player(ctx)?;
    if !me.alive {
        return Err("쓰러진 상태다.".to_string());
    }

    let loot = ctx
        .db
        .loot()
        .id()
        .find(loot_id)
        .ok_or_else(|| "이미 없어진 전리품이다.".to_string())?;

    if dist_sq(me.grid_x, me.grid_y, loot.grid_x, loot.grid_y)
        > LOOT_PICKUP_TILES * LOOT_PICKUP_TILES
    {
        return Err("너무 멀다.".to_string());
    }

    // 우선권이 남아 있으면 주인만 주울 수 있다.
    if ctx.timestamp < loot.reserved_until
        && loot.reserved_for.is_some()
        && loot.reserved_for != Some(me.character_id)
    {
        return Err("아직 임자가 있다.".to_string());
    }

    ctx.db.loot().id().delete(loot_id);
    Ok(())
}

/// 새 좌표가 표에 쓸 만큼 움직였는가.
///
/// **변화 없는 `update` 는 그 행을 구독한 모두에게 델타를 만든다.** 몹은 24 Hz 로
/// 판정하므로, 목표에 이미 도착한 몹을 매 틱 다시 쓰면 아무 일도 일어나지 않는데
/// 초당 스물네 번씩 전원에게 좌표가 밀려간다. [`regen_tick`] 이 만피·만마인 사람을
/// 건너뛰는 것과 같은 원칙이며, **틱을 올릴수록 이 걸러내기가 중요해진다.**
///
/// 기준은 0.01 타일 — 화면에서 보이지 않는 크기이며,
/// [`step_toward`] 가 목표를 지나치지 않으므로 도착 후에는 정확히 0 이 된다.
fn moved_enough(nx: f32, ny: f32, monster: &Monster) -> bool {
    dist_sq(nx, ny, monster.grid_x, monster.grid_y) > 0.0001
}

/// 이 몹이 이번 틱에 **판단할 값어치가 있는가.**
///
/// [`monster_ai`] 가 후보를 담기 **전에** 부른다. 담고 나서 거르면 늦다 —
/// [`Monster`] 는 `kind: String` 을 들고 있어 담는 것 자체가 힙 할당이고,
/// 청크 3×3 안에는 아무 일도 없을 몹이 수백 기 있다.
///
/// 집에 가만히 서 있고 아무도 어그로 안에 없는 몹은 어떤 갈래로 가도 결과가
/// "아무것도 하지 않음" 이다. [`monster_ai`] 의 판단 순서를 그대로 앞당겨 둔
/// 것이므로, 그쪽을 고치면 여기도 함께 고쳐야 한다.
fn needs_tick(monster: &Monster, players: &[WorldPlayer], tick_no: u64) -> bool {
    // 누군가 어그로 안에 있으면 **매 틱** 본다. 쫓기는 사람의 화면에서 몹이
    // 끊겨 보이는 것이 이 게임에서 가장 나쁜 그림이다.
    let aggro_sq = MONSTER_AGGRO_TILES * MONSTER_AGGRO_TILES;
    let engaged = players.iter().any(|p| {
        dist_sq(monster.grid_x, monster.grid_y, p.grid_x, p.grid_y) <= aggro_sq
    });
    if engaged {
        return true;
    }

    // 집에 서 있고 아무도 없다면 어느 갈래로 가도 결과가 "아무것도 하지 않음" 이다.
    // 문턱은 `monster_ai` 의 귀환 판정(`from_home > 0.2`)과 같은 값이다.
    let away_from_home =
        dist_sq(monster.grid_x, monster.grid_y, monster.home_x, monster.home_y) > 0.04;
    if !away_from_home {
        return false;
    }

    // 아무도 없는데 집 밖에 있다 — 혼자 돌아가는 중이다. **이런 몹은 24 Hz 로
    // 그려 줄 이유가 없다.** 아무도 쫓고 있지 않고, 남이 보더라도 등을 보이며
    // 멀어지는 몸이며, 클라이언트가 그 사이를 보간해 걸어가는 모습으로 메운다.
    //
    // `id` 를 위상으로 섞는 것이 중요하다. 그냥 `tick_no % N` 으로 나누면
    // 귀환 중인 몹 전부가 **같은 틱에 몰려** 그 틱만 세 배로 무거워진다. 몹마다
    // 다른 틱에 배정하면 일감이 고르게 퍼진다.
    (tick_no.wrapping_add(monster.id)) % FAR_MONSTER_TICK_DIVISOR == 0
}

/// `(fx, fy)` 에서 `(tx, ty)` 를 향하는 단위 벡터. 겹쳐 있으면 `(0, 0)`.
///
/// 공격 방향을 남의 화면에 전하는 데 쓴다. 각도가 아니라 벡터로 두는 것은
/// 삼각함수를 서버에서 돌리지 않기 위해서다 — 받는 쪽이 필요하면 각도로
/// 바꾸면 되고, 그리기용 값이라 미세한 차이는 문제되지 않는다.
fn unit_toward(fx: f32, fy: f32, tx: f32, ty: f32) -> (f32, f32) {
    let dx = tx - fx;
    let dy = ty - fy;
    let len = (dx * dx + dy * dy).sqrt();
    if len < 0.0001 {
        (0.0, 0.0)
    } else {
        (dx / len, dy / len)
    }
}

/// `(fx, fy)` 에서 `(tx, ty)` 쪽으로 `step` 만큼 나아간 좌표.
///
/// 목표를 지나치지 않는다 — 지나치면 목표 주위에서 떨리게 된다.
fn step_toward(fx: f32, fy: f32, tx: f32, ty: f32, step: f32) -> (f32, f32) {
    let dx = tx - fx;
    let dy = ty - fy;
    let dist = (dx * dx + dy * dy).sqrt();
    if dist <= step || dist <= 0.0001 {
        return (tx, ty);
    }
    let ratio = step / dist;
    (
        (fx + dx * ratio).clamp(WORLD_EDGE_MARGIN, PLAYABLE_MAX),
        (fy + dy * ratio).clamp(WORLD_EDGE_MARGIN, PLAYABLE_MAX),
    )
}

/// 체력과 마력을 자연 회복시킨다.
///
/// 안전지대 안에서는 빠르게, 밖에서는 마력만 아주 느리게 찬다. 사이보그의 몸체와
/// 마력 회로는 용량이 커서 야전에서는 거의 차지 않고, 적이 들어올 수 없는 구역으로
/// 물러나 쉬어야 정비 설비가 붙는다.
///
/// **얻어맞자마자 뛰어들어 즉시 낫는 것은 막는다**([`REST_WARMUP_MICROS`]).
/// 그러지 않으면 위험할 때마다 거점으로 튀는 것이 최적 전략이 된다.
///
/// 회복량을 누적 상태로 들고 있지 않고 매 틱 최대치에서 다시 계산하는 이유는
/// reducer 가 같은 인자로 재실행될 수 있기 때문이다(모듈 머리말 참고).
#[spacetimedb::reducer]
pub fn regen_tick(ctx: &ReducerContext, _timer: RegenTimer) {
    // 회복이 필요한 사람만 고른다. 만피·만마인 사람에게 쓰기를 하면 구독자
    // 전원에게 변화 없는 갱신이 밀려간다.
    let players: Vec<WorldPlayer> = ctx
        .db
        .world_player()
        .iter()
        .filter(|p| p.hp < p.max_hp || p.mp < p.max_mp)
        .collect();

    for player in players {
        let sheltered = in_safe_zone(player.grid_x, player.grid_y);
        // 피격 직후에는 거점 회복이 걸리지 않는다. 야전 마력 회복은 그대로 둔다 —
        // 그쪽은 어차피 초당 0.5% 라 전투 중 판세를 바꾸지 못한다.
        let warmed = micros_between(ctx.timestamp, player.last_damaged_at) >= REST_WARMUP_MICROS;
        let resting = sheltered && warmed;

        let hp_gain = if resting {
            (player.max_hp / 1000) * REST_HP_PER_MILLE
        } else {
            0
        };
        let mp_rate = if resting {
            REST_MP_PER_MILLE
        } else {
            FIELD_MP_PER_MILLE
        };
        // 최대치가 1000 보다 작아도 최소 1 은 차도록 올림한다. 지금 규격에서는
        // 최대 체력이 10,000 부터라 걸릴 일이 없지만, 수치를 낮추면 회복이
        // 통째로 0 이 되는 함정이 된다.
        let mp_gain = ((player.max_mp as i64 * mp_rate as i64 + 999) / 1000) as i32;

        let hp = (player.hp + hp_gain).min(player.max_hp);
        let mp = (player.mp + mp_gain).min(player.max_mp);
        if hp == player.hp && mp == player.mp {
            continue;
        }

        ctx.db
            .world_player()
            .identity()
            .update(WorldPlayer { hp, mp, ..player });
    }
}

/// 쓰러진 몹을 되살린다.
#[spacetimedb::reducer]
pub fn monster_tick(ctx: &ReducerContext, _timer: MonsterTickTimer) {
    // 아무도 줍지 않은 전리품을 치운다. 두지 않으면 표가 끝없이 자란다.
    let loot_cutoff = ctx.timestamp - TimeDuration::from_micros(LOOT_TTL_MICROS);
    let stale: Vec<u64> = ctx
        .db
        .loot()
        .iter()
        .filter(|l| l.dropped_at < loot_cutoff)
        .map(|l| l.id)
        .collect();
    for id in stale {
        ctx.db.loot().id().delete(id);
    }

    let cutoff = ctx.timestamp - TimeDuration::from_micros(RESPAWN_MICROS);

    // 죽은 지 오래된 것부터 훑는다. 전체를 스캔하지 않도록 인덱스를 쓴다.
    let due: Vec<Monster> = ctx
        .db
        .monster()
        .by_alive_died()
        .filter((false, ..cutoff))
        .collect();

    for monster in due {
        let max_hp = monster_max_hp(&monster.kind, monster.level);
        ctx.db.monster().id().update(Monster {
            grid_x: monster.home_x,
            grid_y: monster.home_y,
            // 집으로 돌아왔으니 구독 청크도 집 청크와 같아진다.
            pos_chunk: chunk_of(monster.home_x, monster.home_y),
            hp: max_hp,
            max_hp,
            alive: true,
            // 되살아난 몹은 임자가 없다.
            tagged_by: None,
            tagged_at: ctx.timestamp,
            ..monster
        });
    }
}

// ── 내부 헬퍼 ───────────────────────────────────────────────────────────

/// 호출자의 월드 상태를 꺼낸다. 월드에 없으면 에러다.
///
/// 캐릭터를 인자로 받지 않고 여기서 도출하므로, 남의 캐릭터로 공격하는 호출
/// 자체가 성립하지 않는다.
fn require_world_player(ctx: &ReducerContext) -> Result<WorldPlayer, String> {
    ctx.db
        .world_player()
        .identity()
        .find(ctx.sender())
        .ok_or_else(|| "먼저 월드에 들어가야 한다.".to_string())
}

/// 재가동 직후 유지되는 무적 시간(마이크로초). 2 초.
///
/// 클라이언트 `Player.respawnInvulnerability` 와 같아야 한다.
const RESPAWN_INVULNERABLE_MICROS: i64 = 2_000_000;

/// 피해를 입은 뒤 안전지대 회복이 시작되기까지의 대기(마이크로초). 1.5 초.
///
/// 클라이언트 `RestRecovery.warmupAfterDamage` 와 같아야 한다.
const REST_WARMUP_MICROS: i64 = 1_500_000;

/// 플레이어가 피해를 입었을 때의 **유일한 수렴점**.
///
/// 몹의 공격도, PK 도, 앞으로 붙을 지형 피해도 전부 여기를 지난다. 판정을 한
/// 곳에 모으는 이유는 무적·안전지대 면역·방어력·사망·재가동이 서로 맞물려 있어서,
/// 경로가 갈라지는 순간 "PK 로는 안전지대에서도 맞는다" 같은 구멍이 생기기
/// 때문이다. 라리엔이 `CombatResolve` 하나로 사망을 모으는 것과 같은 이유다.
///
/// 돌려주는 값은 **갱신된 플레이어**다. 호출자가 표에 쓰기 전에 다른 열을 더
/// 얹을 수 있도록 여기서는 표를 건드리지 않는다 — 한 트랜잭션 안에서 같은 행을
/// 두 번 쓰면 나중 쓰기가 앞의 것을 덮어 쓴다.
///
/// `raw_damage` 는 방어력을 적용하기 **전**의 값이다. 방어를 무시해야 하는
/// 피해(지형 등)는 `ignore_defense` 로 알린다.
fn apply_damage_to_player(
    ctx: &ReducerContext,
    victim: WorldPlayer,
    raw_damage: i32,
    ignore_defense: bool,
    ignore_invulnerable: bool,
) -> WorldPlayer {
    // 안전지대 안에서는 어떤 피해도 통하지 않는다. 재접속 직후의 무방비 상태를
    // 지켜 주는 것이 이 구역의 존재 이유다.
    if in_safe_zone(victim.grid_x, victim.grid_y) {
        return victim;
    }
    if !ignore_invulnerable && ctx.timestamp < victim.invulnerable_until {
        return victim;
    }

    let taken = if ignore_defense {
        raw_damage.max(0)
    } else {
        damage_after_defense(raw_damage, victim.defense)
    };
    if taken <= 0 {
        return victim;
    }

    let hp = victim.hp - taken;
    if hp > 0 {
        return WorldPlayer {
            hp,
            last_damaged_at: ctx.timestamp,
            ..victim
        };
    }

    // 쓰러졌다. 이 세계에 게임 오버는 없다 — 파괴된 것은 몸체뿐이고 의식은
    // 백업되어 있으므로 안전지대에서 곧바로 새 몸체로 재가동한다. 레벨·경험치는
    // 그대로 두고 전투 상태만 되돌린다.
    let (cx, cy) = world_center();
    WorldPlayer {
        hp: victim.max_hp,
        mp: victim.max_mp,
        alive: true,
        grid_x: cx,
        grid_y: cy,
        // **재가동은 좌표가 바뀌는 네 곳 중 가장 놓치기 쉬운 자리다.** 여기서
        // 구독 청크를 함께 밀지 않으면, 쓰러진 사람은 안전지대에 서 있는데 구독
        // 상으로는 죽은 사냥터에 남는다 — 본인 화면에서는 주변이 통째로 비고,
        // 남들 화면에서는 유령이 사냥터에 남는다.
        sub_chunk: player_sub_chunk_of(cx, cy),
        // 재가동은 월드를 가로지르는 이동이다. 기준 시각을 함께 밀지 않으면
        // 다음 좌표 보고가 "방금 500 타일을 뛰었다" 로 읽혀 속도 상한에 잘린다.
        last_move_at: ctx.timestamp,
        deaths: victim.deaths.saturating_add(1),
        invulnerable_until: ctx.timestamp
            + TimeDuration::from_micros(RESPAWN_INVULNERABLE_MICROS),
        last_damaged_at: ctx.timestamp,
        ..victim
    }
}

/// 킬을 확정하고 경험치를 준다.
///
/// **크레딧은 선점자 한 사람의 것이고, 경험치만 파티가 나눈다.** 막타를 넣은
/// 사람이 따로 있어도 기록에만 남고 보상은 없다 — 가로채기가 성립하지 않는다는
/// 규칙은 파티가 생겨도 그대로다.
///
/// 나누는 규칙은 [`crate::party::split_xp`] 가 쥐고 있다. 여기서는 자리를 모아
/// 넘기고 결과를 받아 적을 뿐이다. 파티가 없거나 곁에 아무도 없으면 예전과 똑같이
/// 선점자가 전액을 받는다.
fn award_kill(
    ctx: &ReducerContext,
    owner_character_id: u64,
    last_hit_by: Option<u64>,
    monster_kind: &str,
    monster_level: u32,
    mx: f32,
    my: f32,
) {
    let xp = monster_xp(monster_kind, monster_level);

    let Some(character) = ctx.db.player_character().id().find(owner_character_id) else {
        // 잡는 사이에 캐릭터가 지워졌다. 기록만 남기고 보상은 흘려보낸다.
        log::warn!("킬 크레딧 대상 캐릭터가 사라졌다: {owner_character_id}");
        return;
    };

    let name = character.name.clone();

    // 곁에서 함께 사냥한 파티원을 모아 몫을 정한다. 파티가 없으면 빈 목록이 와서
    // 아래 `unwrap_or(xp)` 가 예전 동작(전액 지급)으로 되돌린다.
    let seats = crate::party::xp_share_seats(
        ctx,
        owner_character_id,
        character.level,
        mx,
        my,
    );
    let shares = crate::party::split_xp(xp, monster_level, &seats);

    let owner_xp = shares
        .iter()
        .find(|(id, _)| *id == owner_character_id)
        .map(|(_, amount)| *amount)
        .unwrap_or(xp);

    // 선점자는 이미 행을 손에 들고 있으므로 다시 찾지 않는다.
    grant_xp(ctx, character, owner_xp);

    for (character_id, amount) in &shares {
        if *character_id == owner_character_id {
            continue;
        }
        let Some(member) = ctx.db.player_character().id().find(*character_id) else {
            // 나누는 사이에 캐릭터가 지워졌다. 나머지 사람들의 몫은 그대로 간다.
            continue;
        };
        grant_xp(ctx, member, *amount);
    }

    spawn_loot(ctx, monster_kind, monster_level, owner_character_id, mx, my);

    ctx.db.monster_kill().insert(MonsterKill {
        id: 0,
        character_id: owner_character_id,
        character_name: name,
        monster_kind: monster_kind.to_string(),
        monster_level,
        // 나눈 뒤 **선점자가 실제로 받은** 값이다. 몹이 주는 총량이 아니다 —
        // 기록을 나중에 읽는 사람이 "이 킬로 내가 얼마를 얻었나" 를 물을 것이기
        // 때문이다. 총량은 `monster_kind`·`monster_level` 로 언제든 다시 구한다.
        xp_awarded: owner_xp,
        last_hit_by,
        killed_at: ctx.timestamp,
    });
}

/// 캐릭터 한 명에게 경험치를 주고, 레벨이 올랐으면 월드 상태도 따라 올린다.
///
/// 파티 분배가 생기면서 이 일이 킬 한 번에 여러 번 일어나게 되어 따로 뽑았다.
/// 나눠 받는 사람도 레벨업해야 하는데, 그때 체력 상한이 따라 오르지 않으면
/// "레벨은 올랐는데 몸은 그대로" 인 상태가 남는다.
fn grant_xp(ctx: &ReducerContext, character: PlayerCharacter, xp: u32) {
    if xp == 0 {
        return;
    }

    let character_id = character.id;

    // 누적에 더하고 레벨·진행도는 거기서 다시 만든다. 성장의 진실은
    // `total_xp` 하나이고 나머지는 그 사본이다.
    let total_xp = character.total_xp.saturating_add(xp);
    let (level, remaining) = apply_xp(character.total_xp, xp);

    ctx.db.player_character().id().update(PlayerCharacter {
        level,
        xp: remaining,
        total_xp,
        last_played_at: ctx.timestamp,
        ..character
    });

    // 레벨이 올랐으면 월드 상태의 체력 상한도 따라 올린다.
    let Some(world_player) = ctx.db.world_player().character_id().find(character_id) else {
        return;
    };
    if world_player.level == level {
        return;
    }

    // 마력 상한도 함께 올린다. 체력만 올리면 레벨이 오를수록 스킬을 쓸 수 있는
    // 횟수가 상대적으로 줄어, 성장할수록 약해지는 축이 생긴다.
    let max_hp = max_hp_for_level(level);
    let max_mp = max_mp_for_level(level);
    ctx.db.world_player().identity().update(WorldPlayer {
        level,
        max_hp,
        hp: max_hp,
        max_mp,
        mp: max_mp,
        ..world_player
    });
}

/// 누적 경험치에 [`gained`] 를 더한 뒤의 (레벨, 현재 레벨 안의 경험치).
///
/// 레벨업 루프를 돌리지 않는다. 레벨은 누적의 함수이므로 더한 값을 한 번
/// 변환하면 그만이고, 몇 레벨이 한꺼번에 올랐는지 셀 필요도 없다. 만렙에
/// 닿으면 레벨은 멈추지만 누적은 계속 쌓인다 — 그 차이가 만렙끼리의 순위를
/// 가른다.
///
/// `saturating_add` 는 `u32` 상한에서 멈추므로 넘칠 일이 없다.
fn apply_xp(total_xp: u32, gained: u32) -> (u32, u32) {
    crate::leaderboard::level_and_progress(total_xp.saturating_add(gained))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 아는_계열만_통과한다() {
        assert_eq!(normalize_build("drone"), Ok("drone".into()));
        assert_eq!(normalize_build(" Sovereign "), Ok("sovereign".into()));
        assert!(normalize_build("robot_overlord").is_err());
    }

    // ── 관심 영역 구독 격자 ─────────────────────────────────────────────
    //
    // 이 값들은 **클라이언트와 글자 단위로 맞아야 한다**
    // (`lib/spacetime/cyborg_connection.dart` 의 `kPlayerSubChunkTiles` 등).
    // 어긋나면 서로 다른 격자를 가리켜 아무도 서로를 보지 못하는데, 오류가 나지
    // 않고 그냥 "빈 월드" 로 보이기 때문에 눈으로는 원인을 찾기 어렵다.

    #[test]
    fn 플레이어_구독_청크는_사람_오십_명에서_역산한_크기다() {
        // 동접 1,000 명이 걸을 수 있는 1,000 × 1,000 타일에 고르게 퍼졌을 때
        //   9C² × (1,000 / 1,000,000) = 50  →  C ≈ 74.5
        let density = 1_000.0 / (WORLD_PLAYABLE_TILES * WORLD_PLAYABLE_TILES);
        let in_view = 9.0 * PLAYER_SUB_CHUNK_TILES * PLAYER_SUB_CHUNK_TILES * density;
        assert!(
            (in_view - 50.0).abs() < 1.0,
            "3×3 에 들어오는 인원이 {in_view} 명이다. 50 명에서 역산한 값이어야 한다."
        );
    }

    #[test]
    fn 같은_청크_안의_두_좌표는_같은_번호를_받는다() {
        // 이것이 성립해야 재구독이 청크 단위로만 일어난다. 좌표마다 달라지면
        // 한 발짝 걸을 때마다 다시 구독하게 된다.
        let a = player_sub_chunk_of(300.0, 300.0);
        let b = player_sub_chunk_of(300.0 + PLAYER_SUB_CHUNK_TILES - 1.0, 300.0);
        let same_column = (300.0 / PLAYER_SUB_CHUNK_TILES) as u32
            == ((300.0 + PLAYER_SUB_CHUNK_TILES - 1.0) / PLAYER_SUB_CHUNK_TILES) as u32;
        if same_column {
            assert_eq!(a, b);
        }
    }

    #[test]
    fn 청크_번호는_월드_안에서_유일하다() {
        // 행 번호 × 한 줄 청크 수 + 열 번호. 한 줄 수가 실제보다 작으면 서로 다른
        // 자리가 같은 번호를 받아, 월드 반대편 사람이 화면에 나타난다.
        let mut seen = std::collections::HashSet::new();
        let mut tile = 0.0f32;
        while tile < WORLD_TILES {
            let mut other = 0.0f32;
            while other < WORLD_TILES {
                assert!(
                    seen.insert(player_sub_chunk_of(tile, other)),
                    "({tile}, {other}) 의 청크 번호가 앞선 것과 겹친다"
                );
                other += PLAYER_SUB_CHUNK_TILES;
            }
            tile += PLAYER_SUB_CHUNK_TILES;
        }
    }

    #[test]
    fn 몬스터_구독_청크는_화면을_덮는다() {
        // 몹은 밀도가 자리마다 열 배 넘게 달라 면적으로 마릿수를 자를 수 없다.
        // 그래서 기준은 인원이 아니라 **3×3 이 화면을 덮는가** 다. 3×3 의 보장
        // 반경은 한 변과 같고, 최대 축소 시 화면 AABB 반폭은 약 22.4 타일이다.
        assert!(
            CHUNK_TILES >= 23.0,
            "구독 청크가 {CHUNK_TILES} 타일이면 최대 축소 화면의 구석이 구독 밖으로 나간다"
        );
    }

    #[test]
    fn 몹의_집_청크는_구독에_쓸_수_없다() {
        // 집 청크로 3×3 을 조회하면 확실히 잡히는 것은
        //   한 변 − 최대 배회 거리 = 32 − 26 = 6 타일
        // 안의 몹뿐이다. 화면 반폭(11~22 타일)보다 작으므로 구독용으로는
        // `pos_chunk`(현재 좌표) 를 따로 두어야 한다. 이 테스트는 그 전제가
        // 무너지는 것을 알린다 — 배회 거리를 줄여 6 이 화면을 덮게 되면
        // 컬럼 하나를 없앨 수 있다.
        let guaranteed = CHUNK_TILES - MONSTER_MAX_ROAM_TILES;
        assert!(
            guaranteed < 11.0,
            "보장 반경이 {guaranteed} 타일이면 집 청크만으로 구독할 수 있다. \
             pos_chunk 를 없앨 수 있는지 다시 보라."
        );
    }

    // ── 전투 수치의 단일 진실 공급원 ────────────────────────────────────
    //
    // 아래 테스트들은 **클라이언트와 손으로 맞춘 값**을 못 박는다. 한쪽만 바뀌면
    // 화면과 판정이 갈라져 "분명히 맞았는데 안 죽는" 상태가 되는데, 클라이언트
    // 테스트는 자기 파생끼리만 비교하므로 그 어긋남을 잡지 못한다. 대조는
    // 여기서만 가능하다.

    #[test]
    fn 플레이어_체력은_클라이언트_규격을_따른다() {
        // 클라이언트 `Player.baseMaxHp` = 10000.
        assert_eq!(max_hp_for_level(1), 10_000);
        // 클라이언트 `LevelGains.maxHp` = 1000 (레벨마다 정확히 1,000).
        assert_eq!(max_hp_for_level(2), 11_000);
        // 레벨 N 의 최대 체력 = 10,000 + (N-1) × 1,000.
        assert_eq!(max_hp_for_level(30), 39_000);
    }

    #[test]
    fn 플레이어_마력은_클라이언트_규격을_따른다() {
        // 클라이언트 `Player.mp` 초기값 5000, `LevelGains.maxMp` = 600.
        assert_eq!(max_mp_for_level(1), 5_000);
        assert_eq!(max_mp_for_level(2), 5_600);
        assert_eq!(max_mp_for_level(30), 22_400);
    }

    #[test]
    fn 근접_피해는_5레벨마다_더_오른다() {
        // 클라이언트 `Player.meleeDamage` = 26 에서 시작.
        assert_eq!(player_damage(1), 26);
        // 레벨 2~4 는 +4.5 씩. 26 + 4.5 = 30.5 → 31 (반올림).
        assert_eq!(player_damage(2), 31);
        // 레벨 5 는 강화 구간이라 +8.0. 26 + 4.5×3 + 8.0 = 47.5 → 48.
        assert_eq!(player_damage(5), 48);
        // 레벨 10 = 26 + 4.5×9 + 8.0×2 − 4.5×2 = 26 + 40.5 + 7 = 73.5 → 74.
        assert_eq!(player_damage(10), 74);
    }

    #[test]
    fn 원거리_피해도_같은_규칙이다() {
        // 클라이언트 `Player.rangedDamage` = 18 에서 시작.
        assert_eq!(player_ranged_damage(1), 18);
        assert_eq!(player_ranged_damage(2), 21);
        // 26 + ... 가 아니라 18 + 3×4 + 2.5 = 32.5 → 33 (레벨 5).
        assert_eq!(player_ranged_damage(5), 33);
    }

    #[test]
    fn 방어력_0이면_받는_피해가_그대로다() {
        // 기획 규격: 방어력 0 인 플레이어가 받는 피해 = 몬스터의 레벨.
        for level in [1, 3, 10, 200] {
            assert_eq!(damage_after_defense(level, 0), level);
        }
    }

    #[test]
    fn 방어력이_상수와_같으면_피해가_절반이다() {
        // 클라이언트 `Player.defenseConstant` = 100 과 같은 승수형 공식.
        assert_eq!(damage_after_defense(100, DEFENSE_CONSTANT), 50);
        // 감산형이 아니므로 방어력이 아무리 높아도 0 이 되지는 않는다.
        assert!(damage_after_defense(200, 10_000) >= 0);
    }

    #[test]
    fn 몬스터_체력은_클라이언트_곡선을_따른다() {
        // 클라이언트 `MonsterCodex._statsFor`: baseHp = 26 + (lv-1)×23, drone ×0.72.
        assert_eq!(monster_max_hp("drone", 1), (26.0f32 * 0.72).round() as i32);
        // walker ×1.15, 레벨 10 → (26 + 9×23) × 1.15.
        assert_eq!(
            monster_max_hp("walker", 10),
            ((26.0f32 + 9.0 * 23.0) * 1.15).round() as i32
        );
        // 계통이 셀수록 단단하다.
        assert!(monster_max_hp("sovereign", 5) > monster_max_hp("siege", 5));
        assert!(monster_max_hp("siege", 5) > monster_max_hp("walker", 5));
        assert!(monster_max_hp("walker", 5) > monster_max_hp("drone", 5));
    }

    #[test]
    fn 몬스터_경험치도_클라이언트_곡선을_따른다() {
        // baseXp = 10 + (lv-1)×9, walker ×1.0.
        assert_eq!(monster_xp("walker", 1), 10);
        assert_eq!(monster_xp("walker", 10), 91);
        // sovereign ×4.0.
        assert_eq!(monster_xp("sovereign", 1), 40);
    }

    #[test]
    fn 강화_구간_횟수는_5레벨마다_하나씩_는다() {
        assert_eq!(milestones_upto(1), 0);
        assert_eq!(milestones_upto(4), 0);
        assert_eq!(milestones_upto(5), 1);
        assert_eq!(milestones_upto(9), 1);
        assert_eq!(milestones_upto(10), 2);
    }

    #[test]
    fn 아는_스킬만_통과한다() {
        assert!(skill_spec("plasma").is_some());
        assert!(skill_spec(" PLASMA ").is_some());
        assert!(skill_spec("meteor").is_none());
        assert!(skill_spec("").is_none());
    }

    #[test]
    fn 플라즈마는_클라이언트와_같은_마력을_쓴다() {
        // 클라이언트 `Player.plasmaMpCost` = 60, `_shootCooldown` = 0.24 초.
        let spec = skill_spec("plasma").unwrap();
        assert_eq!(spec.mp_cost, 60);
        assert_eq!(spec.cooldown_micros, 240_000);
        // 사거리는 몹이 알아채는 거리보다 길어야 "보이는 적을 쏠 수 있다".
        assert!(spec.range_tiles > MONSTER_AGGRO_TILES);
    }

    #[test]
    fn 회복_비율은_클라이언트_규격과_같다() {
        // 클라이언트 `RestRecovery`: HP 0.12/s, MP 0.15/s, 야전 MP 0.005/s.
        assert_eq!(REST_HP_PER_MILLE, 120);
        assert_eq!(REST_MP_PER_MILLE, 150);
        assert_eq!(FIELD_MP_PER_MILLE, 5);
        // 거점 회복이 야전보다 훨씬 빨라야 물러날 이유가 생긴다.
        assert!(REST_MP_PER_MILLE > FIELD_MP_PER_MILLE * 10);
    }

    #[test]
    fn 무적과_회복_대기는_클라이언트와_같다() {
        // 클라이언트 `Player.respawnInvulnerability` = 2.0 초.
        assert_eq!(RESPAWN_INVULNERABLE_MICROS, 2_000_000);
        // 클라이언트 `RestRecovery.warmupAfterDamage` = 1.5 초.
        assert_eq!(REST_WARMUP_MICROS, 1_500_000);
    }

    #[test]
    fn 안전지대는_월드_한가운데_50타일이다() {
        let (cx, cy) = world_center();
        assert!(in_safe_zone(cx, cy));
        assert!(in_safe_zone(cx + 24.0, cy + 24.0));
        assert!(!in_safe_zone(cx + 26.0, cy));
        assert!(!in_safe_zone(cx, cy - 26.0));
    }

    #[test]
    fn 경험치가_모자라면_레벨은_그대로다() {
        // 1 → 2 에 60 이 필요하다.
        assert_eq!(apply_xp(0, 59), (1, 59));
    }

    #[test]
    fn 필요량을_채우면_레벨이_오르고_나머지가_남는다() {
        assert_eq!(apply_xp(0, 70), (2, 10));
    }

    #[test]
    fn 한_번에_여러_레벨도_오른다() {
        // 1 → 2 는 60, 2 → 3 은 93 이므로 200 이면 3 레벨이 된다.
        let (level, rest) = apply_xp(0, 200);
        assert!(level >= 3, "레벨이 {level} 에 그쳤다");
        assert!(rest < crate::leaderboard::xp_to_next(level));
    }

    #[test]
    fn 만렙이_없어_계속_오른다() {
        // 예전 상한(30)을 훌쩍 넘긴 누적에서도 레벨이 계속 붙는다.
        let (level, _) = apply_xp(0, 999_999);
        assert!(level > 30, "레벨이 {level} 에서 멈췄다");

        // 거기서 더 벌면 또 오른다.
        let (higher, _) = apply_xp(999_999, 9_000_000);
        assert!(higher > level);
    }

    #[test]
    fn 누적은_상한에서_멈추고_레벨은_만렙에서_멈춘다() {
        // `saturating_add` 라 넘치지 않고, 레벨은 만렙에서 멈춘다.
        let (level, _) = apply_xp(crate::leaderboard::MAX_TOTAL_XP, u32::MAX);
        assert_eq!(level, crate::leaderboard::MAX_LEVEL);
    }

    #[test]
    fn 필요_경험치는_레벨마다_늘어난다() {
        assert_eq!(crate::leaderboard::xp_to_next(1), 60);
        assert!(crate::leaderboard::xp_to_next(2) > crate::leaderboard::xp_to_next(1));
        assert!(crate::leaderboard::xp_to_next(10) > crate::leaderboard::xp_to_next(9));
    }

    #[test]
    fn 계열이_셀수록_체력과_경험치가_크다() {
        assert!(hp_scale("sovereign") > hp_scale("siege"));
        assert!(hp_scale("siege") > hp_scale("walker"));
        assert!(hp_scale("walker") > hp_scale("drone"));
        assert!(monster_xp("sovereign", 1) > monster_xp("drone", 1));
    }

    #[test]
    fn 레벨이_오르면_몹도_단단해진다() {
        assert!(monster_max_hp("walker", 10) > monster_max_hp("walker", 1));
    }

    #[test]
    fn 아는_텔레포트_목적지만_통과한다() {
        for name in TELEPORT_DESTINATIONS {
            assert!(teleport_anchor(name).is_some(), "{name} 의 기준점이 없다");
        }
        assert!(teleport_anchor("nowhere").is_none());
        assert!(teleport_anchor("").is_none());
    }

    #[test]
    fn 안전지대_목적지는_월드_중앙이다() {
        let (cx, cy) = world_center();
        assert_eq!(teleport_anchor("safe_zone"), Some((cx, cy)));
        // 이름대로 정말 안전지대 안이어야 한다.
        assert!(in_safe_zone(cx, cy));
    }

    /// 클라이언트와 손으로 맞춘 값이므로 여기서 못 박아 둔다.
    ///
    /// 한쪽만 바뀌면 월드 중심이 서로 어긋나는데, 클라이언트 테스트는 자기
    /// 파생끼리 비교하므로 그 어긋남을 잡지 못한다. 대조는 여기서만 가능하다.
    #[test]
    fn 월드_격자는_통행_1km에_테두리를_더한_크기다() {
        // 규격: 걸을 수 있는 거리가 가로 1 km × 세로 1 km.
        // 클라이언트 kWorldSizeMeters / kWorldPlayableTiles 와 같아야 한다.
        assert_eq!(WORLD_PLAYABLE_TILES, 1000.0);
        // 클라이언트 kWorldEdgeMarginTiles 와 같아야 한다.
        assert_eq!(WORLD_EDGE_MARGIN, 3.0);
        // 클라이언트 kWorldTiles = 1000 + 3 * 2 와 같아야 한다.
        assert_eq!(WORLD_TILES, 1006.0);
        // 월드 중심은 클라이언트 LevelMap.worldCenter(= width/2) 와 같아야 한다.
        assert_eq!(world_center(), (503.0, 503.0));
    }

    #[test]
    fn 이동_클램프는_통행_가능_격자_안에_머문다() {
        // 통행 가능 구간은 [MARGIN, WORLD_TILES - MARGIN) 이고 상한은 배타적이다.
        assert!(PLAYABLE_MAX < WORLD_TILES - WORLD_EDGE_MARGIN);
        // 마지막 통행 가능 칸(1002)에 머물러야 한다. 상한을 포함하면 테두리로 넘어간다.
        assert_eq!(PLAYABLE_MAX.floor(), WORLD_TILES - WORLD_EDGE_MARGIN - 1.0);
        // 하한은 테두리 바로 안쪽 첫 칸이다.
        assert_eq!(WORLD_EDGE_MARGIN.floor(), WORLD_EDGE_MARGIN);
    }

    #[test]
    fn 가장자리_목적지는_경계에서_안쪽으로_들어와_있다() {
        let (cx, cy) = world_center();
        let inset = TELEPORT_EDGE_INSET;
        assert_eq!(teleport_anchor("north"), Some((cx, inset)));
        assert_eq!(teleport_anchor("south"), Some((cx, WORLD_TILES - inset)));
        assert_eq!(teleport_anchor("west"), Some((inset, cy)));
        assert_eq!(teleport_anchor("east"), Some((WORLD_TILES - inset, cy)));

        // 통행 불가한 외곽 테두리(3칸) 밖이어야 착지할 수 있다.
        assert!(inset > 3.0);
    }

    #[test]
    fn 가장자리_목적지는_안전지대_밖이다() {
        for name in ["north", "east", "south", "west"] {
            let (x, y) = teleport_anchor(name).unwrap();
            assert!(!in_safe_zone(x, y), "{name} 이 안전지대 안이다");
        }
    }

    #[test]
    fn 착지_허용_범위는_클라이언트_보정_폭을_덮는다() {
        // 클라이언트는 최대 12회 × 12타일 = 144 타일까지 안쪽으로 물러나고,
        // 거기서 다시 반경 24 안을 훑는다. 서버 허용치는 그보다 넉넉해야
        // 정상적인 착지가 거절되지 않는다.
        assert!(TELEPORT_LANDING_SLACK >= 12.0 * 12.0 + 24.0);
    }
}
