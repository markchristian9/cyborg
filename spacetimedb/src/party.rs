//! 파티 — 함께 다니기 위한 것이지 보상을 나누기 위한 것이 아니다.
//!
//! ## 파티가 하는 일과 하지 않는 일
//!
//! 파티는 **누가 누구와 함께 다니는가**만 정한다. 경험치도 드롭도 나누지 않는다.
//! 킬 크레딧은 [`crate::world`] 의 선점 태그 그대로다 — 처음 때린 사람이 몹의
//! 주인이고 경험치는 그 사람에게만 간다.
//!
//! 나누지 않는 이유는 두 가지다.
//!
//! 첫째, **선점 태그는 PK 의 동기와 한 세트다**. "남이 선점한 몹을 뺏고 싶으면
//! 몹이 아니라 그 사람을 쓰러뜨려라"([`crate::world`] 머리말)가 사냥터 다툼을
//! 만든다. 파티에 분배를 넣으면 파티가 곧 상호 PK 면제 구역이 되어 그 동기가
//! 통째로 사라진다.
//!
//! 둘째, **자동 사냥과 추종이 함께 있으면 분배는 곧 봇 농장이 된다.** 여러 계정이
//! 한 사람 뒤를 따라다니게 하는 것이 이 게임에서는 버튼 몇 번이다. 서버는 전투를
//! 보지 않으므로 그것을 가려낼 수단이 없다. 분배가 없으면 그렇게 해서 얻는 것이
//! 없다 — 각자 자기 몹을 자기가 때려야 하므로 계정 수만큼 노동만 늘어난다.
//!
//! ## 추종은 왜 여기에 없는가
//!
//! 이 표들은 "누가 파티원이고 누가 따라가기로 했는가" 라는 **의사**만 담는다.
//! 실제로 따라 걷는 일은 클라이언트가 한다. 서버에 30Hz 시뮬레이션이 없기
//! 때문이다 — 이동 권위는 "클라가 좌표를 보내고 서버는 속도 상한만 본다"
//! ([`crate::world::move_to`])이고, 주기 작업이라고는 5 초 몬스터 리스폰뿐이다.
//! 매 프레임 follower 를 리더 쪽으로 밀어 줄 자리가 서버에는 없다.
//!
//! 그래서 [`PartyMember::following_character_id`] 는 "따라가는 중" 이라는 사실만
//! 기록하고, 그 사실을 본 클라이언트가 자기 자동 사냥의 중심을 리더 위치로 옮긴다.
//!
//! ## 파티는 접속과 함께 끝난다
//!
//! 월드를 떠나면([`on_character_left`]) 파티에서도 빠진다. 접속 종료·강제 종료·
//! 월드 이탈이 모두 같다. 다시 들어오면 새로 맺는다.
//!
//! 남겨 두는 편이 친절해 보이지만 그렇지 않다 — 조종하는 사람이 없는 파티가
//! 생기고, 파티장이 앱을 닫으면 남은 사람은 해산도 위임도 부를 수 없다(둘 다
//! 파티장 전용). 파티는 함께 다니기 위한 것이라 함께 있지 않으면 남겨 둘 이유가
//! 없다.
//!
//! ## 표가 모두 비공개인 이유
//!
//! [`crate`] 의 설계 원칙 3 번(모든 표가 비공개)을 그대로 지킨다.
//! [`crate::world`] 의 세 표가 공개인 것은 "월드에 드러난 사실"이기 때문인데,
//! **남의 파티가 누구로 이뤄졌는지는 월드에 드러난 사실이 아니다.** 게임이
//! 성립하는 데 필요하지도 않다. 그래서 자기 파티만 view 로 본다.
//!
//! ## view 에 좌표와 체력을 싣지 않는 이유
//!
//! view 는 의존하는 표가 바뀔 때마다 다시 계산되어 구독자 전원에게 밀려온다.
//! `world_player` 는 접속자마다 초당 몇 번씩 좌표가 갱신되는 표라, view 가 그것을
//! 읽으면 좌표 보고 하나하나가 파티원 전원에게 재전송을 일으킨다. 그래서 여기서는
//! **멤버십만** 내보내고, 위치·체력·이름은 클라이언트가 이미 구독하고 있는
//! `world_player` 에서 `character_id` 로 맞춰 본다.

use spacetimedb::{ReducerContext, Table, Timestamp, ViewContext, view};

use crate::player_character;
use crate::require_session;
use crate::world::world_player;
// view 안에서 읽는 표는 reducer 와 다른 트레이트로 들어온다(`_ _view` 접미사).
// 읽기 전용 핸들(`LocalReadOnly`)에는 쓰기용 메서드가 아예 없기 때문이다.
use crate::session__view;

// ── 상수 ────────────────────────────────────────────────────────────────

/// 한 파티에 들어갈 수 있는 최대 인원.
///
/// 라리엔은 32 명이지만 그것은 Flutter 오버레이로 목록을 그리기 때문이다. 여기는
/// Flame 캔버스에 직접 그리므로 목록의 스크롤과 잘림을 손으로 만들어야 한다.
///
/// 이 수는 화면 한 칸에 몇 명을 그릴 수 있느냐가 아니라 **한 사람을 따라다니는
/// 무리가 몇 명까지 그림이 되느냐**로 정한다. 추종은 인원이 늘수록 파티장 주위에
/// 겹쳐 서므로, 그 덩어리가 사냥터 하나를 덮을 정도가 되면 다른 사람의 사냥이
/// 성립하지 않는다.
pub const MAX_PARTY_SIZE: usize = 12;

/// 초대가 살아 있는 시간(마이크로초). 20 초.
///
/// 만료를 두는 이유는 손실 대응이 아니라 화면 정리다 — 답하지 않은 초대가 언제까지나
/// 떠 있으면, 한참 전에 지나간 제안을 수락해 엉뚱한 곳으로 끌려간다.
const INVITE_TTL_MICROS: i64 = 20_000_000;

/// 한 번에 부를 때 닿는 거리(타일 = m).
///
/// 눈앞에 함께 서 있는 사람들을 부르는 기능이라 화면에 보이는 범위를 넘지 않는다.
/// 넓히면 얼굴도 못 본 사람에게 초대가 날아가고, 받는 쪽에는 그것이 광고와
/// 구별되지 않는다.
const NEARBY_INVITE_RANGE_TILES: f32 = 30.0;

// ── 표 ──────────────────────────────────────────────────────────────────

