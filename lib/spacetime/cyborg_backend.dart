import 'package:flutter/foundation.dart';
import 'package:spacetimedb_sdk/spacetimedb_sdk.dart';

import 'cyborg_connection.dart';
import 'generated/client.dart';

/// 백엔드 연결의 현재 상태.
enum BackendStatus {
  /// 아직 붙어 보지 않았다.
  idle,

  connecting,

  connected,

  /// 붙지 못했다. 게임은 그대로 돌아가고 서버가 필요한 화면만 이 사실을 알린다.
  failed,
}

/// 앱 전체가 공유하는 SpacetimeDB 연결.
///
/// **연결은 게임의 전제 조건이 아니다.** 서버에 못 붙어도 게임은 오프라인으로
/// 끝까지 돌아가고, 서버가 있어야만 되는 것(리더보드 열람, 기록 전송)만 조용히
/// 빠진다. 그래서 [connect] 는 실패를 던지지 않고 [status] 에 남긴다 —
/// 네트워크가 없다고 첫 화면에서 막히는 게임은 만들지 않는다.
class CyborgBackend extends ChangeNotifier {
  CyborgBackend._();

  static final CyborgBackend instance = CyborgBackend._();

  SpacetimeDbClient? _client;

  /// 접속에 성공했을 때만 값이 있다.
  SpacetimeDbClient? get client => _client;

  BackendStatus _status = BackendStatus.idle;
  BackendStatus get status => _status;

  /// 실패했을 때 사람이 읽을 수 있는 이유.
  String? _failureMessage;
  String? get failureMessage => _failureMessage;

  /// 서버에 붙는다. 이미 붙어 있거나 붙는 중이면 아무것도 하지 않는다.
  Future<void> connect() async {
    if (_status == BackendStatus.connecting ||
        _status == BackendStatus.connected) {
      return;
    }

    _setStatus(BackendStatus.connecting);

    try {
      final client = await SpacetimeDbClient.create(
        host: kCyborgHost,
        database: kCyborgDatabase,
        ssl: kCyborgSsl,
        authStorage: PrefsTokenStore(),
      );
      await client.connect();
      _client = client;
      _failureMessage = null;
      _setStatus(BackendStatus.connected);
    } on SpacetimeDbException catch (e) {
      _client = null;
      _failureMessage = e.message;
      _setStatus(BackendStatus.failed);
    } catch (e) {
      // SDK 밖에서 터지는 것(타임아웃, 플랫폼 오류)도 게임을 멈추게 두지 않는다.
      _client = null;
      _failureMessage = '$e';
      _setStatus(BackendStatus.failed);
    }
  }

  /// 실패한 연결을 다시 시도한다.
  Future<void> retry() async {
    if (_status == BackendStatus.connecting) return;
    _setStatus(BackendStatus.idle);
    await connect();
  }

  void _setStatus(BackendStatus status) {
    _status = status;
    notifyListeners();
  }

  @override
  void dispose() {
    _client?.disconnect();
    _client = null;
    super.dispose();
  }
}
