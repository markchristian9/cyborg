import 'package:spacetimedb_sdk/spacetimedb_sdk.dart' show AuthTokenStore;

/// 웹에는 프로세스 환경변수가 없다. 항상 비어 있다.
const Map<String, String> devEnvironment = <String, String>{};

/// 웹에는 인스턴스별 파일 저장소를 둘 곳이 없다.
///
/// 브라우저 탭마다 저장소를 나누는 것은 그 자체로 다른 문제이며, 여러 클라이언트를
/// 동시에 띄우는 스크립트는 macOS 앱만 대상으로 한다. 여기서는 항상 null 을 돌려
/// 기본 저장소를 쓰게 한다.
AuthTokenStore? devSlotTokenStore(String slot) => null;
