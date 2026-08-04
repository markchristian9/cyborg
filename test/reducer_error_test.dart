import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:actionrpg/spacetime/reducer_error.dart';

/// SDK 가 실제로 넘겨주는 형태를 만든다.
///
/// `spacetimedb_sdk` 2.4.0 은 `Err(Bytes)` 안의 BSATN 문자열을 풀지 않고 통째로
/// UTF-8 디코딩하므로, u32(리틀엔디언) 길이 4바이트가 본문 앞에 문자로 남는다.
String asReceived(String body) {
  final length = utf8.encode(body).length;
  final prefix = String.fromCharCodes([
    length & 0xFF,
    (length >> 8) & 0xFF,
    (length >> 16) & 0xFF,
    (length >> 24) & 0xFF,
  ]);
  return '$prefix$body';
}

void main() {
  group('길이 프리픽스', () {
    test('실제 서버 응답에서 프리픽스를 벗긴다', () {
      // 실측한 문장들. 앞 바이트가 각각 '5'(53)·'!'(33)로 보였다.
      const messages = [
        '이메일 또는 비밀번호가 올바르지 않다.',
        '이미 가입된 이메일이다.',
        '이메일 형식이 아니다.',
        '비밀번호는 최소 8자다.',
        '로그인이 필요하다.',
        '같은 이름의 캐릭터가 이미 있다.',
      ];

      for (final message in messages) {
        expect(cleanReducerError(asReceived(message)), message);
      }
    });

    test('ASCII 문장에도 통한다', () {
      expect(cleanReducerError(asReceived('unauthorized')), 'unauthorized');
    });

    test('프리픽스가 없으면 건드리지 않는다', () {
      // SDK 가 이 버그를 고치면 이 경로로 들어온다. 그때도 멀쩡해야 한다.
      expect(cleanReducerError('이메일 형식이 아니다.'), '이메일 형식이 아니다.');
    });

    test('길이가 맞지 않으면 벗기지 않는다', () {
      // 우연히 앞 네 글자가 프리픽스처럼 생겼어도 길이가 어긋나면 본문이다.
      const looksLikePrefix = '5000원을 결제할 수 없다.';
      expect(cleanReducerError(looksLikePrefix), looksLikePrefix);
    });

    test('네 글자보다 짧으면 그대로 둔다', () {
      expect(cleanReducerError('짧다'), '짧다');
    });
  });

  group('빈 값과 여러 줄', () {
    test('비어 있으면 기본 문구를 준다', () {
      expect(cleanReducerError(null), '요청이 거절되었다.');
      expect(cleanReducerError(''), '요청이 거절되었다.');
    });

    test('공백뿐이면 기본 문구를 준다', () {
      expect(cleanReducerError('   \n  \n '), '요청이 거절되었다.');
    });

    test('여러 줄이면 마지막 줄만 남긴다', () {
      // 호스트가 트랜잭션 정보를 앞에 붙이는 경우.
      expect(
        cleanReducerError('reducer login failed\n이메일 또는 비밀번호가 올바르지 않다.'),
        '이메일 또는 비밀번호가 올바르지 않다.',
      );
    });

    test('프리픽스와 여러 줄이 함께 와도 처리한다', () {
      expect(
        cleanReducerError(asReceived('첫 줄\n마지막 줄이다.')),
        '마지막 줄이다.',
      );
    });
  });
}
