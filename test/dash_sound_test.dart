import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// 대시 소리는 대시를 다시 쓰기 전에 끝나야 한다.
///
/// 소리가 재사용 대기(0.9초)보다 길면, 연타할 때마다 아직 울리고 있는 소리
/// 위에 새 소리가 겹친다. 겹친 파형은 진폭이 더해지므로 누를수록 점점 커진다.
/// 실제로 대시 효과음이 5초짜리였던 적이 있고, 그때 여섯 겹까지 쌓였다.
///
/// 재생 쪽에서도 같은 사운드의 목소리 수를 `maxPlayers` 로 묶어 두었지만
/// (대시는 1), 그것은 마지막 방어선이다. 소리 자체가 한 동작의 길이를 넘지
/// 않는 것이 먼저다.
void main() {
  /// 대시 재사용 대기. `Player._dashCooldown` 에 넣는 값과 같아야 한다.
  const dashCooldown = 0.9;

  test('대시 효과음은 재사용 대기보다 짧다', () {
    for (final name in ['dash_0', 'dash_1']) {
      final path = 'assets/audio/sfx/$name.wav';
      final seconds = _wavDuration(File(path));
      expect(
        seconds,
        lessThan(dashCooldown),
        reason: '$path 이 ${seconds.toStringAsFixed(2)}초라 대시를 연타하면 소리가 겹쳐 커진다',
      );
    }
  });
}

/// WAV 파일의 재생 길이를 초 단위로 읽는다.
///
/// `fmt ` 청크에서 초당 바이트 수를, `data` 청크에서 실제 음성 데이터의
/// 크기를 찾아 나눈다. 청크 순서와 개수는 파일마다 다를 수 있으므로 헤더
/// 길이를 가정하지 않고 훑는다.
double _wavDuration(File file) {
  final bytes = file.readAsBytesSync();
  final view = ByteData.sublistView(bytes);

  var offset = 12; // 'RIFF' + 크기 + 'WAVE'
  var byteRate = 0;
  while (offset + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final size = view.getUint32(offset + 4, Endian.little);
    final body = offset + 8;

    if (id == 'fmt ') {
      byteRate = view.getUint32(body + 8, Endian.little);
    } else if (id == 'data') {
      expect(byteRate, greaterThan(0), reason: '${file.path}: fmt 청크를 찾지 못했다');
      return size / byteRate;
    }
    // 청크는 짝수 경계에 놓인다.
    offset = body + size + (size.isOdd ? 1 : 0);
  }
  fail('${file.path}: data 청크를 찾지 못했다');
}
