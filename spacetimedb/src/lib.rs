//! Cyborg 액션 RPG 서버 모듈.
//!
//! 세계관: AI 로봇이 점령한 세계를 인간 사이보그가 되찾는다.
//!
//! 현재 범위는 **계정과 캐릭터 선택**까지다.
//!
//! ## 설계 원칙
//!
//! 1. **클라이언트를 신뢰하지 않는다.** 소유자는 클라이언트가 보낸 값이 아니라
//!    `ctx.sender()` 에서 도출한 세션으로만 정한다. `account_id` 를 인자로 받는
//!    reducer 는 하나도 없다.
//! 2. **비밀번호는 다른 표에 둔다.** [`AccountSecret`] 을 [`Account`] 에서 떼어
//!    놓았으므로, 계정 정보를 노출하는 어떤 경로도 해시를 함께 흘릴 수 없다.
//!    "실수로 같이 나가는" 일이 구조적으로 불가능하다.
//! 3. **모든 테이블이 비공개다.** `public` 을 붙인 테이블이 없으므로 구독으로
//!    남의 데이터가 새어 나가지 않는다. 본인 데이터는 아래 view 로만 읽는다.
//! 4. **시각은 서버 기준이다.** `ctx.timestamp` 만 쓰고 클라이언트 시각은 받지 않는다.
//! 5. **난수는 서버 시드로만 만든다.** salt 는 `ctx.random()` 에서 얻는다.

pub mod auth;
pub mod character;
pub mod leaderboard;
pub mod party;
pub mod world;

use spacetimedb::{Identity, ReducerContext, Timestamp, ViewContext, view};

// 접속이 끊길 때 월드에서 내보내기 위해 필요하다([`on_disconnect`]).
use world::{world_player, world_player__view};

// ── 테이블 ──────────────────────────────────────────────────────────────

/// 계정의 공개 가능한 부분.
///
/// 비밀번호는 여기 없다([`AccountSecret`]). 그래서 이 행이 통째로
/// 클라이언트에 가도 문제가 없고, [`my_account`] view 가 그대로 돌려준다.
#[spacetimedb::table(accessor = account)]
pub struct Account {
    #[primary_key]
    #[auto_inc]
    pub id: u64,

    /// 로그인 아이디. 소문자로 정규화해 저장한다([`auth::normalize_email`]).
    ///
    /// `unique` 이므로 같은 이메일로 두 계정이 생기는 것을 DB 가 막는다.
    /// 애플리케이션 검사에만 의존하면 동시 요청에 뚫린다.
    #[unique]
    pub email: String,

    pub created_at: Timestamp,
    pub last_login_at: Timestamp,
}

/// 계정의 비밀번호. **어떤 view 도 이 표를 읽지 않는다.**
///
/// [`Account`] 와 1:1 이며 `account_id` 로 이어진다. 굳이 나눈 이유는 노출
/// 사고를 설계로 막기 위해서다 — 계정을 보여주는 코드가 아무리 늘어나도
/// 이 표를 따로 읽지 않는 한 해시는 서버 밖으로 나갈 수 없다.
#[spacetimedb::table(accessor = account_secret)]
pub struct AccountSecret {
    #[primary_key]
    pub account_id: u64,

    /// [`auth::hash_password`] 의 결과(hex). 평문 비밀번호는 어디에도 남기지 않는다.
    pub password_hash: String,

    /// 계정마다 다른 무작위 salt(hex). 같은 비밀번호라도 해시가 달라진다.
    pub password_salt: String,
}

/// 접속 identity 와 계정의 연결. 로그인하면 생기고 로그아웃하면 사라진다.
///
/// SpacetimeDB 의 identity 는 **연결 주체**를 가리킬 뿐 우리 계정 체계와는
/// 무관하다. 그래서 "누가 로그인했는가" 는 이 표로 따로 관리한다.
/// identity 가 기본 키이므로 한 기기(연결)는 한 계정에만 붙는다. 반대로 한
/// 계정이 여러 기기에서 로그인하는 것은 허용된다(행이 여러 개 생긴다).
#[spacetimedb::table(accessor = session)]
pub struct Session {
    #[primary_key]
    pub identity: Identity,

    #[index(btree)]
    pub account_id: u64,

