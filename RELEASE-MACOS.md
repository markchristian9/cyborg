# macOS 앱을 남에게 건네주기

```bash
./scripts/release-macos.sh
```

빌드 → 서명 확인 → 앱 공증 → DMG 생성 → DMG 공증 → 도장 박기 → 최종 확인까지
한 번에 한다. 결과물은 `build/dist/actionrpg-<버전>.dmg`. 그 파일은 메신저·메일·웹
어디로 보내도 되고, 받는 사람은 그냥 열면 된다.

## 무엇이 문제였나

`flutter build macos` 로 만든 앱을 다른 사람에게 보내면 받는 쪽에서 이렇게 막혔다.

> "actionrpg"은(는) 손상되었기 때문에 열 수 없습니다. 휴지통으로 이동하십시오.

앱이 망가진 게 아니다. Flutter 의 macOS 템플릿은 서명 항목을 `CODE_SIGN_IDENTITY = "-"` 로
둔다. 이건 **ad-hoc 서명** — 만든 기계 안에서만 통하는 임시 도장이다.

메신저·메일·웹으로 받은 파일에는 macOS 가 격리(quarantine) 딱지를 붙인다. Gatekeeper 는
그 딱지를 보고 도장을 확인하려 하는데, 임시 도장은 그 기계에서 확인할 방법이 없다.
확인 실패를 macOS 는 "손상"이라고 표현한다. 그래서 휴지통으로 가라는 말이 나온다.

## 어떻게 고쳤나

두 겹이다.

**① 서명** — [macos/Runner/Configs/Release.xcconfig](macos/Runner/Configs/Release.xcconfig)

Release 빌드에 Developer ID 인증서로 진짜 도장을 찍는다. 이걸로 휴지통 문제는 끝난다.
함께 켠 것이 둘 더 있다.

| 설정 | 왜 |
|---|---|
| `ENABLE_HARDENED_RUNTIME = YES` | 공증의 전제 조건. 꺼져 있으면 Apple 이 검사 자체를 거절한다 |
| `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO` | 아래 함정 참고 |

**② 공증** — [scripts/release-macos.sh](scripts/release-macos.sh)

서명된 앱을 Apple 서버에 올려 검사받고, 통과 도장을 앱 안에 박아 넣는다(staple).
박아 넣기 때문에 받는 사람이 인터넷에 연결돼 있지 않아도 통과한다.

## 밟았던 함정 두 개

### 하나 — Xcode 가 몰래 끼워 넣는 디버그 권한

첫 공증은 이 사유로 거절당했다.

> The executable requests the `com.apple.security.get-task-allow` entitlement.

디버거를 붙일 수 있게 해 주는 권한이다. `Release.entitlements` 에 적은 적이 없는데도
Xcode 가 서명할 때 자동으로 끼워 넣는다. 개발 중에는 필요하지만 배포판에 남아 있으면
Apple 이 거절한다. `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO` 로 막았다.

배포판에 들어 있어야 할 권한은 이 둘뿐이다.

```
com.apple.security.app-sandbox
com.apple.security.network.client    ← SpacetimeDB 접속용
```

스크립트는 공증에 올리기 **전에** 이걸 검사한다. 5 분 기다렸다 거절당하지 않으려는 것이다.

### 둘 — DMG 에만 도장을 박으면 앱을 옮기는 순간 풀린다

DMG 만 공증하면 통과 도장이 DMG 껍데기에만 박힌다. 받는 사람이 앱을 응용 프로그램
폴더로 끌어다 놓는 순간 도장은 따라가지 않고, 그때부터는 열 때마다 Apple 서버에
물어봐야 한다. 인터넷이 끊겨 있으면 열리지 않을 수 있다.

그래서 스크립트는 **앱을 먼저 공증해 앱 자체에 도장을 박고**, 그 앱으로 DMG 를 만든 뒤
**DMG 도 따로 공증한다.** 공증을 두 번 하므로 시간은 두 배지만, 앱을 어디로 옮기든
인터넷이 있든 없든 열린다.

## 어디까지 하면 어떻게 되나

| | 받는 사람이 겪는 일 |
|---|---|
| ad-hoc 서명 (이전) | "손상되었습니다 → 휴지통으로 이동". 사실상 실행 불가 |
| **서명만** (`--skip-notarize`) | "확인되지 않은 개발자" 경고. 아래 절차를 거치면 실행됨 |
| **서명 + 공증** (기본) | 그냥 더블클릭. 경고 없음 |

공증 없이 보낼 때 받는 사람에게 알려 줄 절차 (macOS 15 Sequoia 기준):

1. 앱을 실행 → 차단 메시지가 뜨면 [완료]
2. 시스템 설정 → 개인정보 보호 및 보안 → 맨 아래로 내려 [그래도 열기]
3. 다시 실행 → [열기]

Sequoia 부터는 예전의 "우클릭 → 열기" 우회가 막혀서 시스템 설정을 거쳐야 한다.
플레이어마다 이걸 안내해야 하므로, 배포용이라면 공증을 받는 편이 낫다.

## 처음 한 번만 — 공증 계정 등록

공증은 Apple 서버에 로그인해야 한다. 이 저장소는 App Store Connect API 키를 쓴다.
키는 `env/AuthKey_<키ID>.p8` 에 있고, `env/` 는 `.gitignore` 에 있어 저장소에 올라가지 않는다.

```bash
./scripts/release-macos.sh --setup
```

`env/` 에서 키를 찾아, 그대로 붙여 넣어 실행할 등록 명령을 찍어 준다. 한 번 등록하면
키체인에 저장되어 그 뒤로는 스크립트가 알아서 꺼내 쓴다. 기계를 옮기면 다시 해야 한다.

키가 없다면 App Store Connect → [Users and Access] → [Integrations] → [Team Keys]
에서 발급받아 `env/AuthKey_<키ID>.p8` 로 저장한다. 앱 암호(app-specific password) 방식도
쓸 수 있다 — `--setup` 이 둘 다 안내한다.

## 옵션

| 옵션 | 뜻 |
|---|---|
| `--format zip` | DMG 대신 ZIP. `ditto` 로 묶는다 — 일반 `zip` 은 서명을 깨뜨린다 |
| `--no-build` | 이미 빌드된 앱을 그대로 쓴다 |
| `--skip-notarize` | 서명까지만. 계정 등록 전에 급히 보낼 때 |
| `--setup` | 공증 계정 등록 안내 |

스크립트는 ad-hoc 서명이 새어 나오거나, Hardened Runtime 이 꺼져 있거나, 디버그 권한이
남아 있으면 거기서 멈춘다. 잘못된 앱이 배포까지 흘러가지 않게 하려는 것이다.

## 제대로 됐는지 보는 법

받는 사람 입장을 그대로 재현하려면 격리 딱지를 손으로 붙여 보면 된다.

```bash
cp build/dist/actionrpg-1.0.0.dmg /tmp/received.dmg
xattr -w com.apple.quarantine "0083;0;Safari;$(uuidgen)" /tmp/received.dmg
hdiutil attach /tmp/received.dmg -nobrowse

spctl --assess --type execute --verbose=4 /Volumes/actionrpg/actionrpg.app
xcrun stapler validate /Volumes/actionrpg/actionrpg.app
```

`spctl` 의 답이 무슨 뜻인지:

| 출력 | 상태 |
|---|---|
| `rejected` / `source=no usable signature` | ad-hoc. 휴지통행 |
| `rejected` / `source=Unnotarized Developer ID` | 서명은 됐고 공증만 남았다 |
| `accepted` / `source=Notarized Developer ID` | 끝. 그냥 보내면 된다 |
