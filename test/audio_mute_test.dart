import 'package:actionrpg/game/audio/game_audio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 꺼 둔 소리는 다음 실행에도 꺼진 채여야 한다.
///
/// 음소거는 "지금 이 판만" 의 설정이 아니다. 조용히 하려고 껐는데 게임을 다시
/// 켤 때마다 소리가 되살아나면 버튼을 누른 의미가 없다.
///
/// [GameAudio] 는 정적 상태를 들고 있어 한 프로세스 안에서 초기화를 되돌릴 수
/// 없다. 그래서 불러오기와 저장하기를 한 흐름에서 이어 확인한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('꺼 둔 소리는 다음 실행에서도 꺼진 채로 돌아온다', () async {
    // 지난 실행에서 소리를 꺼 둔 상태를 흉내 낸다.
    SharedPreferences.setMockInitialValues({'audio.muted': true});

    // 테스트 환경에는 오디오 장치가 없어 에셋 로딩은 실패한다. 그래도 음소거
    // 설정만은 살아남아야 한다 — 버튼이 지난번 상태를 그대로 보여야 하므로.
    await GameAudio.init();
    expect(GameAudio.isReady, isFalse, reason: '테스트 환경에서는 무음으로 진행한다');
    expect(GameAudio.muted, isTrue, reason: '저장해 둔 음소거 설정이 되살아나지 않았다');

    // 다시 켜면 그 사실도 남아야 한다.
    expect(GameAudio.toggleMuted(), isFalse);
    expect(GameAudio.muted, isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getBool('audio.muted'),
      isFalse,
      reason: '소리를 다시 켠 것이 저장되지 않아 다음 실행에서 또 꺼진다',
    );

    // 끄는 쪽으로도 남는다.
    expect(GameAudio.toggleMuted(), isTrue);
    final after = await SharedPreferences.getInstance();
    expect(after.getBool('audio.muted'), isTrue);
  });
}
