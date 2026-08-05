#!/usr/bin/env bash
#
# 다른 사람에게 건네줄 수 있는 macOS 앱을 만든다.
#
#   ./scripts/release-macos.sh
#
# 왜 필요한가
# ───────────
# 그냥 `flutter build macos` 로 만든 앱은 ad-hoc 서명이라 만든 기계에서만 열린다.
# 그걸 남에게 보내면 받는 쪽 macOS 가 이렇게 막는다.
#
#   "actionrpg" 은(는) 손상되었기 때문에 열 수 없습니다. 휴지통으로 이동하십시오.
#
# 앱이 실제로 망가진 게 아니다. 인터넷·메신저로 받은 파일에는 격리(quarantine)
# 딱지가 붙는데, Gatekeeper 가 그 딱지를 보고 서명을 확인하려다 실패해서 나오는 말이다.
# 넘어가려면 두 가지가 필요하다.
#
#   1. 서명   — Developer ID 인증서로 앱에 도장을 찍는다. (Release.xcconfig 가 처리)
#   2. 공증   — 그 앱을 Apple 에 올려 검사받고, 통과 도장을 앱에 박아 넣는다(staple).
#
# 서명만 하면 "확인되지 않은 개발자" 경고까지는 줄어들지만 여전히 한 번은 막힌다.
# 공증까지 마쳐야 받는 사람이 두 번 클릭으로 그냥 실행할 수 있다.
#
# 공증 계정 등록 (기계마다 맨 처음 한 번만)
# ─────────────────────────────────────────
# 공증은 Apple 서버에 로그인해야 한다. 이 저장소는 App Store Connect API 키를
# env/ 에 두고 쓴다(env/ 는 .gitignore 에 있어 저장소에 올라가지 않는다).
#
#   ./scripts/release-macos.sh --setup
#
# 이 명령이 env/ 에서 키를 찾아, 그대로 붙여 넣어 실행할 등록 명령을 찍어 준다.
# 한 번 넣어 두면 그 다음부터는 스크립트가 키체인에서 알아서 꺼내 쓴다.

set -euo pipefail

# ── 기본값 ──────────────────────────────────────────────────────────────

TEAM_ID="AX352BQR6K"
APPLE_ID="thruthesky@gmail.com"
KEYCHAIN_PROFILE="actionrpg-notary"
SIGN_IDENTITY="Developer ID Application"

APP_NAME="actionrpg"
FORMAT="dmg"          # dmg | zip
DO_BUILD=1
DO_NOTARIZE=1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/build/macos/Build/Products/Release"
DIST_DIR="$ROOT/build/dist"

# 공증 계정 등록에 쓸 App Store Connect API 키. 값을 여기 적어 두지 않고 env/ 에서
# 찾아 읽는다 — env/ 는 저장소에 올라가지 않으므로 키 정보가 새어 나갈 일이 없다.
API_KEY_FILE="$(ls "$ROOT"/env/AuthKey_*.p8 2>/dev/null | head -1)"
if [[ -n "$API_KEY_FILE" ]]; then
  API_KEY_ID="$(basename "$API_KEY_FILE" .p8 | sed 's/^AuthKey_//')"
  API_ISSUER="$(grep -m1 -i 'Issuer ID:' "$ROOT/env/ios-app.txt" 2>/dev/null | sed 's/.*[Ii]ssuer ID: *//' | tr -d ' \r')"
fi
API_KEY_FILE="${API_KEY_FILE:-env/AuthKey_<키ID>.p8}"
API_KEY_ID="${API_KEY_ID:-<키ID>}"
API_ISSUER="${API_ISSUER:-<Issuer ID>}"

usage() {
  cat <<'EOF'
사용법: ./scripts/release-macos.sh [옵션]

옵션
  --format <dmg|zip>   배포 파일 형식 (기본 dmg)
  --profile <이름>     notarytool 키체인 프로필 이름 (기본 actionrpg-notary)
  --no-build           이미 빌드된 앱을 그대로 쓴다
  --skip-notarize      서명만 하고 공증은 건너뛴다 (받는 쪽에서 한 번 경고가 뜬다)
  --setup              공증 계정 등록 방법을 안내한다
  -h, --help           이 도움말

예시
  ./scripts/release-macos.sh                    # 빌드 → 서명 → 공증 → DMG
  ./scripts/release-macos.sh --format zip       # DMG 대신 ZIP 으로 묶는다
  ./scripts/release-macos.sh --no-build         # 다시 빌드하지 않고 공증만
EOF
}

