/// 실행 시점 환경을 읽는 통로.
///
/// 웹에는 프로세스 환경변수도 파일 시스템도 없으므로, `dart:io` 가 있는
/// 플랫폼에서만 진짜 구현을 쓰고 나머지는 빈 껍데기로 떨어진다.
library;

export 'dev_env_stub.dart' if (dart.library.io) 'dev_env_io.dart';
