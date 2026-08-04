#!/usr/bin/env bash
#
# 여러 클라이언트를 한꺼번에 띄워 같은 월드에 들여보낸다.
#
#   ./scripts/run.sh --prefix abc --count 10
#
# 위 명령은 abc1@test.com ~ abc10@test.com 으로 계정을 만들거나(있으면 접속하고),
# abc1 ~ abc10 이라는 이름의 남성 사이보그를 만들거나(있으면 그대로 고르고),
# 월드까지 자동으로 진입한 클라이언트 10 개를 화면에 바둑판으로 늘어놓는다.
#
# 자동화는 사람의 키보드·마우스를 가로채지 않는다. 앱이 실행 시점 환경변수를 읽고
# 스스로 입력칸을 채워 자기 이벤트 핸들러를 부른다(lib/dev/dev_login.dart).
#
# 창 배치도 같은 방식이다. 앱이 자기 창을 자기가 놓는다
# (macos/Runner/MainFlutterWindow.swift).

set -euo pipefail

# ── 기본값 ──────────────────────────────────────────────────────────────

PREFIX=""
COUNT=1
PASSWORD='12345a,*'
DOMAIN="test.com"
KIND="male_cyborg"
FLAVOR="release"      # release | debug | profile
WIDTH=600
HEIGHT=500
STAGGER=1.0           # 인스턴스 사이 실행 간격(초)
DO_BUILD=1
DO_STOP=0
DO_FRESH=0

BUNDLE_ID="com.withcenter.actionrpg"
APP_NAME="actionrpg"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_DIR="$ROOT/build/run-logs"
PID_FILE="$RUN_DIR/pids.txt"

# 샌드박스가 켜진 앱이라 HOME 이 이 컨테이너로 바뀐다. 인스턴스별 접속 토큰도
# 여기에 쌓인다(lib/dev/dev_env_io.dart).
CONTAINER="$HOME/Library/Containers/$BUNDLE_ID/Data"

usage() {
  cat <<'EOF'
사용법: ./scripts/run.sh --prefix <이름> --count <개수> [옵션]

필수
  --prefix <이름>     계정·캐릭터 이름의 앞부분. 영문자로 시작하는 영숫자.
                      abc 를 주면 abc1@test.com / 캐릭터 abc1 이 된다.

선택
  --count <N>         띄울 클라이언트 수 (기본 1)
  --password <값>     모든 계정에 쓸 비밀번호 (기본 '12345a,*', 8자 이상)
  --domain <도메인>   이메일 도메인 (기본 test.com)
  --kind <male|female> 캐릭터 외형 (기본 male)
  --width <px>        창 너비 (기본 600)
  --height <px>       창 높이 (기본 500)
  --stagger <초>      인스턴스 사이 실행 간격 (기본 1.0)
  --debug             디버그 빌드로 실행 (기본은 release)
  --profile           프로파일 빌드로 실행
  --no-build          다시 빌드하지 않고 있는 앱을 그대로 쓴다
  --fresh             저장된 접속 토큰을 지우고 새 identity 로 시작한다
  --stop              이 스크립트로 띄운 클라이언트를 모두 종료한다
  -h, --help          이 도움말

예
  ./scripts/run.sh --prefix abc --count 10
  ./scripts/run.sh --prefix qa --count 4 --kind female --no-build
  ./scripts/run.sh --stop
EOF
}

die() { echo "오류: $*" >&2; exit 1; }

# ── 인자 파싱 ───────────────────────────────────────────────────────────

need_value() {
  # $1 옵션 이름, $2 뒤따라온 값(없을 수 있음)
  [ -n "${2:-}" ] || die "$1 에는 값이 필요하다."
}

while [ $# -gt 0 ]; do
  case "$1" in
    --prefix)   need_value "$1" "${2:-}"; PREFIX="$2"; shift 2 ;;
    --count)    need_value "$1" "${2:-}"; COUNT="$2"; shift 2 ;;
    --password) need_value "$1" "${2:-}"; PASSWORD="$2"; shift 2 ;;
    --domain)   need_value "$1" "${2:-}"; DOMAIN="$2"; shift 2 ;;
    --kind)     need_value "$1" "${2:-}"; KIND="$2"; shift 2 ;;
    --width)    need_value "$1" "${2:-}"; WIDTH="$2"; shift 2 ;;
    --height)   need_value "$1" "${2:-}"; HEIGHT="$2"; shift 2 ;;
    --stagger)  need_value "$1" "${2:-}"; STAGGER="$2"; shift 2 ;;
    --debug)    FLAVOR="debug"; shift ;;
    --profile)  FLAVOR="profile"; shift ;;
    --release)  FLAVOR="release"; shift ;;
    --no-build) DO_BUILD=0; shift ;;
    --fresh)    DO_FRESH=1; shift ;;
    --stop)     DO_STOP=1; shift ;;
    -h|--help)  usage; exit 0 ;;
    *)          die "모르는 옵션이다: $1 (--help 참고)" ;;
  esac
done

# ── 종료 ────────────────────────────────────────────────────────────────

stop_all() {
  local stopped=0

  if [ -f "$PID_FILE" ]; then
    while IFS= read -r pid; do
      [ -n "$pid" ] || continue
      if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        stopped=$((stopped + 1))
      fi
    done < "$PID_FILE"
    rm -f "$PID_FILE"
  fi

  # 기록이 없거나 지워졌어도 살아 있는 인스턴스는 정리한다. 앱 번들 안의
  # 실행 파일 경로로 좁혀 잡으므로 같은 이름의 다른 프로세스는 건드리지 않는다.
  pkill -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" 2>/dev/null || true

  echo "종료했다 (기록된 인스턴스 $stopped 개)."
}

