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

/// 캐릭터가 도달할 수 있는 최고 레벨.
///
/// 클라이언트의 `LevelSystem.maxLevel` 과 같은 값이어야 한다. 클라이언트가
/// 보내는 레벨을 그대로 믿지 않기 위한 상한이므로 서버가 자기 몫을 따로 갖는다.
pub const MAX_LEVEL: u32 = 30;

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

    /// 지금 레벨에서 다음 레벨까지 쌓은 경험치.
    ///
    /// 누적 총량이 아니라 **현재 레벨 안의 진행도**다. 같은 레벨끼리 누가 더
    /// 앞섰는지 가리는 것이 리더보드에서 이 값이 하는 일이고, 그 목적에는
    /// 진행도가 맞다. 클라이언트의 `Player.xp` 도 같은 의미다.
    pub xp: u64,
}

/// 리더보드 정렬 기준: 레벨 내림차순 → 경험치 내림차순 → 생성 순.
///
/// 마지막 두 단계는 동점자를 가르기 위한 것이다. 기준이 없으면 표를 훑는 순서가
/// 바뀔 때마다 순위가 흔들려, 아무 일도 없었는데 목록이 요동치는 것처럼 보인다.
fn rank_key(c: &PlayerCharacter) -> (std::cmp::Reverse<u32>, std::cmp::Reverse<u64>, i64, u64) {
    (
        std::cmp::Reverse(c.level),
        std::cmp::Reverse(c.xp),
        c.created_at.to_micros_since_unix_epoch(),
        c.id,
    )
}

/// `a` 가 `b` 보다 앞 순위인가.
fn outranks(a: &PlayerCharacter, b: &PlayerCharacter) -> bool {
    rank_key(a) < rank_key(b)
}

fn to_entry(rank: u32, c: PlayerCharacter) -> LeaderboardEntry {
    LeaderboardEntry {
        rank,
        character_id: c.id,
        name: c.name,
        kind: c.kind,
        level: c.level,
        xp: c.xp,
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

/// 지금 고른 캐릭터의 성장 상황을 기록한다.
///
/// **이 값은 클라이언트가 신고한 것이다.** 서버가 전투를 시뮬레이션하지 않는
/// 동안에는 달리 알 방법이 없다. 그래서 믿는 대신 다음 두 가지만 강제한다.
///
/// 1. 레벨은 [`MAX_LEVEL`] 을 넘지 못한다.
/// 2. 성장은 되돌아가지 않는다. 지금보다 낮은 레벨이 오면 무시한다.
///
/// 이것으로 막을 수 있는 것은 명백히 불가능한 값뿐이고, 조작된 클라이언트가
/// "그럴듯한 속도로" 레벨을 올려 보내는 것은 막지 못한다. 전투 판정이 서버로
/// 올라오면 그때 이 reducer 는 사라지고 서버가 직접 레벨을 올린다.
#[spacetimedb::reducer]
pub fn report_progress(ctx: &ReducerContext, level: u32, xp: u64) -> Result<(), String> {
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

    if level == 0 || level > MAX_LEVEL {
        return Err(format!("레벨은 1~{MAX_LEVEL} 범위다."));
    }

    // 같은 계정을 여러 기기에서 켜 두면 뒤늦게 도착한 옛 보고가 최신 기록을
    // 덮어쓸 수 있다. 뒤로 가는 갱신을 통째로 버려서 그 경우를 없앤다.
    if level < character.level || (level == character.level && xp <= character.xp) {
        return Ok(());
    }

    ctx.db.player_character().id().update(PlayerCharacter {
        level,
        xp,
        last_played_at: ctx.timestamp,
        ..character
    });

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use spacetimedb::Timestamp;

    fn character(id: u64, level: u32, xp: u64, created_micros: i64) -> PlayerCharacter {
        PlayerCharacter {
            id,
            account_id: 1,
            name: format!("요원{id}"),
            kind: "male_cyborg".to_string(),
            level,
            xp,
            created_at: Timestamp::from_micros_since_unix_epoch(created_micros),
            last_played_at: Timestamp::from_micros_since_unix_epoch(created_micros),
        }
    }

    /// 정렬 결과를 캐릭터 id 순서로 돌려준다.
    fn ranked_ids(mut rows: Vec<PlayerCharacter>) -> Vec<u64> {
        rows.sort_by_key(rank_key);
        rows.into_iter().map(|c| c.id).collect()
    }

    #[test]
    fn 레벨이_높은_쪽이_앞선다() {
        let rows = vec![character(1, 3, 0, 0), character(2, 9, 0, 0), character(3, 5, 0, 0)];
        assert_eq!(ranked_ids(rows), vec![2, 3, 1]);
    }

    #[test]
    fn 레벨이_같으면_경험치로_가른다() {
        let rows = vec![character(1, 7, 10, 0), character(2, 7, 90, 0)];
        assert_eq!(ranked_ids(rows), vec![2, 1]);
    }

    #[test]
    fn 레벨과_경험치가_같으면_먼저_만든_쪽이_앞선다() {
        let rows = vec![character(1, 7, 10, 500), character(2, 7, 10, 100)];
        assert_eq!(ranked_ids(rows), vec![2, 1]);
    }

    #[test]
    fn 생성_시각까지_같으면_id_로_갈라_순서가_흔들리지_않는다() {
        let a = character(7, 4, 4, 0);
        let b = character(3, 4, 4, 0);
        assert!(outranks(&b, &a));
        assert!(!outranks(&a, &b));
    }
}
