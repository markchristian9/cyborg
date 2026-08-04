import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:spacetimedb_sdk/spacetimedb_sdk.dart' show AuthTokenStore;

/// 프로세스가 받은 환경변수.
///
/// 컴파일 시점 `--dart-define` 과 달리 **한 번 빌드한 앱을 값만 바꿔 여러 번**
/// 띄울 수 있다. `scripts/run.sh` 가 클라이언트 N 개를 동시에 올리는 방식이 바로
/// 이것이라, 자동 로그인 설정은 이쪽을 먼저 본다.
Map<String, String> get devEnvironment => Platform.environment;

/// 인스턴스마다 접속 토큰을 따로 담을 저장소.
///
/// 같은 기기에서 앱을 여러 개 띄우면 번들 식별자가 같아 `shared_preferences`
/// (macOS 에서는 `NSUserDefaults`)를 통째로 공유한다. 토큰은 곧 identity 이므로
/// 공유하면 나중에 뜬 인스턴스가 앞선 인스턴스의 토큰을 덮어써, 열 개를 띄워도
/// 결국 같은 계정 하나로 수렴한다. 슬롯 이름별로 파일을 따로 두어 그 간섭을 끊는다.
///
/// [slot] 이 비어 있으면 null 을 돌려 기본 저장소를 쓰게 한다 — 평소 실행은
/// 지금까지와 똑같이 동작해야 한다.
AuthTokenStore? devSlotTokenStore(String slot) {
  final safe = _sanitize(slot);
  return safe.isEmpty ? null : _SlotTokenStore(safe);
}

/// 파일 이름으로 쓸 수 있는 글자만 남긴다.
///
/// 슬롯 이름은 밖에서 들어온 값이라 `../` 같은 조각이 섞이면 엉뚱한 곳에 쓰게 된다.
String _sanitize(String raw) =>
    raw.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '');

/// 슬롯 하나의 토큰을 파일 하나에 담는다.
class _SlotTokenStore implements AuthTokenStore {
  _SlotTokenStore(this.slot);

  final String slot;

  /// 토큰 파일 자리.
  ///
  /// 샌드박스가 켜진 macOS 앱에서 `HOME` 은 앱 전용 컨테이너를 가리키므로,
  /// 홈 디렉터리를 그대로 써도 사용자 문서 곁에 파일이 흩어지지 않는다.
  File get _file {
    final home =
        devEnvironment['HOME'] ?? Directory.systemTemp.path;
    return File('$home/.cyborg-slots/$slot.token');
  }

  @override
  Future<String?> loadToken() async {
    try {
      final file = _file;
      if (!file.existsSync()) return null;
      final token = (await file.readAsString()).trim();
      return token.isEmpty ? null : token;
    } on Object catch (e) {
      debugPrint('[DEV-LOGIN] 슬롯 토큰을 읽지 못했다($slot): $e');
      return null;
    }
  }

  @override
  Future<void> saveToken(String token) async {
    try {
      final file = _file;
      await file.parent.create(recursive: true);
      await file.writeAsString(token);
    } on Object catch (e) {
      debugPrint('[DEV-LOGIN] 슬롯 토큰을 저장하지 못했다($slot): $e');
    }
  }

  @override
  Future<void> clearToken() async {
    try {
      final file = _file;
      if (file.existsSync()) await file.delete();
    } on Object catch (e) {
      debugPrint('[DEV-LOGIN] 슬롯 토큰을 지우지 못했다($slot): $e');
    }
  }
}
