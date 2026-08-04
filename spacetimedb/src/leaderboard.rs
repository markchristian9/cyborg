//! 전역 레벨 리더보드.
//!
//! 모든 계정의 캐릭터를 레벨 순으로 줄 세운다. 순위는 **저장하지 않고**
//! [`PlayerCharacter`] 표에서 그때그때 계산한다. 별도의 순위 표를 두면 캐릭터가
//! 지워지거나 레벨이 바뀔 때마다 두 표를 맞춰야 하고, 한 번 어긋나면 아무도
//! 눈치채지 못한 채 틀린 순위가 남는다. 계산으로 만들면 어긋날 표 자체가 없다.
//!
//! ## 무엇을 공개하는가
//!
//! [`crate`] 의 설계 원칙 3번대로 표는 전부 비공개다. 리더보드도 표를 여는 것이
//! 아니라 [`LeaderboardEntry`] 라는 **따로 만든 값**만 내보낸다. 그래서
//! `account_id` 처럼 남에게 갈 이유가 없는 값은 구조적으로 새어 나갈 수 없다.

use spacetimedb::{AnonymousViewContext, ReducerContext, ViewContext, view};

// `*__view` 는 매크로가 만든 trait 다. reducer 는 `player_character` 만 있으면
// 되지만 view 는 읽기 전용 핸들을 쓰므로 이쪽 trait 도 함께 있어야 한다.
use crate::{PlayerCharacter, player_character, player_character__view, session__view};

/// 리더보드에 싣는 최대 인원.
///
/// view 는 호출할 때마다 전체를 정렬하므로 결과 크기를 무한정 키우지 않는다.
/// 100 위 밖의 본인 순위는 [`my_rank`] 가 따로 알려준다.
pub const LEADERBOARD_SIZE: usize = 100;

// ── 성장 곡선 ───────────────────────────────────────────────────────────
//
// 곡선은 **정수 산술만** 쓴다. 예전에는 `60 × 1.22^(level-1)` 이라는 지수식을
// 썼는데, 서버와 클라이언트가 각자 계산하면 부동소수 마지막 자리가 갈릴 수 있어
// 고정 표로 못 박아야 했다. 정수 다항식이면 두 언어가 **같은 정수 연산**을 하므로
// 어긋날 여지가 처음부터 없고, 표 없이 만렙까지 뻗을 수 있다.
//
// 클라이언트 `LevelSystem` 이 같은 상수로 같은 식을 계산한다. 곡선을 바꾸려면
// 양쪽을 함께 고친다 — `test/level_system_curve_test.dart` 와 이 모듈의 테스트가
// 같은 기대값을 검증하므로, 한쪽만 고치면 즉시 깨진다.

/// 도달할 수 있는 최고 레벨.
pub const MAX_LEVEL: u32 = 999;

/// 1 → 2 레벨에 드는 경험치.
pub const XP_BASE: u32 = 60;

/// 레벨마다 선형으로 붙는 몫.
pub const XP_LINEAR: u32 = 30;

/// 레벨의 제곱에 비례해 붙는 몫.
pub const XP_QUADRATIC: u32 = 3;

/// 이 레벨을 넘어서면 곡선이 한 번 더 꺾인다.
pub const XP_STEEP_FROM: u32 = 70;

/// [`XP_STEEP_FROM`] 을 넘은 뒤 레벨마다 선형으로 더 붙는 몫.
///
/// 이 항이 있어야 71 레벨에서 **즉시** 무거워진 것이 느껴진다. 제곱항만 더하면
/// 경계 직후에는 몇 십밖에 차이 나지 않아 "70 부터 어려워진다" 가 체감되지 않는다.
pub const XP_STEEP_LINEAR: u32 = 500;

/// [`XP_STEEP_FROM`] 을 넘은 뒤 제곱에 비례해 더 붙는 몫. 후반을 무겁게 만든다.
pub const XP_STEEP_QUADRATIC: u32 = 8;

