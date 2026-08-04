//! 플레이어 캐릭터의 생성·선택·삭제.
//!
//! 캐릭터는 계정에 속한다. 어떤 reducer 도 `account_id` 를 인자로 받지 않고,
//! 항상 [`crate::require_session`] 으로 호출자의 계정을 도출한다. 그래서
//! "남의 캐릭터를 지목하는 호출" 이라는 것이 성립하지 않는다.

use spacetimedb::{ReducerContext, Table};

use crate::{PlayerCharacter, Session, player_character, session};

/// 한 계정이 가질 수 있는 캐릭터 수.
const MAX_CHARACTERS: usize = 4;

const MIN_NAME_LEN: usize = 2;
const MAX_NAME_LEN: usize = 16;

/// 서버가 인정하는 캐릭터 외형.
///
/// 클라이언트 UI 가 두 가지만 보여준다는 사실을 믿지 않는다. reducer 는 누구나
/// 임의 인자로 부를 수 있으므로 서버가 목록을 갖는다. 외형이 늘어나면 이 배열에
/// 추가하고 재배포한다 — 값의 종류가 적고 클라이언트 렌더가 코드로 그려지므로
/// 서버와 클라이언트가 함께 바뀌는 편이 어긋날 여지가 없다.
pub const CHARACTER_KINDS: [&str; 2] = ["male_cyborg", "female_cyborg"];

/// 외형 값이 서버가 아는 것인지 판정한다.
pub fn normalize_kind(raw: &str) -> Result<String, String> {
    let kind = raw.trim().to_lowercase();
    if CHARACTER_KINDS.contains(&kind.as_str()) {
        Ok(kind)
    } else {
        Err(format!("알 수 없는 캐릭터 종류다: {raw:?}"))
    }
}

/// 캐릭터 이름을 다듬고 검사한다.
///
/// 연속 공백을 하나로 줄인 뒤 길이를 본다. 제어 문자는 화면을 깨뜨릴 수 있어
/// 막는다.
pub fn normalize_name(raw: &str) -> Result<String, String> {
    let name = raw.split_whitespace().collect::<Vec<_>>().join(" ");

    if name.chars().any(char::is_control) {
        return Err("이름에 쓸 수 없는 문자가 있다.".to_string());
    }

    // 길이는 바이트가 아니라 글자 수로 센다. 한글 이름이 부당하게 짧게 취급되면
    // 안 된다.
    let len = name.chars().count();
    if len < MIN_NAME_LEN || len > MAX_NAME_LEN {
        return Err(format!("이름은 {MIN_NAME_LEN}~{MAX_NAME_LEN}자다."));
    }

    Ok(name)
}

// ── reducer ─────────────────────────────────────────────────────────────

/// 캐릭터를 만든다. 만들자마자 선택된 캐릭터가 된다.
#[spacetimedb::reducer]
pub fn create_character(ctx: &ReducerContext, name: String, kind: String) -> Result<(), String> {
    let session = crate::require_session(ctx)?;
    let name = normalize_name(&name)?;
    let kind = normalize_kind(&kind)?;

    let existing: Vec<PlayerCharacter> = ctx
        .db
        .player_character()
        .account_id()
        .filter(session.account_id)
        .collect();

    if existing.len() >= MAX_CHARACTERS {
        return Err(format!(
            "캐릭터는 최대 {MAX_CHARACTERS}개까지 만들 수 있다."
        ));
    }

    // 같은 계정 안에서 이름이 겹치면 목록에서 구별할 수 없다.
    if existing.iter().any(|c| c.name == name) {
        return Err("같은 이름의 캐릭터가 이미 있다.".to_string());
    }

    let created = ctx.db.player_character().insert(PlayerCharacter {
        id: 0, // auto_inc
        account_id: session.account_id,
        name,
        kind,
        // 성장의 진실은 `total_xp` 하나다. `level`·`xp` 는 거기서 나오는
        // 사본이므로 새 캐릭터에서는 셋이 모두 바닥값이다.
        level: 1,
        xp: 0,
        created_at: ctx.timestamp,
        last_played_at: ctx.timestamp,
        total_xp: 0,
    });

    // 생성과 선택이 한 트랜잭션 안에서 끝나므로 "만들었는데 못 고른" 중간 상태가
    // 남지 않는다.
    ctx.db.session().identity().update(Session {
        selected_character_id: Some(created.id),
        ..session
    });

    Ok(())
}

/// 플레이할 캐릭터를 고른다.
#[spacetimedb::reducer]
pub fn select_character(ctx: &ReducerContext, character_id: u64) -> Result<(), String> {
    let session = crate::require_session(ctx)?;

    let character = ctx
        .db
        .player_character()
        .id()
        .find(character_id)
        .ok_or_else(|| "캐릭터를 찾을 수 없다.".to_string())?;

    // 소유자 확인. 이 검사가 없으면 남의 캐릭터 id 를 넣어 고를 수 있다.
    // 존재하지 않을 때와 같은 메시지를 줘서 id 탐색으로 남의 캐릭터 존재 여부를
    // 알아내지 못하게 한다.
    if character.account_id != session.account_id {
        return Err("캐릭터를 찾을 수 없다.".to_string());
    }

    ctx.db.player_character().id().update(PlayerCharacter {
        last_played_at: ctx.timestamp,
        ..character
    });

    ctx.db.session().identity().update(Session {
        selected_character_id: Some(character_id),
        ..session
    });

    Ok(())
}

/// 캐릭터를 지운다. 지금 고른 캐릭터였다면 선택도 함께 해제한다.
#[spacetimedb::reducer]
pub fn delete_character(ctx: &ReducerContext, character_id: u64) -> Result<(), String> {
    let session = crate::require_session(ctx)?;

    let character = ctx
        .db
        .player_character()
        .id()
        .find(character_id)
        .ok_or_else(|| "캐릭터를 찾을 수 없다.".to_string())?;

    if character.account_id != session.account_id {
        return Err("캐릭터를 찾을 수 없다.".to_string());
    }

    ctx.db.player_character().id().delete(character_id);

    // 선택 해제를 같은 트랜잭션에서 처리한다. 안 그러면 세션이 사라진 캐릭터를
    // 가리킨 채 남아 클라이언트가 빈 게임 화면으로 들어간다.
    if session.selected_character_id == Some(character_id) {
        ctx.db.session().identity().update(Session {
            selected_character_id: None,
            ..session
        });
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 아는_외형만_통과한다() {
        assert_eq!(normalize_kind("male_cyborg"), Ok("male_cyborg".into()));
        assert_eq!(
            normalize_kind(" Female_Cyborg "),
            Ok("female_cyborg".into())
        );
        assert!(normalize_kind("robot_overlord").is_err());
        assert!(normalize_kind("").is_err());
    }

    #[test]
    fn 이름의_연속_공백은_하나로_줄인다() {
        assert_eq!(normalize_name("  강   철   "), Ok("강 철".into()));
    }

    #[test]
    fn 이름_길이는_글자수로_센다() {
        // 한글 두 글자는 UTF-8 로 6바이트지만 2자로 세어 통과해야 한다.
        assert!(normalize_name("강철").is_ok());
        assert!(normalize_name("강").is_err());
        assert!(normalize_name(&"가".repeat(17)).is_err());
        assert!(normalize_name(&"가".repeat(16)).is_ok());
    }
}
