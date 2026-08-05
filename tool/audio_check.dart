/// 사운드 에셋과 [GameAudio] 재생 경로만 격리해서 확인하는 임시 진입점.
///
/// 게임 본체와 무관하게 오디오만 점검한다.
///     flutter run -d macos -t tool/audio_check.dart
library;

import 'package:actionrpg/game/audio/game_audio.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const _AudioCheckApp());
}

class _AudioCheckApp extends StatefulWidget {
  const _AudioCheckApp();

  @override
  State<_AudioCheckApp> createState() => _AudioCheckAppState();
}

class _AudioCheckAppState extends State<_AudioCheckApp> {
  final List<String> _log = [];
  bool _running = false;

  void _write(String line) {
    debugPrint(line);
    if (mounted) setState(() => _log.add(line));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    if (_running) return;
    _running = true;
    _log.clear();

    final started = DateTime.now();
    await GameAudio.init();
    final elapsed = DateTime.now().difference(started).inMilliseconds;

    _write('init() 완료: ${elapsed}ms, isReady=${GameAudio.isReady}');
    if (!GameAudio.isReady) {
      _write('❌ 오디오 초기화 실패 — 위 로그의 예외 확인 필요');
      _running = false;
      return;
    }

    // 배경음악 트랙을 차례로 확인한다.
    for (final track in MusicTrack.values) {
      await GameAudio.playMusic(track);
      _write('♪ ${track.name}: '
          '${GameAudio.currentTrack == track ? "재생 중" : "실패"}');
      await Future<void>.delayed(const Duration(seconds: 4));
    }
    // 효과음을 가리지 않도록 배경음악은 여기서 끈다.
    await GameAudio.stopMusic();
    _write('배경음악 정지');

    for (final sfx in Sfx.values) {
      GameAudio.play(sfx);
      _write('▶ ${sfx.name}');
      await Future<void>.delayed(const Duration(milliseconds: 850));
    }

    _write('✅ 전체 ${Sfx.values.length}종 재생 완료');
    _running = false;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('사운드 점검'),
          actions: [
            IconButton(
              onPressed: _running ? null : _run,
              icon: const Icon(Icons.replay),
            ),
          ],
        ),
        body: ListView.builder(
          reverse: true,
          padding: const EdgeInsets.all(16),
          itemCount: _log.length,
          itemBuilder: (_, i) => Text(
            _log[_log.length - 1 - i],
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ),
      ),
    );
  }
}