setup_guide() {
  cat <<EOF
공증 계정 등록 (기계마다 맨 처음 한 번만)

방법 1 — App Store Connect API 키 (이 저장소가 쓰는 방식)

  env/ 에 키가 이미 있다면 이 한 줄이면 끝난다.

     xcrun notarytool store-credentials $KEYCHAIN_PROFILE \\
       --key $API_KEY_FILE \\
       --key-id $API_KEY_ID \\
       --issuer $API_ISSUER

  키가 없다면 App Store Connect 에 $APPLE_ID 로 로그인해서
  [Users and Access] → [Integrations] → [Team Keys] 에서 발급받아
  env/AuthKey_<키ID>.p8 로 저장한다. (env/ 는 저장소에 올라가지 않는다)

방법 2 — 앱 암호

  1) https://account.apple.com → [로그인 및 보안] → [앱 암호] → 생성
     (Apple 계정 암호가 아니다. xxxx-xxxx-xxxx-xxxx 꼴이다)
  2) xcrun notarytool store-credentials $KEYCHAIN_PROFILE \\
       --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "발급받은-앱-암호"

등록했으면 다시 ./scripts/release-macos.sh 를 실행하면 된다.

주의: Apple Developer Program 회원이라야 공증이 된다(연 \$99).
      회원이 아니면 --skip-notarize 로 서명본만 만들 수 있다.
EOF
}

# ── 인자 처리 ───────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    --format)        FORMAT="$2"; shift 2 ;;
    --profile)       KEYCHAIN_PROFILE="$2"; shift 2 ;;
    --no-build)      DO_BUILD=0; shift ;;
    --skip-notarize) DO_NOTARIZE=0; shift ;;
    --setup)         setup_guide; exit 0 ;;
    -h|--help)       usage; exit 0 ;;
    *) echo "모르는 옵션: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ "$FORMAT" != "dmg" && "$FORMAT" != "zip" ]]; then
  echo "--format 은 dmg 또는 zip 이어야 한다: $FORMAT" >&2
  exit 1
fi