/// 파티 하나.
#[spacetimedb::table(
    accessor = party,
    index(accessor = by_leader, btree(columns = [leader_character_id]))
)]
pub struct Party {
    #[primary_key]
    #[auto_inc]
    pub id: u64,

    /// 파티장. 초대·추방·위임을 할 수 있는 유일한 캐릭터다.
    ///
    /// 리더가 누구인지는 **여기 한 곳에만** 둔다. 멤버 행에도 `is_leader` 를 두면
    /// 위임할 때 두 곳을 함께 고쳐야 하고, 한쪽만 고쳐진 상태가 존재할 수 있다.
    ///
    /// **[`hunt_lead_character_id`](Party::hunt_lead_character_id) 와 다른
    /// 축이다.** 파티장은 파티를 만든 사람이고, 사냥을 이끄는 사람은 그때그때
    /// 먼저 나선 사람이다. 둘이 같을 수도 다를 수도 있다.
    pub leader_character_id: u64,

    pub created_at: Timestamp,

    /// 지금 사냥을 이끄는 사람. 아무도 이끌지 않으면 `None`.
    ///
    /// ## 왜 파티장과 나누는가
    ///
    /// 파티장은 **누가 파티에 있는지**를 정하고, 이 사람은 **어디로 갈지**를
    /// 정한다. 다른 일이므로 같은 사람이어야 할 이유가 없다 — 길을 아는 사람이
    /// 앞장서고 파티장은 뒤따라도 된다. 형제 게임 라리엔이 같은 결론에 도달했다
    /// (`docs/party.md` §10.5.1 — "파티장의 권한 기능이 아니라 임시 사냥 지휘").
    ///
    /// ## 왜 별도 표가 아닌가
    ///
    /// 파티 하나에 행이 하나이므로 **"파티당 이끌기는 하나"가 구조로 강제된다.**
    /// 따로 표를 두면 그 제약을 손으로 검사해야 하고, 두 곳이 어긋난 상태가
    /// 생길 수 있다.
    ///
    /// 그리고 파티원 전원이 이미 [`my_party`] 를 구독하므로, 이 값이 채워지는
    /// 순간이 곧 전원에게 알리는 순간이다. 라리엔이 초대를 따로 방송한 것은
    /// UDP 라 행 구독이 없었기 때문이지 그 방식이 더 나아서가 아니다.
    ///
    /// **맨 끝에 있고 기본값이 있어야 한다** — 이미 배포된 표라 자동 마이그레이션이
    /// 두 조건을 요구한다([`PartyMember::following_character_id`] 와 같은 이유).
    #[default(None::<u64>)]
    pub hunt_lead_character_id: Option<u64>,

    /// 이끌기가 시작될 때마다 오르는 번호.
    ///
    /// 참여할 때 이 값을 함께 보내 **어느 이끌기에 참여하는지** 못 박는다. 없으면
    /// 이런 일이 생긴다 — A 가 이끌기를 시작하고, B 가 참여를 누르려는 사이에 A 가
    /// 그만두고 C 가 새로 시작하면, B 의 늦은 참여가 C 를 따라가게 된다. 누른
    /// 것과 다른 결과다.
    ///
    /// `auto_inc` 를 쓰지 않는 이유는 그것이 연속을 보장하지 않기 때문이다. 여기
    /// 필요한 것은 순서가 아니라 **직전 것과 다르다는 사실**이라 직접 센다.
    #[default(0u64)]
    pub hunt_lead_seq: u64,

    // 이끄는 사람의 **이름은 여기 두지 않는다.** 자동 마이그레이션의 기본값은
    // 상수 자리에서 만들어지는데 `String` 은 거기서 만들 수 없다. 대신 따라가는
    // 쪽이 그 사람을 직접 구독하므로(관심 영역 밖이어도) 이름이 함께 온다.
}

/// 파티에 속한 캐릭터 한 명.
#[spacetimedb::table(
    accessor = party_member,
    index(accessor = by_party, btree(columns = [party_id]))
)]
pub struct PartyMember {
    /// 한 캐릭터는 한 파티에만 속한다. 기본 키가 그것을 DB 수준에서 막는다.
    #[primary_key]
    pub character_id: u64,

    // 인덱스는 표 수준 `by_party` 하나로 충분하다. 여기에 또 붙이면 같은 열에
    // 같은 이름의 인덱스가 두 번 생겨 배포가 거부된다.
    pub party_id: u64,

    pub joined_at: Timestamp,

    /// 지금 따라다니기로 한 상대. 따라가지 않으면 `None`.
    ///
    /// 값을 `bool` 이 아니라 **누구를** 따르는지로 둔 이유는, 나중에 "파티장이
    /// 아닌 사람을 따라간다"(라리엔의 hunt lead)로 넓힐 때 표를 바꾸지 않아도
    /// 되기 때문이다. 지금은 파티장만 들어간다.
    ///
    /// **맨 끝에 있고 기본값이 있어야 한다.** 이미 배포된 표에 열을 더하는 자동
    /// 마이그레이션이 두 조건을 모두 요구한다. 타입도 못 박아야 한다 — 그냥
    /// `None` 으로 두면 무엇의 `None` 인지 추론하지 못해 컴파일이 멈춘다.
    #[default(None::<u64>)]
    pub following_character_id: Option<u64>,
}

/// 아직 답하지 않은 초대.
#[spacetimedb::table(
    accessor = party_invite,
    index(accessor = by_target, btree(columns = [to_character_id])),
    index(accessor = by_party_invite, btree(columns = [party_id]))
)]
pub struct PartyInvite {
    #[primary_key]
    #[auto_inc]
    pub id: u64,

    pub party_id: u64,
    pub from_character_id: u64,

    /// 초대한 사람의 이름. 초대 시점에 한 번 복사한다.
    ///
    /// 이름을 캐릭터 표에서 그때그때 읽지 않는 이유는 view 재계산 때문이다 — 초대
    /// 목록이 `player_character` 를 읽으면 누군가 레벨업할 때마다 초대 목록이
    /// 다시 계산되어 밀려온다. 초대는 20 초짜리라 그동안 이름이 바뀔 일도 없다.
    pub from_name: String,

    // 표 수준 `by_target` 이 이 열을 이미 덮는다.
    pub to_character_id: u64,

    pub created_at: Timestamp,

    /// 이 시각이 지나면 없는 초대로 친다.
    pub expires_at: Timestamp,
}

// ── view ────────────────────────────────────────────────────────────────

