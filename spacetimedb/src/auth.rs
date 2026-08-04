//! 이메일·비밀번호 인증.
//!
//! SpacetimeDB 는 identity 기반 인증만 제공한다. identity 는 "이 연결이 누구인가"
//! 를 가리킬 뿐 이메일·비밀번호 개념이 없으므로, 계정 체계는 모듈이 직접 갖는다.
//! 로그인이란 곧 **현재 identity 를 계정에 붙이는 것**([`crate::Session`])이다.
//!
//! ## 비밀번호를 다루는 방식
//!
//! - 평문 비밀번호는 reducer 인자로만 잠깐 존재하고 어디에도 저장하지 않는다.
//!   전송 구간은 wss 로 암호화된다.
//! - 저장하는 것은 계정마다 다른 salt 로 [`STRETCH_ROUNDS`] 회 늘린 SHA-256 해시다.
//!   salt 가 다르므로 같은 비밀번호를 쓰는 두 계정의 해시가 같아지지 않고,
//!   미리 계산해 둔 표(rainbow table)도 통하지 않는다.
//! - 비교는 [`constant_time_eq`] 로 한다. 앞에서부터 다른 지점에 따라 걸리는
//!   시간이 달라지면 그 자체가 정보가 된다.

use sha2::{Digest, Sha256};
use spacetimedb::{ReducerContext, Table};

use crate::{Account, AccountSecret, Session, account, account_secret, session};

/// 비밀번호 해시를 늘리는 횟수.
///
/// 클수록 무차별 대입이 비싸지지만 로그인 reducer 도 그만큼 오래 걸린다.
/// SHA-256 3만 회는 wasm 에서 수십 밀리초 수준이라 reducer 실행 시간 안에 들어오고,
/// 공격자에게는 시도당 같은 비용을 강제한다.
const STRETCH_ROUNDS: u32 = 30_000;

const MIN_PASSWORD_LEN: usize = 8;
const MAX_PASSWORD_LEN: usize = 128;
const MAX_EMAIL_LEN: usize = 254;

/// 이메일을 저장·조회에 쓸 형태로 다듬는다.
///
/// 앞뒤 공백을 없애고 소문자로 바꾼다. 대소문자만 다른 두 계정이 생기면
/// 사용자는 자기 계정이 왜 없다는지 알 수 없다.
///
/// 형식 검증은 최소한만 한다. 정규식으로 RFC 5322 를 흉내 내면 멀쩡한 주소를
/// 거절하는 쪽이 더 흔하다. 여기서 막는 것은 명백히 이메일이 아닌 입력뿐이다.
pub fn normalize_email(raw: &str) -> Result<String, String> {
    let email = raw.trim().to_lowercase();

    if email.is_empty() {
        return Err("이메일을 입력해라.".to_string());
    }
    if email.len() > MAX_EMAIL_LEN {
        return Err("이메일이 너무 길다.".to_string());
    }
    if email.chars().any(char::is_whitespace) {
        return Err("이메일에 공백을 넣을 수 없다.".to_string());
    }

    // `@` 가 정확히 하나 있고, 앞뒤가 모두 비어 있지 않고, 도메인에 점이 있어야 한다.
    let mut parts = email.split('@');
    let (Some(local), Some(domain), None) = (parts.next(), parts.next(), parts.next()) else {
        return Err("이메일 형식이 아니다.".to_string());
    };
    if local.is_empty() || domain.is_empty() {
        return Err("이메일 형식이 아니다.".to_string());
    }
    if !domain.contains('.') || domain.starts_with('.') || domain.ends_with('.') {
        return Err("이메일 도메인이 올바르지 않다.".to_string());
    }

    Ok(email)
}

/// 비밀번호 길이를 검사한다.
///
/// 대문자·기호를 강제하는 규칙은 넣지 않았다. 그런 규칙은 실제 강도보다
/// 사용자가 예측 가능한 변형(`Password1!`)을 쓰게 만드는 효과가 크다.
/// 길이가 강도에 훨씬 크게 기여한다.
pub fn validate_password(password: &str) -> Result<(), String> {
    if password.len() < MIN_PASSWORD_LEN {
        return Err(format!("비밀번호는 최소 {MIN_PASSWORD_LEN}자다."));
    }
    if password.len() > MAX_PASSWORD_LEN {
        return Err(format!("비밀번호는 최대 {MAX_PASSWORD_LEN}자다."));
    }
    Ok(())
}

