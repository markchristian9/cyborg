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
pub const CLUSTER_MIN: u32 = 5;
pub const CLUSTER_MAX: u32 = 20;

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
/// 레벨 200 × 지역 3 × 최대 20 마리 = 12,000. 실제 마릿수는 군집마다 뽑은
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

/// 이동 보고가 허용하는 최대 속도(타일/초).
///
/// 클라이언트가 좌표를 보내고 서버는 **속도 상한만** 본다. 완전한 서버 이동
/// 시뮬레이션은 조작에 더 강하지만 예측·롤백을 함께 만들어야 하고, 그 비용은
/// 지금 단계에서 얻는 것보다 크다. 대시와 지연을 감안해 상한은 넉넉히 둔다 —
/// 여기서 잡으려는 것은 "월드 반대편으로 순간이동해 기습하고 사라지는" 짓이지
/// 미세한 속도 조작이 아니다.
const MAX_MOVE_SPEED: f32 = 14.0;

/// 월드 입장 시 체력. 레벨에 따라 [`max_hp_for_level`] 이 늘려 준다.
const BASE_MAX_HP: i32 = 100;

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
#[spacetimedb::table(accessor = world_player, public)]
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
}

/// 월드에 상주하는 몬스터 한 마리.
///
/// 자리는 [`spawn_slot`](Monster::spawn_slot) 마다 고정이다. 쓰러져도 행을
/// 지우지 않고 `alive` 만 내리는데, 그래야 되살아날 자리를 잃지 않고 클라이언트도
/// 행이 사라졌다 나타나는 대신 상태 변화로 받아 볼 수 있다.
#[spacetimedb::table(
    accessor = monster,
    public,
    index(accessor = by_alive_died, btree(columns = [alive, died_at]))
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
}

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

/// 계열 이름을 서버가 아는 값으로 정규화한다.
pub fn normalize_build(raw: &str) -> Result<String, String> {
    let build = raw.trim().to_lowercase();
    if MONSTER_BUILDS.contains(&build.as_str()) {
        Ok(build)
    } else {
        Err(format!("알 수 없는 몬스터 계열이다: {raw:?}"))
    }
}

/// 계열별 기본 체력.
fn base_hp(build: &str) -> i32 {
    match build {
        "drone" => 40,
        "walker" => 90,
        "siege" => 180,
        "sovereign" => 520,
        _ => 60,
    }
}