/// 내가 속한 파티. 없으면 `None`.
#[view(accessor = my_party, public)]
fn my_party(ctx: &ViewContext) -> Option<Party> {
    let character_id = view_character_id(ctx)?;
    let member = ctx.db.party_member().character_id().find(character_id)?;
    ctx.db.party().id().find(member.party_id)
}

/// 내 파티의 멤버 전원. 파티가 없으면 빈 목록이다.
///
/// 이름·레벨·좌표·체력이 없는 것은 일부러다(모듈 머리말 참조). 클라이언트는 이
/// 목록의 `character_id` 를 `world_player` 와 맞춰 화면에 그린다.
#[view(accessor = my_party_members, public)]
fn my_party_members(ctx: &ViewContext) -> Vec<PartyMember> {
    let Some(character_id) = view_character_id(ctx) else {
        return Vec::new();
    };
    let Some(member) = ctx.db.party_member().character_id().find(character_id) else {
        return Vec::new();
    };
    ctx.db.party_member().by_party().filter(member.party_id).collect()
}

/// 나에게 온 초대.
///
/// **만료된 것을 걸러 내지 않는다.** view 는 시각을 읽을 수 없기 때문이다
/// (`ViewContext` 에는 `timestamp` 가 없다 — 같은 입력에 늘 같은 결과를 내야 하는
/// 읽기이므로 흐르는 시간에 기대면 안 된다). 그래서 `expires_at` 을 그대로 실어
/// 보내고 화면에서 지날 때 지운다.
///
/// 클라이언트 시계를 믿는 것처럼 보이지만 그렇지 않다 — 만료를 **판정**하는 곳은
/// [`accept_invite`] 이고 거기서는 서버 시각으로 본다. 화면의 판단은 표시일 뿐이라,
/// 시계를 조작해 지난 초대를 눌러도 서버가 거절한다.
#[view(accessor = my_party_invites, public)]
fn my_party_invites(ctx: &ViewContext) -> Vec<PartyInvite> {
    let Some(character_id) = view_character_id(ctx) else {
        return Vec::new();
    };
    ctx.db.party_invite().by_target().filter(character_id).collect()
}

// ── reducer ─────────────────────────────────────────────────────────────

/// 파티를 만들고 스스로 파티장이 된다.
///
/// 이미 파티가 있으면 거절한다. 한 캐릭터가 두 파티에 속할 수 없다는 규칙은
/// [`PartyMember`] 의 기본 키가 이미 강제하지만, 여기서 먼저 걸러야 "이미 파티에
/// 있다" 는 뜻이 분명한 오류가 나간다.
#[spacetimedb::reducer]
pub fn create_party(ctx: &ReducerContext) -> Result<(), String> {
    let character_id = require_character(ctx)?;

    if ctx.db.party_member().character_id().find(character_id).is_some() {
        return Err("이미 파티에 속해 있다.".to_string());
    }

    let party = ctx.db.party().insert(Party {
        id: 0,
        leader_character_id: character_id,
        created_at: ctx.timestamp,
        hunt_lead_character_id: None,
        hunt_lead_seq: 0,
    });

    ctx.db.party_member().insert(PartyMember {
        character_id,
        party_id: party.id,
        joined_at: ctx.timestamp,
        following_character_id: None,
    });

    Ok(())
}

/// 월드에 있는 다른 캐릭터를 내 파티로 초대한다.
///
/// ## 남을 지목하는 인자를 받아도 되는 이유
///
/// [`crate`] 의 원칙 1 번은 "남의 것을 조작하지 못하게 소유자를 세션에서 도출한다"
/// 이다. 초대는 그 원칙을 어기지 않는다 — 여기서 일어나는 일은 **제안**이고,
/// 실제 가입은 대상 본인이 [`accept_invite`] 를 부를 때만 일어난다. 남의 파티
/// 소속을 이 호출로 바꿀 수는 없다.
///
/// 파티가 없으면 먼저 만든다. 초대하려면 파티부터 만들라고 요구하면, 화면에서는
/// 버튼 한 번인 일이 서버 왕복 두 번이 되고 그 사이에 실패할 자리가 생긴다.
#[spacetimedb::reducer]
pub fn invite_to_party(ctx: &ReducerContext, target_character_id: u64) -> Result<(), String> {
    let character_id = require_character(ctx)?;

    if target_character_id == character_id {
        return Err("자기 자신은 초대할 수 없다.".to_string());
    }

    // 상대가 월드에 있어야 초대할 수 있다. 접속하지 않은 캐릭터에게 초대를 보내면
    // 20 초 뒤 조용히 사라질 뿐이고, 보낸 쪽은 왜 답이 없는지 알 길이 없다.
    if ctx
        .db
        .world_player()
        .character_id()
        .find(target_character_id)
        .is_none()
    {
        return Err("상대가 월드에 없다.".to_string());
    }

    if ctx
        .db
        .party_member()
        .character_id()
        .find(target_character_id)
        .is_some()
    {
        return Err("상대가 이미 다른 파티에 있다.".to_string());
    }

    // 파티가 없으면 지금 만든다. 있으면 자리가 남았는지만 본다.
    let party_id = ensure_party(ctx, character_id)?;

    sweep_expired_invites(ctx, target_character_id);

    // 같은 사람에게 두 번 보내면 화면에 초대가 두 개 뜬다. 이미 살아 있는 초대가
    // 있으면 시각만 미뤄 하나로 유지한다.
    if let Some(existing) = ctx
        .db
        .party_invite()
        .by_target()
        .filter(target_character_id)
        .find(|invite| invite.party_id == party_id)
    {
        ctx.db.party_invite().id().update(PartyInvite {
            created_at: ctx.timestamp,
            expires_at: ctx.timestamp + invite_ttl(),
            ..existing
        });
        return Ok(());
    }

    let name = character_name(ctx, character_id);

    ctx.db.party_invite().insert(PartyInvite {
        id: 0,
        party_id,
        from_character_id: character_id,
        from_name: name,
        to_character_id: target_character_id,
        created_at: ctx.timestamp,
        expires_at: ctx.timestamp + invite_ttl(),
    });

    Ok(())
}

