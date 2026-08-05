# macOS 앱을 남에게 건네주기

## 무엇이 문제였나

`flutter build macos` 로 만든 앱을 다른 사람에게 보내면 받는 쪽에서 이렇게 막혔다.

> "actionrpg"은(는) 손상되었기 때문에 열 수 없습니다. 휴지통으로 이동하십시오.

앱이 망가진 게 아니다. Flutter 의 macOS 템플릿은 서명 항목을 `CODE_SIGN_IDENTITY = "-"` 로
둔다. 이건 **ad-hoc 서명** — 만든 기계 안에서만 통하는 임시 도장이다.

메신저·메일·웹으로 받은 파일에는 macOS 가 격리(quarantine) 딱지를 붙인다. Gatekeeper 는
그 딱지를 보고 도장을 확인하려 하는데, 임시 도장은 그 기계에서 확인할 방법이 없다.
확인 실패를 macOS 는 "손상"으로 표현한다. 그래서 휴지통으로 가라는 말이 나온다.

## 어떻게 고쳤나

두 겹이다.

**① 서명** — [macos/Runner/Configs/Release.xcconfig](macos/Runner/Configs/Release.xcconfig)

Release 빌드에 Developer ID 인증서로 진짜 도장을 찍는다. 이걸로 휴지통 문제는 끝난다.
`ENABLE_HARDENED_RUNTIME` 과 `--timestamp` 도 함께 켰다. 다음 단계인 공증의 전제 조건이다.

**② 공증** — [scripts/release-macos.sh](scripts/release-macos.sh)

서명된 앱을 Apple 서버에 올려 검사받고, 통과 도장을 앱 안에 박아 넣는다(staple).
박아 넣기 때문에 받는 사람이 인터넷에 연결돼 있지 않아도 통과한다.

## 어디까지 하면 어떻게 되나

| | 받는 사람이 겪는 일 |
|---|---|
| ad-hoc 서명 (이전) | "손상되었습니다 → 휴지통으로 이동". 사실상 실행 불가 |
| **서명만** | "확인되지 않은 개발자" 경고. 아래 수동 절차를 거치면 실행됨 |
| **서명 + 공증** | 그냥 더블클릭. 경고 없음 |

공증 없이 보낼 때 받는 사람에게 알려 줄 절차 (macOS 15 Sequoia 기준):

1. 앱을 실행 → 차단 메시지가 뜨면 [완료]
2. 시스템 설정 → 개인정보 보호 및 보안 → 맨 아래로 내려 [그래도 열기]
3. 다시 실행 → [열기]

Sequoia 부터는 예전의 "우클릭 → 열기" 우회가 막혀서 시스템 설정을 거쳐야 한다.
플레이어마다 이걸 안내해야 하므로, 배포용이라면 공증을 받는 편이 낫다.

## 처음 한 번만 — 공증 계정 등록

공증은 Apple 서버에 로그인해야 하므로 **앱 암호**가 필요하다.
Apple ID 비밀번호가 아니라, 도구 전용으로 따로 발급받는 암호다.

1. https://account.apple.com 로그인
2. [로그인 및 보안] → [앱 암호] → [앱 암호 생성]
   이름은 아무거나 (예: `notarytool`). `xxxx-xxxx-xxxx-xxxx` 꼴의 암호가 나온다
3. 그 암호를 키체인에 넣어 둔다

```bash
xcrun notarytool store-credentials actionrpg-notary \
  --apple-id "thruthesky@gmail.com" \
  --team-id "AX352BQR6K" \
  --password "발급받은-앱-암호"
```

한 번 넣어 두면 그 뒤로는 스크립트가 알아서 꺼내 쓴다.
`./scripts/release-macos.sh --setup` 을 실행하면 이 안내가 그대로 나온다.

## 배포판 만들기

```bash
./scripts/release-macos.sh
```

빌드 → 서명 확인 → DMG 생성 → 공증 → staple → Gatekeeper 최종 확인까지 한 번에 한다.
결과물은 `build/dist/actionrpg-<버전>.dmg`.

| 옵션 | 뜻 |
|---|---|
| `--format zip` | DMG 대신 ZIP. `ditto` 로 묶는다 — 일반 `zip` 은 서명을 깨뜨린다 |
| `--no-build` | 이미 빌드된 앱을 그대로 쓴다 |
| `--skip-notarize` | 서명까지만. 계정 등록 전에 급히 보낼 때 |
| `--setup` | 공증 계정 등록 안내 |

스크립트는 중간에 ad-hoc 서명이 새어 나오거나 Hardened Runtime 이 꺼져 있으면
거기서 멈춘다. 잘못된 앱이 배포까지 흘러가지 않게 하려는 것이다.

## 제대로 됐는지 보는 법

```bash
# 누가 서명했나
codesign -dvv build/macos/Build/Products/Release/actionrpg.app

# 받는 사람의 Mac 이 내릴 판정
spctl --assess --type execute --verbose=4 build/macos/Build/Products/Release/actionrpg.app
```

`spctl` 의 답이 무슨 뜻인지:

| 출력 | 상태 |
|---|---|
| `rejected` / `source=no usable signature` | ad-hoc. 휴지통행 |
| `rejected` / `source=Unnotarized Developer ID` | 서명은 됐고 공증만 남았다 |
| `accepted` / `source=Notarized Developer ID` | 끝. 그냥 보내면 된다 |