    /// 현재 플레이 중으로 고른 캐릭터. 아직 안 골랐으면 `None`.
    pub selected_character_id: Option<u64>,

    pub logged_in_at: Timestamp,
}

/// 계정이 보유한 플레이어 캐릭터.
///
/// 한 계정이 여러 캐릭터를 가질 수 있고, 그중 하나를 골라 플레이한다.
#[spacetimedb::table(accessor = player_character)]
pub struct PlayerCharacter {
    #[primary_key]
    #[auto_inc]
    pub id: u64,

    /// 소유 계정. 세션에서 도출한 값만 들어가며 클라이언트가 지정할 수 없다.
    #[index(btree)]
    pub account_id: u64,

    pub name: String,

    /// 외형 종류. 현재는 `"male_cyborg"` 와 `"female_cyborg"` 두 가지다
    /// ([`character::normalize_kind`] 가 판정한다).
    pub kind: String,

    /// 지금 레벨. **[`total_xp`](PlayerCharacter::total_xp) 에서 유도한 파생값**이며
    /// 진실이 아니다. 서버가 누적 경험치를 받을 때마다 다시 계산해 채운다.
    ///
    /// 파생값을 굳이 저장하는 이유는 두 가지다 — 인덱스를 걸어야 view 가 표를
    /// 훑을 수 있고(읽기 전용 핸들에는 `iter` 가 없다), 캐릭터 목록처럼 레벨만
    /// 필요한 화면이 매번 역함수를 돌리지 않아도 된다.
    #[index(btree)]
    pub level: u32,

    /// 지금 레벨 안에서 다음 레벨까지 쌓은 진행도. 이것도 파생값이다.
    pub xp: u32,

    pub created_at: Timestamp,
    pub last_played_at: Timestamp,

    /// 지금까지 얻은 **경험치의 총합**. 성장에 관한 유일한 진실이다.
    ///
    /// 레벨과 진행도는 여기서 나온다([`leaderboard::level_and_progress`]).
    /// 값 하나만 저장하므로 "레벨은 20 인데 경험치는 3 레벨분" 같은 어긋난 상태가
    /// 존재할 수 없고, 순위도 이 값 하나로 완전히 갈린다.
    ///
    /// **맨 끝에 있고 기본값이 있어야 한다.** 이미 배포된 표에 열을 더하는 자동
    /// 마이그레이션은 두 조건을 모두 요구한다 — 중간에 끼우면 기존 행을 읽지
    /// 못하고, 기본값이 없으면 기존 행의 새 열을 채우지 못한다. 0 으로 두면 옛
    /// 행은 1 레벨에서 다시 시작한다.
    ///
    /// 접미사로 타입을 못 박아야 한다. 그냥 `0` 으로 두면 기본값의 인코딩 폭이
    /// 열 타입과 어긋나 스키마 추출이 "data too short" 로 실패한다.
    #[default(0u32)]
    pub total_xp: u32,
}

// ── view ────────────────────────────────────────────────────────────────

/// 호출자 본인의 계정. 로그인하지 않았으면 `None`.
///
/// 클라이언트는 이 view 로 로그인 여부를 판단한다 — 행이 없으면 로그인 화면,
/// 있으면 캐릭터 목록으로 간다.
#[view(accessor = my_account, public)]
fn my_account(ctx: &ViewContext) -> Option<Account> {
    let session = ctx.db.session().identity().find(ctx.sender())?;
    ctx.db.account().id().find(session.account_id)
}

/// 호출자 본인의 세션. 어떤 캐릭터를 골랐는지 여기서 읽는다.
#[view(accessor = my_session, public)]
fn my_session(ctx: &ViewContext) -> Option<Session> {
    ctx.db.session().identity().find(ctx.sender())
}

/// 호출자 본인 계정의 캐릭터 목록.
///
/// 로그인하지 않았으면 빈 목록이다. 남의 캐릭터는 어떤 경우에도 섞이지 않는다.
#[view(accessor = my_characters, public)]
fn my_characters(ctx: &ViewContext) -> Vec<PlayerCharacter> {
    let Some(session) = ctx.db.session().identity().find(ctx.sender()) else {
        return Vec::new();
    };
    ctx.db
        .player_character()
        .account_id()
        .filter(session.account_id)
        .collect()
}