/// 주변에 있는 요원을 **한 번에** 부른다.
///
/// 한 명씩 눌러 부르는 것과 결과는 같지만, 여럿이 함께 서 있는 자리에서는 그
/// 반복이 곧 일이 된다.
///
/// **이미 파티가 있는 사람에게는 보내지 않는다.** 받는 쪽에서 거절할 수밖에 없는
/// 초대는 보내지 않는 편이 낫고, 보내는 쪽도 "왜 다들 거절하지" 라는 오해를 하지
/// 않는다. 자리가 남는 만큼만 부르는 것도 같은 이유다.
///
/// 몇 명에게 보냈는지 세어 돌려주지 않는 이유는 reducer 가 값을 돌려줄 수 없기
/// 때문이다. 화면은 초대가 오간 결과를 표로 보게 된다.
#[spacetimedb::reducer]
pub fn invite_nearby(ctx: &ReducerContext) -> Result<(), String> {
    let character_id = require_character(ctx)?;

    let me = ctx
        .db
        .world_player()
        .character_id()
        .find(character_id)
        .ok_or_else(|| "먼저 월드에 들어가야 한다.".to_string())?;

    let party_id = ensure_party(ctx, character_id)?;

    // 남은 자리를 먼저 센다. 자리보다 많이 부르면 뒤에 수락한 사람이 문 앞에서
    // 거절당한다.
    let mut room = MAX_PARTY_SIZE.saturating_sub(party_size(ctx, party_id));
    if room == 0 {
        return Err(format!("파티가 가득 찼다(최대 {MAX_PARTY_SIZE}명)."));
    }

    let range_sq = NEARBY_INVITE_RANGE_TILES * NEARBY_INVITE_RANGE_TILES;
    let mut invited = 0u32;

    // 가까운 사람부터 부른다. 자리가 모자랄 때 누가 뽑히는지가 거리로 정해져야
    // 표를 훑는 순서에 좌우되지 않는다.
    let mut candidates: Vec<(u64, u64)> = Vec::new();
    for other in ctx.db.world_player().iter() {
        let target = other.character_id;
        if target == character_id {
            continue;
        }
        let d = dist_sq(me.grid_x, me.grid_y, other.grid_x, other.grid_y);
        if d > range_sq {
            continue;
        }
        // 이미 어딘가에 속한 사람은 부르지 않는다.
        if ctx.db.party_member().character_id().find(target).is_some() {
            continue;
        }
        // 거리를 정수로 바꿔 정렬 기준으로 쓴다. 같은 거리면 번호로 가른다.
        candidates.push(((d * 1000.0) as u64, target));
    }
    candidates.sort_unstable();

    let name = character_name(ctx, character_id);

    for (_, target) in candidates {
        if room == 0 {
            break;
        }
        sweep_expired_invites(ctx, target);

        // 이미 보낸 초대가 살아 있으면 시각만 미룬다. 두 번 보내면 화면에 두 개가
        // 뜬다.
        if let Some(existing) = ctx
            .db
            .party_invite()
            .by_target()
            .filter(target)
            .find(|invite| invite.party_id == party_id)
        {
            ctx.db.party_invite().id().update(PartyInvite {
                created_at: ctx.timestamp,
                expires_at: ctx.timestamp + invite_ttl(),
                ..existing
            });
            continue;
        }

        ctx.db.party_invite().insert(PartyInvite {
            id: 0,
            party_id,
            from_character_id: character_id,
            from_name: name.clone(),
            to_character_id: target,
            created_at: ctx.timestamp,
            expires_at: ctx.timestamp + invite_ttl(),
        });
        room -= 1;
        invited += 1;
    }

    if invited == 0 {
        return Err("주변에 부를 수 있는 요원이 없다.".to_string());
    }

    log::info!("{character_id} 가 주변 {invited} 명을 파티로 불렀다.");
    Ok(())
}

/// 받은 초대를 수락해 파티에 들어간다.
///
/// `invite_id` 를 받는 것은 **어느 초대인지 못 박기 위해서**다. 여러 파티에서
/// 동시에 초대가 오거나, 거절한 직후 새 초대가 도착하는 사이에 화면이 예전 것을
/// 눌러 엉뚱한 파티에 들어가는 일을 막는다. 라리엔이 같은 이유로 `leadSeq` 를
/// 둔다(`docs/party.md` §10.5.4).
#[spacetimedb::reducer]
pub fn accept_invite(ctx: &ReducerContext, invite_id: u64) -> Result<(), String> {
    let character_id = require_character(ctx)?;

    let invite = ctx
        .db
        .party_invite()
        .id()
        .find(invite_id)
        .ok_or_else(|| "초대를 찾을 수 없다.".to_string())?;

    // 남에게 온 초대를 가로챌 수 없다.
    if invite.to_character_id != character_id {
        return Err("나에게 온 초대가 아니다.".to_string());
    }

    if invite.expires_at <= ctx.timestamp {
        ctx.db.party_invite().id().delete(invite_id);
        return Err("초대가 만료되었다.".to_string());
    }

    if ctx.db.party_member().character_id().find(character_id).is_some() {
        return Err("이미 파티에 속해 있다.".to_string());
    }

    // 초대가 오는 사이에 파티가 해산했을 수 있다.
    let party = ctx
        .db
        .party()
        .id()
        .find(invite.party_id)
        .ok_or_else(|| "파티가 이미 사라졌다.".to_string())?;

    if party_size(ctx, party.id) >= MAX_PARTY_SIZE {
        return Err(format!("파티가 가득 찼다(최대 {MAX_PARTY_SIZE}명)."));
    }

    ctx.db.party_member().insert(PartyMember {
        character_id,
        party_id: party.id,
        joined_at: ctx.timestamp,
        following_character_id: None,
    });

    // 들어갔으니 나에게 온 초대는 전부 정리한다. 다른 파티의 초대가 남아 있으면
    // 화면에 수락할 수 없는 제안이 계속 떠 있다.
    clear_invites_for(ctx, character_id);

    Ok(())
}

/// 받은 초대를 거절한다.
#[spacetimedb::reducer]
pub fn decline_invite(ctx: &ReducerContext, invite_id: u64) -> Result<(), String> {
    let character_id = require_character(ctx)?;

    let invite = ctx
        .db
        .party_invite()
        .id()
        .find(invite_id)
        .ok_or_else(|| "초대를 찾을 수 없다.".to_string())?;

    if invite.to_character_id != character_id {
        return Err("나에게 온 초대가 아니다.".to_string());
    }

    ctx.db.party_invite().id().delete(invite_id);
    Ok(())
}