/// 누적 경험치의 상한. `u32` 가 담을 수 있는 최댓값이다.
///
/// 만렙(999)까지 필요한 누적은 33 억 5762 만이고 여기에 9 억 3734 만이 남는다.
/// 그 여유가 **만렙 도달자끼리의 경쟁 공간**이다 — 만렙에서 누적을 더 쌓지
/// 못하면 999 레벨끼리는 전원 동점이 되어 순위가 캐릭터 생성 순으로 굳는다.
///
/// 조작 클라이언트가 이 값을 한 번에 보내는 것은 막지 못한다. 서버가 전투를
/// 직접 보아야 가능한 일이고, 지금은 되돌아가는 보고를 무시하는 규칙만 있다.
pub const MAX_TOTAL_XP: u32 = u32::MAX;

/// [`level`] 에서 다음 레벨로 가는 데 필요한 경험치.
///
/// 레벨 1 은 60, 10 은 573, 70 은 16,413. 71 부터 가속이 붙어 100 은 54,633,
/// 500 은 2,456,233, 만렙 999 는 10,386,840 이다.
pub fn xp_to_next(level: u32) -> u32 {
    let level = level.clamp(1, MAX_LEVEL);
    let n = level - 1;
    let mut need = XP_BASE + XP_LINEAR * n + XP_QUADRATIC * n * n;

    if level > XP_STEEP_FROM {
        let j = level - XP_STEEP_FROM;
        need += XP_STEEP_LINEAR * j + XP_STEEP_QUADRATIC * j * j;
    }
    need
}

/// 레벨 [`level`] 에 도달하는 데 필요한 누적 경험치.
///
/// [`xp_to_next`] 를 1 부터 `level-1` 까지 더한 값이며, 닫힌 식으로 계산한다.
/// 등차수열 합과 사각뿔수 공식을 쓰므로 나눗셈이 항상 정확히 떨어진다.
///
/// 중간 계산은 `u64` 로 한다. 결과는 `u32` 안에 들어가지만 제곱합을 더하는
/// 도중에는 넘칠 수 있다.
pub fn total_xp_for_level(level: u32) -> u32 {
    if level <= 1 {
        return 0;
    }
    let level = level.min(MAX_LEVEL);
    let n = (level - 1) as u64; // 더할 항의 개수

    // Σ 60 + Σ 30·i + Σ 3·i²  (i = 0 .. n-1)
    let mut total = XP_BASE as u64 * n
        + XP_LINEAR as u64 * (n * (n - 1) / 2)
        + XP_QUADRATIC as u64 * ((n - 1) * n * (2 * n - 1) / 6);

    // 가속 구간은 71 레벨분부터 더해진다.
    if level > XP_STEEP_FROM + 1 {
        let m = (level - XP_STEEP_FROM - 1) as u64;
        total += XP_STEEP_LINEAR as u64 * (m * (m + 1) / 2)
            + XP_STEEP_QUADRATIC as u64 * (m * (m + 1) * (2 * m + 1) / 6);
    }
    total as u32
}

/// 누적 경험치가 [`total`] 일 때의 레벨. 만렙에서 멈춘다.
///
/// [`total_xp_for_level`] 의 역함수다. 닫힌 식 대신 이진 탐색을 쓰는 이유는
/// 정확성 때문이다 — 세제곱근을 부동소수로 구하면 경계 레벨에서 1 씩 어긋날 수
/// 있고, 그 어긋남이 서버와 클라이언트에서 다르게 나면 "레벨이 표시마다 다른"
/// 증상이 된다. 정수 비교만 쓰면 두 곳이 반드시 같은 답을 낸다.
pub fn level_for_total_xp(total: u32) -> u32 {
    let mut low: u32 = 1;
    let mut high: u32 = MAX_LEVEL;

    while low < high {
        let mid = low + (high - low + 1) / 2;
        if total_xp_for_level(mid) <= total {
            low = mid;
        } else {
            high = mid - 1;
        }
    }
    low
}