/// 계열별 기본 경험치.
fn base_xp(build: &str) -> u64 {
    match build {
        "drone" => 12,
        "walker" => 26,
        "siege" => 60,
        "sovereign" => 240,
        _ => 15,
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
fn monster_max_hp(build: &str, level: u32) -> i32 {
    let grow = 1.0 + (level.saturating_sub(1) as f32) * 0.18;
    ((base_hp(build) as f32) * grow).round() as i32
}

/// 몹을 잡았을 때 주는 경험치.
///
/// 레벨 차이는 보지 않는다. 개별 사냥이라 남의 몹을 대신 잡아 줄 이유가 없고,
/// 고레벨이 저레벨 사냥터를 쓸어 담아도 얻는 것이 적어 자연히 갈라진다.
fn monster_xp(build: &str, level: u32) -> u32 {
    let grow = 1.0 + (level.saturating_sub(1) as f64) * 0.12;
    ((base_xp(build) as f64) * grow).round() as u32
}

/// 캐릭터 레벨에 따른 최대 체력.
fn max_hp_for_level(level: u32) -> i32 {
    BASE_MAX_HP + (level.saturating_sub(1) as i32) * 18
}

/// 캐릭터가 한 대에 넣는 피해.
///
/// 장비가 아직 없으므로 레벨만 본다. 클라이언트가 보낸 값은 쓰지 않는다.
fn player_damage(level: u32) -> i32 {
    14 + (level.saturating_sub(1) as i32) * 3
}

// ── 좌표 헬퍼 ───────────────────────────────────────────────────────────

/// 월드 한가운데. 안전지대의 중심이자 입장 지점이다.
fn world_center() -> (f32, f32) {
    (WORLD_TILES / 2.0, WORLD_TILES / 2.0)
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
                    grid_x: x,
                    grid_y: y,
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
pub fn enter_world(ctx: &ReducerContext) -> Result<(), String> {
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

    let (cx, cy) = world_center();
    let max_hp = max_hp_for_level(character.level);

    let player = WorldPlayer {
        identity: ctx.sender(),
        character_id,
        name: character.name,
        kind: character.kind,
        level: character.level,
        grid_x: cx,
        grid_y: cy,
        hp: max_hp,
        max_hp,
        alive: true,
        next_attack_at: ctx.timestamp,
        last_move_at: ctx.timestamp,
        entered_at: ctx.timestamp,
        next_teleport_at: ctx.timestamp,
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
    ctx.db.world_player().identity().delete(ctx.sender());
    Ok(())
}

/// 지금 위치를 보고한다.
///
/// 클라이언트가 좌표를 보내고 서버는 **속도 상한만** 본다([`MAX_MOVE_SPEED`]).
/// 상한을 넘으면 거절하는 대신 갈 수 있는 데까지만 당겨서 받아들인다. 거절하면
/// 지연이 한 번 튈 때마다 화면이 뒤로 끌려가 조작감이 무너지기 때문이다.
#[spacetimedb::reducer]
pub fn move_to(ctx: &ReducerContext, grid_x: f32, grid_y: f32) -> Result<(), String> {
    let me = require_world_player(ctx)?;

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

    ctx.db.world_player().identity().update(WorldPlayer {
        grid_x: next_x,
        grid_y: next_y,
        last_move_at: ctx.timestamp,
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
    ctx.db.monster().id().update(monster);

    ctx.db.world_player().identity().update(WorldPlayer {
        next_attack_at: ctx.timestamp + TimeDuration::from_micros(ATTACK_COOLDOWN_MICROS),
        ..me
    });

    if let Some((owner, stealer)) = killed {
        award_kill(ctx, owner, stealer, &kind, level);
    }

    Ok(())
}

/// 쓰러진 몹을 되살린다.
#[spacetimedb::reducer]
pub fn monster_tick(ctx: &ReducerContext, _timer: MonsterTickTimer) {
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

/// 킬을 확정하고 경험치를 준다.
///
/// 경험치는 **선점자에게만** 간다. 막타를 넣은 사람이 따로 있으면 기록에만
/// 남기고 보상은 주지 않는다.
fn award_kill(
    ctx: &ReducerContext,
    owner_character_id: u64,
    last_hit_by: Option<u64>,
    monster_kind: &str,
    monster_level: u32,
) {
    let xp = monster_xp(monster_kind, monster_level);

    let Some(character) = ctx.db.player_character().id().find(owner_character_id) else {
        // 잡는 사이에 캐릭터가 지워졌다. 기록만 남기고 보상은 흘려보낸다.
        log::warn!("킬 크레딧 대상 캐릭터가 사라졌다: {owner_character_id}");
        return;
    };

    let name = character.name.clone();

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
    if let Some(world_player) = ctx
        .db
        .world_player()
        .character_id()
        .find(owner_character_id)
    {
        if world_player.level != level {
            let max_hp = max_hp_for_level(level);
            ctx.db.world_player().identity().update(WorldPlayer {
                level,
                max_hp,
                hp: max_hp,
                ..world_player
            });
        }
    }

    ctx.db.monster_kill().insert(MonsterKill {
        id: 0,
        character_id: owner_character_id,
        character_name: name,
        monster_kind: monster_kind.to_string(),
        monster_level,
        xp_awarded: xp,
        last_hit_by,
        killed_at: ctx.timestamp,
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
        assert!(base_hp("sovereign") > base_hp("siege"));
        assert!(base_hp("siege") > base_hp("walker"));
        assert!(base_hp("walker") > base_hp("drone"));
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