/// 파티에서 나간다.
///
/// 파티장이 나가면 **가장 오래 있은 사람에게 자리를 넘긴다.** 해산시키지 않는
/// 이유는, 파티장의 접속이 잠깐 끊기는 것만으로 남은 사람들이 흩어지면 함께
/// 다니려고 맺은 파티가 너무 쉽게 사라지기 때문이다. 혼자 남으면 그때 해산한다 —
/// 한 명짜리 파티는 파티가 아니다.
#[spacetimedb::reducer]
pub fn leave_party(ctx: &ReducerContext) -> Result<(), String> {
    let character_id = require_character(ctx)?;
    let member = ctx
        .db
        .party_member()
        .character_id()
        .find(character_id)
        .ok_or_else(|| "속한 파티가 없다.".to_string())?;

    remove_member(ctx, member.party_id, character_id);
    Ok(())
}

/// 파티를 해산한다. 파티장만 할 수 있다.
#[spacetimedb::reducer]
pub fn disband_party(ctx: &ReducerContext) -> Result<(), String> {
    let character_id = require_character(ctx)?;
    let party = require_leadership(ctx, character_id)?;

    let members: Vec<u64> = ctx
        .db
        .party_member()
        .by_party()
        .filter(party.id)
        .map(|m| m.character_id)
        .collect();
    for id in members {
        ctx.db.party_member().character_id().delete(id);
    }

    let invites: Vec<u64> = ctx
        .db
        .party_invite()
        .by_party_invite()
        .filter(party.id)
        .map(|i| i.id)
        .collect();
    for id in invites {
        ctx.db.party_invite().id().delete(id);
    }

    ctx.db.party().id().delete(party.id);
    Ok(())
}

/// 파티원을 내보낸다. 파티장만 할 수 있다.
///
/// 라리엔은 멤버십 권위가 Zone 밖(Nakama)에 있어 "추방하면 본인이 스스로 나간다"
/// 는 우회를 만들어야 했다(`docs/party.md` §10.1). 여기는 권위가 하나뿐이라
/// 그럴 이유가 없다 — 자격을 확인하고 바로 지운다. 우회를 따라 하면 없는 문제를
/// 흉내 내는 셈이 된다.
#[spacetimedb::reducer]
pub fn kick_member(ctx: &ReducerContext, target_character_id: u64) -> Result<(), String> {
    let character_id = require_character(ctx)?;
    let party = require_leadership(ctx, character_id)?;

    if target_character_id == character_id {
        return Err("파티장은 자기를 내보낼 수 없다. 나가려면 탈퇴하라.".to_string());
    }

    let target = ctx
        .db
        .party_member()
        .character_id()
        .find(target_character_id)
        .ok_or_else(|| "그 캐릭터는 파티에 없다.".to_string())?;

    if target.party_id != party.id {
        return Err("그 캐릭터는 내 파티가 아니다.".to_string());
    }

    remove_member(ctx, party.id, target_character_id);
    Ok(())
}

/// 파티장 자리를 넘긴다. 파티장만 할 수 있다.
#[spacetimedb::reducer]
pub fn promote_leader(ctx: &ReducerContext, target_character_id: u64) -> Result<(), String> {
    let character_id = require_character(ctx)?;
    let party = require_leadership(ctx, character_id)?;

    let target = ctx
        .db
        .party_member()
        .character_id()
        .find(target_character_id)
        .ok_or_else(|| "그 캐릭터는 파티에 없다.".to_string())?;

    if target.party_id != party.id {
        return Err("그 캐릭터는 내 파티가 아니다.".to_string());
    }

    let old_leader = party.leader_character_id;

    ctx.db.party().id().update(Party {
        leader_character_id: target_character_id,
        ..party
    });

    // 새 파티장이 자기를 따라가는 상태로 남아 있으면 안 된다.
    if target.following_character_id.is_some() {
        ctx.db.party_member().character_id().update(PartyMember {
            following_character_id: None,
            ..target
        });
    }

    // 옛 파티장을 따라가던 사람들을 새 파티장에게 넘긴다.
    //
    // 이들의 의사는 "저 사람" 이 아니라 **파티장을 따라가겠다**는 것이었다. 그대로
    // 두면 기록은 옛 파티장을 가리키는데 화면은 새 파티장을 따라가는, 서로 다른
    // 두 이야기가 된다. 자리를 넘기는 것은 파티장이 스스로 한 일이고 파티는
    // 그대로이므로 따라가던 의사도 이어진다.
    //
    // 파티장이 **나가는** 경우는 다르게 다룬다([`remove_member`]) — 그때는 파티가
    // 깨진 상황이라, 동의한 적 없는 사람을 자동으로 따라가게 하지 않는다.
    let followers: Vec<PartyMember> = ctx
        .db
        .party_member()
        .by_party()
        .filter(party.id)
        .filter(|m| {
            m.following_character_id == Some(old_leader)
                && m.character_id != target_character_id
        })
        .collect();
    for member in followers {
        ctx.db.party_member().character_id().update(PartyMember {
            following_character_id: Some(target_character_id),
            ..member
        });
    }

    Ok(())
}

/// 파티장을 따라다니겠다고 알리거나 그만둔다.
///
/// 서버가 하는 일은 **의사를 기록하는 것뿐**이다. 실제로 따라 걷고 주변 몹을
/// 사냥하는 것은 클라이언트가 한다(모듈 머리말 참조). 그런데도 이 상태를 서버에
/// 두는 이유는, 파티원들이 "누가 따라오고 있는지" 를 서로 볼 수 있어야 하고 그
/// 사실이 한 곳에서만 정해져야 하기 때문이다.
#[spacetimedb::reducer]
pub fn set_following(ctx: &ReducerContext, following: bool) -> Result<(), String> {
    let character_id = require_character(ctx)?;
    let member = ctx
        .db
        .party_member()
        .character_id()
        .find(character_id)
        .ok_or_else(|| "속한 파티가 없다.".to_string())?;

    if !following {
        ctx.db.party_member().character_id().update(PartyMember {
            following_character_id: None,
            ..member
        });
        return Ok(());
    }

    // 따라가겠다는 뜻만으로는 누구를 따라갈지 정할 수 없다. 이끄는 사람이 바뀌는
    // 사이에 늦게 도착한 요청이 엉뚱한 사람에게 붙지 않도록, 참여는 어느 이끌기인지
    // 함께 밝히는 [`accept_hunt_lead`] 로만 받는다.
    Err("참여할 이끌기를 지정해야 한다.".to_string())
}