/// 월드에 서 있는 **내 몸**. 월드 밖이면 비어 있다.
///
/// 관심 영역 구독은 자기가 선 청크 둘레만 가져오는데, 그 판단의 기준이 되는
/// 좌표를 다시 그 구독에서 읽으면 닭과 달걀이 된다. **서버가 나를 옮기는 순간**
/// — 안전지대 밖 입장 좌표 보정, 사망 재가동, 텔레포트 — 내 행은 옛 구독 밖으로
/// 나가고, 그러면 클라이언트는 새 자리를 알 길이 없어 영영 옛 청크를 구독한 채
/// 빈 화면을 본다.
///
/// 이 view 는 청크와 무관하게 **언제나** 내 행 하나를 준다. 재구독의 기준점이
/// 여기에서 나오므로 그 고리가 끊긴다.
#[view(accessor = my_world_player, public)]
fn my_world_player(ctx: &ViewContext) -> Option<world::WorldPlayer> {
    ctx.db.world_player().identity().find(ctx.sender())
}

// ── 내부 헬퍼 ───────────────────────────────────────────────────────────

/// 호출자의 세션을 꺼낸다. 로그인하지 않았으면 에러다.
///
/// 계정을 다루는 모든 reducer 는 여기를 통과한다. `account_id` 를 인자로 받는
/// 대신 이 함수로 도출하기 때문에, 남의 계정을 지목하는 호출 자체가 불가능하다.
pub(crate) fn require_session(ctx: &ReducerContext) -> Result<Session, String> {
    ctx.db
        .session()
        .identity()
        .find(ctx.sender())
        .ok_or_else(|| "로그인이 필요하다.".to_string())
}

// ── 라이프사이클 ────────────────────────────────────────────────────────

#[spacetimedb::reducer(init)]
pub fn init(ctx: &ReducerContext) {
    world::bootstrap(ctx);
    log::info!("cyborg 모듈 초기화 완료");
}

/// 모듈을 다시 배포할 때마다 돈다.
///
/// **[`init`] 은 최초 한 번뿐이다.** 주기 상수를 고쳐 배포해도 이미 들어 있는
/// 스케줄 행은 옛 주기로 계속 돌아, 코드와 실제 동작이 조용히 어긋난다. 실측으로
/// 겪은 함정이다 — AI 틱을 300ms 에서 150ms 로 바꿔 배포했는데 로그의 간격은
/// 그대로 300ms 였다.
#[spacetimedb::reducer(update)]
pub fn on_update(ctx: &ReducerContext) {
    world::bootstrap(ctx);
    log::info!("cyborg 모듈 갱신 완료");
}

#[spacetimedb::reducer(client_connected)]
pub fn on_connect(ctx: &ReducerContext) {
    log::debug!("연결: {}", ctx.sender());
}

/// 연결이 끊겨도 세션은 남긴다.
///
/// 세션을 지우면 앱을 잠깐 백그라운드로 보내거나 네트워크가 끊길 때마다 다시
/// 로그인해야 한다. SDK 가 토큰을 저장해 같은 identity 로 재접속하므로, 세션을
/// 유지하는 편이 "로그인 상태 유지" 라는 사용자 기대에 맞는다. 세션은
/// [`auth::logout`] 을 명시적으로 부를 때만 사라진다.
#[spacetimedb::reducer(client_disconnected)]
pub fn on_disconnect(ctx: &ReducerContext) {
    // 세션과 달리 월드에서는 즉시 내보낸다. 남겨 두면 조종하는 사람이 없는
    // 캐릭터가 사냥터 한복판에 서 있게 되고, 다른 요원 눈에는 가만히 서서
    // 몹을 선점만 하고 있는 것으로 보인다.
    //
    // 파티도 함께 끝낸다. 조종하는 사람이 없는 파티를 남겨 두면 파티장이 앱을
    // 닫은 순간 남은 사람이 해산도 위임도 못 하는 상태가 된다. 캐릭터를 알아내야
    // 하므로 월드 행을 지우기 **전에** 읽는다.
    if let Some(me) = ctx.db.world_player().identity().find(ctx.sender()) {
        party::on_character_left(ctx, me.character_id);
    }
    ctx.db.world_player().identity().delete(ctx.sender());
    log::debug!("연결 해제: {}", ctx.sender());
}