say() { printf '\n\033[1;36m▸ %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

# ── 0. 인증서 확인 ──────────────────────────────────────────────────────

say "서명 인증서를 확인한다"
if ! security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY.*$TEAM_ID"; then
  die "'$SIGN_IDENTITY ... ($TEAM_ID)' 인증서가 키체인에 없다.
   Xcode → Settings → Accounts → Manage Certificates 에서
   'Developer ID Application' 을 내려받아라."
fi
echo "  찾음: $SIGN_IDENTITY ($TEAM_ID)"

# ── 1. 빌드 ─────────────────────────────────────────────────────────────

APP="$BUILD_DIR/$APP_NAME.app"

if [[ $DO_BUILD -eq 1 ]]; then
  say "Release 로 빌드한다 (몇 분 걸린다)"
  cd "$ROOT"
  flutter build macos --release
else
  say "빌드를 건너뛴다 (--no-build)"
fi

[[ -d "$APP" ]] || die "빌드 결과물이 없다: $APP"

# ── 2. 서명 확인 ────────────────────────────────────────────────────────
#
# Xcode 가 Release.xcconfig 를 보고 이미 서명했어야 한다. 정말 그랬는지,
# ad-hoc 으로 새어 나가지는 않았는지 여기서 못을 박는다.

say "서명을 확인한다"
SIGN_INFO="$(codesign -dvv "$APP" 2>&1)"

if grep -q "Signature=adhoc" <<<"$SIGN_INFO"; then
  die "아직 ad-hoc 서명이다. 이대로는 남의 Mac 에서 휴지통으로 간다.
   macos/Runner/Configs/Release.xcconfig 의 서명 설정을 확인하고
   'flutter clean' 후 다시 빌드해 보라."
fi

AUTHORITY="$(grep -m1 '^Authority=' <<<"$SIGN_INFO" | cut -d= -f2-)"
grep -q "Developer ID Application" <<<"$AUTHORITY" \
  || die "Developer ID 로 서명되지 않았다: $AUTHORITY"
echo "  서명자: $AUTHORITY"

# Hardened Runtime 이 켜져 있어야 공증을 받아 준다.
if ! grep -q "flags=.*runtime" <<<"$SIGN_INFO"; then
  die "Hardened Runtime 이 꺼져 있어 공증을 받을 수 없다.
   Release.xcconfig 의 ENABLE_HARDENED_RUNTIME = YES 를 확인하라."
fi
echo "  Hardened Runtime: 켜짐"

# Xcode 는 시키지 않아도 디버거 부착 권한(get-task-allow)을 끼워 넣곤 한다.
# 그대로 올리면 Apple 이 5 분쯤 검사한 뒤 거절한다. 올리기 전에 여기서 잡는다.
ENTS="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null | plutil -p - 2>/dev/null || true)"
if grep -q "get-task-allow" <<<"$ENTS"; then
  die "앱에 디버거 부착 권한(get-task-allow)이 들어 있다. 이대로는 공증이 거절된다.
   Release.xcconfig 의 CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO 를 확인하고
   'flutter clean' 후 다시 빌드하라."
fi
echo "  디버그 권한 없음"

say "번들 전체를 검사한다 (프레임워크·플러그인 포함)"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | sed 's/^/  /'

# ── 3. 공증 준비 ────────────────────────────────────────────────────────

VERSION="$(grep -m1 '^version:' "$ROOT/pubspec.yaml" | sed 's/version: *//' | tr -d ' \r')"
VERSION="${VERSION%%+*}"
[[ -n "$VERSION" ]] || VERSION="0.0.0"

mkdir -p "$DIST_DIR"
ARTIFACT="$DIST_DIR/$APP_NAME-$VERSION.$FORMAT"
rm -f "$ARTIFACT"

if [[ $DO_NOTARIZE -eq 1 ]] \
   && ! xcrun notarytool history --keychain-profile "$KEYCHAIN_PROFILE" >/dev/null 2>&1; then
  echo ""
  echo "  '$KEYCHAIN_PROFILE' 이름으로 저장된 공증 계정이 없다."
  echo ""
  setup_guide
  echo ""
  echo "  지금 당장 배포해야 한다면 --skip-notarize 로 서명본만 만들 수 있다."
  exit 1
fi

# 파일 하나를 Apple 에 올려 검사받는다. 거절당하면 이유를 찾는 법을 알려 주고 멈춘다.
notarize() {
  local target="$1"
  xcrun notarytool submit "$target" \
    --keychain-profile "$KEYCHAIN_PROFILE" \
    --wait 2>&1 | tee "$DIST_DIR/notarize.log" | sed 's/^/  /'

  grep -q "status: Accepted" "$DIST_DIR/notarize.log" && return 0

  local sid
  sid="$(grep -m1 '  id:' "$DIST_DIR/notarize.log" | awk '{print $2}')"
  echo ""
  echo "  거절 사유를 보려면:"
  echo "    xcrun notarytool log $sid --keychain-profile $KEYCHAIN_PROFILE"
  die "공증이 통과하지 못했다."
}

# ── 4. 앱에 통과 도장 박기 ──────────────────────────────────────────────
#
# 배포 파일(DMG)만 공증하면 도장이 DMG 껍데기에만 박힌다. 받는 사람이 앱을
# 응용 프로그램 폴더로 끌어다 놓는 순간 도장은 따라가지 않고, 그때부터는
# 열 때마다 Apple 서버에 물어봐야 한다. 앱 자체에 박아 두면 인터넷이
# 끊겨 있어도 열린다. 그래서 앱을 먼저 공증한다.

if [[ $DO_NOTARIZE -eq 1 ]]; then
  say "앱을 공증한다 (보통 1~5분)"
  APP_ZIP="$DIST_DIR/.notarize-app.zip"
  rm -f "$APP_ZIP"
  # 올릴 때는 ditto 로 싸야 한다. 일반 zip 은 심볼릭 링크를 뭉개 서명을 깨뜨린다.
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$APP_ZIP"
  notarize "$APP_ZIP"
  rm -f "$APP_ZIP"

  say "앱에 통과 도장을 박는다 (staple)"
  xcrun stapler staple "$APP" 2>&1 | sed 's/^/  /'
fi

# ── 5. 배포 파일 만들기 ─────────────────────────────────────────────────

if [[ "$FORMAT" == "dmg" ]]; then
  say "DMG 를 만든다: $(basename "$ARTIFACT")"

  # 앱과 /Applications 바로가기를 함께 담아, 받는 사람이 끌어다 놓기만 하면 되게 한다.
  STAGE="$(mktemp -d)"
  trap 'rm -rf "$STAGE"' EXIT
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"

  hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGE" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "$ARTIFACT" >/dev/null

  # DMG 껍데기에도 도장을 찍어 둔다. 받는 쪽에서 마운트할 때 덜 의심받는다.
  codesign --sign "$SIGN_IDENTITY" --timestamp --force "$ARTIFACT"
else
  say "ZIP 으로 묶는다: $(basename "$ARTIFACT")"
  # 반드시 ditto 를 쓴다. 일반 zip 은 심볼릭 링크와 확장 속성을 뭉개서
  # 앱 번들의 서명을 깨뜨린다.
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARTIFACT"
fi

# ── 6. 배포 파일에도 도장 박기 ──────────────────────────────────────────

if [[ $DO_NOTARIZE -eq 0 ]]; then
  say "공증을 건너뛴다 (--skip-notarize)"
  cat <<EOF

  서명은 됐지만 공증을 받지 않았다. 받는 사람이 처음 실행할 때
  "확인되지 않은 개발자" 경고가 뜬다. 이렇게 알려 줘라.

    앱 실행 → 차단 메시지에서 [완료]
    → 시스템 설정 → 개인정보 보호 및 보안 → 맨 아래 [그래도 열기]
    → 다시 실행 → [열기]

  (macOS 15 Sequoia 부터는 예전의 "우클릭 → 열기" 우회가 막혔다.)

  완성품: $ARTIFACT
EOF
  exit 0
fi

if [[ "$FORMAT" == "dmg" ]]; then
  # 앱에는 이미 도장이 박혀 있다. DMG 껍데기에도 박아야 마운트할 때 조용하다.
  say "DMG 를 공증한다 (보통 1~5분)"
  notarize "$ARTIFACT"

  say "DMG 에 통과 도장을 박는다 (staple)"
  xcrun stapler staple "$ARTIFACT" 2>&1 | sed 's/^/  /'
fi
# ZIP 껍데기에는 도장을 박을 수 없다. 안의 앱에 이미 박혀 있으니 그걸로 족하다.

# ── 7. 받는 사람 입장에서 최종 확인 ─────────────────────────────────────

say "받는 사람의 Mac 이 보게 될 것을 그대로 확인한다"
if spctl --assess --type execute --verbose=4 "$APP" 2>&1 | sed 's/^/  /' | grep -q "accepted"; then
  echo "  Gatekeeper 통과"
else
  spctl --assess --type execute --verbose=4 "$APP" 2>&1 | sed 's/^/  /' || true
  die "Gatekeeper 검사를 통과하지 못했다."
fi

say "앱에 도장이 박혀 있는지 확인한다 (인터넷 없이도 열리는가)"
xcrun stapler validate "$APP" 2>&1 | sed 's/^/  /'

# ── 끝 ──────────────────────────────────────────────────────────────────

SIZE="$(du -h "$ARTIFACT" | cut -f1)"
printf '\n\033[1;32m✓ 배포 준비 완료\033[0m\n'
cat <<EOF

  파일   $ARTIFACT
  크기   $SIZE
  버전   $VERSION
  서명   $AUTHORITY
  공증   완료 (staple 됨)

이 파일은 메신저·메일·웹 어디로 보내도 된다. 받는 사람은 그냥 열면 된다.
휴지통으로 보내라는 말도, 확인되지 않은 개발자 경고도 뜨지 않는다.
EOF