/// 사냥을 이끌기 시작한다. **파티원이면 누구나** 할 수 있다.
///
/// 파티장의 권한이 아니다 — 파티장은 누가 파티에 있는지를 정하고, 이끄는 사람은
/// 어디로 갈지를 정한다. 길을 아는 사람이 앞장서면 된다.
///
/// 파티당 하나만 돌아간다. 이미 누가 이끌고 있으면 거절하는데, 가로채기를 허용하면
/// 따라가던 사람들이 영문도 모른 채 다른 방향으로 끌려간다.
#[spacetimedb::reducer]
pub fn start_hunt_lead(ctx: &ReducerContext) -> Result<(), String> {
    let character_id = require_character(ctx)?;
    let member = ctx
        .db
        .party_member()
        .character_id()
        .find(character_id)
        .ok_or_else(|| "속한 파티가 없다.".to_string())?;

    let party = ctx
        .db
        .party()
        .id()
        .find(member.party_id)
        .ok_or_else(|| "파티를 찾을 수 없다.".to_string())?;

    if let Some(current) = party.hunt_lead_character_id {
        if current == character_id {
            return Err("이미 이끌고 있다.".to_string());
        }
        return Err("다른 요원이 이끌고 있다.".to_string());
    }

    // 이끄는 사람이 남을 따라갈 수는 없다. 앞장서면서 뒤따르는 상태는 없다.
    if member.following_character_id.is_some() {
        ctx.db.party_member().character_id().update(PartyMember {
            following_character_id: None,
            ..member
        });
    }

    ctx.db.party().id().update(Party {
        hunt_lead_character_id: Some(character_id),
        hunt_lead_seq: party.hunt_lead_seq.saturating_add(1),
        ..party
    });

    Ok(())
}

/// 이끌기를 그만둔다. **이끄는 본인만** 할 수 있다.
///
/// 따라가던 사람들의 추종도 함께 푼다. 이끄는 사람이 사라졌는데 따라가는 상태만
/// 남으면, 화면은 없는 사람을 향해 계속 걸으려 한다.
#[spacetimedb::reducer]
pub fn stop_hunt_lead(ctx: &ReducerContext) -> Result<(), String> {
    let character_id = require_character(ctx)?;
    let member = ctx
        .db
        .party_member()
        .character_id()
        .find(character_id)
        .ok_or_else(|| "속한 파티가 없다.".to_string())?;

    let party = ctx
        .db
        .party()
        .id()
        .find(member.party_id)
        .ok_or_else(|| "파티를 찾을 수 없다.".to_string())?;

    if party.hunt_lead_character_id != Some(character_id) {
        return Err("이끄는 중이 아니다.".to_string());
    }

    end_hunt_lead(ctx, party);
    Ok(())
}

/// 진행 중인 이끌기에 참여한다.
///
/// [`lead_seq`](Party::hunt_lead_seq) 를 함께 받아 **어느 이끌기인지** 대조한다.
/// 화면에 떠 있던 버튼이 오래된 것일 수 있고, 그 사이 이끄는 사람이 바뀌었다면
/// 참여를 거절해야 누른 것과 다른 결과가 나오지 않는다.
#[spacetimedb::reducer]
pub fn accept_hunt_lead(ctx: &ReducerContext, lead_seq: u64) -> Result<(), String> {
    let character_id = require_character(ctx)?;
    let member = ctx
        .db
        .party_member()
        .character_id()
        .find(character_id)
        .ok_or_else(|| "속한 파티가 없다.".to_string())?;

    let party = ctx
        .db
        .party()
        .id()
        .find(member.party_id)
        .ok_or_else(|| "파티를 찾을 수 없다.".to_string())?;

    let Some(leader) = party.hunt_lead_character_id else {
        return Err("이끄는 요원이 없다.".to_string());
    };

    if party.hunt_lead_seq != lead_seq {
        return Err("이미 끝난 이끌기다.".to_string());
    }

    if leader == character_id {
        return Err("자기 자신을 따라갈 수는 없다.".to_string());
    }

    ctx.db.party_member().character_id().update(PartyMember {
        following_character_id: Some(leader),
        ..member
    });

    Ok(())
}

// ── 내부 헬퍼 ───────────────────────────────────────────────────────────

/// view 안에서 호출자가 고른 캐릭터를 꺼낸다.
///
/// reducer 쪽 [`require_character`] 와 하는 일은 같지만 컨텍스트 타입이 달라
/// 공유할 수 없다. view 는 실패를 에러로 알릴 수단이 없으므로 `Option` 을 준다 —
/// 로그인하지 않았거나 캐릭터를 고르지 않은 상태는 오류가 아니라 "아직 볼 것이
/// 없는" 정상 상태다.
fn view_character_id(ctx: &ViewContext) -> Option<u64> {
    ctx.db
        .session()
        .identity()
        .find(ctx.sender())?
        .selected_character_id
}

/// 호출자가 고른 캐릭터를 꺼낸다.
///
/// [`crate::world::require_world_player`] 를 쓰지 않고 세션에서 바로 도출하는
/// 이유는 파티를 다루는 동작 중 일부가 월드 밖에서도 성립하기 때문이다(받은
/// 초대를 거절하는 것 따위). 월드를 **떠나면** 파티에서도 빠지지만
/// ([`on_character_left`]), 그 판단은 여기가 아니라 떠나는 자리에서 한다.
fn require_character(ctx: &ReducerContext) -> Result<u64, String> {
    let session = require_session(ctx)?;
    session
        .selected_character_id
        .ok_or_else(|| "플레이할 캐릭터를 먼저 골라라.".to_string())
}

/// 호출자가 파티장인 파티를 꺼낸다. 아니면 에러다.
fn require_leadership(ctx: &ReducerContext, character_id: u64) -> Result<Party, String> {
    let member = ctx
        .db
        .party_member()
        .character_id()
        .find(character_id)
        .ok_or_else(|| "속한 파티가 없다.".to_string())?;

    let party = ctx
        .db
        .party()
        .id()
        .find(member.party_id)
        .ok_or_else(|| "파티를 찾을 수 없다.".to_string())?;

    if party.leader_character_id != character_id {
        return Err("파티장만 할 수 있다.".to_string());
    }

    Ok(party)
}

fn party_size(ctx: &ReducerContext, party_id: u64) -> usize {
    ctx.db.party_member().by_party().filter(party_id).count()
}

fn invite_ttl() -> spacetimedb::TimeDuration {
    spacetimedb::TimeDuration::from_micros(INVITE_TTL_MICROS)
}

/// 캐릭터 이름. 사라졌으면 빈 문자열.
fn character_name(ctx: &ReducerContext, character_id: u64) -> String {
    ctx.db
        .player_character()
        .id()
        .find(character_id)
        .map(|c| c.name)
        .unwrap_or_default()
}