/// salt 와 비밀번호로 저장용 해시(hex)를 만든다.
pub fn hash_password(password: &str, salt_hex: &str) -> String {
    let mut digest = Sha256::new();
    digest.update(salt_hex.as_bytes());
    digest.update(password.as_bytes());
    let mut out = digest.finalize();

    // 매 회 salt 를 다시 섞어 넣어, salt 없이 중간부터 이어 계산할 수 없게 한다.
    for _ in 1..STRETCH_ROUNDS {
        let mut round = Sha256::new();
        round.update(out);
        round.update(salt_hex.as_bytes());
        out = round.finalize();
    }

    hex::encode(out)
}

/// 길이와 내용이 모두 같은지 **입력에 따라 걸리는 시간이 달라지지 않게** 비교한다.
fn constant_time_eq(a: &str, b: &str) -> bool {
    let (a, b) = (a.as_bytes(), b.as_bytes());
    if a.len() != b.len() {
        return false;
    }
    let mut diff = 0u8;
    for (x, y) in a.iter().zip(b.iter()) {
        diff |= x ^ y;
    }
    diff == 0
}

/// 서버 시드 난수로 16바이트 salt(hex 32자)를 만든다.
fn generate_salt(ctx: &ReducerContext) -> String {
    let high = ctx.random::<u64>();
    let low = ctx.random::<u64>();
    let mut bytes = [0u8; 16];
    bytes[..8].copy_from_slice(&high.to_be_bytes());
    bytes[8..].copy_from_slice(&low.to_be_bytes());
    hex::encode(bytes)
}

/// 현재 identity 를 계정에 붙인다(= 로그인 상태로 만든다).
///
/// 이미 세션이 있으면 갈아끼운다. 로그아웃 없이 다른 계정으로 로그인하는 흐름을
/// 막을 이유가 없고, identity 가 기본 키라 행이 두 개 생기지도 않는다.
fn bind_session(ctx: &ReducerContext, account_id: u64) {
    let logged_in_at = ctx.timestamp;
    let identity = ctx.sender();

    if ctx.db.session().identity().find(identity).is_some() {
        ctx.db.session().identity().update(Session {
            identity,
            account_id,
            // 계정이 바뀌었을 수 있으므로 캐릭터 선택은 초기화한다.
            selected_character_id: None,
            logged_in_at,
        });
    } else {
        ctx.db.session().insert(Session {
            identity,
            account_id,
            selected_character_id: None,
            logged_in_at,
        });
    }
}

// ── reducer ─────────────────────────────────────────────────────────────

/// 계정을 만들고 곧바로 로그인 상태로 만든다.
///
/// 가입 직후 다시 로그인시키는 것은 사용자에게 아무 의미 없는 한 단계다.
#[spacetimedb::reducer]
pub fn register_account(
    ctx: &ReducerContext,
    email: String,
    password: String,
) -> Result<(), String> {
    let email = normalize_email(&email)?;
    validate_password(&password)?;

    // `unique` 제약이 최종 방어선이지만, 여기서 먼저 걸러야 사용자에게
    // "이미 가입된 이메일" 이라는 뜻이 통하는 메시지를 줄 수 있다.
    if ctx.db.account().email().find(&email).is_some() {
        return Err("이미 가입된 이메일이다.".to_string());
    }

    let salt = generate_salt(ctx);
    let password_hash = hash_password(&password, &salt);

    let account = ctx.db.account().insert(Account {
        id: 0, // auto_inc
        email,
        created_at: ctx.timestamp,
        last_login_at: ctx.timestamp,
    });

    // 계정과 비밀번호는 다른 표에 있지만 한 reducer = 한 트랜잭션이므로,
    // "계정은 생겼는데 비밀번호가 없는" 중간 상태는 존재할 수 없다.
    ctx.db.account_secret().insert(AccountSecret {
        account_id: account.id,
        password_hash,
        password_salt: salt,
    });

    bind_session(ctx, account.id);
    Ok(())
}

