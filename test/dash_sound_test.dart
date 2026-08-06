import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:actionrpg/game/entities/cyborg_design.dart';
import 'package:actionrpg/game/entities/player.dart';
import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';

/// 대시를 눌렀을 때 소리가 제대로 나는지 지킨다.
///
/// 이 파일이 막는 것은 실제로 두 번 겪은 두 가지 고장이다.
///
/// 1. **길면 겹쳐 쌓인다.** 소리가 재사용 대기(0.9초)보다 길면 연타할 때마다
///    아직 울리고 있는 소리 위에 새 소리가 얹힌다. 겹친 파형은 진폭이
///    더해지므로 누를수록 커진다. 대시 효과음이 5초짜리였을 때 여섯 겹까지
///    쌓였다.
/// 2. **작으면 묻힌다.** 그렇다고 짧게만 자르면 전투음과 배경음 사이에서
///    들리지 않는다. 한 번 잘라 냈을 때 체감 세기가 발소리 수준으로 떨어져
///    "소리가 아예 안 난다" 로 돌아왔다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 대시 재사용 대기. `Player.tryDash` 가 넣는 값과 같아야 한다.
  const dashCooldown = 0.9;

  /// 가장 센 100ms 구간 RMS 의 하한(전체 진폭 대비).
  ///
  /// 다른 효과음의 같은 잣대: 발소리 0.09, 근접 명중 0.17, 폭발 0.31.
  /// 대시는 폭발과 같은 자리에 있어야 전투 한복판에서도 들린다.
  const bodyRmsFloor = 0.25;

  for (final name in ['dash_0', 'dash_1']) {
    final wav = _Wav.read(File('assets/audio/sfx/$name.wav'));

    test('$name 은 재사용 대기보다 짧다', () {
      expect(
        wav.seconds,
        lessThan(dashCooldown),
        reason: '${wav.seconds.toStringAsFixed(2)}초라 연타하면 소리가 겹쳐 커진다',
      );
    });

    test('$name 은 전투음에 묻히지 않을 만큼 세다', () {
      expect(
        wav.bodyRms,
        greaterThan(bodyRmsFloor),
        reason: '체감 세기가 ${wav.bodyRms.toStringAsFixed(3)} 이라 전투 중에 들리지 않는다',
      );
    });
  }

  group('대시 버튼', () {
    Player fresh() => Player(
          grid: Vector2(100, 100),
          design: CyborgDesign.assault,
        );

    test('에너지가 모자라도 덮개로 남은 정도를 알린다', () {
      final player = fresh();
      expect(player.dashBlockedRatio, 0, reason: '가득 찼으면 바로 나가야 한다');

      player.energy = Player.dashEnergyCost / 2;
      expect(player.dashBlockedRatio, closeTo(0.5, 0.001));

      player.energy = 0;
      expect(player.dashBlockedRatio, 1);
    });

    test('한 번 나가면 대기 동안에는 다시 나가지 않는다', () {
      final player = fresh()..energy = 100;

      player.tryDash();
      expect(player.energy, 100 - Player.dashEnergyCost);
      expect(player.dashCooldownRatio, 1, reason: '대기가 시작되어야 한다');

      // 대기 중의 연타는 에너지를 더 쓰지 않는다 — 소리로만 답한다.
      player.tryDash();
      player.tryDash();
      expect(player.energy, 100 - Player.dashEnergyCost);
    });
  });
}

/// 시험에 필요한 만큼만 읽어 낸 WAV.
class _Wav {
  const _Wav({required this.seconds, required this.bodyRms});

  /// 재생 길이(초).
  final double seconds;

  /// 가장 센 100ms 구간의 RMS(0~1). 체감 세기에 가깝다.
  final double bodyRms;

  /// `fmt ` 와 `data` 청크를 찾아 길이와 세기를 잰다.
  ///
  /// 청크의 순서와 개수는 파일마다 다를 수 있으므로 헤더 길이를 가정하지
  /// 않고 훑는다.
  static _Wav read(File file) {
    final bytes = file.readAsBytesSync();
    final view = ByteData.sublistView(bytes);

    var offset = 12; // 'RIFF' + 크기 + 'WAVE'
    var byteRate = 0;
    var sampleRate = 0;
    var bitsPerSample = 0;

    while (offset + 8 <= bytes.length) {
      final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final size = view.getUint32(offset + 4, Endian.little);
      final body = offset + 8;

      if (id == 'fmt ') {
        sampleRate = view.getUint32(body + 4, Endian.little);
        byteRate = view.getUint32(body + 8, Endian.little);
        bitsPerSample = view.getUint16(body + 14, Endian.little);
      } else if (id == 'data') {
        if (byteRate <= 0) {
          throw StateError('${file.path}: fmt 청크를 찾지 못했다');
        }
        if (bitsPerSample != 16) {
          throw StateError('${file.path}: 16비트 PCM 만 읽는다');
        }
        return _Wav(
          seconds: size / byteRate,
          bodyRms: _bodyRms(view, body, size, sampleRate),
        );
      }
      // 청크는 짝수 경계에 놓인다.
      offset = body + size + (size.isOdd ? 1 : 0);
    }
    throw StateError('${file.path}: data 청크를 찾지 못했다');
  }

  /// 100ms 창을 50ms 씩 밀며 가장 센 구간의 RMS 를 찾는다.
  static double _bodyRms(ByteData view, int start, int size, int sampleRate) {
    final count = size ~/ 2;
    final window = math.min(sampleRate ~/ 10, count);
    final hop = math.max(1, window ~/ 2);

    var best = 0.0;
    for (var i = 0; i + window <= count; i += hop) {
      var sum = 0.0;
      for (var j = i; j < i + window; j++) {
        final sample = view.getInt16(start + j * 2, Endian.little) / 32768;
        sum += sample * sample;
      }
      best = math.max(best, math.sqrt(sum / window));
    }
    return best;
  }
}