/// 만료된 초대를 지운다.
///
/// 별도의 정리 타이머를 두지 않는 이유는 초대가 오래 쌓이는 종류의 데이터가
/// 아니기 때문이다. 초대를 보내거나 받을 때 그 사람 몫만 훑으면 충분하고,
/// 스케줄 표를 하나 더 두는 값을 하지 않는다.
fn sweep_expired_invites(ctx: &ReducerContext, character_id: u64) {
    let now = ctx.timestamp;
    let stale: Vec<u64> = ctx
        .db
        .party_invite()
        .by_target()
        .filter(character_id)
        .filter(|invite| invite.expires_at <= now)
        .map(|invite| invite.id)
        .collect();
    for id in stale {
        ctx.db.party_invite().id().delete(id);
    }
}

/// 그 캐릭터에게 온 초대를 전부 지운다.
fn clear_invites_for(ctx: &ReducerContext, character_id: u64) {
    let ids: Vec<u64> = ctx
        .db
        .party_invite()
        .by_target()
        .filter(character_id)
        .map(|invite| invite.id)
        .collect();
    for id in ids {
        ctx.db.party_invite().id().delete(id);
    }
}

/// 월드를 떠난 캐릭터를 파티에서 빼낸다.
///
/// 접속 종료·강제 종료·월드 이탈이 모두 여기로 온다. **파티는 접속과 함께
/// 끝난다** — 다시 들어오면 새로 맺는다.
///
/// ## 왜 남겨 두지 않는가
///
/// 처음에는 "잠깐 자리를 비운 것과 파티를 떠난 것은 다르다" 는 이유로 남겨
/// 뒀는데, 그렇게 두면 조종하는 사람이 없는 파티가 생긴다. 파티장이 앱을 닫으면
/// 남은 사람은 해산도 위임도 부를 수 없고(둘 다 파티장 전용), 각자 나가는 것
/// 말고는 손쓸 방법이 없다. 파티는 함께 다니기 위한 것이라 함께 있지 않으면
/// 남겨 둘 이유가 없다.
///
/// 뒤처리는 [`remove_member`] 가 한다 — 이끌기 종료, 따라가던 사람 해제,
/// 파티장 승계, 혼자 남으면 해체까지 한 곳에서 일어난다.
pub(crate) fn on_character_left(ctx: &ReducerContext, character_id: u64) {
    // 답하지 않은 초대부터 지운다. 파티에 속하지 않은 사람도 초대는 받아 둘 수
    // 있으므로 멤버십과 따로 정리해야 한다.
    clear_invites_for(ctx, character_id);

    let sent: Vec<u64> = ctx
        .db
        .party_invite()
        .iter()
        .filter(|invite| invite.from_character_id == character_id)
        .map(|invite| invite.id)
        .collect();
    for id in sent {
        ctx.db.party_invite().id().delete(id);
    }

    if let Some(member) = ctx.db.party_member().character_id().find(character_id) {
        remove_member(ctx, member.party_id, character_id);
    }
}

/// 두 점 사이 거리의 제곱. 제곱근을 피해 비교만 한다.
fn dist_sq(ax: f32, ay: f32, bx: f32, by: f32) -> f32 {
    let dx = ax - bx;
    let dy = ay - by;
    dx * dx + dy * dy
}

/// 부르는 사람의 파티를 확보한다. 없으면 만들고, 있으면 자리가 남았는지 본다.
///
/// 초대는 두 갈래([`invite_to_party`]·[`invite_nearby`])인데 앞단이 똑같다 —
/// 파티가 없으면 만들고, 있으면 자리를 본다. 한 곳에 모아 두 갈래가 어긋나지
/// 않게 한다.
///
/// ## 파티장만 부를 수 있게 하지 않는 이유
///
/// 파티는 함께 다니려고 맺는 것이지 위계가 아니다. 아는 사람을 만났을 때 파티장을
/// 찾아 부탁해야 한다면, 그 사람은 대개 그냥 지나간다. 이끌기를 누구나 할 수 있게
/// 한 것과 같은 판단이다 — 파티장이 쥐는 것은 **내보내는 일**(추방·해산)이지
/// 불러들이는 일이 아니다.
///
/// 들어오는 쪽은 어차피 본인이 수락해야 하므로, 아무나 부를 수 있어도 남의 파티에
/// 강제로 넣는 일은 생기지 않는다.
fn ensure_party(ctx: &ReducerContext, character_id: u64) -> Result<u64, String> {
    match ctx.db.party_member().character_id().find(character_id) {
        Some(member) => {
            let party = ctx
                .db
                .party()
                .id()
                .find(member.party_id)
                .ok_or_else(|| "파티를 찾을 수 없다.".to_string())?;
            if party_size(ctx, party.id) >= MAX_PARTY_SIZE {
                return Err(format!("파티가 가득 찼다(최대 {MAX_PARTY_SIZE}명)."));
            }
            Ok(party.id)
        }
        None => {
            let party = ctx.db.party().insert(Party {
                id: 0,
                leader_character_id: character_id,
                created_at: ctx.timestamp,
                hunt_lead_character_id: None,
                hunt_lead_seq: 0,
            });
            ctx.db.party_member().insert(PartyMember {
                character_id,
                party_id: party.id,
                joined_at: ctx.timestamp,
                following_character_id: None,
            });
            Ok(party.id)
        }
    }
}

/// 이끌기를 끝내고 따라가던 사람들을 놓아 준다.
///
/// 그만두기·탈퇴·추방·해산이 모두 같은 뒤처리를 해야 하므로 한 곳에 모은다.
/// 따로 쓰면 한 경로에서만 따라가던 상태를 남겨, 없는 사람을 향해 계속 걷는
/// 파티원이 생긴다.
fn end_hunt_lead(ctx: &ReducerContext, party: Party) {
    let leader = party.hunt_lead_character_id;
    let party_id = party.id;

    ctx.db.party().id().update(Party {
        hunt_lead_character_id: None,
        // 번호는 되돌리지 않는다. 다음 이끌기가 같은 번호를 다시 쓰면, 방금 끝난
        // 이끌기를 향한 늦은 참여가 새 것에 붙는다.
        ..party
    });

    let Some(leader) = leader else { return };
    let followers: Vec<PartyMember> = ctx
        .db
        .party_member()
        .by_party()
        .filter(party_id)
        .filter(|m| m.following_character_id == Some(leader))
        .collect();
    for member in followers {
        ctx.db.party_member().character_id().update(PartyMember {
            following_character_id: None,
            ..member
        });
    }
}