/// 이메일·비밀번호를 확인하고 현재 identity 를 그 계정에 붙인다.
#[spacetimedb::reducer]
pub fn login(ctx: &ReducerContext, email: String, password: String) -> Result<(), String> {
    let email = normalize_email(&email)?;

    // 계정이 없을 때와 비밀번호가 틀렸을 때 같은 메시지를 준다. 다르게 답하면
    // 어떤 이메일이 가입되어 있는지 확인해 주는 창구가 된다.
    const REJECT: &str = "이메일 또는 비밀번호가 올바르지 않다.";

    let Some(account) = ctx.db.account().email().find(&email) else {
        return Err(REJECT.to_string());
    };
    let Some(secret) = ctx.db.account_secret().account_id().find(account.id) else {
        // 계정은 있는데 비밀번호가 없다면 데이터가 깨진 것이다. 로그인시키지 않는다.
        log::error!("계정 {}에 비밀번호 행이 없다", account.id);
        return Err(REJECT.to_string());
    };

    let attempt = hash_password(&password, &secret.password_salt);
    if !constant_time_eq(&attempt, &secret.password_hash) {
        return Err(REJECT.to_string());
    }

    let account_id = account.id;
    ctx.db.account().id().update(Account {
        last_login_at: ctx.timestamp,
        ..account
    });

    bind_session(ctx, account_id);
    Ok(())
}

/// 세션을 지운다. 계정과 캐릭터는 그대로 남는다.
#[spacetimedb::reducer]
pub fn logout(ctx: &ReducerContext) -> Result<(), String> {
    ctx.db.session().identity().delete(ctx.sender());
    Ok(())
}

/// 로그인한 상태에서 비밀번호를 바꾼다.
///
/// 현재 비밀번호를 다시 확인한다. 세션만으로 바꾸게 두면 기기를 잠깐 손댄
/// 사람이 계정을 통째로 가져갈 수 있다.
#[spacetimedb::reducer]
pub fn change_password(
    ctx: &ReducerContext,
    current_password: String,
    new_password: String,
) -> Result<(), String> {
    let session = crate::require_session(ctx)?;
    validate_password(&new_password)?;

    let secret = ctx
        .db
        .account_secret()
        .account_id()
        .find(session.account_id)
        .ok_or_else(|| "계정을 찾을 수 없다.".to_string())?;

    let attempt = hash_password(&current_password, &secret.password_salt);
    if !constant_time_eq(&attempt, &secret.password_hash) {
        return Err("현재 비밀번호가 올바르지 않다.".to_string());
    }

    // salt 도 새로 만든다. 예전 해시를 이미 가져간 공격자가 있다면 그 계산을
    // 재활용하지 못하게 된다.
    let salt = generate_salt(ctx);
    let password_hash = hash_password(&new_password, &salt);

    ctx.db.account_secret().account_id().update(AccountSecret {
        password_hash,
        password_salt: salt,
        ..secret
    });

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 이메일은_소문자로_정규화된다() {
        assert_eq!(
            normalize_email("  User@Example.COM "),
            Ok("user@example.com".into())
        );
    }

    #[test]
    fn 형식이_아닌_이메일은_거절한다() {
        for bad in [
            "",
            "user",
            "user@",
            "@example.com",
            "a@b",
            "a b@c.com",
            "a@@b.com",
        ] {
            assert!(normalize_email(bad).is_err(), "통과하면 안 된다: {bad:?}");
        }
    }

    #[test]
    fn 같은_salt_와_비밀번호는_같은_해시를_준다() {
        let salt = "0123456789abcdef0123456789abcdef";
        assert_eq!(
            hash_password("hunter2!", salt),
            hash_password("hunter2!", salt)
        );
    }

    #[test]
    fn salt_가_다르면_해시가_달라진다() {
        let a = hash_password("hunter2!", "0123456789abcdef0123456789abcdef");
        let b = hash_password("hunter2!", "fedcba9876543210fedcba9876543210");
        assert_ne!(a, b);
    }

    #[test]
    fn 짧은_비밀번호는_거절한다() {
        assert!(validate_password("1234567").is_err());
        assert!(validate_password("12345678").is_ok());
    }

    #[test]
    fn 상수시간_비교는_동등성을_지킨다() {
        assert!(constant_time_eq("abc", "abc"));
        assert!(!constant_time_eq("abc", "abd"));
        assert!(!constant_time_eq("abc", "abcd"));
    }
}