/// 누적 경험치에서 (레벨, 그 레벨 안의 진행도) 를 함께 구한다.
///
/// 만렙에서는 진행도가 "만렙에 도달한 뒤 더 쌓은 양" 이 된다. 더 오를 레벨이
/// 없으니 게이지로는 의미가 없지만, 만렙끼리의 순위를 가르는 값이다.
pub fn level_and_progress(total: u32) -> (u32, u32) {
    let level = level_for_total_xp(total);
    (level, total - total_xp_for_level(level))
}

/// 리더보드 한 줄.
///
/// [`PlayerCharacter`] 에서 필요한 것만 옮겨 담은 값이다. 그래서 캐릭터 표에
/// 어떤 열이 늘어나도 여기 적지 않는 한 밖으로 나가지 않는다 — `account_id` 가
/// 리더보드를 타고 남에게 갈 일이 구조적으로 없다.
///
/// **행을 한 줄도 넣지 않는 표다.** 순위는 [`leaderboard`] view 가 그때그때
/// 계산해서 만들고 어디에도 저장하지 않는다. 그런데도 표로 선언한 이유는
/// 클라이언트 코드 생성기가 view 반환 타입의 이름을 **표 목록에서만** 찾기
/// 때문이다. 표가 아니면 생성기가 이름을 잃고 `Type2` 같은 존재하지 않는
/// 클래스를 참조하는 코드를 뱉는다. 비공개 표이므로 구독으로 새지 않는다.
#[spacetimedb::table(accessor = leaderboard_entry)]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LeaderboardEntry {
    /// 1 부터 시작하는 순위. 같은 레벨·경험치라도 순위는 겹치지 않는다.
    pub rank: u32,

    /// 캐릭터 하나는 리더보드에 한 번만 오르므로 이 값이 행을 가른다.
    /// 클라이언트 캐시가 갱신을 추적하는 데 쓴다.
    #[primary_key]
    pub character_id: u64,
    pub name: String,
    pub kind: String,
    pub level: u32,

    /// 지금 레벨 안에서 다음 레벨까지 쌓은 진행도. 화면의 게이지가 쓴다.
    pub xp: u32,

    /// 지금까지 얻은 경험치의 총합. **순위를 정하는 값이다.**
    ///
    /// **맨 끝에 있고 기본값이 있어야 한다.** `PlayerCharacter::total_xp` 와 같은
    /// 이유이며(자동 마이그레이션이 두 조건을 모두 요구한다), 접미사 `u64` 도
    /// 마찬가지로 빼면 안 된다. 이 표는 캐릭터에서 매번 다시 만들어지는 파생
    /// 뷰이므로, 기본값으로 채워진 옛 행은 다음 갱신에서 실제 값으로 덮인다.
    #[default(0u32)]
    pub total_xp: u32,
}

/// 리더보드 정렬 기준: 누적 경험치 내림차순 → 생성 순.
///
/// 레벨을 따로 보지 않는다. 레벨은 누적 경험치의 함수이므로 누적이 많은 쪽이
/// 반드시 레벨도 같거나 높다 — 두 기준을 겹쳐 보면 같은 말을 두 번 하는 셈이고,
/// 만에 하나 파생값이 어긋나면 정렬이 그 어긋남을 따라간다.
///
/// 생성 순은 동점자를 가르기 위한 것이다. 기준이 없으면 표를 훑는 순서가 바뀔
/// 때마다 순위가 흔들려, 아무 일도 없었는데 목록이 요동치는 것처럼 보인다.
fn rank_key(c: &PlayerCharacter) -> (std::cmp::Reverse<u32>, i64, u64) {
    (
        std::cmp::Reverse(c.total_xp),
        c.created_at.to_micros_since_unix_epoch(),
        c.id,
    )
}

/// `a` 가 `b` 보다 앞 순위인가.
fn outranks(a: &PlayerCharacter, b: &PlayerCharacter) -> bool {
    rank_key(a) < rank_key(b)
}