/// 파티장이 빠졌을 때 자리를 이어받을 사람을 고른다.
///
/// 가장 오래 있은 사람이며, 같은 시각에 들어온 둘이 있으면 캐릭터 번호가 작은
/// 쪽이다. 동점을 가르는 규칙이 필요한 이유는 **누가 이어받을지가 실행할 때마다
/// 달라지면 안 되기** 때문이다 — 표를 훑는 순서는 보장되지 않으므로, 규칙 없이
/// 첫 줄을 집으면 같은 상황에서 다른 답이 나올 수 있다.
///
/// 인자를 `(들어온 시각, 캐릭터 번호)` 로 받는 것은 이 규칙만 따로 검사하기
/// 위해서다. 표 행을 받으면 데이터베이스 없이는 확인할 수 없다.
fn pick_next_leader(mut seats: Vec<(i64, u64)>) -> Option<u64> {
    // 튜플의 사전식 정렬이 곧 "먼저 들어온 순, 동점이면 번호 순" 이다.
    seats.sort_unstable();
    seats.first().map(|(_, character_id)| *character_id)
}

/// 멤버 한 명을 빼고, 그 결과로 파티가 성립하지 않으면 정리한다.
///
/// 여기 한 곳에 모아 둔 이유는 탈퇴·추방·(나중에) 접속 종료가 모두 같은 뒤처리를
/// 해야 하기 때문이다. 각자 따로 쓰면 한 경로에서만 파티장 승계를 빠뜨리는 일이
/// 생긴다.
fn remove_member(ctx: &ReducerContext, party_id: u64, character_id: u64) {
    ctx.db.party_member().character_id().delete(character_id);

    let remaining: Vec<PartyMember> =
        ctx.db.party_member().by_party().filter(party_id).collect();

    // 혼자 남았거나 아무도 없으면 파티를 접는다.
    if remaining.len() <= 1 {
        for member in &remaining {
            ctx.db
                .party_member()
                .character_id()
                .delete(member.character_id);
        }
        let invites: Vec<u64> = ctx
            .db
            .party_invite()
            .by_party_invite()
            .filter(party_id)
            .map(|i| i.id)
            .collect();
        for id in invites {
            ctx.db.party_invite().id().delete(id);
        }
        ctx.db.party().id().delete(party_id);
        return;
    }

    let Some(party) = ctx.db.party().id().find(party_id) else {
        return;
    };

    // 나간 사람이 이끌고 있었으면 이끌기부터 끝낸다. 따라가던 사람들을 놓아 주는
    // 일까지 여기서 함께 일어난다.
    let party = if party.hunt_lead_character_id == Some(character_id) {
        end_hunt_lead(ctx, party);
        match ctx.db.party().id().find(party_id) {
            Some(refreshed) => refreshed,
            None => return,
        }
    } else {
        party
    };

    // 나간 사람이 파티장이었으면 가장 오래 있은 사람이 이어받는다.
    if party.leader_character_id == character_id {
        let seats: Vec<(i64, u64)> = remaining
            .iter()
            .map(|m| (m.joined_at.to_micros_since_unix_epoch(), m.character_id))
            .collect();
        let Some(next) = pick_next_leader(seats) else {
            return;
        };
        ctx.db.party().id().update(Party {
            leader_character_id: next,
            ..party
        });

        // 새 파티장이 누군가를 따라가는 중이었다면 풀어 준다.
        if let Some(member) = ctx.db.party_member().character_id().find(next) {
            if member.following_character_id.is_some() {
                ctx.db.party_member().character_id().update(PartyMember {
                    following_character_id: None,
                    ..member
                });
            }
        }
    }

    // 나간 사람을 따라가고 있던 파티원은 추종을 푼다. 따라갈 대상이 사라졌는데
    // 상태만 남으면, 클라이언트는 없는 사람을 향해 계속 걸으려 한다.
    let followers: Vec<PartyMember> = ctx
        .db
        .party_member()
        .by_party()
        .filter(party_id)
        .filter(|m| m.following_character_id == Some(character_id))
        .collect();
    for member in followers {
        ctx.db.party_member().character_id().update(PartyMember {
            following_character_id: None,
            ..member
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 파티_정원은_열두명이다() {
        assert_eq!(MAX_PARTY_SIZE, 12);
    }

    #[test]
    fn 파티장은_가장_오래_있은_사람이_이어받는다() {
        // (들어온 시각, 캐릭터 번호)
        let seats = vec![(300, 11), (100, 42), (200, 7)];
        assert_eq!(pick_next_leader(seats), Some(42));
    }

    #[test]
    fn 같은_시각에_들어왔으면_번호가_작은_쪽이_이어받는다() {
        let seats = vec![(100, 9), (100, 3), (100, 5)];
        assert_eq!(pick_next_leader(seats), Some(3));
    }

    #[test]
    fn 훑는_순서가_달라도_같은_사람이_이어받는다() {
        // 표를 훑는 순서는 보장되지 않는다. 그 순서가 답을 바꾸면 안 된다.
        let forward = vec![(100, 9), (100, 3), (200, 1)];
        let backward = vec![(200, 1), (100, 3), (100, 9)];
        assert_eq!(pick_next_leader(forward), pick_next_leader(backward));
    }

    #[test]
    fn 남은_사람이_없으면_이어받을_사람도_없다() {
        assert_eq!(pick_next_leader(Vec::new()), None);
    }

    #[test]
    fn 이끌기_번호는_시작할_때마다_달라진다() {
        // 같은 번호가 다시 쓰이면, 방금 끝난 이끌기를 향한 늦은 참여가 새 것에
        // 붙는다. 끝낼 때 되돌리지 않고 시작할 때 올리는 이유다.
        let mut seq: u64 = 0;
        let first = seq.saturating_add(1);
        seq = first;
        // 끝나도 번호는 그대로 남는다.
        let second = seq.saturating_add(1);
        assert_ne!(first, second);
    }

    #[test]
    fn 이끌기_번호는_상한에서_멈춘다() {
        // `saturating_add` 라 넘치지 않는다. 상한에 닿으면 더는 오르지 않지만,
        // 그 지경이 되려면 한 파티에서 1800경 번을 시작해야 한다.
        assert_eq!(u64::MAX.saturating_add(1), u64::MAX);
    }

    #[test]
    fn 초대는_이십초만_살아_있다() {
        assert_eq!(INVITE_TTL_MICROS, 20_000_000);
    }
}