if [ "$DO_STOP" -eq 1 ]; then
  stop_all
  exit 0
fi

# ── 검증 ────────────────────────────────────────────────────────────────

[ "$(uname -s)" = "Darwin" ] || die "이 스크립트는 macOS 전용이다."
[ -n "$PREFIX" ] || { usage; echo; die "--prefix 는 필수다."; }

echo "$PREFIX" | grep -qE '^[A-Za-z][A-Za-z0-9]*$' \
  || die "--prefix 는 영문자로 시작하는 영숫자여야 한다: $PREFIX"
echo "$COUNT" | grep -qE '^[1-9][0-9]*$' \
  || die "--count 는 1 이상의 정수여야 한다: $COUNT"
[ "${#PASSWORD}" -ge 8 ] || die "비밀번호는 8자 이상이어야 한다."

case "$KIND" in
  male|male_cyborg)     KIND="male_cyborg" ;;
  female|female_cyborg) KIND="female_cyborg" ;;
  *) die "--kind 는 male 또는 female 이다: $KIND" ;;
esac

# 캐릭터 이름은 서버가 2~16자로 제한한다. 마지막 번호가 가장 길다.
NAME_LEN=$(( ${#PREFIX} + ${#COUNT} ))
[ "$NAME_LEN" -le 16 ] || die "캐릭터 이름이 16자를 넘는다(${PREFIX}${COUNT}). --prefix 를 줄여라."
[ $(( ${#PREFIX} + 1 )) -ge 2 ] || die "캐릭터 이름이 너무 짧다."

command -v flutter >/dev/null 2>&1 || die "flutter 를 찾을 수 없다."

# ── 빌드 ────────────────────────────────────────────────────────────────

case "$FLAVOR" in
  release) PRODUCT_DIR="Release" ;;
  debug)   PRODUCT_DIR="Debug" ;;
  profile) PRODUCT_DIR="Profile" ;;
esac

APP="$ROOT/build/macos/Build/Products/$PRODUCT_DIR/$APP_NAME.app"
BIN="$APP/Contents/MacOS/$APP_NAME"

if [ "$DO_BUILD" -eq 1 ]; then
  # 한 번만 빌드한다. 계정·캐릭터는 실행 시점 환경변수로 주므로 인스턴스마다
  # 다시 빌드할 이유가 없다.
  echo "▶ $FLAVOR 빌드 중… (한 번만 한다)"
  ( cd "$ROOT" && flutter build macos "--$FLAVOR" ) \
    || die "빌드에 실패했다."
fi

[ -x "$BIN" ] || die "실행 파일이 없다: $BIN
빌드부터 하려면 --no-build 를 빼고 다시 실행해라."

# ── 이전 인스턴스 정리 ──────────────────────────────────────────────────

if pgrep -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" >/dev/null 2>&1; then
  echo "▶ 이미 떠 있는 클라이언트를 정리한다."
  stop_all
  sleep 1
fi

if [ "$DO_FRESH" -eq 1 ]; then
  echo "▶ 저장된 접속 토큰을 지운다."
  rm -rf "$CONTAINER/.cyborg-slots"
fi

# ── 실행 ────────────────────────────────────────────────────────────────

mkdir -p "$RUN_DIR"
: > "$PID_FILE"

echo "▶ 클라이언트 $COUNT 개를 띄운다 (${WIDTH}x${HEIGHT}, $KIND)"

i=1
while [ "$i" -le "$COUNT" ]; do
  slot="${PREFIX}${i}"
  # 서버가 이메일을 소문자로 정규화하므로 여기서도 맞춰 둔다. 로그에 찍힌 주소와
  # 서버에 저장된 주소가 달라 보이면 추적이 어려워진다.
  email="$(echo "${slot}@${DOMAIN}" | tr '[:upper:]' '[:lower:]')"
  log="$RUN_DIR/$slot.log"

  DEV_LOGIN_EMAIL="$email" \
  DEV_LOGIN_PASSWORD="$PASSWORD" \
  DEV_CHARACTER_NAME="$slot" \
  DEV_CHARACTER_KIND="$KIND" \
  DEV_SESSION_SLOT="$slot" \
  CYBORG_TILE_INDEX="$((i - 1))" \
  CYBORG_TILE_WIDTH="$WIDTH" \
  CYBORG_TILE_HEIGHT="$HEIGHT" \
    nohup "$BIN" > "$log" 2>&1 &

  echo "$!" >> "$PID_FILE"
  printf '  [%2d/%d] %-20s → %s\n' "$i" "$COUNT" "$email" "$slot"

  i=$((i + 1))
  # 한꺼번에 밀어 넣으면 서버 접속과 앱 시작이 서로 붙어 느려진다.
  [ "$i" -le "$COUNT" ] && sleep "$STAGGER"
done

cat <<EOF

띄웠다. 비밀번호는 모두 '$PASSWORD' 다.

  로그    tail -f $RUN_DIR/${PREFIX}1.log
  진행    grep DEV-LOGIN $RUN_DIR/*.log
  종료    ./scripts/run.sh --stop
EOF
