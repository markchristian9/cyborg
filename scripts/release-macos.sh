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
# 공증 계정 등록 (맨 처음 한 번만)
# ────────────────────────────────
# 공증은 Apple 서버에 로그인해야 하므로 앱 암호가 필요하다.
#
#   1) https://account.apple.com → 로그인 및 보안 → 앱 암호 → 새로 만들기
#      (Apple 계정 암호가 아니라 "앱 암호"다. xxxx-xxxx-xxxx-xxxx 꼴)
#   2) 아래 명령으로 그 암호를 키체인에 넣어 둔다.
#
#      xcrun notarytool store-credentials actionrpg-notary \
#        --apple-id "thruthesky@gmail.com" \
#        --team-id "AX352BQR6K" \
#        --password "발급받은-앱-암호"
#
# 한 번 넣어 두면 그 다음부터는 이 스크립트가 알아서 쓴다.

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
공증 계정 등록 (맨 처음 한 번만)

  1) https://account.apple.com 에 로그인
  2) [로그인 및 보안] → [앱 암호] → [앱 암호 생성]
     이름은 아무거나 (예: notarytool). xxxx-xxxx-xxxx-xxxx 꼴의 암호가 나온다.
  3) 아래 명령을 그대로 실행 (마지막 암호만 바꿔서)

     xcrun notarytool store-credentials $KEYCHAIN_PROFILE \\
       --apple-id "$APPLE_ID" \\
       --team-id "$TEAM_ID" \\
       --password "여기에-앱-암호"

  4) 다시 ./scripts/release-macos.sh 실행

주의: Apple Developer Program 에 가입돼 있어야 공증이 된다(연 \$99).
      가입 없이 배포하려면 --skip-notarize 를 쓰되, 받는 사람이
      [제어 클릭 → 열기] 를 한 번 해 줘야 실행된다.
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

say "번들 전체를 검사한다 (프레임워크·플러그인 포함)"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | sed 's/^/  /'

# ── 3. 배포 파일 만들기 ─────────────────────────────────────────────────

VERSION="$(grep -m1 '^version:' "$ROOT/pubspec.yaml" | sed 's/version: *//' | tr -d ' \r')"
VERSION="${VERSION%%+*}"
[[ -n "$VERSION" ]] || VERSION="0.0.0"

mkdir -p "$DIST_DIR"
ARTIFACT="$DIST_DIR/$APP_NAME-$VERSION.$FORMAT"
rm -f "$ARTIFACT"

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

# ── 4. 공증 ─────────────────────────────────────────────────────────────

if [[ $DO_NOTARIZE -eq 0 ]]; then
  say "공증을 건너뛴다 (--skip-notarize)"
  cat <<EOF

  서명은 됐지만 공증을 받지 않았다. 받는 사람이 처음 실행할 때
  "확인되지 않은 개발자" 경고가 뜬다. 이렇게 알려 줘라.

    Finder 에서 앱을 [제어 클릭(우클릭)] → [열기] → [열기]

  완성품: $ARTIFACT
EOF
  exit 0
fi

if ! xcrun notarytool history --keychain-profile "$KEYCHAIN_PROFILE" >/dev/null 2>&1; then
  echo ""
  echo "  '$KEYCHAIN_PROFILE' 이름으로 저장된 공증 계정이 없다."
  echo ""
  setup_guide
  echo ""
  echo "  지금 당장 배포해야 한다면 --skip-notarize 로 서명본만 만들 수 있다."
  echo "  이미 만들어진 서명본: $ARTIFACT"
  exit 1
fi

say "Apple 에 공증을 맡긴다 (보통 1~5분, 처음엔 더 걸릴 수 있다)"
xcrun notarytool submit "$ARTIFACT" \
  --keychain-profile "$KEYCHAIN_PROFILE" \
  --wait 2>&1 | tee "$DIST_DIR/notarize.log" | sed 's/^/  /'

if ! grep -q "status: Accepted" "$DIST_DIR/notarize.log"; then
  SUBMISSION_ID="$(grep -m1 '  id:' "$DIST_DIR/notarize.log" | awk '{print $2}')"
  echo ""
  echo "  거절 사유를 보려면:"
  echo "    xcrun notarytool log $SUBMISSION_ID --keychain-profile $KEYCHAIN_PROFILE"
  die "공증이 통과하지 못했다."
fi

# ── 5. 통과 도장 박아 넣기 ──────────────────────────────────────────────
#
# staple 을 해 두면 받는 사람이 인터넷에 연결돼 있지 않아도 검사를 통과한다.

say "공증 결과를 파일에 박아 넣는다 (staple)"
xcrun stapler staple "$ARTIFACT" 2>&1 | sed 's/^/  /'

if [[ "$FORMAT" == "zip" ]]; then
  # ZIP 자체에는 도장을 박을 수 없다. 앱에 박고 다시 묶는다.
  say "ZIP 은 앱에 직접 도장을 박고 다시 묶는다"
  xcrun stapler staple "$APP" 2>&1 | sed 's/^/  /'
  rm -f "$ARTIFACT"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARTIFACT"
fi

# ── 6. 받는 사람 입장에서 최종 확인 ─────────────────────────────────────

say "받는 사람의 Mac 이 보게 될 것을 그대로 확인한다"
if spctl --assess --type execute --verbose=4 "$APP" 2>&1 | sed 's/^/  /' | grep -q "accepted"; then
  echo "  Gatekeeper 통과"
else
  spctl --assess --type execute --verbose=4 "$APP" 2>&1 | sed 's/^/  /' || true
  die "Gatekeeper 검사를 통과하지 못했다."
fi

xcrun stapler validate "$ARTIFACT" 2>&1 | sed 's/^/  /'

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