fn to_entry(rank: u32, c: PlayerCharacter) -> LeaderboardEntry {
    // 표에 저장된 파생값을 믿지 않고 누적에서 다시 만든다. 저장된 `level`·`xp`
    // 는 편의를 위한 사본일 뿐이고, 리더보드가 보여 주는 숫자는 순위를 정한
    // 값과 반드시 같은 데서 나와야 한다.
    let (level, progress) = level_and_progress(c.total_xp);
    LeaderboardEntry {
        rank,
        character_id: c.id,
        name: c.name,
        kind: c.kind,
        level,
        xp: progress,
        total_xp: c.total_xp,
    }
}

// ── view ────────────────────────────────────────────────────────────────

/// 전체 캐릭터의 레벨 순위 상위 [`LEADERBOARD_SIZE`] 명.
///
/// 누가 보든 같은 결과이므로 [`AnonymousViewContext`] 를 쓴다. 호출자마다
/// 결과가 달라지지 않는다는 사실을 서버가 알면 같은 결과를 여러 접속에
/// 나눠 줄 수 있다.
/// view 가 받는 핸들은 읽기 전용이라 `iter()` 가 없다. 여러 행을 보는 길은
/// 인덱스 범위 조회뿐이므로, `level` 인덱스에 하한 없는 범위를 걸어 표 전체를
/// 받아 온다. 나오는 순서는 인덱스 순서라 우리가 원하는 순위와 다르고, 아래에서
/// 다시 정렬한다.
#[view(accessor = leaderboard, public)]
fn leaderboard(ctx: &AnonymousViewContext) -> Vec<LeaderboardEntry> {
    let mut rows: Vec<PlayerCharacter> = ctx.db.player_character().level().filter(0u32..).collect();
    rows.sort_by_key(rank_key);

    rows.into_iter()
        .take(LEADERBOARD_SIZE)
        .enumerate()
        .map(|(i, c)| to_entry(i as u32 + 1, c))
        .collect()
}

/// 지금 고른 캐릭터의 순위. 로그인하지 않았거나 캐릭터를 고르지 않았으면 `None`.
///
/// 상위 100 위 밖이어도 본인 순위는 보여야 한다. 전체를 정렬하는 대신 "나보다
/// 앞선 캐릭터가 몇 명인가" 만 세므로 인원이 늘어도 한 번만 훑는다.
#[view(accessor = my_rank, public)]
fn my_rank(ctx: &ViewContext) -> Option<LeaderboardEntry> {
    let session = ctx.db.session().identity().find(ctx.sender())?;
    let me = ctx
        .db
        .player_character()
        .id()
        .find(session.selected_character_id?)?;

    let ahead = ctx
        .db
        .player_character()
        .level()
        .filter(0u32..)
        .filter(|other| outranks(other, &me))
        .count();

    Some(to_entry(ahead as u32 + 1, me))
}

// ── reducer ─────────────────────────────────────────────────────────────

