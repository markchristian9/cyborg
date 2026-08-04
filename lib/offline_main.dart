import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'game/action_rpg_game.dart';
import 'game/palette.dart';

/// 계정·서버 없이 게임 월드만 띄우는 진입점.
///
/// 본체(`main.dart`)는 SpacetimeDB 로그인을 거쳐야 월드에 들어가지만,
/// 지형·몬스터·전투처럼 서버와 무관한 부분을 확인할 때는 그 절차가
/// 걸림돌이 된다. 이 진입점은 [ActionRpgGame.sync]를 비운 채로 곧장
/// 월드를 연다.
///
/// ```sh
/// flutter run -t lib/offline_main.dart -d macos
/// ```
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OfflineCyborgApp());
}

class OfflineCyborgApp extends StatelessWidget {
  const OfflineCyborgApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cyborg (오프라인)',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: GamePalette.hudBorder,
          brightness: Brightness.light,
        ),
      ),
      home: const OfflineGameScreen(),
    );
  }
}

class OfflineGameScreen extends StatefulWidget {
  const OfflineGameScreen({super.key});

  @override
  State<OfflineGameScreen> createState() => _OfflineGameScreenState();
}

class _OfflineGameScreenState extends State<OfflineGameScreen> {
  /// sync를 넘기지 않으므로 백엔드 전송은 전부 no-op이 된다.
  late final ActionRpgGame _game = ActionRpgGame();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GamePalette.skyLow,
      body: GameWidget<ActionRpgGame>(
        game: _game,
        overlayBuilderMap: {
          Overlays.mainMenu: (context, game) => _OfflineMenu(game: game),
          Overlays.pauseMenu: (context, game) => _OfflinePauseMenu(game: game),
        },
      ),
    );
  }
}

class _OfflineMenu extends StatelessWidget {
  const _OfflineMenu({required this.game});

  final ActionRpgGame game;

  static const List<(String, String)> _controls = [
    ('이동', 'WASD  ·  방향키'),
    ('근접 공격', 'Space  ·  J'),
    ('플라즈마 사격', 'K  ·  F'),
    ('대시', 'Shift  ·  L'),
    ('인벤토리', 'I  ·  Tab'),
    ('캐릭터 정보', 'C'),
    ('포션 사용', 'Q  ·  1~6'),
    ('일시정지', 'ESC  ·  P'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: GamePalette.skyLow.withValues(alpha: 0.88),
      alignment: Alignment.center,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'CYBORG',
              style: TextStyle(
                color: GamePalette.textPrimary,
                fontSize: 60,
                fontWeight: FontWeight.w900,
                letterSpacing: 14,
                shadows: [
                  Shadow(color: GamePalette.playerAccent, blurRadius: 24),
                ],
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '오프라인 월드 — 서버에 접속하지 않는다',
              style: TextStyle(
                color: GamePalette.textDim,
                fontSize: 14,
                letterSpacing: 2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 30),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
              decoration: BoxDecoration(
                color: GamePalette.hudBackground,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: GamePalette.hudBorder.withValues(alpha: 0.35),
                  width: 1.2,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (label, keys) in _controls)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 116,
                            child: Text(
                              label,
                              style: const TextStyle(
                                color: GamePalette.textDim,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 168,
                            child: Text(
                              keys,
                              style: const TextStyle(
                                color: GamePalette.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: 260,
              height: 52,
              child: FilledButton(
                onPressed: game.startGame,
                style: FilledButton.styleFrom(
                  backgroundColor: GamePalette.hudBorder,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  '월드 진입',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfflinePauseMenu extends StatelessWidget {
  const _OfflinePauseMenu({required this.game});

  final ActionRpgGame game;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: GamePalette.skyLow.withValues(alpha: 0.88),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '일시정지',
            style: TextStyle(
              color: GamePalette.textPrimary,
              fontSize: 36,
              fontWeight: FontWeight.w900,
              letterSpacing: 6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '처치 ${game.kills}   ·   점수 ${game.score}   ·   재가동 ${game.deaths}회',
            style: const TextStyle(
              color: GamePalette.textDim,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 26),
          SizedBox(
            width: 260,
            height: 52,
            child: FilledButton(
              onPressed: game.resumeGame,
              style: FilledButton.styleFrom(
                backgroundColor: GamePalette.hudBorder,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                '계속하기',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