/// 캐릭터의 누적 경험치를 [`total_xp`](PlayerCharacter::total_xp) 로 올려 잡고
/// 레벨·진행도를 다시 계산한다.
///
/// 레벨을 인자로 받지 않는다. 받아 봐야 누적에서 다시 계산할 것이고, 둘을 함께
/// 받으면 "레벨 30 인데 누적은 3 레벨분" 같은 어긋난 보고가 가능해진다. 값이
/// 하나면 그런 상태 자체가 만들어지지 않는다.
///
/// **이 값은 클라이언트가 신고한 것이다.** 로컬 전투는 아직 클라이언트가 굴리고
/// 있어 달리 알 방법이 없다. 그래서 믿는 대신 두 가지만 강제한다.
///
/// 1. 누적은 [`MAX_TOTAL_XP`] 를 넘지 못한다(`u32` 상한이라 자연히 걸린다).
/// 2. 성장은 되돌아가지 않는다. 지금보다 적은 누적이 오면 무시한다.
///
/// 이것으로 막는 것은 명백히 불가능한 값뿐이다. 조작된 클라이언트가 "그럴듯한
/// 속도로" 경험치를 올려 보내는 것은 막지 못한다.
///
/// ⚠️ **서버 월드(`crate::world`)도 몬스터를 잡으면 같은 열을 올린다.** 두 경로가
/// 한 값을 쓰지만 둘 다 "더 큰 누적만 채택" 이라는 같은 규칙을 지키므로 서로를
/// 되돌리지 않는다. 서버 전투가 유일한 출처가 되면 이 reducer 는 사라진다.
#[spacetimedb::reducer]
pub fn report_progress(ctx: &ReducerContext, total_xp: u32) -> Result<(), String> {
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

    // 자른 뒤에 비교한다. 순서가 반대면 잘리기 전의 큰 값이 단조 검사를 통과해
    // 버려, 자르는 의미가 없어진다.
    let total_xp = total_xp.min(MAX_TOTAL_XP);

    // 같은 계정을 여러 기기에서 켜 두면 뒤늦게 도착한 옛 보고가 최신 기록을
    // 덮어쓸 수 있다. 뒤로 가는 갱신을 통째로 버려서 그 경우를 없앤다.
    if total_xp <= character.total_xp {
        return Ok(());
    }

    let (level, xp) = level_and_progress(total_xp);

    ctx.db.player_character().id().update(PlayerCharacter {
        level,
        xp,
        total_xp,
        last_played_at: ctx.timestamp,
        ..character
    });

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use spacetimedb::Timestamp;

    fn character(id: u64, total_xp: u32, created_micros: i64) -> PlayerCharacter {
        let (level, xp) = level_and_progress(total_xp);
        PlayerCharacter {
            id,
            account_id: 1,
            name: format!("요원{id}"),
            kind: "male_cyborg".to_string(),
            level,
            xp,
            created_at: Timestamp::from_micros_since_unix_epoch(created_micros),
            last_played_at: Timestamp::from_micros_since_unix_epoch(created_micros),
            total_xp,
        }
    }

    /// 정렬 결과를 캐릭터 id 순서로 돌려준다.
    fn ranked_ids(mut rows: Vec<PlayerCharacter>) -> Vec<u64> {
        rows.sort_by_key(rank_key);
        rows.into_iter().map(|c| c.id).collect()
    }

    #[test]
    fn 누적_경험치가_많은_쪽이_앞선다() {
        let rows = vec![
            character(1, 500, 0),
            character(2, 90_000, 0),
            character(3, 5_000, 0),
        ];
        assert_eq!(ranked_ids(rows), vec![2, 3, 1]);
    }

    #[test]
    fn 같은_레벨이어도_누적이_많으면_앞선다() {
        // 둘 다 3 레벨이지만(누적 153 ~ 284) 쌓은 양이 다르다.
        let low = character(1, 160, 0);
        let high = character(2, 280, 0);
        assert_eq!(low.level, high.level);
        assert_eq!(ranked_ids(vec![low, high]), vec![2, 1]);
    }

    #[test]
    fn 누적이_같으면_먼저_만든_쪽이_앞선다() {
        let rows = vec![character(1, 1_000, 500), character(2, 1_000, 100)];
        assert_eq!(ranked_ids(rows), vec![2, 1]);
    }

    #[test]
    fn 생성_시각까지_같으면_id_로_갈라_순서가_흔들리지_않는다() {
        let a = character(7, 400, 0);
        let b = character(3, 400, 0);
        assert!(outranks(&b, &a));
        assert!(!outranks(&a, &b));
    }

    // ── 성장 곡선 ───────────────────────────────────────────────────────

    /// 클라이언트 `LevelSystem.xpToNext` 와 **같은 값**이어야 한다.
    /// `test/level_system_curve_test.dart` 가 Dart 쪽에서 같은 기대값을 검증한다.
    /// 한쪽만 고치면 둘 중 하나가 깨진다 — 그게 이 테스트의 목적이다.
    #[test]
    fn 다음_레벨까지의_경험치가_고정값과_일치한다() {
        assert_eq!(xp_to_next(1), 60);
        assert_eq!(xp_to_next(2), 93);
        assert_eq!(xp_to_next(3), 132);
        assert_eq!(xp_to_next(10), 573);
        assert_eq!(xp_to_next(30), 3_453);
        assert_eq!(xp_to_next(50), 8_733);
        assert_eq!(xp_to_next(70), 16_413);
        assert_eq!(xp_to_next(100), 54_633);
        assert_eq!(xp_to_next(500), 2_456_233);
        assert_eq!(xp_to_next(MAX_LEVEL), 10_386_840);
    }

    #[test]
    fn 칠십_레벨을_넘으면_곡선이_확_꺾인다() {
        // 70 까지는 완만한 2 차 곡선이다.
        let before = xp_to_next(70) - xp_to_next(69);

        // 71 부터는 가속항이 붙어 한 칸 오르는 값이 눈에 띄게 커진다.
        let after = xp_to_next(71) - xp_to_next(70);
        assert!(
            after > before * 2,
            "70 을 넘어선 증가폭({after})이 그 전({before})의 두 배도 안 된다"
        );

        // 그리고 그 격차는 레벨이 오를수록 더 벌어진다.
        let far = xp_to_next(200) - xp_to_next(199);
        assert!(far > after);
    }

    #[test]
    fn 누적_공식이_실제_합과_같다() {
        let mut running: u32 = 0;
        for level in 1..=MAX_LEVEL {
            assert_eq!(
                total_xp_for_level(level),
                running,
                "레벨 {level} 의 누적이 실제 합과 다르다"
            );
            running = running.saturating_add(xp_to_next(level));
        }
    }

    #[test]
    fn 누적에서_레벨을_되돌릴_수_있다() {
        for level in 1..MAX_LEVEL {
            let at = total_xp_for_level(level);
            assert_eq!(level_for_total_xp(at), level);
            assert_eq!(level_for_total_xp(at + xp_to_next(level) - 1), level);
            assert_eq!(level_for_total_xp(at + xp_to_next(level)), level + 1);
        }
    }

    #[test]
    fn 레벨과_진행도가_함께_맞아떨어진다() {
        // 3 레벨은 누적 153 에서 시작하고 다음까지 132 가 든다 → 4 레벨은 285.
        assert_eq!(level_and_progress(153), (3, 0));
        assert_eq!(level_and_progress(200), (3, 47));
        assert_eq!(level_and_progress(284), (3, 131));
        assert_eq!(level_and_progress(285), (4, 0));
        assert_eq!(level_and_progress(0), (1, 0));
    }

    #[test]
    fn 만렙은_구백구십구다() {
        let at_max = total_xp_for_level(MAX_LEVEL);
        assert_eq!(level_for_total_xp(at_max), MAX_LEVEL);

        // 만렙을 넘길 만큼 쌓아도 레벨은 멈춘다.
        assert_eq!(level_for_total_xp(MAX_TOTAL_XP), MAX_LEVEL);
    }

    #[test]
    fn 만렙_이후에도_누적은_쌓여_순위를_가른다() {
        let at_max = total_xp_for_level(MAX_LEVEL);
        let just_max = character(1, at_max, 0);
        let veteran = character(2, at_max + 1_000_000, 0);

        assert_eq!(just_max.level, veteran.level, "둘 다 만렙이어야 한다");
        assert_eq!(
            ranked_ids(vec![just_max, veteran]),
            vec![2, 1],
            "만렙끼리는 더 쌓은 쪽이 앞서야 한다"
        );
    }

    #[test]
    fn 만렙까지의_누적이_u32_안에_들어간다() {
        // 이 성질이 깨지면 `total_xp` 를 u32 로 둘 수 없다. 곡선을 바꿀 때마다
        // 확인해야 하는 조건이라 테스트로 잠가 둔다.
        let at_max = total_xp_for_level(MAX_LEVEL);
        assert_eq!(at_max, 3_357_620_767);
        assert!(at_max < MAX_TOTAL_XP);

        // 만렙 도달 후에도 9 억 넘게 더 쌓을 수 있어야 순위 경쟁이 이어진다.
        assert!(MAX_TOTAL_XP - at_max > 900_000_000);
    }
}
